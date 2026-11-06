import 'dart:convert';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const String _secret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _courseId = 'course-1';
const String _sessionId = 'session-1';

void main() {
  group('ventana temporal y hashes cortos', () {
    test('computeTimeTick usa ventanas de 30 segundos', () {
      expect(
        BlePacketCodec.computeTimeTick(
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
        0,
      );
      expect(
        BlePacketCodec.computeTimeTick(
          DateTime.fromMillisecondsSinceEpoch(29999, isUtc: true),
        ),
        0,
      );
      expect(
        BlePacketCodec.computeTimeTick(
          DateTime.fromMillisecondsSinceEpoch(30000, isUtc: true),
        ),
        1,
      );
      expect(
        BlePacketCodec.computeTimeTick(
          DateTime.fromMillisecondsSinceEpoch(89999, isUtc: true),
        ),
        2,
      );
    });

    test(
      'courseHash16 y sessionShortId son los dos primeros bytes SHA-256',
      () {
        final courseDigest = sha256.convert(utf8.encode(_courseId)).bytes;
        final sessionDigest = sha256.convert(utf8.encode(_sessionId)).bytes;

        expect(
          BlePacketCodec.computeCourseHash16(_courseId),
          (courseDigest[0] << 8) | courseDigest[1],
        );
        expect(
          BlePacketCodec.computeSessionShortId(_sessionId),
          (sessionDigest[0] << 8) | sessionDigest[1],
        );
        expect(
          BlePacketCodec.computeCourseHash16(_courseId),
          inInclusiveRange(0, 0xFFFF),
        );
      },
    );
  });

  group('anuncio del estudiante', () {
    test('construye 16 bytes con flag, PIN, tick y HMAC verificable', () {
      const timeTick = 123456;
      final packet = BlePacketCodec.buildStudentBeaconBytes(
        courseId: _courseId,
        bitIndex: 17,
        sessionPin: 42,
        secretHex: _secret.toUpperCase(),
        timeTick: timeTick,
      );

      expect(packet, hasLength(16));
      expect(packet[2] & 0x80, 0x80);
      expect(packet[2] & 0x3F, 17);
      expect(packet[3], 42);
      final data = ByteData.sublistView(packet);
      expect(
        data.getUint16(0, Endian.big),
        BlePacketCodec.computeCourseHash16(_courseId),
      );
      expect(data.getUint32(4, Endian.big), timeTick);

      final expectedTag = Hmac(
        sha256,
        utf8.encode(_secret.toLowerCase()),
      ).convert(packet.sublist(0, 8)).bytes.sublist(0, 8);
      expect(packet.sublist(8, 16), expectedTag);

      final result = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packet,
        expectedCourseId: _courseId,
        expectedSessionPin: 42,
        secretHexByBitIndex: <int, String>{17: _secret.toUpperCase()},
        currentTimeTick: timeTick,
      );
      expect(result.isValid, isTrue);
      expect(result.bitIndex, 17);
      expect(result.timeTick, timeTick);
      expect(result.failureReason, isNull);
    });

    test('acepta tolerancia de un tick y rechaza dos ticks de diferencia', () {
      final packet = BlePacketCodec.buildStudentBeaconBytes(
        courseId: _courseId,
        bitIndex: 3,
        sessionPin: 7,
        secretHex: _secret,
        timeTick: 100,
      );
      final secrets = <int, String>{3: _secret};

      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedSessionPin: 7,
          secretHexByBitIndex: secrets,
          currentTimeTick: 101,
        ).isValid,
        isTrue,
      );
      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedSessionPin: 7,
          secretHexByBitIndex: secrets,
          currentTimeTick: 98,
        ).isValid,
        isFalse,
      );
      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedSessionPin: 7,
          secretHexByBitIndex: secrets,
          currentTimeTick: 102,
        ).isValid,
        isFalse,
      );
    });

    test('rechaza longitud, tipo, curso, PIN, secreto y firma inválidos', () {
      final packet = BlePacketCodec.buildStudentBeaconBytes(
        courseId: _courseId,
        bitIndex: 9,
        sessionPin: 12,
        secretHex: _secret,
        timeTick: 500,
      );
      final secrets = <int, String>{9: _secret};

      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: Uint8List(15),
          expectedCourseId: _courseId,
          expectedSessionPin: 12,
          secretHexByBitIndex: secrets,
          currentTimeTick: 500,
        ).isValid,
        isFalse,
      );

      final notStudent = Uint8List.fromList(packet);
      notStudent[2] = 9;
      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: notStudent,
          expectedCourseId: _courseId,
          expectedSessionPin: 12,
          secretHexByBitIndex: secrets,
          currentTimeTick: 500,
        ).isValid,
        isFalse,
      );

      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: 'otro-curso',
          expectedSessionPin: 12,
          secretHexByBitIndex: secrets,
          currentTimeTick: 500,
        ).isValid,
        isFalse,
      );
      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedSessionPin: 13,
          secretHexByBitIndex: secrets,
          currentTimeTick: 500,
        ).isValid,
        isFalse,
      );
      expect(
        BlePacketCodec.verifyStudentBeaconBytes(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedSessionPin: 12,
          secretHexByBitIndex: <int, String>{},
          currentTimeTick: 500,
        ).isValid,
        isFalse,
      );

      final brokenSignature = Uint8List.fromList(packet);
      brokenSignature[15] ^= 0x01;
      final signatureResult = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: brokenSignature,
        expectedCourseId: _courseId,
        expectedSessionPin: 12,
        secretHexByBitIndex: secrets,
        currentTimeTick: 500,
      );
      expect(signatureResult.isValid, isFalse);
      expect(signatureResult.failureReason, isNotNull);
      expect(signatureResult.bitIndex, 9);
    });
  });

  group('bitmap de 64 estudiantes', () {
    test(
      'crea, enciende, consulta, limpia y extrae bits sin mutar el origen',
      () {
        final empty = BlePacketCodec.createEmptyBitmap8();
        expect(empty, hasLength(8));
        expect(BlePacketCodec.extractPresentBitIndices(empty), isEmpty);

        var bitmap = BlePacketCodec.setStudentBit(empty, 0);
        bitmap = BlePacketCodec.setStudentBit(bitmap, 7);
        bitmap = BlePacketCodec.setStudentBit(bitmap, 8);
        bitmap = BlePacketCodec.setStudentBit(bitmap, 63);

        expect(empty, everyElement(0));
        expect(BlePacketCodec.isStudentBitSet(bitmap, 0), isTrue);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 7), isTrue);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 8), isTrue);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 63), isTrue);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 1), isFalse);
        expect(BlePacketCodec.extractPresentBitIndices(bitmap), <int>[
          0,
          7,
          8,
          63,
        ]);

        final withoutEight = BlePacketCodec.clearStudentBit(bitmap, 8);
        expect(BlePacketCodec.isStudentBitSet(withoutEight, 8), isFalse);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 8), isTrue);
        expect(BlePacketCodec.extractPresentBitIndices(withoutEight), <int>[
          0,
          7,
          63,
        ]);
      },
    );

    test('valida el tamaño del Bitmap y el rango 0..63', () {
      expect(
        () => BlePacketCodec.setStudentBit(Uint8List(7), 0),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.isStudentBitSet(Uint8List(8), 64),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.clearStudentBit(Uint8List(8), -1),
        throwsArgumentError,
      );
    });
  });

  group('eco del docente', () {
    test('construye y verifica el Bitmap completo', () {
      final bitmap = BlePacketCodec.setStudentBit(
        BlePacketCodec.createEmptyBitmap8(),
        5,
      );
      final packet = BlePacketCodec.buildTeacherEchoBytes(
        courseId: _courseId,
        sessionId: _sessionId,
        bitmap8: bitmap,
        sharedSecretHex: _secret.toUpperCase(),
      );

      expect(packet, hasLength(16));
      expect(packet[2] & 0x80, 0);
      expect(
        ByteData.sublistView(packet).getUint16(0, Endian.big),
        BlePacketCodec.computeCourseHash16(_courseId),
      );
      expect(
        packet[3],
        (BlePacketCodec.computeSessionShortId(_sessionId) >> 8) & 0xFF,
      );

      final result = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: packet,
        expectedCourseId: _courseId,
        sharedSecretHex: _secret,
      );
      expect(result.isValid, isTrue);
      expect(result.bitmap8, bitmap);
      expect(result.failureReason, isNull);
      expect(BlePacketCodec.extractPresentBitIndices(result.bitmap8!), <int>[
        5,
      ]);
    });

    test('rechaza firma, curso, longitud y paquetes de estudiante', () {
      final packet = BlePacketCodec.buildTeacherEchoBytes(
        courseId: _courseId,
        sessionId: _sessionId,
        bitmap8: BlePacketCodec.createEmptyBitmap8(),
        sharedSecretHex: _secret,
      );

      final broken = Uint8List.fromList(packet);
      broken[15] ^= 0x01;
      expect(
        BlePacketCodec.verifyTeacherEchoBytes(
          packet16: broken,
          expectedCourseId: _courseId,
          sharedSecretHex: _secret,
        ).isValid,
        isFalse,
      );
      expect(
        BlePacketCodec.verifyTeacherEchoBytes(
          packet16: packet,
          expectedCourseId: 'otro-curso',
          sharedSecretHex: _secret,
        ).isValid,
        isFalse,
      );
      expect(
        BlePacketCodec.verifyTeacherEchoBytes(
          packet16: Uint8List(15),
          expectedCourseId: _courseId,
          sharedSecretHex: _secret,
        ).isValid,
        isFalse,
      );

      final studentPacket = BlePacketCodec.buildStudentBeaconBytes(
        courseId: _courseId,
        bitIndex: 1,
        sessionPin: 10,
        secretHex: _secret,
        timeTick: 1,
      );
      expect(
        BlePacketCodec.verifyTeacherEchoBytes(
          packet16: studentPacket,
          expectedCourseId: _courseId,
          sharedSecretHex: _secret,
        ).isValid,
        isFalse,
      );
    });
  });

  group('UUID de 128 bits', () {
    test('convierte 16 bytes al formato 8-4-4-4-12 y regresa', () {
      final bytes = Uint8List.fromList(List<int>.generate(16, (int i) => i));
      const expected = '00010203-0405-0607-0809-0a0b0c0d0e0f';

      expect(BlePacketCodec.bytes16ToUuid(bytes), expected);
      final roundTrip = BlePacketCodec.tryUuidToBytes16(expected);
      expect(roundTrip, bytes);
      expect(
        BlePacketCodec.tryUuidToBytes16('{${expected.toUpperCase()}}'),
        bytes,
      );
    });

    test('rechaza longitudes y textos que no son UUID', () {
      expect(
        () => BlePacketCodec.bytes16ToUuid(Uint8List(15)),
        throwsArgumentError,
      );
      expect(BlePacketCodec.tryUuidToBytes16(''), isNull);
      expect(BlePacketCodec.tryUuidToBytes16('no-es-un-uuid'), isNull);
      expect(
        BlePacketCodec.tryUuidToBytes16('00010203-0405-0607-0809-0a0b0c0d0e'),
        isNull,
      );
      expect(BlePacketCodec.tryUuidToBytes16('g' * 32), isNull);
    });
  });

  group('token del Sello Verde', () {
    test('genera UG-XXXXXXXX determinista y auditable', () {
      const bitIndex = 5;
      const timeTick = 987654;
      final code = BlePacketCodec.generateAttendanceVerifyCode(
        courseId: _courseId,
        studentCode: '0182120016',
        bitIndex: bitIndex,
        timeTick: timeTick,
        secretHex: _secret.toUpperCase(),
      );

      expect(RegExp(r'^UG-[0-9A-F]{8}$').hasMatch(code), isTrue);

      final digest = Hmac(
        sha256,
        utf8.encode(_secret.toLowerCase()),
      ).convert(utf8.encode('$_courseId|0182120016|$bitIndex|$timeTick')).bytes;
      final expected =
          'UG-${digest.sublist(0, 4).map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
      expect(code, expected);
      expect(
        BlePacketCodec.generateAttendanceVerifyCode(
          courseId: _courseId,
          studentCode: '0182120016',
          bitIndex: bitIndex,
          timeTick: timeTick + 1,
          secretHex: _secret,
        ),
        isNot(code),
      );
    });
  });
}
