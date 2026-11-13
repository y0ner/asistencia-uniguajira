import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';

/// Resultado de validar un anuncio de 16 bytes emitido por un estudiante.
class StudentBeaconVerificationResult {
  const StudentBeaconVerificationResult({
    required this.isValid,
    this.bitIndex,
    this.timeTick,
    this.failureReason,
  });

  /// `true` solo si firma, curso, PIN y ventana temporal coinciden.
  final bool isValid;

  /// Posición del estudiante en el Bitmap, cuando el paquete la contiene.
  final int? bitIndex;

  /// Tick de 30 segundos incluido en el anuncio.
  final int? timeTick;

  /// Motivo del rechazo; `null` cuando [isValid] es `true`.
  final String? failureReason;
}

/// Resultado de validar un paquete de eco emitido por el docente.
class TeacherEchoVerificationResult {
  const TeacherEchoVerificationResult({
    required this.isValid,
    this.bitmap8,
    this.failureReason,
  });

  /// `true` solo si firma y curso coinciden.
  final bool isValid;

  /// Mapa de bits de 64 estudiantes extraído del eco.
  final Uint8List? bitmap8;

  /// Motivo del rechazo; `null` cuando [isValid] es `true`.
  final String? failureReason;
}

/// Códec del protocolo BLE de Asistencia Uniguajira.
///
/// Todos los paquetes ocupan exactamente 16 bytes para poder viajar dentro de
/// un Service UUID de 128 bits sin superar el límite de 31 bytes del
/// advertising BLE Legacy de Android.
abstract final class BlePacketCodec {
  /// Cabecera de los anuncios emitidos por estudiantes.
  static const int studentPacketFlag = 0x80;

  /// Cabecera de los paquetes de eco emitidos por el docente.
  static const int teacherPacketFlag = 0x00;

  /// Bit que marca los paquetes de inscripción (ver `EnrollmentPacketCodec`).
  /// Los verificadores de asistencia los ignoran.
  static const int enrollmentPacketFlag = 0x40;

  /// Longitud fija de cualquier paquete del protocolo.
  static const int packetLength = 16;

  /// Longitud del mapa de bits de 64 estudiantes.
  static const int bitmapLength = AppConstants.bitmapByteLength;

  /// Calcula el tick de 30 segundos usado por la ventana HMAC.
  static int computeTimeTick(DateTime timestamp) {
    return timestamp.millisecondsSinceEpoch ~/
        (AppConstants.hmacWindowSeconds * 1000);
  }

  /// Primeros 16 bits (big-endian) del SHA-256 del identificador del curso.
  static int computeCourseHash16(String courseId) {
    final digest = sha256.convert(utf8.encode(courseId)).bytes;
    return (digest[0] << 8) | digest[1];
  }

  /// Primeros 16 bits (big-endian) del SHA-256 del identificador de sesión.
  static int computeSessionShortId(String sessionId) {
    final digest = sha256.convert(utf8.encode(sessionId)).bytes;
    return (digest[0] << 8) | digest[1];
  }

  /// Construye el anuncio de 16 bytes que emite el teléfono del estudiante.
  ///
  /// Layout: `[courseHash16:2][0x80|bitIndex:1][pin:1][timeTick:4][HMAC:8]`.
  static Uint8List buildStudentBeaconBytes({
    required String courseId,
    required int bitIndex,
    required int sessionPin,
    required String secretHex,
    required int timeTick,
  }) {
    _validateBitIndex(bitIndex);
    if (sessionPin < 0 || sessionPin > 99) {
      throw ArgumentError.value(
        sessionPin,
        'sessionPin',
        'El PIN debe estar entre 0 y 99.',
      );
    }
    if (timeTick < 0 || timeTick > 0xFFFFFFFF) {
      throw ArgumentError.value(
        timeTick,
        'timeTick',
        'El tick debe caber en un uint32 sin signo.',
      );
    }

    final packet = Uint8List(packetLength);
    final data = ByteData.sublistView(packet);
    data.setUint16(0, computeCourseHash16(courseId), Endian.big);
    packet[2] = studentPacketFlag | (bitIndex & 0x3F);
    packet[3] = sessionPin & 0xFF;
    data.setUint32(4, timeTick, Endian.big);

    final tag = _hmacSha256(secretHex, packet.sublist(0, 8));
    packet.setRange(8, packetLength, tag.sublist(0, 8));
    return packet;
  }

