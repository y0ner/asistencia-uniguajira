/// Constantes globales del dominio de asistencia de Uniguajira.
///
/// Centraliza los parámetros del protocolo (ventana HMAC, tamaño del Bitmap,
/// umbral de proximidad y dominio institucional) para que ninguna capa
/// introduzca valores mágicos.
abstract final class AppConstants {
  /// Nombre visible de la aplicación.
  static const String appName = 'Asistencia Uniguajira';

  /// Dominio institucional autorizado para la sincronización con Google.
  static const String institutionalDomain = '@uniguajira.edu.co';

  /// Ventana de rotación de la etiqueta HMAC-SHA256, en segundos.
  static const int hmacRotationSeconds = 30;

  /// Alias de la ventana HMAC usado por el protocolo BLE de 16 bytes.
  static const int hmacWindowSeconds = hmacRotationSeconds;

  /// Cantidad de posiciones del mapa de bits de asistencia (64 bits).
  static const int bitmapBitCount = 64;

  /// Tamaño del mapa de bits de asistencia, en bytes (8 bytes = 64 bits).
  static const int bitmapByteLength = 8;

  /// Longitud de la representación hexadecimal del mapa de bits (16 caracteres).
  static const int bitmapHexLength = 16;

  /// Mapa de bits sin posiciones marcadas.
  static const String emptyBitmapHex = '0000000000000000';

  /// Posición máxima válida dentro del mapa de bits.
  static const int maxBitIndex = bitmapBitCount - 1;

  /// RSSI mínimo aceptado por defecto para considerar proximidad real (-75 dBm).
  static const int defaultMinRssi = -75;

  /// Alias del umbral de proximidad usado por el escáner BLE.
  static const int minRssiDbm = defaultMinRssi;

  /// Longitud del PIN verbal de la sesión (2 dígitos).
  /// Umbral de señal para la inscripción: basta con estar en el salón (la
  /// asistencia sí exige cercanía con [minRssiDbm]).
  static const int enrollmentMinRssiDbm = -95;

  static const int roomPinLength = 2;

  /// PIN verbal mínimo que puede generar el docente.
  static const int minimumSessionPin = 10;

  /// PIN verbal máximo que puede generar el docente.
  static const int maximumSessionPin = 99;

  /// Intervalo de reemisión del eco docente con el Bitmap actualizado.
  static const int teacherEchoIntervalSeconds = 1;

  /// Método de registro por proximidad criptográfica BLE.
  static const String attendanceMethodBleHmac = 'BLE_HMAC';

  /// Método de registro manual desde la lista invertida de excepción.
  static const String attendanceMethodManualInverted = 'MANUAL_INVERTED';

  /// Estado de un estudiante presente en el acta de cierre.
  /// Estado de un estudiante dentro de la clase.
  static const String studentStatusActive = 'active';
  static const String studentStatusRetired = 'retired';

  /// Cómo llegó el estudiante a la clase.
  static const String studentOriginRoster = 'roster';
  static const String studentOriginAddedInClass = 'added_in_class';

  static const String attendanceStatusPresent = 'PRESENT';

  /// Estado de un estudiante ausente en el acta de cierre.
  static const String attendanceStatusAbsent = 'ABSENT';

  /// Nombre del archivo SQLite local.
  static const String databaseName = 'asistencia_uniguajira.db';

  /// Versión del esquema SQLite.
  static const int databaseVersion = 4;
}
