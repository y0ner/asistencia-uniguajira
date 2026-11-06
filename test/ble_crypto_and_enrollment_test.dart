import 'dart:convert';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:asistencia_uniguajira/data/services/roster_import_service.dart';
import 'package:asistencia_uniguajira/data/services/student_enrollment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _testCourseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _testStudentSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
const String _otherSecret =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  sqfliteFfiInit();

  group('1. Manipulación exacta del Mapa de Bits de 8 bytes (64 posiciones)', () {
    test(
      'enciende y apaga bits extremos (0, 1, 31, 32, 63) preservando el resto',
      () {
        var bitmap = BlePacketCodec.createEmptyBitmap8();
        expect(bitmap, hasLength(AppConstants.bitmapByteLength));
        expect(BlePacketCodec.extractPresentBitIndices(bitmap), isEmpty);

        final extremeBits = <int>[0, 1, 31, 32, 63];
        for (final bit in extremeBits) {
          expect(BlePacketCodec.isStudentBitSet(bitmap, bit), isFalse);
          bitmap = BlePacketCodec.setStudentBit(bitmap, bit);
          expect(BlePacketCodec.isStudentBitSet(bitmap, bit), isTrue);
        }

        expect(
          BlePacketCodec.extractPresentBitIndices(bitmap),
          equals(<int>[0, 1, 31, 32, 63]),
        );

        // Verificación de bytes específicos para bits extremos
        // bit 0 (byte 0, bit 0) y bit 1 (byte 0, bit 1) => 0x03
        expect(bitmap[0], 0x03);
        // bit 31 (byte 3, bit 7 => 0x80)
        expect(bitmap[3], 0x80);
        // bit 32 (byte 4, bit 0 => 0x01)
        expect(bitmap[4], 0x01);
        // bit 63 (byte 7, bit 7 => 0x80)
        expect(bitmap[7], 0x80);

        // Apagar bit 31 y verificar que los demás permanecen encendidos
        bitmap = BlePacketCodec.clearStudentBit(bitmap, 31);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 31), isFalse);
        expect(bitmap[3], 0x00);
        expect(
          BlePacketCodec.extractPresentBitIndices(bitmap),
          equals(<int>[0, 1, 32, 63]),
        );

        // Apagar bit 0
        bitmap = BlePacketCodec.clearStudentBit(bitmap, 0);
        expect(BlePacketCodec.isStudentBitSet(bitmap, 0), isFalse);
        expect(bitmap[0], 0x02); // bit 1 sigue encendido
        expect(
          BlePacketCodec.extractPresentBitIndices(bitmap),
          equals(<int>[1, 32, 63]),
        );
      },
    );

    test(
      'los 64 bits encendidos simultáneamente sin errores de signo ni desbordamiento',
      () {
        var bitmap = BlePacketCodec.createEmptyBitmap8();
        for (var bit = 0; bit < 64; bit++) {
          bitmap = BlePacketCodec.setStudentBit(bitmap, bit);
        }

        // Cada uno de los 8 bytes debe valer exactamente 0xFF (255 sin signo)
        for (var i = 0; i < AppConstants.bitmapByteLength; i++) {
          expect(bitmap[i], equals(0xFF));
        }

        // Verificar isStudentBitSet para todas las 64 posiciones
        for (var bit = 0; bit < 64; bit++) {
          expect(
            BlePacketCodec.isStudentBitSet(bitmap, bit),
            isTrue,
            reason: 'Bit $bit debe estar encendido',
          );
        }

        // extractPresentBitIndices debe devolver exactamente de 0 a 63 en orden
        final extracted = BlePacketCodec.extractPresentBitIndices(bitmap);
        expect(extracted, hasLength(64));
        expect(
          extracted,
          equals(List<int>.generate(64, (int index) => index)),
        );
      },
    );

    test('valida rango de bitIndex (0..63) y longitud del Bitmap (8 bytes)', () {
      final validBitmap = BlePacketCodec.createEmptyBitmap8();
      final invalidBitmap7 = Uint8List(7);
      final invalidBitmap9 = Uint8List(9);

      expect(
        () => BlePacketCodec.setStudentBit(validBitmap, -1),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.setStudentBit(validBitmap, 64),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.clearStudentBit(validBitmap, -1),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.clearStudentBit(validBitmap, 64),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.isStudentBitSet(validBitmap, -1),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.isStudentBitSet(validBitmap, 64),
        throwsArgumentError,
      );

      expect(
        () => BlePacketCodec.isStudentBitSet(invalidBitmap7, 0),
        throwsArgumentError,
      );
      expect(
        () => BlePacketCodec.extractPresentBitIndices(invalidBitmap9),
        throwsArgumentError,
      );
    });
  });

  group('2. Conversión bidireccional sin pérdida entre Uint8List(16) y UUID String', () {
    test('bytes16ToUuid y tryUuidToBytes16 preservan exactamente los 16 bytes', () {
      final samplePackets = <Uint8List>[
        Uint8List(16), // todos ceros
        Uint8List.fromList(List<int>.filled(16, 0xFF)), // todos 0xFF
        Uint8List.fromList(List<int>.generate(16, (int i) => i * 17 % 256)),
        Uint8List.fromList(<int>[
          0x01, 0x82, 0x12, 0x00, 0x16, 0xAA, 0xBB, 0xCC,
          0xDD, 0xEE, 0xFF, 0x00, 0x11, 0x22, 0x33, 0x44,
        ]),
      ];

      for (final original in samplePackets) {
        final uuid = BlePacketCodec.bytes16ToUuid(original);
        expect(uuid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));

        final recovered = BlePacketCodec.tryUuidToBytes16(uuid);
        expect(recovered, isNotNull);
        expect(recovered, equals(original));
      }
    });

    test('tryUuidToBytes16 tolera mayúsculas, minúsculas y formato entre llaves', () {
      const canonical = '01821200-16aa-bbcc-ddee-ff0011223344';
      final expectedBytes = Uint8List.fromList(<int>[
        0x01, 0x82, 0x12, 0x00, 0x16, 0xAA, 0xBB, 0xCC,
        0xDD, 0xEE, 0xFF, 0x00, 0x11, 0x22, 0x33, 0x44,
      ]);

      expect(BlePacketCodec.tryUuidToBytes16(canonical), equals(expectedBytes));
      expect(
        BlePacketCodec.tryUuidToBytes16(canonical.toUpperCase()),
        equals(expectedBytes),
      );
      expect(
        BlePacketCodec.tryUuidToBytes16('{$canonical}'),
        equals(expectedBytes),
      );
      expect(
        BlePacketCodec.tryUuidToBytes16('{${canonical.toUpperCase()}}'),
        equals(expectedBytes),
      );
      expect(
        BlePacketCodec.tryUuidToBytes16('0182120016aabbccddeeff0011223344'),
        equals(expectedBytes),
      );
    });

    test('rechazo de cadenas corruptas o longitudes erróneas en UUID', () {
      expect(BlePacketCodec.tryUuidToBytes16(''), isNull);
      expect(BlePacketCodec.tryUuidToBytes16('not-a-valid-uuid'), isNull);
      expect(BlePacketCodec.tryUuidToBytes16('01821200-16aa-bbcc-ddee-ff001122334'), isNull); // 31 chars
      expect(BlePacketCodec.tryUuidToBytes16('01821200-16aa-bbcc-ddee-ff001122334455'), isNull); // 34 chars
      expect(BlePacketCodec.tryUuidToBytes16('01821200-16aa-bbcc-ddee-ff00112233zz'), isNull); // caracteres 'zz'

      expect(() => BlePacketCodec.bytes16ToUuid(Uint8List(15)), throwsArgumentError);
      expect(() => BlePacketCodec.bytes16ToUuid(Uint8List(17)), throwsArgumentError);
    });
  });

  group('3. Construcción y verificación criptográfica del paquete BLE del Estudiante', () {
    const courseId = 'course-inf-2026';
    const bitIndex = 14;
    const sessionPin = 47;
    const timeTick = 200000;

    test('caso exitoso en el mismo timeTick', () {
      final packet = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick,
      );

      expect(packet, hasLength(BlePacketCodec.packetLength));
      // Flag de estudiante (0x80) con bitIndex
      expect(packet[2] & BlePacketCodec.studentPacketFlag, equals(0x80));
      expect(packet[2] & 0x3F, equals(bitIndex));
      expect(packet[3], equals(sessionPin));

      final verification = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packet,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
      );

      expect(verification.isValid, isTrue);
      expect(verification.bitIndex, equals(bitIndex));
      expect(verification.timeTick, equals(timeTick));
      expect(verification.failureReason, isNull);
    });

    test('tolerancia de reloj de +1 y -1 tick (±30 segundos)', () {
      final packetPlus1 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick + 1,
      );
      final packetMinus1 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick - 1,
      );

      final verifyPlus1 = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packetPlus1,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
        clockSkewToleranceTicks: 1,
      );
      expect(verifyPlus1.isValid, isTrue);
      expect(verifyPlus1.timeTick, equals(timeTick + 1));

      final verifyMinus1 = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packetMinus1,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
        clockSkewToleranceTicks: 1,
      );
      expect(verifyMinus1.isValid, isTrue);
      expect(verifyMinus1.timeTick, equals(timeTick - 1));
    });

    test('rechazo automático cuando el desfase supera la tolerancia (+2 y -2 ticks)', () {
      final packetSkewPlus2 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick + 2,
      );
      final packetSkewMinus2 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick - 2,
      );

      final verifyPlus2 = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packetSkewPlus2,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
        clockSkewToleranceTicks: 1,
      );
      expect(verifyPlus2.isValid, isFalse);
      expect(verifyPlus2.failureReason, contains('fuera de la ventana'));

      final verifyMinus2 = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packetSkewMinus2,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
        clockSkewToleranceTicks: 1,
      );
      expect(verifyMinus2.isValid, isFalse);
      expect(verifyMinus2.failureReason, contains('fuera de la ventana'));
    });

    test('rechazo automático cuando el PIN de 2 dígitos del salón no coincide', () {
      final packetPin47 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: 47,
        secretHex: _testStudentSecret,
        timeTick: timeTick,
      );

      final verifyWrongPin = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packetPin47,
        expectedCourseId: courseId,
        expectedSessionPin: 12, // Docente espera PIN 12
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
      );

      expect(verifyWrongPin.isValid, isFalse);
      expect(verifyWrongPin.failureReason, contains('PIN de la sesión no coincide'));
    });

    test('rechazo cuando se altera 1 solo bit del HMAC o secreto no corresponde', () {
      final validPacket = BlePacketCodec.buildStudentBeaconBytes(
        courseId: courseId,
        bitIndex: bitIndex,
        sessionPin: sessionPin,
        secretHex: _testStudentSecret,
        timeTick: timeTick,
      );

      // Alterar exactamente un bit en el HMAC (bytes 8 a 15)
      final tamperedHmacPacket = Uint8List.fromList(validPacket);
      tamperedHmacPacket[8] ^= 0x01;

      final verifyTampered = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: tamperedHmacPacket,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
      );
      expect(verifyTampered.isValid, isFalse);
      expect(verifyTampered.failureReason, contains('La firma HMAC del anuncio no es válida'));

      // Verificar con un secreto que no corresponde al estudiante
      final verifyWrongSecret = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: validPacket,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _otherSecret},
        currentTimeTick: timeTick,
      );
      expect(verifyWrongSecret.isValid, isFalse);
      expect(verifyWrongSecret.failureReason, contains('La firma HMAC del anuncio no es válida'));

      // Verificar cuando no hay secreto registrado para el bitIndex
      final verifyMissingSecret = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: validPacket,
        expectedCourseId: courseId,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{}, // vacío
        currentTimeTick: timeTick,
      );
      expect(verifyMissingSecret.isValid, isFalse);
      expect(verifyMissingSecret.failureReason, contains('No hay secreto registrado'));

      // Verificar con curso no coincidente
      final verifyWrongCourse = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: validPacket,
        expectedCourseId: 'otro-curso-distinto',
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{bitIndex: _testStudentSecret},
        currentTimeTick: timeTick,
      );
      expect(verifyWrongCourse.isValid, isFalse);
      expect(verifyWrongCourse.failureReason, contains('otro curso'));
    });
  });

  group('4. Construcción y verificación criptográfica del paquete de Eco del Docente', () {
    const courseId = 'course-inf-2026';
    const sessionId = 'session-2026-11-06-01';

    test('estudiante recupera bitmap8 intacto y detecta su bitIndex encendido', () {
      // Docente marca presente a estudiantes 5, 14 y 63
      var teacherBitmap = BlePacketCodec.createEmptyBitmap8();
      teacherBitmap = BlePacketCodec.setStudentBit(teacherBitmap, 5);
      teacherBitmap = BlePacketCodec.setStudentBit(teacherBitmap, 14);
      teacherBitmap = BlePacketCodec.setStudentBit(teacherBitmap, 63);

      final echoBytes = BlePacketCodec.buildTeacherEchoBytes(
        courseId: courseId,
        sessionId: sessionId,
        bitmap8: teacherBitmap,
        sharedSecretHex: _testCourseSecret,
      );

      expect(echoBytes, hasLength(BlePacketCodec.packetLength));
      // Flag de eco docente en byte 2 debe ser 0x00
      expect(echoBytes[2], equals(BlePacketCodec.teacherPacketFlag));

      final verifyResult = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: echoBytes,
        expectedCourseId: courseId,
        sharedSecretHex: _testCourseSecret,
      );

      expect(verifyResult.isValid, isTrue);
      expect(verifyResult.failureReason, isNull);
      expect(verifyResult.bitmap8, isNotNull);
      expect(verifyResult.bitmap8, equals(teacherBitmap));

      // El estudiante en bitIndex 14 comprueba que fue marcado como presente
      expect(BlePacketCodec.isStudentBitSet(verifyResult.bitmap8!, 14), isTrue);
      // El estudiante en bitIndex 5 comprueba que fue marcado como presente
      expect(BlePacketCodec.isStudentBitSet(verifyResult.bitmap8!, 5), isTrue);
      // El estudiante en bitIndex 63 comprueba que fue marcado como presente
      expect(BlePacketCodec.isStudentBitSet(verifyResult.bitmap8!, 63), isTrue);
      // El estudiante en bitIndex 0 comprueba que no fue marcado
      expect(BlePacketCodec.isStudentBitSet(verifyResult.bitmap8!, 0), isFalse);
    });

    test('rechazo automático de eco docente ante HMAC adulterado o curso erróneo', () {
      final validEcho = BlePacketCodec.buildTeacherEchoBytes(
        courseId: courseId,
        sessionId: sessionId,
        bitmap8: BlePacketCodec.createEmptyBitmap8(),
        sharedSecretHex: _testCourseSecret,
      );

      // Adulterar 1 bit en la firma HMAC del docente (bytes 12..15)
      final tamperedEcho = Uint8List.fromList(validEcho);
      tamperedEcho[13] ^= 0x02;

      final verifyTampered = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: tamperedEcho,
        expectedCourseId: courseId,
        sharedSecretHex: _testCourseSecret,
      );
      expect(verifyTampered.isValid, isFalse);
      expect(verifyTampered.failureReason, contains('La firma HMAC del eco no es válida'));

      // Verificar contra secreto compartido erróneo
      final verifyWrongSecret = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: validEcho,
        expectedCourseId: courseId,
        sharedSecretHex: _otherSecret,
      );
      expect(verifyWrongSecret.isValid, isFalse);
      expect(verifyWrongSecret.failureReason, contains('La firma HMAC del eco no es válida'));

      // Verificar contra curso erróneo
      final verifyWrongCourse = BlePacketCodec.verifyTeacherEchoBytes(
        packet16: validEcho,
        expectedCourseId: 'otro-curso-distinto',
        sharedSecretHex: _testCourseSecret,
      );
      expect(verifyWrongCourse.isValid, isFalse);
      expect(verifyWrongCourse.failureReason, contains('El eco pertenece a otro curso'));
    });
  });

  group('5. Ciclo extremo a extremo de Enrolamiento QR', () {
    late AppDatabase database;
    late RosterImportService rosterService;
    late StudentEnrollmentService enrollmentService;

    setUp(() {
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      rosterService = RosterImportService(database: database);
      enrollmentService = StudentEnrollmentService(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'crear curso y estudiante "0182120016", generar QR, enrolar y verificar credenciales',
      () async {
        const courseId = 'course-sistemas-301';
        const studentCodeWithLeadingZero = '0182120016';

        // 1. Crear el curso en AppDatabase
        final course = CourseModel(
          id: courseId,
          code: 'SIST-301',
          name: 'Sistemas Distribuidos',
          groupCode: '01',
          semester: '2026-2',
          courseSecret: _testCourseSecret,
          spreadsheetId: 'sheet-ug-distribuidos',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        await database.insertCourse(course);

        // 2. Dar de alta al estudiante preservando el código con su cero inicial
        final student = await rosterService.addManualStudent(
          courseId: courseId,
          studentCode: studentCodeWithLeadingZero,
          fullName: 'Carlos Alberto Perez Guajiro',
          email: 'cperez@uniguajira.edu.co',
        );

        expect(student.studentCode, equals(studentCodeWithLeadingZero));
        expect(student.studentCode.startsWith('0'), isTrue);
        expect(student.bitIndex, equals(0)); // Primer estudiante recibe bit 0
        expect(student.personalSecret, isNotEmpty);

        // 3. Generar el payload del QR con RosterImportService
        final qrPayloadJson = rosterService.generateEnrollmentQrPayload(
          course: course,
          student: student,
        );

        // Verificar contrato del QR
        final decodedQr = jsonDecode(qrPayloadJson) as Map<String, dynamic>;
        expect(decodedQr['studentCode'], equals('0182120016'));
        expect(decodedQr['bitmapIndex'], equals(0));
        expect(decodedQr['deviceSecret'], equals(student.personalSecret));
        expect(decodedQr['sharedSecret'], equals(course.courseSecret));

        // 4. Enrolar en el teléfono del estudiante con StudentEnrollmentService
        final enrolledModel = await enrollmentService.enrollFromQrPayload(qrPayloadJson);

        expect(enrolledModel.studentCode, equals('0182120016'));
        expect(enrolledModel.bitIndex, equals(0));
        expect(enrolledModel.deviceSecret, equals(student.personalSecret));
        expect(enrolledModel.sharedSecret, equals(course.courseSecret));

        // 5. Verificar persistencia en tabla student_enrollments
        final stored = await database.getStudentEnrollmentByCourse(courseId);
        expect(stored, isNotNull);
        expect(stored!.studentCode, equals('0182120016'));
        expect(stored.bitIndex, equals(0));
        expect(stored.deviceSecret, equals(student.personalSecret));
        expect(stored.sharedSecret, equals(course.courseSecret));

        // 6. Usar las credenciales enroladas para construir y verificar un paquete BLE
        const testPin = 88;
        const testTick = 300000;
        final studentPacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: stored.courseId,
          bitIndex: stored.bitIndex,
          sessionPin: testPin,
          secretHex: stored.deviceSecret,
          timeTick: testTick,
        );

        final verifyResult = BlePacketCodec.verifyStudentBeaconBytes(
          packet16: studentPacket,
          expectedCourseId: courseId,
          expectedSessionPin: testPin,
          secretHexByBitIndex: <int, String>{stored.bitIndex: student.personalSecret},
          currentTimeTick: testTick,
        );

        expect(verifyResult.isValid, isTrue);
        expect(verifyResult.bitIndex, equals(0));
      },
    );
  });

  group('6. Simulación de inyección de paquetes en BleAttendanceService', () {
    test('acepta paquete dentro del aula (-65 dBm) y descarta en pasillo (-88 dBm)', () async {
      final bleService = BleAttendanceService(
        minRssiDbm: AppConstants.minRssiDbm, // -75 dBm
      );
      addTearDown(bleService.dispose);

      final dummyPacket = Uint8List.fromList(
        List<int>.generate(16, (int i) => (i * 3 + 1) & 0xFF),
      );

      final eventsReceived = <BlePacketEvent>[];
      final subscription = bleService.packetEvents.listen(eventsReceived.add);
      addTearDown(subscription.cancel);

      // Inyección en pasillo (-88 dBm, menor al umbral -75 dBm) => DESCARTADO
      final hallwayResult = bleService.injectSimulatedPacket(
        packet16: dummyPacket,
        rssi: -88,
      );
      expect(hallwayResult, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(eventsReceived, isEmpty);

      // Inyección dentro del aula (-65 dBm, mayor a -75 dBm) => ACEPTADO
      final classroomResult = bleService.injectSimulatedPacket(
        packet16: dummyPacket,
        rssi: -65,
      );
      expect(classroomResult, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(eventsReceived, hasLength(1));
      expect(eventsReceived.first.rssi, equals(-65));
      expect(eventsReceived.first.packet16, equals(dummyPacket));

      // Inyección en el umbral exacto (-75 dBm) => ACEPTADO
      final boundaryResult = bleService.injectSimulatedPacket(
        packet16: dummyPacket,
        rssi: -75,
      );
      expect(boundaryResult, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(eventsReceived, hasLength(2));
      expect(eventsReceived.last.rssi, equals(-75));
    });
  });

  group('7. Generación del token de auditoría Sello Verde', () {
    test('genera token determinista con prefijo UG- y 8 caracteres hexadecimales', () {
      const courseId = 'course-1';
      const studentCode = '0182120016';
      const bitIndex = 14;
      const timeTick = 12345;

      final token1 = BlePacketCodec.generateAttendanceVerifyCode(
        courseId: courseId,
        studentCode: studentCode,
        bitIndex: bitIndex,
        timeTick: timeTick,
        secretHex: _testStudentSecret,
      );

      final token2 = BlePacketCodec.generateAttendanceVerifyCode(
        courseId: courseId,
        studentCode: studentCode,
        bitIndex: bitIndex,
        timeTick: timeTick,
        secretHex: _testStudentSecret,
      );

      expect(token1, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
      expect(token1, equals(token2));

      // Diferente timeTick genera diferente token
      final tokenDifferentTick = BlePacketCodec.generateAttendanceVerifyCode(
        courseId: courseId,
        studentCode: studentCode,
        bitIndex: bitIndex,
        timeTick: timeTick + 1,
        secretHex: _testStudentSecret,
      );
      expect(tokenDifferentTick, isNot(equals(token1)));

      // Diferente studentCode genera diferente token
      final tokenDifferentCode = BlePacketCodec.generateAttendanceVerifyCode(
        courseId: courseId,
        studentCode: '0182110099',
        bitIndex: bitIndex,
        timeTick: timeTick,
        secretHex: _testStudentSecret,
      );
      expect(tokenDifferentCode, isNot(equals(token1)));
    });
  });
}
