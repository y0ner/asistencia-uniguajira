import 'dart:convert';

/// Credencial local que el teléfono del estudiante conserva tras escanear el
/// QR de enrolamiento del primer día de clase.
///
/// El [id] se deriva como `courseId_studentCode` para que una recarga del QR
/// reemplace la misma credencial en lugar de duplicarla. Las semillas se
/// mantienen como texto hexadecimal y el código estudiantil nunca se convierte
/// a número, preservando los ceros a la izquierda.
class StudentEnrollmentModel {
  const StudentEnrollmentModel({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.studentId,
    required this.studentCode,
    required this.fullName,
    required this.bitIndex,
    required this.deviceSecret,
    required this.sharedSecret,
    required this.enrolledAtEpochMs,
  }) : assert(
         bitIndex >= 0 && bitIndex <= 63,
         'bitIndex debe estar entre 0 y 63.',
       );

  /// Reconstruye la credencial desde una fila SQLite.
  factory StudentEnrollmentModel.fromMap(Map<String, dynamic> map) {
    final bitIndex = _readInt(map, <String>[
      'bit_index',
      'bitmapIndex',
      'bitIndex',
    ]);
    return _validated(
      id: _readString(map, const <String>['id']),
      courseId: _readString(map, const <String>['course_id', 'courseId']),
      courseCode: _readString(map, const <String>['course_code', 'courseCode']),
      courseName: _readString(map, const <String>['course_name', 'courseName']),
      studentId: _readString(map, const <String>['student_id', 'studentId']),
      studentCode: _readString(map, const <String>[
        'student_code',
        'studentCode',
      ]),
      fullName: _readString(map, const <String>['full_name', 'fullName']),
      bitIndex: bitIndex,
      deviceSecret: _readString(map, const <String>[
        'device_secret',
        'deviceSecret',
      ]),
      sharedSecret: _readString(map, const <String>[
        'shared_secret',
        'sharedSecret',
      ]),
      enrolledAtEpochMs: _readInt(map, const <String>[
        'enrolled_at_epoch_ms',
        'enrolledAtEpochMs',
      ]),
    );
  }

  /// Reconstruye la credencial desde el JSON compacto que genera
  /// `RosterImportService.generateEnrollmentQrPayload`.
  ///
  /// El QR no transporta la fecha de enrolamiento, por lo que se usa el
  /// instante de lectura como sello local.
  factory StudentEnrollmentModel.fromQrPayloadJson(String qrJsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(qrJsonString);
    } on FormatException catch (error) {
      throw FormatException(
        'El QR no contiene JSON válido: ${error.message}',
        qrJsonString,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El QR de Asistencia Uniguajira debe contener un objeto JSON.',
      );
    }

    final courseId = _readString(decoded, const <String>['courseId']);
    final studentCode = _readString(decoded, const <String>['studentCode']);
    return _validated(
      id: '${courseId}_$studentCode',
      courseId: courseId,
      courseCode: _readString(decoded, const <String>['courseCode']),
      courseName: _readString(decoded, const <String>['courseName']),
      studentId: _readString(decoded, const <String>['studentId']),
      studentCode: studentCode,
      fullName: _readString(decoded, const <String>['fullName']),
      bitIndex: _readInt(decoded, const <String>['bitmapIndex', 'bitIndex']),
      deviceSecret: _readString(decoded, const <String>['deviceSecret']),
      sharedSecret: _readString(decoded, const <String>['sharedSecret']),
      enrolledAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Identificador local de la credencial (`courseId_studentCode`).
  final String id;

  /// Curso al que pertenece la credencial.
  final String courseId;

  /// Código institucional de la asignatura.
  final String courseCode;

  /// Nombre de la asignatura.
  final String courseName;

  /// Identificador del estudiante en la base del curso.
  final String studentId;

  /// Código estudiantil, conservado como texto con sus ceros a la izquierda.
  final String studentCode;

  /// Nombre completo normalizado del estudiante.
  final String fullName;

  /// Posición fija del estudiante en el Bitmap (0..63).
  final int bitIndex;

  /// Secreto individual del estudiante en hexadecimal.
  final String deviceSecret;

  /// Secreto compartido del curso en hexadecimal.
  final String sharedSecret;

  /// Instante de enrolamiento local, en milisegundos desde la época UNIX.
  final int enrolledAtEpochMs;

  /// Alias usado por el protocolo BLE para la posición en el Bitmap.
  int get bitmapIndex => bitIndex;

  /// Serializa la credencial a una fila SQLite.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'course_id': courseId,
      'course_code': courseCode,
      'course_name': courseName,
      'student_id': studentId,
      'student_code': studentCode,
      'full_name': fullName,
      'bit_index': bitIndex,
      'device_secret': deviceSecret,
      'shared_secret': sharedSecret,
      'enrolled_at_epoch_ms': enrolledAtEpochMs,
    };
  }

  /// Serializa la credencial con el mismo contrato del QR de enrolamiento.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'courseId': courseId,
      'courseCode': courseCode,
      'courseName': courseName,
      'studentId': studentId,
      'studentCode': studentCode,
      'fullName': fullName,
      'bitmapIndex': bitIndex,
      'deviceSecret': deviceSecret,
      'sharedSecret': sharedSecret,
    };
  }

  static StudentEnrollmentModel _validated({
    required String id,
    required String courseId,
    required String courseCode,
    required String courseName,
    required String studentId,
    required String studentCode,
    required String fullName,
    required int bitIndex,
    required String deviceSecret,
    required String sharedSecret,
    required int enrolledAtEpochMs,
  }) {
    if (bitIndex < 0 || bitIndex > 63) {
      throw FormatException(
        'El QR tiene bitmapIndex $bitIndex; debe estar entre 0 y 63.',
      );
    }
    if (enrolledAtEpochMs < 0) {
      throw const FormatException(
        'La fecha de enrolamiento no puede ser negativa.',
      );
    }
    return StudentEnrollmentModel(
      id: id,
      courseId: courseId,
      courseCode: courseCode,
      courseName: courseName,
      studentId: studentId,
      studentCode: studentCode,
      fullName: fullName,
      bitIndex: bitIndex,
      deviceSecret: deviceSecret,
      sharedSecret: sharedSecret,
      enrolledAtEpochMs: enrolledAtEpochMs,
    );
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    throw FormatException(
      'El QR de Asistencia Uniguajira no contiene "${keys.first}" o está vacío.',
    );
  }

  static int _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final Object? value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num && value == value.roundToDouble()) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    throw FormatException(
      'El QR de Asistencia Uniguajira no contiene "${keys.first}" como entero.',
    );
  }

  @override
  String toString() {
    return 'StudentEnrollmentModel(id: $id, studentCode: $studentCode, '
        'bitIndex: $bitIndex)';
  }
}
