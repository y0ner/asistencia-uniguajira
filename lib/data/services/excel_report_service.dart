import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../local/app_database.dart';

/// Estados de alerta académica calculados a partir de la inasistencia.
abstract final class AttendanceAlertStatus {
  /// El estudiante conserva una inasistencia inferior al 20 %.
  static const String normal = 'NORMAL';

  /// El estudiante está entre el 20 % y el 29.9 % de inasistencia.
  static const String attendanceAlert = 'ALERTA_INASISTENCIA';

  /// El estudiante alcanzó o superó el 30 % de inasistencia.
  static const String failureByAbsences = 'PERDIDA_POR_FALLAS';

  /// Alias corto de [attendanceAlert].
  static const String alert = attendanceAlert;

  /// Alias corto de [failureByAbsences].
  static const String lost = failureByAbsences;
}

/// Métricas consolidadas de un estudiante para el reporte de un curso.
class StudentAttendanceMetric {
  const StudentAttendanceMetric({
    required this.studentId,
    required this.bitIndex,
    required this.studentCode,
    required this.fullName,
    required this.email,
    required this.totalSessions,
    required this.bleAttendances,
    required this.manualAttendances,
    required this.totalAttendances,
    required this.totalAbsences,
    required this.attendancePercentage,
    required this.alertStatus,
  });

  /// Identificador local del estudiante.
  final String studentId;

  /// Posición fija en el Bitmap del curso (0..63).
  final int bitIndex;

  /// Código institucional conservado como texto.
  final String studentCode;

  /// Nombre completo del estudiante.
  final String fullName;

  /// Correo del estudiante, si está registrado.
  final String? email;

  /// Cantidad de sesiones cerradas incluidas en el cálculo.
  final int totalSessions;

  /// Asistencias registradas por proximidad BLE.
  final int bleAttendances;

  /// Asistencias registradas por la lista invertida manual.
  final int manualAttendances;

  /// Total de asistencias, sin importar el método.
  final int totalAttendances;

  /// Total de sesiones cerradas sin asistencia.
  final int totalAbsences;

  /// Porcentaje de asistencia (0..100), redondeado a dos decimales.
  final double attendancePercentage;

  /// Uno de los valores de [AttendanceAlertStatus].
  final String alertStatus;

  /// Alias de [totalSessions].
  int get totalClosedSessions => totalSessions;

  /// Alias semántico de [totalSessions].
  int get totalSessionsClosed => totalSessions;

  /// Alias de [bleAttendances].
  int get attendanceBle => bleAttendances;

  /// Alias de [manualAttendances].
  int get attendanceManualInverted => manualAttendances;

  /// Porcentaje de inasistencia, complementario a la asistencia.
  double get absencePercentage => 100.0 - attendancePercentage;

  /// Alias corto del estado de alerta.
  String get status => alertStatus;

  /// Indica si el estudiante está en el rango normal.
  bool get isNormal => alertStatus == AttendanceAlertStatus.normal;

  /// Indica si el estudiante requiere seguimiento por inasistencia.
  bool get requiresAttention =>
      alertStatus == AttendanceAlertStatus.attendanceAlert;

  /// Indica si el estudiante perdió la asignatura por fallas.
  bool get failedByAbsences =>
      alertStatus == AttendanceAlertStatus.failureByAbsences;

  /// Serializa las métricas para consumo de UI o exportación JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'studentId': studentId,
      'bitIndex': bitIndex,
      'studentCode': studentCode,
      'fullName': fullName,
      'email': email,
      'totalSessions': totalSessions,
      'bleAttendances': bleAttendances,
      'manualAttendances': manualAttendances,
      'totalAttendances': totalAttendances,
      'totalAbsences': totalAbsences,
      'attendancePercentage': attendancePercentage,
      'alertStatus': alertStatus,
    };
  }
}

