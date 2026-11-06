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
    );
  }

  @override
  String toString() {
    return 'StudentModel(id: $id, studentCode: $studentCode, bitIndex: $bitIndex)';
  }
}
