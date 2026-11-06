import 'dart:convert';
import 'dart:math';

import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../core/models/student_model.dart';
import '../local/app_database.dart';

/// Resumen de una importación masiva de estudiantes a un curso.
class RosterImportResult {
  const RosterImportResult({
    required this.insertedCount,
    required this.duplicatesSkipped,
    required this.invalidRowsSkipped,
    required this.insertedStudents,
  });

  /// Cantidad de estudiantes efectivamente persistidos.
  final int insertedCount;

  /// Filas descartadas por repetir código o nombre dentro del lote o del curso.
  final int duplicatesSkipped;

  /// Filas descartadas por datos incompletos o por falta de cupo en el Bitmap.
  final int invalidRowsSkipped;

  /// Estudiantes persistidos, en el mismo orden en que fueron asignados.
  final List<StudentModel> insertedStudents;
}

/// Motor de ingesta de cursos y estudiantes sin dependencia del SMA.
///
/// Acepta tres vías de entrada (CSV, Excel y texto pegado), además del alta
/// manual, y aplica las reglas de normalización, deduplicación y capacidad del
/// Bitmap de 64 posiciones.
class RosterImportService {
  RosterImportService({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  static const Set<String> _codeHeaders = <String>{
    'codigo',
    'codigo estudiante',
    'codigo del estudiante',
  };
  static const Set<String> _nameHeaders = <String>{
    'nombre',
    'nombre completo',
    'estudiante',
  };
  static const Set<String> _emailHeaders = <String>{
    'correo',
    'email',
    'correo electronico',
  };

  /// Importa estudiantes desde el contenido literal de un archivo CSV.
  ///
  /// La fila de encabezados se detecta y se ignora, y los códigos se conservan
  /// como texto para no perder los ceros a la izquierda.
  Future<RosterImportResult> importFromCsvString(
    String courseId,
    String csvContent,
  ) async {
    return _importRows(courseId, _parseCsvRows(csvContent));
  }

  /// Importa estudiantes desde los bytes de un libro de Excel (`.xlsx`).
  Future<RosterImportResult> importFromExcelBytes(
    String courseId,
    List<int> bytes,
  ) async {
    return _importRows(courseId, _parseExcelRows(bytes));
  }

  /// Importa estudiantes desde texto pegado con columnas separadas por
  /// tabulador, punto y coma, coma o guion.
  Future<RosterImportResult> importFromClipboardText(
    String courseId,
    String rawText,
  ) async {
    return _importRows(courseId, _parseClipboardRows(rawText));
  }

  /// Da de alta un estudiante individual en el siguiente Bitmap libre.
  ///
  /// Rechaza códigos o nombres ya registrados y aplica el límite de 64 cupos.
  Future<StudentModel> addManualStudent({
    required String courseId,
    required String studentCode,
    required String fullName,
    String? email,
  }) async {
    final course = await _database.getCourseById(courseId);
    if (course == null) {
      throw ArgumentError.value(
        courseId,
        'courseId',
        'El curso no existe.',
      );
    }

    final code = studentCode.trim();
    final name = _normalizeFullName(fullName);
    if (code.isEmpty) {
      throw ArgumentError.value(
        studentCode,
        'studentCode',
        'El código del estudiante no puede estar vacío.',
      );
    }
    if (name.isEmpty) {
      throw ArgumentError.value(
        fullName,
        'fullName',
        'El nombre del estudiante no puede estar vacío.',
      );
    }

    final existing = await _database.getStudentsByCourse(courseId);
    if (existing.length >= AppConstants.bitmapBitCount) {
      throw StateError(
        'El curso $courseId ya ocupó las '
        '${AppConstants.bitmapBitCount} posiciones del Bitmap.',
      );
    }
    final existingCodes = existing
        .map((StudentModel student) => student.studentCode.trim())
        .toSet();
    final existingNames = existing
        .map((StudentModel student) => _normalizeFullName(student.fullName))
        .toSet();
    if (existingCodes.contains(code)) {
      throw StateError('El código $code ya está registrado en el curso.');
    }
    if (existingNames.contains(name)) {
      throw StateError('El nombre $name ya está registrado en el curso.');
    }

    final usedBits =
        existing.map((StudentModel student) => student.bitIndex).toSet();
    final student = StudentModel(
      id: _uuid.v4(),
      courseId: courseId,
      studentCode: code,
      fullName: name,
      email: _normalizeEmail(email),
      bitIndex: _firstFreeBit(usedBits),
      personalSecret: _generateSecret(),
      enrolledAt: _nowIso(),
    );
    await _database.insertStudent(student);
    return student;
  }

  /// Genera el JSON compacto que el teléfono del estudiante escanea una sola vez.
  ///
  /// [deviceSecret] es el secreto personal persistido para ese estudiante y
  /// [sharedSecret] es el secreto del curso con el que se verifica el HMAC.
  String generateEnrollmentQrPayload({
    required CourseModel course,
    required StudentModel student,
  }) {
    if (student.courseId != course.id) {
      throw ArgumentError.value(
        student.courseId,
        'student',
        'El estudiante no pertenece al curso indicado.',
      );
    }
    return jsonEncode(<String, Object?>{
      'courseId': course.id,
      'courseCode': course.code,
      'courseName': course.name,
      'studentId': student.id,
      'studentCode': student.studentCode,
      'fullName': student.fullName,
      'bitmapIndex': student.bitIndex,
      'deviceSecret': student.personalSecret,
      'sharedSecret': course.courseSecret,
    });
  }

  // ---------------------------------------------------------------------------
  // Ingesta y reglas de negocio
  // ---------------------------------------------------------------------------

  Future<RosterImportResult> _importRows(
    String courseId,
    List<List<String>> rawRows,
  ) async {
    final course = await _database.getCourseById(courseId);
    if (course == null) {
      throw ArgumentError.value(
        courseId,
        'courseId',
        'El curso no existe.',
      );
    }

    final existing = await _database.getStudentsByCourse(courseId);
    final existingCodes = existing
        .map((StudentModel student) => student.studentCode.trim())
        .toSet();
    final existingNames = existing
        .map((StudentModel student) => _normalizeFullName(student.fullName))
        .toSet();
    final usedBits =
        existing.map((StudentModel student) => student.bitIndex).toSet();

    final batchCodes = <String>{};
    final batchNames = <String>{};
    final inserted = <StudentModel>[];
    var duplicatesSkipped = 0;
    var invalidRowsSkipped = 0;

    for (final _ParsedRow row in _mapRows(rawRows)) {
      final code = row.code.trim();
      final name = _normalizeFullName(row.name);
      if (code.isEmpty || name.isEmpty) {
        invalidRowsSkipped++;
        continue;
      }

      final repeated = batchCodes.contains(code) ||
          batchNames.contains(name) ||
          existingCodes.contains(code) ||
          existingNames.contains(name);
      if (repeated) {
        duplicatesSkipped++;
        continue;
      }

      if (existing.length + inserted.length >=
          AppConstants.bitmapBitCount) {
        invalidRowsSkipped++;
        continue;
      }

      final student = StudentModel(
        id: _uuid.v4(),
        courseId: courseId,
        studentCode: code,
        fullName: name,
        email: _normalizeEmail(row.email),
        bitIndex: _firstFreeBit(usedBits),
        personalSecret: _generateSecret(),
        enrolledAt: _nowIso(),
      );
      await _database.insertStudent(student);

      usedBits.add(student.bitIndex);
      batchCodes.add(code);
      batchNames.add(name);
      inserted.add(student);
    }

    return RosterImportResult(
      insertedCount: inserted.length,
      duplicatesSkipped: duplicatesSkipped,
      invalidRowsSkipped: invalidRowsSkipped,
      insertedStudents: List<StudentModel>.unmodifiable(inserted),
    );
  }

  List<_ParsedRow> _mapRows(List<List<String>> rows) {
    if (rows.isEmpty) {
      return const <_ParsedRow>[];
    }

    var start = 0;
    var codeIndex = 0;
    var nameIndex = 1;
    int? emailIndex = 2;

    final header = _headerMapping(rows.first);
    if (header != null) {
      start = 1;
      codeIndex = header['code'] ?? 0;
      nameIndex = header['name'] ?? 1;
      emailIndex = header['email'];
    }

    final parsed = <_ParsedRow>[];
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((String cell) => cell.trim().isEmpty)) {
        continue;
      }
      parsed.add(
        _ParsedRow(
          code: _cellAt(row, codeIndex),
          name: _cellAt(row, nameIndex),
          email: emailIndex == null ? null : _cellAt(row, emailIndex),
        ),
      );
    }
    return parsed;
  }