/// Snapshot analítico e inmutable del reporte de un curso.
class CourseAttendanceSummary {
  CourseAttendanceSummary({
    required this.course,
    required this.teacherEmail,
    required this.totalSessions,
    required this.totalClosedSessions,
    required this.totalSignedActas,
    required this.reportHmacSha256,
    required this.generatedAtIso,
    required List<StudentAttendanceMetric> students,
    required Map<String, List<List<Object?>>> sheets,
  }) : students = List<StudentAttendanceMetric>.unmodifiable(students),
       sheets = _freezeSheets(sheets);

  /// Curso al que pertenece el reporte.
  final CourseModel course;

  /// Correo del docente configurado en el servicio; vacío si no se informó.
  final String teacherEmail;

  /// Cantidad total de sesiones del curso, cerradas o abiertas.
  final int totalSessions;

  /// Cantidad de sesiones con fecha de cierre.
  final int totalClosedSessions;

  /// Cantidad de actas criptográficas firmadas encontradas.
  final int totalSignedActas;

  /// HMAC-SHA256 de la concatenación ordenada de las firmas de las actas.
  final String reportHmacSha256;

  /// Instante de generación del snapshot en ISO8601 UTC.
  final String generatedAtIso;

  /// Métricas por estudiante ordenadas por [StudentAttendanceMetric.bitIndex].
  final List<StudentAttendanceMetric> students;

  /// Filas tabulares de las cuatro hojas, incluyendo el encabezado.
  final Map<String, List<List<Object?>>> sheets;

  /// Identificador del curso.
  String get courseId => course.id;

  /// Código institucional del curso.
  String get courseCode => course.code;

  /// Nombre del curso.
  String get courseName => course.name;

  /// Código del grupo.
  String get groupCode => course.groupCode;

  /// Alias de [groupCode].
  String get group => course.groupCode;

  /// Periodo académico.
  String get semester => course.semester;

  /// Alias de [students] para consumidores que los llaman métricas.
  List<StudentAttendanceMetric> get studentMetrics => students;

  /// Alias de [students].
  List<StudentAttendanceMetric> get metrics => students;

  /// Cantidad de estudiantes matriculados.
  int get totalStudents => students.length;

  /// Alias de [totalStudents].
  int get totalEnrolled => students.length;

  /// Alias de [totalClosedSessions].
  int get totalSessionsClosed => totalClosedSessions;

  /// Alias de [totalSignedActas].
  int get signedActaCount => totalSignedActas;

  /// Alias de la huella criptográfica del reporte.
  String get reportSignatureHmac => reportHmacSha256;

  /// Serializa el resumen analítico y las tablas a JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'courseId': course.id,
      'courseCode': course.code,
      'courseName': course.name,
      'groupCode': course.groupCode,
      'semester': course.semester,
      'teacherEmail': teacherEmail,
      'totalStudents': students.length,
      'totalSessions': totalSessions,
      'totalClosedSessions': totalClosedSessions,
      'totalSignedActas': totalSignedActas,
      'reportHmacSha256': reportHmacSha256,
      'generatedAtIso': generatedAtIso,
      'students': students
          .map((StudentAttendanceMetric metric) => metric.toJson())
          .toList(growable: false),
      'sheets': <String, Object?>{
        for (final MapEntry<String, List<List<Object?>>> entry
            in sheets.entries)
          entry.key: entry.value
              .map((List<Object?> row) => List<Object?>.of(row))
              .toList(growable: false),
      },
    };
  }
}

/// Genera el libro oficial de asistencia de la Universidad de La Guajira.
///
/// El reporte se construye desde SQLite y contiene exactamente cuatro hojas:
/// `Resumen`, `Detalle`, `Sesiones` y `Metadatos`.
class ExcelReportService {
  ExcelReportService({AppDatabase? database, String teacherEmail = ''})
    : _database = database ?? AppDatabase.instance,
      _teacherEmail = teacherEmail.trim();

  final AppDatabase _database;
  final String _teacherEmail;

  /// Base de datos utilizada por el generador.
  AppDatabase get database => _database;

  /// Correo docente incluido en la hoja de metadatos.
  String get teacherEmail => _teacherEmail;

  /// Construye y codifica el libro `.xlsx` oficial de un curso.
  Future<Uint8List> generateCourseAttendanceWorkbook(String courseId) async {
    final summary = await buildCourseSummary(courseId);
    return generateWorkbookFromSummary(summary);
  }

