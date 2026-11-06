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

  /// Longitud del PIN verbal de la sesión (2 dígitos).
  static const int roomPinLength = 2;

  /// Método de registro por proximidad criptográfica BLE.
  static const String attendanceMethodBleHmac = 'BLE_HMAC';

  /// Método de registro manual desde la lista invertida de excepción.
  static const String attendanceMethodManualInverted = 'MANUAL_INVERTED';

  /// Nombre del archivo SQLite local.
  static const String databaseName = 'asistencia_uniguajira.db';

  /// Versión del esquema SQLite.
  static const int databaseVersion = 1;
}