  /// Verifica un anuncio de estudiante con tolerancia de reloj en ticks.
  static StudentBeaconVerificationResult verifyStudentBeaconBytes({
    required Uint8List packet16,
    required String expectedCourseId,
    required int expectedSessionPin,
    required Map<int, String> secretHexByBitIndex,
    required int currentTimeTick,
    int clockSkewToleranceTicks = 1,
  }) {
    if (packet16.length != packetLength) {
      return const StudentBeaconVerificationResult(
        isValid: false,
        failureReason: 'El paquete no tiene 16 bytes.',
      );
    }
    if ((packet16[2] & studentPacketFlag) == 0) {
      return const StudentBeaconVerificationResult(
        isValid: false,
        failureReason: 'El paquete no es un anuncio de estudiante.',
      );
    }
    if ((packet16[2] & enrollmentPacketFlag) != 0) {
      return const StudentBeaconVerificationResult(
        isValid: false,
        failureReason: 'El paquete es de inscripción, no de asistencia.',
      );
    }
    if (clockSkewToleranceTicks < 0) {
      throw ArgumentError.value(
        clockSkewToleranceTicks,
        'clockSkewToleranceTicks',
        'La tolerancia no puede ser negativa.',
      );
    }

    final data = ByteData.sublistView(packet16);
    final courseHash = data.getUint16(0, Endian.big);
    if (courseHash != computeCourseHash16(expectedCourseId)) {
      return const StudentBeaconVerificationResult(
        isValid: false,
        failureReason: 'El anuncio pertenece a otro curso.',
      );
    }

    final bitIndex = packet16[2] & 0x3F;
    final packetTimeTick = data.getUint32(4, Endian.big);
    final sessionPin = packet16[3];
    if (sessionPin != expectedSessionPin) {
      return StudentBeaconVerificationResult(
        isValid: false,
        bitIndex: bitIndex,
        timeTick: packetTimeTick,
        failureReason: 'El PIN de la sesión no coincide.',
      );
    }
    if ((packetTimeTick - currentTimeTick).abs() > clockSkewToleranceTicks) {
      return StudentBeaconVerificationResult(
        isValid: false,
        bitIndex: bitIndex,
        timeTick: packetTimeTick,
        failureReason: 'El tick del anuncio está fuera de la ventana.',
      );
    }

    final secretHex = secretHexByBitIndex[bitIndex];
    if (secretHex == null || secretHex.isEmpty) {
      return StudentBeaconVerificationResult(
        isValid: false,
        bitIndex: bitIndex,
        timeTick: packetTimeTick,
        failureReason: 'No hay secreto registrado para el estudiante.',
      );
    }

    final expectedTag = _hmacSha256(
      secretHex,
      packet16.sublist(0, 8),
    ).sublist(0, 8);
    if (!_constantTimeEquals(expectedTag, packet16.sublist(8, 16))) {
      return StudentBeaconVerificationResult(
        isValid: false,
        bitIndex: bitIndex,
        timeTick: packetTimeTick,
        failureReason: 'La firma HMAC del anuncio no es válida.',
      );
    }

    return StudentBeaconVerificationResult(
      isValid: true,
      bitIndex: bitIndex,
      timeTick: packetTimeTick,
    );
  }

  /// Crea un mapa de bits vacío de 8 bytes (64 estudiantes).
  static Uint8List createEmptyBitmap8() => Uint8List(bitmapLength);

  /// Enciende el bit indicado y devuelve una copia nueva de 8 bytes.
  static Uint8List setStudentBit(Uint8List bitmap8, int bitIndex) {
    _validateBitmap8(bitmap8);
    _validateBitIndex(bitIndex);
    final result = Uint8List.fromList(bitmap8);
    result[bitIndex ~/ 8] |= 1 << (bitIndex % 8);
    return result;
  }

  /// Apaga el bit indicado y devuelve una copia nueva de 8 bytes.
  static Uint8List clearStudentBit(Uint8List bitmap8, int bitIndex) {
    _validateBitmap8(bitmap8);
    _validateBitIndex(bitIndex);
    final result = Uint8List.fromList(bitmap8);
    result[bitIndex ~/ 8] &= ~(1 << (bitIndex % 8));
    return result;
  }

  /// Indica si el estudiante de [bitIndex] está marcado como presente.
  static bool isStudentBitSet(Uint8List bitmap8, int bitIndex) {
    _validateBitmap8(bitmap8);
    _validateBitIndex(bitIndex);
    return (bitmap8[bitIndex ~/ 8] & (1 << (bitIndex % 8))) != 0;
  }

  /// Extrae, en orden ascendente, todos los bitIndex encendidos.
  static List<int> extractPresentBitIndices(Uint8List bitmap8) {
    _validateBitmap8(bitmap8);
    final present = <int>[];
    for (var bitIndex = 0; bitIndex < 64; bitIndex++) {
      if (isStudentBitSet(bitmap8, bitIndex)) {
        present.add(bitIndex);
      }
    }
    return present;
  }