  /// Codifica en `.xlsx` un snapshot previamente calculado.
  ///
  /// Se expone para que la sincronización use exactamente el mismo contenido
  /// firmado que se muestra en pantalla, sin volver a consultar SQLite.
  Uint8List generateWorkbookFromSummary(CourseAttendanceSummary summary) {
    final workbook = Excel.createExcel();
    final requiredSheets = <String>[
      _summarySheet,
      _detailSheet,
      _sessionsSheet,
      _metadataSheet,
    ];

    for (final String sheetName in requiredSheets) {
      workbook[sheetName];
    }

    // Excel.createExcel() crea `Sheet1` por defecto. Se elimina cualquier hoja
    // que no pertenezca a las cuatro hojas reglamentarias.
    final allowed = requiredSheets.toSet();
    for (final String existingSheet in workbook.tables.keys.toList(
      growable: false,
    )) {
      if (!allowed.contains(existingSheet)) {
        workbook.delete(existingSheet);
      }
    }

    for (final String sheetName in requiredSheets) {
      final sheet = workbook[sheetName];
      final rows = summary.sheets[sheetName] ?? const <List<Object?>>[];
      for (final List<Object?> row in rows) {
        sheet.appendRow(row.map(_toCellValue).toList(growable: false));
      }
    }

    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('No fue posible codificar el libro Excel del curso.');
    }
    return Uint8List.fromList(encoded);
  }

  /// Guarda el libro en [directoryPath] con el nombre oficial normalizado.
  ///
  /// Retorna la ruta absoluta del archivo generado.
  Future<String> exportWorkbookToFile({
    required String courseId,
    required String directoryPath,
  }) async {
    final normalizedDirectory = directoryPath.trim();
    if (normalizedDirectory.isEmpty) {
      throw ArgumentError.value(
        directoryPath,
        'directoryPath',
        'El directorio de exportación no puede estar vacío.',
      );
    }

    final summary = await buildCourseSummary(courseId);
    final bytes = generateWorkbookFromSummary(summary);
    final directory = Directory(normalizedDirectory);
    await directory.create(recursive: true);

    final fileName = exportFileNameFor(summary.course);
    final file = File(p.join(directory.absolute.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.absolute.path;
  }

  /// Calcula el resumen analítico y las cuatro tablas oficiales del curso.
  Future<CourseAttendanceSummary> buildCourseSummary(String courseId) async {
    final normalizedCourseId = courseId.trim();
    if (normalizedCourseId.isEmpty) {
      throw ArgumentError.value(
        courseId,
        'courseId',
        'El identificador del curso no puede estar vacío.',
      );
    }

    final course = await _database.getCourseById(normalizedCourseId);
    if (course == null) {
      throw StateError('No existe el curso $normalizedCourseId.');
    }

    final students =
        List<StudentModel>.of(await _database.getStudentsByCourse(course.id))
          ..sort(
            (StudentModel left, StudentModel right) =>
                left.bitIndex.compareTo(right.bitIndex),
          );
    final sessions = List<SessionModel>.of(
      await _database.getSessionsByCourse(course.id),
    )..sort(_compareSessionsChronologically);

    final snapshots = <_SessionSnapshot>[];
    for (final SessionModel session in sessions) {
      final records =
          List<AttendanceRecordModel>.of(
            await _database.getAttendanceRecordsBySession(session.id),
          )..sort(
            (AttendanceRecordModel left, AttendanceRecordModel right) =>
                left.bitIndex.compareTo(right.bitIndex),
          );
      final actaJson = await _database.getSessionActaJson(session.id);
      final storedSignature = await _database.getSessionActaSignature(
        session.id,
      );
      final acta = _decodeActa(actaJson);
      final signature = (storedSignature?.trim().isNotEmpty ?? false)
          ? storedSignature!.trim()
          : _readString(acta?['actaHmacSignature']) ?? '';

      snapshots.add(
        _SessionSnapshot(
          session: session,
          records: records,
          acta: acta,
          signature: signature,
          totalEnrolled: students.length,
        ),
      );
    }

    final closedSnapshots = snapshots
        .where((_SessionSnapshot snapshot) => snapshot.isClosed)
        .toList(growable: false);
    final signatures = snapshots
        .map((_SessionSnapshot snapshot) => snapshot.signature)
        .where((String signature) => signature.isNotEmpty)
        .toList(growable: false);
    final generatedAtIso = DateTime.now().toUtc().toIso8601String();
    final reportHmacSha256 = _buildReportHmac(course.courseSecret, signatures);

    final metrics = <StudentAttendanceMetric>[];
    for (final StudentModel student in students) {
      var bleAttendances = 0;
      var manualAttendances = 0;
      var totalAttendances = 0;

      for (final _SessionSnapshot snapshot in closedSnapshots) {
        final record = snapshot.recordsByStudentId[student.id];
        if (record == null) {
          continue;
        }
        totalAttendances++;
        if (record.method == AppConstants.attendanceMethodBleHmac) {
          bleAttendances++;
        } else {
          manualAttendances++;
        }
      }

      final totalAbsences = closedSnapshots.length - totalAttendances;
      final attendancePercentage = closedSnapshots.isEmpty
          ? 100.0
          : _round2(totalAttendances / closedSnapshots.length * 100.0);
      final absencePercentage = closedSnapshots.isEmpty
          ? 0.0
          : 100.0 - (totalAttendances / closedSnapshots.length * 100.0);

      metrics.add(
        StudentAttendanceMetric(
          studentId: student.id,
          bitIndex: student.bitIndex,
          studentCode: student.studentCode,
          fullName: student.fullName,
          email: student.email,
          totalSessions: closedSnapshots.length,
          bleAttendances: bleAttendances,
          manualAttendances: manualAttendances,
          totalAttendances: totalAttendances,
          totalAbsences: totalAbsences,
          attendancePercentage: attendancePercentage,
          alertStatus: _alertStatusForAbsence(absencePercentage),
        ),
      );
    }

    final summaryRows = <List<Object?>>[
      <Object?>[
        'BitIndex',
        'CodigoEstudiantil',
        'NombreCompleto',
        'Email',
        'TotalSesionesCerradas',
        'AsistenciasBLE',
        'AsistenciasManualInvertida',
        'TotalAsistencias',
        'TotalInasistencias',
        'PorcentajeAsistencia',
        'EstadoAlerta',
      ],
      for (final StudentAttendanceMetric metric in metrics)
        <Object?>[
          metric.bitIndex,
          metric.studentCode,
          metric.fullName,
          metric.email ?? '',
          metric.totalSessions,
          metric.bleAttendances,
          metric.manualAttendances,
          metric.totalAttendances,
          metric.totalAbsences,
          metric.attendancePercentage,
          metric.alertStatus,
        ],
    ];

    final detailRows = <List<Object?>>[
      <Object?>[
        'SesionID',
        'FechaApertura',
        'FechaCierre',
        'BitIndex',
        'CodigoEstudiantil',
        'NombreCompleto',
        'EstadoAsistencia',
        'MetodoRegistro',
        'RssiDbm',
        'TimeTick',
        'Observacion',
      ],
    ];
    final studentsById = <String, StudentModel>{
      for (final StudentModel student in students) student.id: student,
    };

    for (final _SessionSnapshot snapshot in snapshots) {
      if (snapshot.isClosed) {
        for (final StudentModel student in students) {
          final record = snapshot.recordsByStudentId[student.id];
          final present = record != null;
          detailRows.add(<Object?>[
            snapshot.session.id,
            snapshot.session.startedAt,
            snapshot.closedAtIso,
            student.bitIndex,
            student.studentCode,
            student.fullName,
            present
                ? AppConstants.attendanceStatusPresent
                : AppConstants.attendanceStatusAbsent,
            record?.method ?? '',
            record?.rssiAvg ?? '',
            record?.timeTick ?? '',
            record?.observation ?? '',
          ]);
        }
        continue;
      }

      // Una sesión abierta aún no tiene estado final de ausencia. Se listan
      // únicamente las asistencias ya persistidas para no reportar faltas
      // prematuras como si la sesión estuviera cerrada.
      for (final AttendanceRecordModel record in snapshot.records) {
        final student = studentsById[record.studentId];
        if (student == null) {
          continue;
        }
        detailRows.add(<Object?>[
          snapshot.session.id,
          snapshot.session.startedAt,
          '',
          student.bitIndex,
          student.studentCode,
          student.fullName,
          AppConstants.attendanceStatusPresent,
          record.method,
          record.rssiAvg ?? '',
          record.timeTick ?? '',
          record.observation ?? '',
        ]);
      }
    }

    final sessionRows = <List<Object?>>[
      <Object?>[
        'SesionID',
        'CursoID',
        'FechaApertura',
        'FechaCierre',
        'EstadoSesion',
        'PinVerbal',
        'BitmapHexFinal',
        'TotalPresentesBLE',
        'TotalManualInvertida',
        'TotalAusentes',
        'HashActaHmacSha256',
      ],
      for (final _SessionSnapshot snapshot in snapshots)
        <Object?>[
          snapshot.session.id,
          snapshot.session.courseId,
          snapshot.session.startedAt,
          snapshot.closedAtIso,
          snapshot.isClosed ? 'CERRADA' : 'ABIERTA',
          snapshot.session.roomPin,
          snapshot.bitmapHex,
          snapshot.presentBleCount,
          snapshot.presentManualCount,
          snapshot.absentCount,
          snapshot.signature,
        ],
    ];

    final metadataRows = <List<Object?>>[
      <Object?>['Clave', 'Valor'],
      <Object?>['Institucion', 'Universidad de La Guajira'],
      <Object?>[
        'Sistema',
        'Asistencia Multimodal Uniguajira (BLE + Mapa de Bits 8B)',
      ],
      <Object?>['CursoID', course.id],
      <Object?>['CodigoCurso', course.code],
      <Object?>['NombreCurso', course.name],
      <Object?>['Grupo', course.groupCode],
      <Object?>['Semestre', course.semester],
      <Object?>['DocenteEmail', _teacherEmail],
      <Object?>['TotalEstudiantesMatriculados', students.length],
      <Object?>['CupoMaximoBitmap', AppConstants.bitmapBitCount],
      <Object?>['TotalSesionesCerradas', closedSnapshots.length],
      <Object?>['TotalActasFirmadas', signatures.length],
      <Object?>['FechaGeneracionISO8601', generatedAtIso],
      <Object?>['HuellaIntegridadReporteHmacSha256', reportHmacSha256],
    ];

    return CourseAttendanceSummary(
      course: course,
      teacherEmail: _teacherEmail,
      totalSessions: snapshots.length,
      totalClosedSessions: closedSnapshots.length,
      totalSignedActas: signatures.length,
      reportHmacSha256: reportHmacSha256,
      generatedAtIso: generatedAtIso,
      students: metrics,
      sheets: <String, List<List<Object?>>>{
        _summarySheet: summaryRows,
        _detailSheet: detailRows,
        _sessionsSheet: sessionRows,
        _metadataSheet: metadataRows,
      },
    );
  }

  static const String _summarySheet = 'Resumen';
  static const String _detailSheet = 'Detalle';
  static const String _sessionsSheet = 'Sesiones';
  static const String _metadataSheet = 'Metadatos';

  static int _compareSessionsChronologically(
    SessionModel left,
    SessionModel right,
  ) {
    final leftDate = DateTime.tryParse(left.startedAt);
    final rightDate = DateTime.tryParse(right.startedAt);
    final int comparison;
    if (leftDate != null && rightDate != null) {
      comparison = leftDate.compareTo(rightDate);
    } else {
      comparison = left.startedAt.compareTo(right.startedAt);
    }
    if (comparison != 0) {
      return comparison;
    }
    return left.id.compareTo(right.id);
  }

  static String _buildReportHmac(String courseSecret, List<String> signatures) {
    final orderedSignatures = List<String>.of(signatures)..sort();
    return Hmac(
      sha256,
      utf8.encode(courseSecret.toLowerCase()),
    ).convert(utf8.encode(orderedSignatures.join())).toString();
  }

  static String _alertStatusForAbsence(double absencePercentage) {
    if (absencePercentage < 20.0) {
      return AttendanceAlertStatus.normal;
    }
    if (absencePercentage < 30.0) {
      return AttendanceAlertStatus.attendanceAlert;
    }
    return AttendanceAlertStatus.failureByAbsences;
  }

  static double _round2(double value) {
    return (value * 100.0).roundToDouble() / 100.0;
  }

  static CellValue _toCellValue(Object? value) {
    if (value is int) {
      return IntCellValue(value);
    }
    if (value is double) {
      return DoubleCellValue(value);
    }
    if (value is bool) {
      return BoolCellValue(value);
    }
    return TextCellValue(value?.toString() ?? '');
  }

  /// Nombre del archivo Excel que [exportWorkbookToFile] genera para [course].
  ///
  /// Es fijo por curso y grupo: cada exportación sobrescribe la anterior.
  static String exportFileNameFor(CourseModel course) {
    final courseCode = _sanitizeFileSegment(course.code);
    final groupCode = _sanitizeFileSegment(course.groupCode);
    return 'Asistencia_Uniguajira_${courseCode}_$groupCode.xlsx';
  }

  static String _sanitizeFileSegment(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'SIN_DATO' : sanitized;
  }

  static Map<String, dynamic>? _decodeActa(String? actaJson) {
    if (actaJson == null || actaJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(actaJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return <String, dynamic>{
          for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _readString(Object? value) {
    if (value is String) {
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class _SessionSnapshot {
  _SessionSnapshot({
    required this.session,
    required List<AttendanceRecordModel> records,
    required this.acta,
    required this.signature,
    required this.totalEnrolled,
  }) : records = List<AttendanceRecordModel>.unmodifiable(records),
       recordsByStudentId = Map<String, AttendanceRecordModel>.unmodifiable(
         <String, AttendanceRecordModel>{
           for (final AttendanceRecordModel record in records)
             record.studentId: record,
         },
       );

  final SessionModel session;
  final List<AttendanceRecordModel> records;
  final Map<String, AttendanceRecordModel> recordsByStudentId;
  final Map<String, dynamic>? acta;
  final String signature;
  final int totalEnrolled;

  bool get isClosed => session.closedAt != null || acta != null;

  String get closedAtIso =>
      session.closedAt ??
      ExcelReportService._readString(acta?['closedAtIso']) ??
      '';

  String get bitmapHex =>
      ExcelReportService._readString(acta?['bitmapHex']) ?? session.bitmapHex;

  int get presentBleCount {
    final signed = ExcelReportService._readInt(acta?['presentBleCount']);
    if (signed != null) {
      return signed;
    }
    return records
        .where(
          (AttendanceRecordModel record) =>
              record.method == AppConstants.attendanceMethodBleHmac,
        )
        .length;
  }

  int get presentManualCount {
    final signed = ExcelReportService._readInt(acta?['presentManualCount']);
    if (signed != null) {
      return signed;
    }
    return records
        .where(
          (AttendanceRecordModel record) =>
              record.method == AppConstants.attendanceMethodManualInverted,
        )
        .length;
  }

  int get absentCount {
    final signed = ExcelReportService._readInt(acta?['absentCount']);
    if (signed != null) {
      return signed;
    }
    final present = presentBleCount + presentManualCount;
    final absent = totalEnrolled - present;
    return absent < 0 ? 0 : absent;
  }
}

Map<String, List<List<Object?>>> _freezeSheets(
  Map<String, List<List<Object?>>> sheets,
) {
  final frozen = <String, List<List<Object?>>>{};
  for (final MapEntry<String, List<List<Object?>>> entry in sheets.entries) {
    frozen[entry.key] = List<List<Object?>>.unmodifiable(
      entry.value
          .map((List<Object?> row) => List<Object?>.unmodifiable(row))
          .toList(growable: false),
    );
  }
  return Map<String, List<List<Object?>>>.unmodifiable(frozen);
}
