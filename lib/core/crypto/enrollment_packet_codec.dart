import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ble_packet_codec.dart';
import 'enrollment_crypto.dart';

/// Estado que el docente responde a una solicitud de inscripción.
enum EnrollmentStatus {
  /// Inscrito: el paquete trae su casilla.
  accepted(1),

  /// Espera la decisión del docente (fuera de lista o conflicto de celular).
  pending(2),

  /// El docente no aprobó la solicitud.
  rejected(3),

  /// La clase ya ocupó sus 64 casillas.
  classFull(4);

  const EnrollmentStatus(this.code);

  final int code;

  /// `true` si el estudiante ya no debe seguir pidiendo.
  bool get isFinal => this != EnrollmentStatus.pending;

  static EnrollmentStatus? fromCode(int code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// Solicitud completa y verificada que recibe el docente.
class EnrollmentRequest {
  const EnrollmentRequest({
    required this.requestId,
    required this.studentCode,
    required this.studentPublicKeyHex,
  });

  final int requestId;
  final String studentCode;
  final String studentPublicKeyHex;
}

/// Respuesta verificada que recibe el estudiante.
class EnrollmentResponse {
  const EnrollmentResponse({required this.requestId, required this.status, this.bitIndex});

  final int requestId;
  final EnrollmentStatus status;

  /// Casilla asignada; solo con [EnrollmentStatus.accepted].
  final int? bitIndex;
}

/// Paquetes Bluetooth de la inscripción (16 bytes, como todo el protocolo).
///
/// - Solicitud (estudiante): 4 fragmentos `[courseHash16:2][0xC0|i:1][reqId:2][11 bytes]`
///   de un mensaje de 44 bytes: `código(6) | clave pública(32) | firma(6)`.
/// - Respuesta (docente): `[courseHash16:2][0x40|estado:1][reqId:2][bitIndex:1][firma:10]`.
abstract final class EnrollmentPacketCodec {
  /// Bit que marca un paquete de inscripción en el byte de tipo.
  static const int enrollmentFlag = 0x40;

  static const int fragmentCount = 4;
  static const int fragmentPayloadLength = 11;
  static const int messageLength = fragmentCount * fragmentPayloadLength; // 44
  static const int codeFieldLength = 6;
  static const int requestMacLength = 6;
  static const int responseMacLength = 10;
  static const int noBitIndex = 0xFF;

  /// Códigos numéricos de 4 a 12 dígitos (en la Uniguajira son 10).
  static final RegExp studentCodePattern = RegExp(r'^\d{4,12}$');

  static bool isValidStudentCode(String code) => studentCodePattern.hasMatch(code);

  /// `true` si el paquete pertenece a la inscripción (solicitud o respuesta).
  static bool isEnrollmentPacket(Uint8List packet16) =>
      packet16.length == BlePacketCodec.packetLength && (packet16[2] & enrollmentFlag) != 0;

  static bool isRequestFragment(Uint8List packet16) =>
      isEnrollmentPacket(packet16) && (packet16[2] & BlePacketCodec.studentPacketFlag) != 0;

  static bool isResponse(Uint8List packet16) =>
      isEnrollmentPacket(packet16) && (packet16[2] & BlePacketCodec.studentPacketFlag) == 0;

  /// Código → `[cantidad de dígitos:1][número big-endian:5]` (conserva ceros a la izquierda).
  static Uint8List encodeStudentCode(String code) {
    if (!isValidStudentCode(code)) {
      throw ArgumentError.value(code, 'code', 'El código debe tener de 4 a 12 dígitos.');
    }
    final out = Uint8List(codeFieldLength);
    out[0] = code.length;
    var value = int.parse(code);
    for (var i = codeFieldLength - 1; i >= 1; i--) {
      out[i] = value & 0xFF;
      value >>= 8;
    }
    return out;
  }

  static String? decodeStudentCode(Uint8List field) {
    if (field.length != codeFieldLength) return null;
    final digits = field[0];
    if (digits < 4 || digits > 12) return null;
    var value = 0;
    for (var i = 1; i < codeFieldLength; i++) {
      value = (value << 8) | field[i];
    }
    final text = value.toString().padLeft(digits, '0');
    return text.length == digits ? text : null;
  }

  /// Construye los 4 fragmentos de la solicitud.
  static List<Uint8List> buildRequestFragments({
    required String courseId,
    required int requestId,
    required String studentCode,
    required String studentPublicKeyHex,
    required String sharedSecretHex,
  }) {
    _validateRequestId(requestId);
    final publicKey = EnrollmentCrypto.hexToBytes(studentPublicKeyHex);
    if (publicKey.length != EnrollmentCrypto.keyLength) {
      throw ArgumentError('La clave pública debe medir 32 bytes.');
    }
    final message = Uint8List(messageLength);
    message.setRange(0, codeFieldLength, encodeStudentCode(studentCode));
    message.setRange(codeFieldLength, codeFieldLength + 32, publicKey);
    final mac = _requestMac(sharedSecretHex, requestId, message.sublist(0, codeFieldLength + 32));
    message.setRange(codeFieldLength + 32, messageLength, mac);

    final courseHash = BlePacketCodec.computeCourseHash16(courseId);
    return List<Uint8List>.generate(fragmentCount, (index) {
      final packet = Uint8List(BlePacketCodec.packetLength);
      final data = ByteData.sublistView(packet);
      data.setUint16(0, courseHash, Endian.big);
      packet[2] = BlePacketCodec.studentPacketFlag | enrollmentFlag | index;
      data.setUint16(3, requestId, Endian.big);
      packet.setRange(
        5,
        BlePacketCodec.packetLength,
        message.sublist(index * fragmentPayloadLength, (index + 1) * fragmentPayloadLength),
      );
      return packet;
    }, growable: false);
  }

  /// Construye la respuesta del docente, firmada con el secreto del dispositivo.
  static Uint8List buildResponse({
    required String courseId,
    required int requestId,
    required EnrollmentStatus status,
    required String deviceSecretHex,
    int? bitIndex,
  }) {
    _validateRequestId(requestId);
    if (status == EnrollmentStatus.accepted && (bitIndex == null || bitIndex < 0 || bitIndex > 63)) {
      throw ArgumentError.value(bitIndex, 'bitIndex', 'Una respuesta aceptada necesita casilla (0 a 63).');
    }
    final packet = Uint8List(BlePacketCodec.packetLength);
    final data = ByteData.sublistView(packet);
    data.setUint16(0, BlePacketCodec.computeCourseHash16(courseId), Endian.big);
    packet[2] = enrollmentFlag | status.code;
    data.setUint16(3, requestId, Endian.big);
    packet[5] = status == EnrollmentStatus.accepted ? bitIndex! : noBitIndex;
    packet.setRange(6, BlePacketCodec.packetLength, _responseMac(deviceSecretHex, packet.sublist(0, 6)));
    return packet;
  }

  /// Verifica una respuesta. Devuelve nulo si no es para esta solicitud o la firma no coincide.
  static EnrollmentResponse? verifyResponse({
    required Uint8List packet16,
    required String expectedCourseId,
    required int expectedRequestId,
    required String deviceSecretHex,
  }) {
    if (!isResponse(packet16)) return null;
    final data = ByteData.sublistView(packet16);
    if (data.getUint16(0, Endian.big) != BlePacketCodec.computeCourseHash16(expectedCourseId)) return null;
    if (data.getUint16(3, Endian.big) != expectedRequestId) return null;
    final status = EnrollmentStatus.fromCode(packet16[2] & 0x0F);
    if (status == null) return null;
    final expectedMac = _responseMac(deviceSecretHex, packet16.sublist(0, 6));
    if (!_constantTimeEquals(expectedMac, packet16.sublist(6))) return null;
    final bit = packet16[5];
    if (status == EnrollmentStatus.accepted && bit > 63) return null;
    return EnrollmentResponse(
      requestId: expectedRequestId,
      status: status,
      bitIndex: status == EnrollmentStatus.accepted ? bit : null,
    );
  }

  static Uint8List _requestMac(String sharedSecretHex, int requestId, List<int> body) {
    final input = <int>[...utf8.encode('ENR1'), (requestId >> 8) & 0xFF, requestId & 0xFF, ...body];
    final digest = Hmac(sha256, EnrollmentCrypto.hexToBytes(sharedSecretHex)).convert(input).bytes;
    return Uint8List.fromList(digest.sublist(0, requestMacLength));
  }

  static Uint8List _responseMac(String deviceSecretHex, List<int> header) {
    final input = <int>[...utf8.encode('ENR2'), ...header];
    final digest = Hmac(sha256, EnrollmentCrypto.hexToBytes(deviceSecretHex)).convert(input).bytes;
    return Uint8List.fromList(digest.sublist(0, responseMacLength));
  }

  static void _validateRequestId(int requestId) {
    if (requestId < 0 || requestId > 0xFFFF) {
      throw ArgumentError.value(requestId, 'requestId', 'Debe caber en 16 bits.');
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Usado por [EnrollmentRequestAssembler] para validar el mensaje armado.
  static EnrollmentRequest? parseRequestMessage({
    required int requestId,
    required Uint8List message,
    required String sharedSecretHex,
  }) {
    if (message.length != messageLength) return null;
    final body = message.sublist(0, codeFieldLength + 32);
    final mac = message.sublist(codeFieldLength + 32);
    if (!_constantTimeEquals(_requestMac(sharedSecretHex, requestId, body), mac)) return null;
    final code = decodeStudentCode(Uint8List.fromList(body.sublist(0, codeFieldLength)));
    if (code == null) return null;
    return EnrollmentRequest(
      requestId: requestId,
      studentCode: code,
      studentPublicKeyHex: EnrollmentCrypto.bytesToHex(body.sublist(codeFieldLength)),
    );
  }
}

/// Arma solicitudes a partir de fragmentos que llegan sueltos y en desorden.
class EnrollmentRequestAssembler {
  EnrollmentRequestAssembler({
    required this.courseId,
    required this.sharedSecretHex,
    this.maxPartialRequests = 128,
  }) : _courseHash = BlePacketCodec.computeCourseHash16(courseId);

  final String courseId;
  final String sharedSecretHex;

  /// Tope de solicitudes a medio armar (protege la memoria ante ruido).
  final int maxPartialRequests;

  final int _courseHash;
  final Map<int, List<Uint8List?>> _partial = <int, List<Uint8List?>>{};

  /// Agrega un paquete. Devuelve la solicitud cuando tiene los 4 fragmentos y
  /// la firma coincide; nulo en cualquier otro caso (incluidos paquetes ajenos).
  EnrollmentRequest? add(Uint8List packet16) {
    if (!EnrollmentPacketCodec.isRequestFragment(packet16)) return null;
    final data = ByteData.sublistView(packet16);
    if (data.getUint16(0, Endian.big) != _courseHash) return null;
    final index = packet16[2] & 0x0F;
    if (index >= EnrollmentPacketCodec.fragmentCount) return null;
    final requestId = data.getUint16(3, Endian.big);

    if (!_partial.containsKey(requestId) && _partial.length >= maxPartialRequests) {
      _partial.remove(_partial.keys.first);
    }
    final slots = _partial.putIfAbsent(
      requestId,
      () => List<Uint8List?>.filled(EnrollmentPacketCodec.fragmentCount, null),
    );
    slots[index] = Uint8List.fromList(packet16.sublist(5));
    if (slots.any((s) => s == null)) return null;

    final message = Uint8List(EnrollmentPacketCodec.messageLength);
    for (var i = 0; i < slots.length; i++) {
      message.setRange(
        i * EnrollmentPacketCodec.fragmentPayloadLength,
        (i + 1) * EnrollmentPacketCodec.fragmentPayloadLength,
        slots[i]!,
      );
    }
    _partial.remove(requestId);
    return EnrollmentPacketCodec.parseRequestMessage(
      requestId: requestId,
      message: message,
      sharedSecretHex: sharedSecretHex,
    );
  }

  void clear() => _partial.clear();
}
