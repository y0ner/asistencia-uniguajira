import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// Par de claves X25519 en hexadecimal (32 bytes cada una).
class EnrollmentKeyPair {
  const EnrollmentKeyPair({required this.privateKeyHex, required this.publicKeyHex});

  final String privateKeyHex;
  final String publicKeyHex;
}

/// Criptografía de la inscripción (Oleada 2).
///
/// Cada celular genera su propio par X25519. El estudiante conoce la clave
/// pública del docente por el QR de la clase (canal visual, auténtico) y envía
/// la suya por Bluetooth. Ambos calculan el mismo secreto sin que viaje por el
/// aire; de ahí se deriva el secreto del dispositivo que firma la asistencia.
abstract final class EnrollmentCrypto {
  static final X25519 _x25519 = X25519();

  static const int keyLength = 32;

  /// Genera un par de claves nuevo.
  static Future<EnrollmentKeyPair> generateKeyPair() async {
    final pair = await _x25519.newKeyPair();
    final privateBytes = await pair.extractPrivateKeyBytes();
    final publicKey = await pair.extractPublicKey();
    return EnrollmentKeyPair(
      privateKeyHex: bytesToHex(privateBytes),
      publicKeyHex: bytesToHex(publicKey.bytes),
    );
  }

  /// Deriva el secreto del dispositivo (64 caracteres hexadecimales).
  ///
  /// `X25519(propia, ajena)` → HKDF-SHA256 con la clave de la clase como sal y
  /// el código estudiantil en `info`, para que el secreto quede atado a ese
  /// código y a esa clase.
  static Future<String> deriveDeviceSecret({
    required String ownPrivateKeyHex,
    required String peerPublicKeyHex,
    required String sharedSecretHex,
    required String studentCode,
  }) async {
    final ownPrivate = hexToBytes(ownPrivateKeyHex);
    final peerPublic = hexToBytes(peerPublicKeyHex);
    if (ownPrivate.length != keyLength || peerPublic.length != keyLength) {
      throw ArgumentError('Las claves X25519 deben medir $keyLength bytes.');
    }
    final pair = await _x25519.newKeyPairFromSeed(ownPrivate);
    final shared = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);
    final derived = await hkdf.deriveKey(
      secretKey: shared,
      nonce: hexToBytes(sharedSecretHex),
      info: utf8.encode('asistencia/device/v1|$studentCode'),
    );
    return bytesToHex(await derived.extractBytes());
  }

  /// Huella corta de una clave pública (16 hex), para mostrar y auditar.
  static String keyId(String publicKeyHex) {
    final digest = hash.sha256.convert(hexToBytes(publicKeyHex)).bytes;
    return bytesToHex(digest.sublist(0, 8));
  }

  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
    final clean = hex.trim();
    if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
      throw ArgumentError.value(hex, 'hex', 'No es hexadecimal válido.');
    }
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
