import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/crypto/enrollment_crypto.dart';
import 'package:asistencia_uniguajira/core/crypto/enrollment_packet_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _shared = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _courseId = 'curso-bd2';

void main() {
  group('EnrollmentCrypto', () {
    test('docente y estudiante derivan el mismo secreto sin compartirlo', () async {
      final teacher = await EnrollmentCrypto.generateKeyPair();
      final student = await EnrollmentCrypto.generateKeyPair();

      final onStudent = await EnrollmentCrypto.deriveDeviceSecret(
        ownPrivateKeyHex: student.privateKeyHex,
        peerPublicKeyHex: teacher.publicKeyHex,
        sharedSecretHex: _shared,
        studentCode: '0182120016',
      );
      final onTeacher = await EnrollmentCrypto.deriveDeviceSecret(
        ownPrivateKeyHex: teacher.privateKeyHex,
        peerPublicKeyHex: student.publicKeyHex,
        sharedSecretHex: _shared,
        studentCode: '0182120016',
      );

      expect(onStudent, onTeacher);
      expect(onStudent, hasLength(64));
    });

    test('quien solo escucha (claves públicas y QR) no obtiene el secreto', () async {
      final teacher = await EnrollmentCrypto.generateKeyPair();
      final student = await EnrollmentCrypto.generateKeyPair();
      final eavesdropper = await EnrollmentCrypto.generateKeyPair();

      final real = await EnrollmentCrypto.deriveDeviceSecret(
        ownPrivateKeyHex: student.privateKeyHex,
        peerPublicKeyHex: teacher.publicKeyHex,
        sharedSecretHex: _shared,
        studentCode: '0182120016',
      );
      final guess = await EnrollmentCrypto.deriveDeviceSecret(
        ownPrivateKeyHex: eavesdropper.privateKeyHex,
        peerPublicKeyHex: teacher.publicKeyHex,
        sharedSecretHex: _shared,
        studentCode: '0182120016',
      );
      expect(guess, isNot(real));
    });

    test('el secreto cambia con el código y con la clase', () async {
      final teacher = await EnrollmentCrypto.generateKeyPair();
      final student = await EnrollmentCrypto.generateKeyPair();
      Future<String> derive(String code, String shared) => EnrollmentCrypto.deriveDeviceSecret(
            ownPrivateKeyHex: student.privateKeyHex,
            peerPublicKeyHex: teacher.publicKeyHex,
            sharedSecretHex: shared,
            studentCode: code,
          );
      final base = await derive('0182120016', _shared);
      expect(await derive('0182120017', _shared), isNot(base));
      expect(await derive('0182120016', _shared.replaceFirst('0', 'f')), isNot(base));
    });
  });

  group('código estudiantil', () {
    test('conserva ceros a la izquierda y admite de 4 a 12 dígitos', () {
      for (final code in ['0182120016', '0001', '999999999999', '1234']) {
        final field = EnrollmentPacketCodec.encodeStudentCode(code);
        expect(field, hasLength(6));
        expect(EnrollmentPacketCodec.decodeStudentCode(field), code);
      }
    });

    test('rechaza códigos con letras, cortos o largos', () {
      for (final bad in ['018A120016', '123', '1234567890123', '']) {
        expect(EnrollmentPacketCodec.isValidStudentCode(bad), isFalse);
        expect(() => EnrollmentPacketCodec.encodeStudentCode(bad), throwsArgumentError);
      }
    });
  });

  group('solicitud en fragmentos', () {
    late EnrollmentKeyPair student;
    late List<Uint8List> fragments;

    setUp(() async {
      student = await EnrollmentCrypto.generateKeyPair();
      fragments = EnrollmentPacketCodec.buildRequestFragments(
        courseId: _courseId,
        requestId: 0xBEEF,
        studentCode: '0182120016',
        studentPublicKeyHex: student.publicKeyHex,
        sharedSecretHex: _shared,
      );
    });

    test('son 4 paquetes de 16 bytes marcados como solicitud', () {
      expect(fragments, hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect(fragments[i], hasLength(16));
        expect(fragments[i][2], 0xC0 | i);
        expect(EnrollmentPacketCodec.isRequestFragment(fragments[i]), isTrue);
        expect(EnrollmentPacketCodec.isResponse(fragments[i]), isFalse);
      }
    });

    test('se arma en desorden y con repetidos', () {
      final assembler = EnrollmentRequestAssembler(courseId: _courseId, sharedSecretHex: _shared);
      expect(assembler.add(fragments[2]), isNull);
      expect(assembler.add(fragments[0]), isNull);
      expect(assembler.add(fragments[2]), isNull);
      expect(assembler.add(fragments[3]), isNull);
      final request = assembler.add(fragments[1]);
      expect(request, isNotNull);
      expect(request!.requestId, 0xBEEF);
      expect(request.studentCode, '0182120016');
      expect(request.studentPublicKeyHex, student.publicKeyHex);
    });

    test('dos estudiantes a la vez no se mezclan', () async {
      final other = await EnrollmentCrypto.generateKeyPair();
      final otherFragments = EnrollmentPacketCodec.buildRequestFragments(
        courseId: _courseId,
        requestId: 0x1234,
        studentCode: '0182120099',
        studentPublicKeyHex: other.publicKeyHex,
        sharedSecretHex: _shared,
      );
      final assembler = EnrollmentRequestAssembler(courseId: _courseId, sharedSecretHex: _shared);
      final results = <EnrollmentRequest>[];
      for (var i = 0; i < 4; i++) {
        for (final packet in [fragments[i], otherFragments[3 - i]]) {
          final r = assembler.add(packet);
          if (r != null) results.add(r);
        }
      }
      expect(results.map((r) => r.studentCode).toSet(), {'0182120016', '0182120099'});
    });

    test('se ignora si no conoce la clave de la clase, es de otra clase o fue alterada', () {
      final wrongKey = EnrollmentRequestAssembler(
        courseId: _courseId,
        sharedSecretHex: _shared.replaceFirst('0', 'a'),
      );
      EnrollmentRequest? last;
      for (final f in fragments) {
        last = wrongKey.add(f);
      }
      expect(last, isNull);

      final otherCourse = EnrollmentRequestAssembler(courseId: 'otra-clase', sharedSecretHex: _shared);
      for (final f in fragments) {
        expect(otherCourse.add(f), isNull);
      }

      final tampered = EnrollmentRequestAssembler(courseId: _courseId, sharedSecretHex: _shared);
      final altered = fragments.map(Uint8List.fromList).toList();
      altered[1][8] ^= 0x01;
      for (final f in altered) {
        last = tampered.add(f);
      }
      expect(last, isNull);
    });
  });

  group('respuesta del docente', () {
    const deviceSecret = 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';

    test('aceptado lleva la casilla y se verifica con el secreto del dispositivo', () {
      final packet = EnrollmentPacketCodec.buildResponse(
        courseId: _courseId,
        requestId: 0xBEEF,
        status: EnrollmentStatus.accepted,
        deviceSecretHex: deviceSecret,
        bitIndex: 37,
      );
      expect(packet, hasLength(16));
      expect(EnrollmentPacketCodec.isResponse(packet), isTrue);

      final ok = EnrollmentPacketCodec.verifyResponse(
        packet16: packet,
        expectedCourseId: _courseId,
        expectedRequestId: 0xBEEF,
        deviceSecretHex: deviceSecret,
      );
      expect(ok!.status, EnrollmentStatus.accepted);
      expect(ok.bitIndex, 37);
    });

    test('se descarta con otro secreto, otra solicitud o si se altera', () {
      final packet = EnrollmentPacketCodec.buildResponse(
        courseId: _courseId,
        requestId: 0xBEEF,
        status: EnrollmentStatus.accepted,
        deviceSecretHex: deviceSecret,
        bitIndex: 5,
      );
      EnrollmentResponse? verify(Uint8List p, {int req = 0xBEEF, String secret = deviceSecret}) =>
          EnrollmentPacketCodec.verifyResponse(
            packet16: p,
            expectedCourseId: _courseId,
            expectedRequestId: req,
            deviceSecretHex: secret,
          );
      expect(verify(packet, secret: deviceSecret.replaceFirst('a', 'b')), isNull);
      expect(verify(packet, req: 0x0001), isNull);
      final altered = Uint8List.fromList(packet)..[5] = 6;
      expect(verify(altered), isNull);
    });

    test('estados sin casilla: en revisión, rechazado y clase completa', () {
      for (final status in [EnrollmentStatus.pending, EnrollmentStatus.rejected, EnrollmentStatus.classFull]) {
        final packet = EnrollmentPacketCodec.buildResponse(
          courseId: _courseId,
          requestId: 7,
          status: status,
          deviceSecretHex: deviceSecret,
        );
        final r = EnrollmentPacketCodec.verifyResponse(
          packet16: packet,
          expectedCourseId: _courseId,
          expectedRequestId: 7,
          deviceSecretHex: deviceSecret,
        );
        expect(r!.status, status);
        expect(r.bitIndex, isNull);
      }
      expect(EnrollmentStatus.pending.isFinal, isFalse);
      expect(EnrollmentStatus.accepted.isFinal, isTrue);
    });
  });

  group('convivencia con la asistencia', () {
    test('los verificadores de asistencia ignoran los paquetes de inscripción', () async {
      final student = await EnrollmentCrypto.generateKeyPair();
      final fragments = EnrollmentPacketCodec.buildRequestFragments(
        courseId: _courseId,
        requestId: 1,
        studentCode: '0182120016',
        studentPublicKeyHex: student.publicKeyHex,
        sharedSecretHex: _shared,
      );
      final beacon = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: fragments.first,
        expectedCourseId: _courseId,
        expectedSessionPin: 47,
        secretHexByBitIndex: const {0: _shared},
        currentTimeTick: 1,
      );
      expect(beacon.isValid, isFalse);
      expect(beacon.failureReason, contains('inscripción'));

      final response = EnrollmentPacketCodec.buildResponse(
        courseId: _courseId,
        requestId: 1,
        status: EnrollmentStatus.pending,
        deviceSecretHex: _shared,
      );
      final echo = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: response,
        expectedCourseId: _courseId,
        sharedSecretHex: _shared,
      );
      expect(echo.isValid, isFalse);
      expect(echo.failureReason, contains('inscripción'));
    });

    test('los paquetes de asistencia no se confunden con inscripción', () {
      final beacon = BlePacketCodec.buildStudentBeaconBytes(
        courseId: _courseId,
        bitIndex: 63,
        sessionPin: 47,
        secretHex: _shared,
        timeTick: 100,
      );
      final echo = BlePacketCodec.buildTeacherEchoBytes(
        courseId: _courseId,
        sessionId: 's1',
        bitmap8: BlePacketCodec.createEmptyBitmap8(),
        sharedSecretHex: _shared,
      );
      expect(EnrollmentPacketCodec.isEnrollmentPacket(beacon), isFalse);
      expect(EnrollmentPacketCodec.isEnrollmentPacket(echo), isFalse);
    });
  });
}
