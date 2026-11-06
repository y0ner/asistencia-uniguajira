/// Registro individual de asistencia de un estudiante dentro de una sesión.
class AttendanceRecordModel {
  const AttendanceRecordModel({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.bitIndex,
    required this.method,
    required this.recordedAt,
    this.rssiAvg,
    this.hmacTag,
    this.timeTick,
    this.observation,
  });

  /// Construye el modelo a partir de una fila SQLite.
  factory AttendanceRecordModel.fromMap(Map<String, Object?> map) {
    return AttendanceRecordModel(
      id: map['id']! as String,
      sessionId: map['session_id']! as String,
      studentId: map['student_id']! as String,
      bitIndex: map['bit_index']! as int,
      method: map['method']! as String,
      rssiAvg: (map['rssi_avg'] as num?)?.toDouble(),
      recordedAt: map['recorded_at']! as String,
      hmacTag: map['hmac_tag'] as String?,
      timeTick: map['time_tick'] as int?,
      observation: map['observation'] as String?,
    );
  }

  /// Identificador único (UUID).
  final String id;

  /// Sesión en la que se registró la asistencia.
  final String sessionId;

  /// Estudiante registrado.
  final String studentId;

  /// Posición del estudiante en el Bitmap de la sesión (0..63).
  final int bitIndex;

  /// Método de registro: `BLE_HMAC` o `MANUAL_INVERTED`.
  final String method;

  /// Promedio de RSSI observado durante la proximidad BLE.
  final double? rssiAvg;

  /// Fecha y hora del registro en formato ISO8601.
  final String recordedAt;

  /// Etiqueta HMAC-SHA256 que respalda el registro BLE.
  final String? hmacTag;

  /// Tick de la ventana HMAC en la que se aceptó el anuncio BLE.
  final int? timeTick;

  /// Observación escrita por el docente al usar la lista invertida.
  final String? observation;

  /// Serializa el modelo a una fila SQLite.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'session_id': sessionId,
      'student_id': studentId,
      'bit_index': bitIndex,
      'method': method,
      'rssi_avg': rssiAvg,
      'recorded_at': recordedAt,
      'hmac_tag': hmacTag,
      'time_tick': timeTick,
      'observation': observation,
    };
  }

  /// Devuelve una copia con los campos indicados reemplazados.
  AttendanceRecordModel copyWith({
    String? id,
    String? sessionId,
    String? studentId,
    int? bitIndex,
    String? method,
    double? rssiAvg,
    String? recordedAt,
    String? hmacTag,
    int? timeTick,
    String? observation,
  }) {
    return AttendanceRecordModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentId: studentId ?? this.studentId,
      bitIndex: bitIndex ?? this.bitIndex,
      method: method ?? this.method,
      rssiAvg: rssiAvg ?? this.rssiAvg,
      recordedAt: recordedAt ?? this.recordedAt,
      hmacTag: hmacTag ?? this.hmacTag,
      timeTick: timeTick ?? this.timeTick,
      observation: observation ?? this.observation,
    );
  }

  @override
  String toString() {
    return 'AttendanceRecordModel(id: $id, sessionId: $sessionId, method: $method)';
  }
}
