/// Curso o grupo académico importado por el docente.
///
/// Contrato inmutable compartido por las capas de datos y de presentación.
class CourseModel {
  const CourseModel({
    required this.id,
    required this.code,
    required this.name,
    required this.groupCode,
    required this.semester,
    required this.courseSecret,
    required this.createdAt,
    this.spreadsheetId,
  });

  /// Construye el modelo a partir de una fila SQLite.
  factory CourseModel.fromMap(Map<String, Object?> map) {
    return CourseModel(
      id: map['id']! as String,
      code: map['code']! as String,
      name: map['name']! as String,
      groupCode: map['group_code']! as String,
      semester: map['semester']! as String,
      courseSecret: map['course_secret']! as String,
      spreadsheetId: map['spreadsheet_id'] as String?,
      createdAt: map['created_at']! as String,
    );
  }

  /// Identificador único (UUID).
  final String id;

  /// Código institucional de la asignatura.
  final String code;

  /// Nombre de la asignatura.
  final String name;

  /// Código del grupo (por ejemplo, `01`).
  final String groupCode;

  /// Periodo académico (por ejemplo, `2026-2`).
  final String semester;

  /// Secreto del curso en hexadecimal (32 bytes) para firmar HMAC.
  final String courseSecret;

  /// Hoja de cálculo opcional de Google Sheets asociada al curso.
  final String? spreadsheetId;

  /// Fecha de creación en formato ISO8601.
  final String createdAt;

  /// Serializa el modelo a una fila SQLite.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'code': code,
      'name': name,
      'group_code': groupCode,
      'semester': semester,
      'course_secret': courseSecret,
      'spreadsheet_id': spreadsheetId,
      'created_at': createdAt,
    };
  }

  /// Devuelve una copia con los campos indicados reemplazados.
  CourseModel copyWith({
    String? id,
    String? code,
    String? name,
    String? groupCode,
    String? semester,
    String? courseSecret,
    String? spreadsheetId,
    String? createdAt,
  }) {
    return CourseModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      groupCode: groupCode ?? this.groupCode,
      semester: semester ?? this.semester,
      courseSecret: courseSecret ?? this.courseSecret,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'CourseModel(id: $id, code: $code, groupCode: $groupCode)';
  }
}