  /// Reconoce una fila de títulos y devuelve el índice de cada columna.
  Map<String, int>? _headerMapping(List<String> row) {
    final mapping = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final token = _normalizeHeaderToken(row[i]);
      if (_codeHeaders.contains(token)) {
        mapping.putIfAbsent('code', () => i);
      } else if (_nameHeaders.contains(token)) {
        mapping.putIfAbsent('name', () => i);
      } else if (_emailHeaders.contains(token)) {
        mapping.putIfAbsent('email', () => i);
      }
    }
    if (mapping.isEmpty) {
      return null;
    }
    if (!mapping.containsKey('code') && mapping.length < 2) {
      return null;
    }
    final codePosition = mapping['code'];
    if (codePosition != null &&
        RegExp(r'^\d{4,}$').hasMatch(_cellAt(row, codePosition))) {
      return null;
    }
    return mapping;
  }

  List<List<String>> _parseCsvRows(String content) {
    final normalized = _normalizeNewlines(_stripBom(content)).trim();
    if (normalized.isEmpty) {
      return const <List<String>>[];
    }
    return _parseDelimitedRows(
      normalized,
      _detectCsvDelimiter(normalized),
    );
  }

  /// Parser CSV/DSV con soporte de campos entre comillas y comillas escapadas.
  ///
  /// No convierte números: cada celda se conserva como texto para preservar los
  /// ceros a la izquierda de los códigos estudiantiles.
  List<List<String>> _parseDelimitedRows(String content, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      if (char == '"') {
        inQuotes = true;
      } else if (char == delimiter) {
        row.add(field.toString().trim());
        field = StringBuffer();
      } else if (char == '\n') {
        row.add(field.toString().trim());
        rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(char);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString().trim());
      rows.add(row);
    }
    return rows;
  }

  List<List<String>> _parseExcelRows(List<int> bytes) {
    final workbook = Excel.decodeBytes(bytes);
    for (final String tableName in workbook.tables.keys) {
      final sheet = workbook.tables[tableName];
      if (sheet == null) {
        continue;
      }
      final rows = sheet.rows
          .map(
            (List<Data?> row) => row
                .map((Data? cell) => _excelCellText(cell).trim())
                .toList(growable: false),
          )
          .toList(growable: false);
      final hasData = rows.any(
        (List<String> row) => row.any((String cell) => cell.isNotEmpty),
      );
      if (hasData) {
        return rows;
      }
    }
    throw ArgumentError.value(
      bytes,
      'bytes',
      'El archivo Excel no contiene filas con datos.',
    );
  }

  List<List<String>> _parseClipboardRows(String rawText) {
    final normalized = _normalizeNewlines(_stripBom(rawText));
    final rows = <List<String>>[];
    for (final String line in normalized.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      rows.add(_splitClipboardLine(line));
    }
    return rows;
  }

  List<String> _splitClipboardLine(String line) {
    for (final String delimiter in <String>['\t', ';', ',']) {
      if (line.contains(delimiter)) {
        return line.split(delimiter);
      }
    }
    final spacedHyphen = RegExp(r'\s+-\s+').firstMatch(line);
    if (spacedHyphen != null) {
      return <String>[
        line.substring(0, spacedHyphen.start),
        line.substring(spacedHyphen.end),
      ];
    }
    final hyphen = line.indexOf('-');
    if (hyphen > 0 && hyphen < line.length - 1) {
      return <String>[
        line.substring(0, hyphen),
        line.substring(hyphen + 1),
      ];
    }
    return <String>[line];
  }

  static String _excelCellText(Data? cell) {
    final CellValue? value = cell?.value;
    if (value == null) {
      return '';
    }
    if (value is TextCellValue) {
      return value.value.text ?? '';
    }
    if (value is IntCellValue) {
      return value.value.toString();
    }
    if (value is DoubleCellValue) {
      return value.value.toString();
    }
    if (value is BoolCellValue) {
      return value.value.toString();
    }
    return value.toString();
  }

  static String _detectCsvDelimiter(String content) {
    final sample = content.split('\n').firstWhere(
          (String line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
    final candidates = <String>['\t', ';', ','];
    var best = ',';
    var bestCount = -1;
    for (final String candidate in candidates) {
      final count = candidate.allMatches(sample).length;
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  static String _normalizeNewlines(String content) {
    return content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static String _stripBom(String content) {
    return content.startsWith('\uFEFF') ? content.substring(1) : content;
  }

  static String _cellAt(List<String> row, int index) {
    return index >= 0 && index < row.length ? row[index].trim() : '';
  }

  static String _normalizeHeaderToken(String value) {
    return _stripAccents(value).trim().toLowerCase().replaceAll(':', '');
  }

  static String _normalizeFullName(String value) {
    return _stripAccents(value)
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _normalizeEmail(String? email) {
    final value = email?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String _stripAccents(String value) {
    var result = value;
    _accentMap.forEach((String from, String to) {
      result = result.replaceAll(from, to);
    });
    return result;
  }

  static int _firstFreeBit(Set<int> usedBits) {
    for (var bit = 0; bit < AppConstants.bitmapBitCount; bit++) {
      if (!usedBits.contains(bit)) {
        return bit;
      }
    }
    throw StateError(
      'El curso ya ocupó las ${AppConstants.bitmapBitCount} '
      'posiciones del Bitmap.',
    );
  }

  static String _generateSecret() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  static const Map<String, String> _accentMap = <String, String>{
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ü': 'U',
    'á': 'A',
    'é': 'E',
    'í': 'I',
    'ó': 'O',
    'ú': 'U',
    'ü': 'U',
    'À': 'A',
    'È': 'E',
    'Ì': 'I',
    'Ò': 'O',
    'Ù': 'U',
    'à': 'A',
    'è': 'E',
    'ì': 'I',
    'ò': 'O',
    'ù': 'U',
  };
}

/// Fila cruda ya mapeada a las tres columnas del roster.
class _ParsedRow {
  const _ParsedRow({
    required this.code,
    required this.name,
    this.email,
  });

  final String code;
  final String name;
  final String? email;
}
