import '../constants/app_constants.dart';

/// Sesión de clase registrada por el docente para un curso.
class SessionModel {
  const SessionModel({
    required this.id,
    required this.courseId,
    required this.startedAt,
    required this.roomPin,
    this.closedAt,
    this.bitmapHex = AppConstants.emptyBitmapHex,
    this.actHash,
    this.syncedToCloud = 0,
  });

  /// Construye el modelo a partir de una fila SQLite.
  factory SessionModel.fromMap(Map<String, Object?> map) {
    return SessionModel(
      id: map['id']! as String,
      courseId: map['course_id']! as String,
      startedAt: map['started_at']! as String,
      closedAt: map['closed_at'] as String?,
      roomPin: map['room_pin']! as String,
      bitmapHex: map['bitmap_hex']! as String,
      actHash: map['act_hash'] as String?,
      syncedToCloud: map['synced_to_cloud']! as int,
    );
  }

  /// Identificador único (UUID).
  final String id;

  /// Curso al que pertenece la sesión.
  final String courseId;

  /// Inicio de la sesión en formato ISO8601.
  final String startedAt;

  /// Cierre de la sesión en formato ISO8601; `null` mientras está abierta.
  final String? closedAt;

  /// PIN verbal de 2 dígitos que evita el fraude de pasillo.
  final String roomPin;

  /// Mapa de bits de 8 bytes en hexadecimal (16 caracteres).
  final String bitmapHex;

  /// SHA-256 del acta cerrada.
  final String? actHash;

  /// Indicador de sincronización con la nube (0 = pendiente, 1 = sincronizada).
  final int syncedToCloud;

  /// Serializa el modelo a una fila SQLite.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'course_id': courseId,
      'started_at': startedAt,
      'closed_at': closedAt,
      'room_pin': roomPin,
      'bitmap_hex': bitmapHex,
      'act_hash': actHash,
      'synced_to_cloud': syncedToCloud,
    };
  }

  /// Devuelve una copia con los campos indicados reemplazados.
  SessionModel copyWith({
    String? id,
    String? courseId,
    String? startedAt,
    String? closedAt,
    String? roomPin,
    String? bitmapHex,
    String? actHash,
    int? syncedToCloud,
  }) {
    return SessionModel(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      startedAt: startedAt ?? this.startedAt,
      closedAt: closedAt ?? this.closedAt,
      roomPin: roomPin ?? this.roomPin,
      bitmapHex: bitmapHex ?? this.bitmapHex,
      actHash: actHash ?? this.actHash,
      syncedToCloud: syncedToCloud ?? this.syncedToCloud,
    );
  }

  @override
  String toString() {
    return 'SessionModel(id: $id, courseId: $courseId, roomPin: $roomPin)';
  }
}