  /// Construye el eco de 16 bytes que emite el docente con el Bitmap actual.
  ///
  /// Layout: `[courseHash16:2][0x00:1][sessionShortId alto:1][bitmap:8][HMAC:4]`.
  static Uint8List buildTeacherEchoBytes({
    required String courseId,
    required String sessionId,
    required Uint8List bitmap8,
    required String sharedSecretHex,
  }) {
    _validateBitmap8(bitmap8);
    final packet = Uint8List(packetLength);
    final data = ByteData.sublistView(packet);
    data.setUint16(0, computeCourseHash16(courseId), Endian.big);
    packet[2] = teacherPacketFlag;
    packet[3] = (computeSessionShortId(sessionId) >> 8) & 0xFF;
    packet.setRange(4, 12, bitmap8);

    final tag = _hmacSha256(
      sharedSecretHex,
      packet.sublist(0, 12),
    ).sublist(0, 4);
    packet.setRange(12, packetLength, tag);
    return packet;
  }

  /// Verifica la firma del eco docente y extrae su mapa de 64 bits.
  static TeacherEchoVerificationResult verifyTeacherEchoBytes({
    required Uint8List packet16,
    required String expectedCourseId,
    required String sharedSecretHex,
  }) {
    if (packet16.length != packetLength) {
      return const TeacherEchoVerificationResult(
        isValid: false,
        failureReason: 'El paquete no tiene 16 bytes.',
      );
    }
    if ((packet16[2] & studentPacketFlag) != 0) {
      return const TeacherEchoVerificationResult(
        isValid: false,
        failureReason: 'El paquete no es un eco del docente.',
      );
    }
    if ((packet16[2] & enrollmentPacketFlag) != 0) {
      return const TeacherEchoVerificationResult(
        isValid: false,
        failureReason: 'El paquete es de inscripción, no un eco de asistencia.',
      );
    }

    final data = ByteData.sublistView(packet16);
    if (data.getUint16(0, Endian.big) !=
        computeCourseHash16(expectedCourseId)) {
      return const TeacherEchoVerificationResult(
        isValid: false,
        failureReason: 'El eco pertenece a otro curso.',
      );
    }

    final expectedTag = _hmacSha256(
      sharedSecretHex,
      packet16.sublist(0, 12),
    ).sublist(0, 4);
    if (!_constantTimeEquals(expectedTag, packet16.sublist(12, 16))) {
      return const TeacherEchoVerificationResult(
        isValid: false,
        failureReason: 'La firma HMAC del eco no es válida.',
      );
    }

    return TeacherEchoVerificationResult(
      isValid: true,
      bitmap8: Uint8List.fromList(packet16.sublist(4, 12)),
    );
  }

  /// Convierte exactamente 16 bytes a un UUID con formato `8-4-4-4-12`.
  static String bytes16ToUuid(Uint8List bytes16) {
    if (bytes16.length != packetLength) {
      throw ArgumentError.value(
        bytes16.length,
        'bytes16',
        'El UUID requiere exactamente 16 bytes.',
      );
    }
    final hex = bytes16
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Intenta convertir un UUID de 128 bits a sus 16 bytes.
  ///
  /// Acepta mayúsculas, minúsculas, guiones y llaves; devuelve `null` si el
  /// texto no representa exactamente 16 bytes.
  static Uint8List? tryUuidToBytes16(String uuidString) {
    var normalized = uuidString.trim();
    if (normalized.startsWith('{') && normalized.endsWith('}')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    normalized = normalized.replaceAll('-', '');
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(normalized)) {
      return null;
    }
    final bytes = Uint8List(packetLength);
    for (var i = 0; i < packetLength; i++) {
      bytes[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Genera el token corto y auditable del Sello Verde.
  ///
  /// El mensaje firmado es `courseId|studentCode|bitIndex|timeTick`; el token
  /// expone los primeros 8 caracteres hexadecimales del HMAC-SHA256.
  static String generateAttendanceVerifyCode({
    required String courseId,
    required String studentCode,
    required int bitIndex,
    required int timeTick,
    required String secretHex,
  }) {
    _validateBitIndex(bitIndex);
    if (timeTick < 0) {
      throw ArgumentError.value(
        timeTick,
        'timeTick',
        'El tick no puede ser negativo.',
      );
    }
    final message = utf8.encode('$courseId|$studentCode|$bitIndex|$timeTick');
    final digest = _hmacSha256(secretHex, message);
    final token = digest
        .sublist(0, 4)
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return 'UG-$token';
  }

  static List<int> _hmacSha256(String secretHex, List<int> message) {
    return Hmac(
      sha256,
      utf8.encode(secretHex.toLowerCase()),
    ).convert(message).bytes;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  static void _validateBitmap8(Uint8List bitmap8) {
    if (bitmap8.length != bitmapLength) {
      throw ArgumentError.value(
        bitmap8.length,
        'bitmap8',
        'El Bitmap debe tener exactamente $bitmapLength bytes.',
      );
    }
  }

  static void _validateBitIndex(int bitIndex) {
    if (bitIndex < 0 || bitIndex > AppConstants.maxBitIndex) {
      throw ArgumentError.value(
        bitIndex,
        'bitIndex',
        'Debe estar entre 0 y ${AppConstants.maxBitIndex}.',
      );
    }
  }
}
