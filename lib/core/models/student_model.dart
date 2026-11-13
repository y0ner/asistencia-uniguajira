import '../constants/app_constants.dart';

/// Estudiante matriculado en un curso, con su posición fija en el Bitmap.
class StudentModel {
  const StudentModel({
    required this.id,
    required this.courseId,
    required this.studentCode,
    required this.fullName,
    required this.bitIndex,
    required this.personalSecret,
    this.email,
    this.enrolledAt,
    this.status = AppConstants.studentStatusActive,
    this.origin = AppConstants.studentOriginRoster,
    this.deviceKeyId,
    this.deviceBoundAt,
    this.retiredAt,
  });

  /// Construye el modelo a partir de una fila SQLite.
  factory StudentModel.fromMap(Map<String, Object?> map) {
    return StudentModel(
      id: map['id']! as String,
      courseId: map['course_id']! as String,
      studentCode: map['student_code']! as String,
      fullName: map['full_name']! as String,
      email: map['email'] as String?,
      bitIndex: map['bit_index']! as int,
      personalSecret: map['personal_secret']! as String,
      enrolledAt: map['enrolled_at'] as String?,
      status: map['status'] as String? ?? AppConstants.studentStatusActive,
      origin: map['origin'] as String? ?? AppConstants.studentOriginRoster,
      deviceKeyId: map['device_key_id'] as String?,
      deviceBoundAt: map['device_bound_at'] as String?,
      retiredAt: map['retired_at'] as String?,
    );
  }

  /// Identificador único (UUID).
  final String id;

  /// Curso al que pertenece el estudiante.
  final String courseId;

  /// Código institucional del estudiante.
  final String studentCode;

  /// Nombre completo del estudiante.
  final String fullName;

  /// Correo electrónico opcional.
  final String? email;

  /// Posición única en el Bitmap del curso (0..63).
  final int bitIndex;

  /// Secreto personal en hexadecimal derivado para firmar HMAC.
  final String personalSecret;

  /// Fecha de enrolamiento en formato ISO8601.
  final String? enrolledAt;

  /// `active` o `retired` (ver [AppConstants.studentStatusActive]).
  final String status;

  /// `roster` (venía en la lista) o `added_in_class` (lo agregó el docente al inscribirse).
  final String origin;

  /// Huella de la clave del celular vinculado; nula si aún no tiene celular.
  final String? deviceKeyId;

  /// Cuándo se vinculó el celular (ISO 8601).
  final String? deviceBoundAt;

  /// Cuándo fue retirado de la clase (ISO 8601).
  final String? retiredAt;

  bool get isActive => status == AppConstants.studentStatusActive;

  bool get isRetired => status == AppConstants.studentStatusRetired;

  /// `true` si ya vinculó un celular con el flujo de inscripción.
  bool get hasDevice => deviceKeyId != null && deviceKeyId!.isNotEmpty;

  bool get wasAddedInClass => origin == AppConstants.studentOriginAddedInClass;

  /// Serializa el modelo a una fila SQLite.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'course_id': courseId,
      'student_code': studentCode,
      'full_name': fullName,
      'email': email,
      'bit_index': bitIndex,
      'personal_secret': personalSecret,
      'enrolled_at': enrolledAt,
      'status': status,
      'origin': origin,
      'device_key_id': deviceKeyId,
      'device_bound_at': deviceBoundAt,
      'retired_at': retiredAt,
    };
  }

  /// Devuelve una copia con los campos indicados reemplazados.
  StudentModel copyWith({
    String? id,
    String? courseId,
    String? studentCode,
    String? fullName,
    String? email,
    int? bitIndex,
    String? personalSecret,
    String? enrolledAt,
    String? status,
    String? origin,
    String? deviceKeyId,
    String? deviceBoundAt,
    String? retiredAt,
  }) {
    return StudentModel(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      studentCode: studentCode ?? this.studentCode,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      bitIndex: bitIndex ?? this.bitIndex,
      personalSecret: personalSecret ?? this.personalSecret,
      enrolledAt: enrolledAt ?? this.enrolledAt,
      status: status ?? this.status,
      origin: origin ?? this.origin,
      deviceKeyId: deviceKeyId ?? this.deviceKeyId,
      deviceBoundAt: deviceBoundAt ?? this.deviceBoundAt,
      retiredAt: retiredAt ?? this.retiredAt,
    );
  }

  @override
  String toString() {
    return 'StudentModel(id: $id, studentCode: $studentCode, bitIndex: $bitIndex)';
  }
}
