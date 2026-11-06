import 'dart:convert';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/student_enrollment_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/attendance_session_controller.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _courseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _studentSecret0 =
    '1111111111111111111111111111111111111111111111111111111111111111';
const String _studentSecret1 =
    '2222222222222222222222222222222222222222222222222222222222222222';
const String _studentSecret2 =
    '3333333333333333333333333333333333333333333333333333333333333333';
const String _studentSecret63 =
    '4444444444444444444444444444444444444444444444444444444444444444';

CourseModel _course() {
  return const CourseModel(
    id: 'course-session-1',
    code: 'SIST-301',
    name: 'Sistemas Distribuidos',
    groupCode: '01',
    semester: '2026-2',
    courseSecret: _courseSecret,
    createdAt: '2026-11-06T08:00:00.000Z',
  );
}

StudentModel _student({
  required String id,
  required String studentCode,
  required String fullName,
  required int bitIndex,
  required String personalSecret,
}) {
  return StudentModel(
    id: id,
    courseId: 'course-session-1',
    studentCode: studentCode,
    fullName: fullName,
    email: '$studentCode${AppConstants.institutionalDomain}',
    bitIndex: bitIndex,
    personalSecret: personalSecret,
    enrolledAt: '2026-11-06T08:02:00.000Z',
  );
}

StudentEnrollmentModel _enrollment(StudentModel student) {
  return StudentEnrollmentModel(
    id: '${student.courseId}_${student.studentCode}',
    courseId: student.courseId,
    courseCode: 'SIST-301',
    courseName: 'Sistemas Distribuidos',
    studentId: student.id,
    studentCode: student.studentCode,
    fullName: student.fullName,
    bitIndex: student.bitIndex,
    deviceSecret: student.personalSecret,
    sharedSecret: _courseSecret,
    enrolledAtEpochMs: 1762416120000,
  );
}

class _FakeBleAttendanceService extends BleAttendanceService {
  final List<Uint8List> advertisements = <Uint8List>[];
  final List<String> lifecycle = <String>[];

  @override
  Future<void> startScan({Duration? timeout}) async {
    lifecycle.add('scan-start');
  }

  @override
  Future<void> stopScan() async {
    lifecycle.add('scan-stop');
  }

  @override
  Future<void> startAdvertisingPacket(Uint8List packet16) async {
    advertisements.add(Uint8List.fromList(packet16));
  }

  @override
  Future<void> stopAdvertising() async {
    lifecycle.add('ad-stop');
  }
}

Future<void> _waitUntil(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('La condición asíncrona no se cumplió en 2 segundos.');
}

void main() {
  sqfliteFfiInit();

  group('AttendanceSessionController', () {
    late AppDatabase database;
    late _FakeBleAttendanceService ble;
    late AttendanceSessionController controller;
    late CourseModel course;
    late StudentModel student0;
    late StudentModel student1;
    late StudentModel student2;
    late StudentModel student63;

    setUp(() async {
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      course = _course();
      await database.insertCourse(course);
      student0 = _student(
        id: 'student-0',
        studentCode: '0182120016',
        fullName: 'ANA MARIA GOMEZ',
        bitIndex: 0,
        personalSecret: _studentSecret0,
      );
      student1 = _student(
        id: 'student-1',
        studentCode: '0182120017',
        fullName: 'LUIS ALBERTO PEREZ',
        bitIndex: 1,
        personalSecret: _studentSecret1,
      );
      student2 = _student(
        id: 'student-2',
        studentCode: '0182120018',
        fullName: 'SOFIA GARRIDO',
        bitIndex: 2,
        personalSecret: _studentSecret2,
      );
      student63 = _student(
        id: 'student-63',
        studentCode: '0182120063',
        fullName: 'CARLOS ENRIQUE VALDEZ',
        bitIndex: 63,
        personalSecret: _studentSecret63,
      );
      for (final StudentModel student in <StudentModel>[
        student0,
        student1,
        student2,
        student63,
      ]) {
        await database.insertStudent(student);
      }
      ble = _FakeBleAttendanceService();
      controller = AttendanceSessionController(
        database: database,
        bleService: ble,
      );
    });

    tearDown(() async {
      await controller.dispose();
      await ble.dispose();
      await database.close();
    });

    // -------------------------------------------------------------------------
    // 1. Inicio de sesión docente y configuración inicial
    // -------------------------------------------------------------------------
    test(
      '1.1 startTeacherSession inicializa sesión con PIN de 2 dígitos, roster y bitmap8 en ceros',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );

        expect(state.pin, 42);
        expect(state.session.roomPin, '42');
        expect(state.session.closedAt, isNull);
        expect(state.isOpen, isTrue);
        expect(state.isClosed, isFalse);
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(state.bitmap8.length, BlePacketCodec.bitmapLength);
        expect(state.bitmap8.every((int byte) => byte == 0), isTrue);
        expect(state.students, hasLength(4));
        expect(state.totalEnrolled, 4);
        expect(state.presentBitIndices, isEmpty);

        // Mapa de secretos por bitIndex
        expect(state.secretHexByBitIndex[0], _studentSecret0);
        expect(state.secretHexByBitIndex[1], _studentSecret1);
        expect(state.secretHexByBitIndex[2], _studentSecret2);
        expect(state.secretHexByBitIndex[63], _studentSecret63);

        // Hardware BLE iniciado
        expect(ble.lifecycle, contains('scan-start'));
        expect(ble.advertisements, isNotEmpty);

        // Persistencia en SQLite
        final stored = await database.getSessionById(state.session.id);
        expect(stored, isNotNull);
        expect(stored!.roomPin, '42');
        expect(stored.bitmapHex, AppConstants.emptyBitmapHex);
        expect(stored.closedAt, isNull);

        final sessions = await database.getSessionsByCourse(course.id);
        expect(sessions, hasLength(1));
      },
    );

    test(
      '1.2 startTeacherSession genera PIN verbal aleatorio (10..99) cuando no se pasa customPin',
      () async {
        final state = await controller.startTeacherSession(course: course);

        expect(state.pin, inInclusiveRange(AppConstants.minimumSessionPin, AppConstants.maximumSessionPin));
        expect(state.sessionPin.length, AppConstants.roomPinLength);
        expect(int.parse(state.sessionPin), state.pin);
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
      },
    );

    test(
      '1.3 startTeacherSession rechaza abrir una segunda sesión si ya existe una abierta',
      () async {
        await controller.startTeacherSession(course: course, customPin: 42);

        await expectLater(
          controller.startTeacherSession(course: course, customPin: 77),
          throwsStateError,
        );
      },
    );

    test(
      '1.4 startTeacherSession rechaza PINs fuera del rango institucional 10..99',
      () async {
        await expectLater(
          controller.startTeacherSession(course: course, customPin: 9),
          throwsArgumentError,
        );
        await expectLater(
          controller.startTeacherSession(course: course, customPin: 100),
          throwsArgumentError,
        );
        expect(await database.getSessionsByCourse(course.id), isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // 2. Procesamiento de paquetes BLE de múltiples estudiantes (incluyendo bitIndex 63)
    // -------------------------------------------------------------------------
    test(
      '2.1 processIncomingStudentPacket enciende bits 0, 1 y 63 en bitmap8 y persiste registros con UG-XXXXXXXX',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 0, 0);
        final tick = BlePacketCodec.computeTimeTick(now);

        // 1. Paquete para estudiante bitIndex 0
        final packet0 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );
        final outcome0 = await controller.processIncomingStudentPacket(
          packet16: packet0,
          rssi: -65,
          nowOverride: now,
        );

        expect(outcome0.isAccepted, isTrue);
        expect(outcome0.student?.id, student0.id);
        expect(outcome0.bitIndex, 0);
        expect(outcome0.rssi, -65);
        expect(outcome0.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
        expect(outcome0.bitmapHex, '0100000000000000');
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 0), isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isFalse);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 63), isFalse);

        // 2. Paquete para estudiante bitIndex 1
        final packet1 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student1.bitIndex,
          sessionPin: 42,
          secretHex: student1.personalSecret,
          timeTick: tick,
        );
        final outcome1 = await controller.processIncomingStudentPacket(
          packet16: packet1,
          rssi: -62,
          nowOverride: now,
        );

        expect(outcome1.isAccepted, isTrue);
        expect(outcome1.student?.id, student1.id);
        expect(outcome1.bitIndex, 1);
        expect(outcome1.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
        expect(outcome1.bitmapHex, '0300000000000000');
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 0), isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 63), isFalse);

        // 3. Paquete para estudiante bitIndex 63 (límite superior de 64 bits)
        final packet63 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student63.bitIndex,
          sessionPin: 42,
          secretHex: student63.personalSecret,
          timeTick: tick,
        );
        final outcome63 = await controller.processIncomingStudentPacket(
          packet16: packet63,
          rssi: -58,
          nowOverride: now,
        );

        expect(outcome63.isAccepted, isTrue);
        expect(outcome63.student?.id, student63.id);
        expect(outcome63.bitIndex, 63);
        expect(outcome63.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));

        // 03 en el byte 0 (bits 0 y 1) y 80 en el byte 7 (bit 63: 1 << 7 = 0x80)
        expect(outcome63.bitmapHex, '0300000000000080');
        expect(state.bitmapHex, '0300000000000080');
        expect(state.presentBitIndices, <int>[0, 1, 63]);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 0), isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 2), isFalse);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 63), isTrue);

        // Verificación de persistencia en SQLite
        final records = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(records, hasLength(3));
        for (final record in records) {
          expect(record.method, AppConstants.attendanceMethodBleHmac);
          expect(record.hmacTag, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
          expect(record.timeTick, tick);
          expect(record.sessionId, state.session.id);
        }

        final record0 = records.firstWhere((r) => r.studentId == student0.id);
        expect(record0.bitIndex, 0);
        expect(record0.hmacTag, outcome0.verifyCode);
        expect(record0.rssiAvg, -65.0);

        final record1 = records.firstWhere((r) => r.studentId == student1.id);
        expect(record1.bitIndex, 1);
        expect(record1.hmacTag, outcome1.verifyCode);
        expect(record1.rssiAvg, -62.0);

        final record63 = records.firstWhere((r) => r.studentId == student63.id);
        expect(record63.bitIndex, 63);
        expect(record63.hmacTag, outcome63.verifyCode);
        expect(record63.rssiAvg, -58.0);

        // Verificación del eco docente con el bitmap actualizado
        final echo = BlePacketCodec.verifyTeacherEchoBytes(
          packet16: ble.advertisements.last,
          expectedCourseId: course.id,
          sharedSecretHex: course.courseSecret,
        );
        expect(echo.isValid, isTrue);
        expect(BlePacketCodec.extractPresentBitIndices(echo.bitmap8!), <int>[0, 1, 63]);
      },
    );

    test(
      '2.2 processIncomingStudentPacket es idempotente ante recepciones repetidas y actualiza RSSI',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 0, 0);
        final tick = BlePacketCodec.computeTimeTick(now);
        final packet = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );

        final first = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -70,
          nowOverride: now,
        );
        expect(first.isAccepted, isTrue);

        final recordsFirst = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(recordsFirst, hasLength(1));
        expect(recordsFirst.first.rssiAvg, -70.0);

        // Envío repetido con mejor señal
        final second = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -55,
          nowOverride: now,
        );
        expect(second.isAccepted, isTrue);

        final recordsSecond = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(recordsSecond, hasLength(1));
        expect(recordsSecond.first.rssiAvg, -55.0);
        expect(state.bitmapHex, '0100000000000000');
      },
    );

    // -------------------------------------------------------------------------
    // 3. Rechazo de paquetes BLE en la sesión (RSSI débil, PIN erróneo, HMAC inválido)
    // -------------------------------------------------------------------------
    test(
      '3.1 rechaza paquetes cuando el RSSI es débil (-85 dBm y -76 dBm < -75 dBm umbral de aula)',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 1, 0);
        final tick = BlePacketCodec.computeTimeTick(now);
        final packet = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );

        // Estudiante en el pasillo a -85 dBm
        final hallwayOutcome = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -85,
          nowOverride: now,
        );
        expect(hallwayOutcome.isAccepted, isFalse);
        expect(
          hallwayOutcome.failureReason,
          contains('El RSSI -85 dBm no alcanza el umbral -75 dBm'),
        );
        expect(hallwayOutcome.record, isNull);
        expect(hallwayOutcome.verifyCode, isNull);

        // Estudiante justo fuera del umbral (-76 dBm)
        final boundaryOutcome = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -76,
          nowOverride: now,
        );
        expect(boundaryOutcome.isAccepted, isFalse);
        expect(
          boundaryOutcome.failureReason,
          contains('El RSSI -76 dBm no alcanza el umbral -75 dBm'),
        );

        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
      },
    );

    test(
      '3.2 rechaza paquetes cuando el PIN verbal de 2 dígitos es incorrecto',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 1, 0);
        final tick = BlePacketCodec.computeTimeTick(now);

        // Estudiante escuchó mal el PIN verbal y puso 99 en vez de 42
        final wrongPinPacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 99,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );

        final outcome = await controller.processIncomingStudentPacket(
          packet16: wrongPinPacket,
          rssi: -60,
          nowOverride: now,
        );

        expect(outcome.isAccepted, isFalse);
        expect(outcome.failureReason, contains('El PIN de la sesión no coincide'));
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
      },
    );

    test(
      '3.3 rechaza paquetes cuando la firma HMAC-SHA256 es inválida o adulterada',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 1, 0);
        final tick = BlePacketCodec.computeTimeTick(now);
        final validPacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );

        // 1. Bit alterado en la sección HMAC del paquete
        final tamperedPacket = Uint8List.fromList(validPacket);
        tamperedPacket[8] ^= 0x01;

        final tamperedOutcome = await controller.processIncomingStudentPacket(
          packet16: tamperedPacket,
          rssi: -60,
          nowOverride: now,
        );

        expect(tamperedOutcome.isAccepted, isFalse);
        expect(tamperedOutcome.failureReason, contains('La firma HMAC del anuncio no es válida'));

        // 2. Paquete firmado con secreto no correspondiente
        final wrongSecretPacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: _studentSecret1, // Secreto ajeno
          timeTick: tick,
        );

        final wrongSecretOutcome = await controller.processIncomingStudentPacket(
          packet16: wrongSecretPacket,
          rssi: -60,
          nowOverride: now,
        );

        expect(wrongSecretOutcome.isAccepted, isFalse);
        expect(wrongSecretOutcome.failureReason, contains('La firma HMAC del anuncio no es válida'));
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
      },
    );

    test(
      '3.4 rechaza paquetes pertenecientes a otro curso o con desfase temporal excesivo',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.utc(2026, 11, 6, 15, 1, 0);
        final tick = BlePacketCodec.computeTimeTick(now);

        // 1. Paquete generado para otro curso
        final foreignCoursePacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: 'course-otro-curso-99',
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick,
        );
        final foreignOutcome = await controller.processIncomingStudentPacket(
          packet16: foreignCoursePacket,
          rssi: -60,
          nowOverride: now,
        );
        expect(foreignOutcome.isAccepted, isFalse);
        expect(foreignOutcome.failureReason, contains('El anuncio pertenece a otro curso'));

        // 2. Paquete con tick desfasado más de 1 ventana (30s)
        final expiredPacket = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: tick - 3,
        );
        final expiredOutcome = await controller.processIncomingStudentPacket(
          packet16: expiredPacket,
          rssi: -60,
          nowOverride: now,
        );
        expect(expiredOutcome.isAccepted, isFalse);
        expect(expiredOutcome.failureReason, contains('El tick del anuncio está fuera de la ventana'));
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
      },
    );

    // -------------------------------------------------------------------------
    // 4. Funcionamiento de la Lista Invertida (toggleManualAttendance)
    // -------------------------------------------------------------------------
    test(
      '4.1 toggleManualAttendance marca a estudiante sin celular como MANUAL_INVERTED y enciende su bit en bitmap8',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );

        await controller.toggleManualAttendance(
          studentId: student2.id,
          isPresent: true,
          observation: 'Estudiante sin celular / batería descargada',
        );

        // Bit 2 encendido (1 << 2 = 0x04)
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 2), isTrue);
        expect(state.bitmapHex, '0400000000000000');
        expect(state.session.bitmapHex, '0400000000000000');

        final records = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(records, hasLength(1));
        expect(records.first.studentId, student2.id);
        expect(records.first.bitIndex, 2);
        expect(
          records.first.method,
          AppConstants.attendanceMethodManualInverted,
        );
        expect(
          records.first.observation,
          'Estudiante sin celular / batería descargada',
        );
        expect(records.first.hmacTag, isNull);
        expect(records.first.timeTick, isNotNull);

        // El eco docente emitido refleja el bit 2 encendido
        final echo = BlePacketCodec.verifyTeacherEchoBytes(
          packet16: ble.advertisements.last,
          expectedCourseId: course.id,
          sharedSecretHex: course.courseSecret,
        );
        expect(echo.isValid, isTrue);
        expect(BlePacketCodec.isStudentBitSet(echo.bitmap8!, 2), isTrue);
      },
    );

    test(
      '4.2 toggleManualAttendance desmarca a estudiante (isPresent: false), apaga su bit y elimina registro SQLite',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );

        // Primero se marca
        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: true,
          observation: 'Asistencia manual previa',
        );
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isTrue);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          hasLength(1),
        );

        // Ahora se desmarca
        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: false,
        );

        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isFalse);
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(state.session.bitmapHex, AppConstants.emptyBitmapHex);

        final recordsAfter = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(recordsAfter, isEmpty);

        final storedSession = await database.getSessionById(state.session.id);
        expect(storedSession!.bitmapHex, AppConstants.emptyBitmapHex);

        // El eco docente emitido refleja el bit apagado
        final echo = BlePacketCodec.verifyTeacherEchoBytes(
          packet16: ble.advertisements.last,
          expectedCourseId: course.id,
          sharedSecretHex: course.courseSecret,
        );
        expect(echo.isValid, isTrue);
        expect(BlePacketCodec.isStudentBitSet(echo.bitmap8!, 1), isFalse);
      },
    );

    test(
      '4.3 toggleManualAttendance rechaza estudiante que no pertenezca al curso',
      () async {
        await controller.startTeacherSession(course: course, customPin: 42);

        await expectLater(
          controller.toggleManualAttendance(
            studentId: 'student-no-existe',
            isPresent: true,
          ),
          throwsArgumentError,
        );
      },
    );

    // -------------------------------------------------------------------------
    // 5. Confirmación en el teléfono del estudiante (checkTeacherEchoForStudent)
    // -------------------------------------------------------------------------
    test(
      '5.1 checkTeacherEchoForStudent confirma con Sello Verde UG-XXXXXXXX cuando el bit está encendido',
      () async {
        final enrollment = _enrollment(student0);
        final now = DateTime.utc(2026, 11, 6, 15, 3, 0);

        // Docente emite eco con bitIndex 0 encendido
        final bitmapWithBit0 = BlePacketCodec.setStudentBit(
          BlePacketCodec.createEmptyBitmap8(),
          0,
        );
        final teacherEcho = BlePacketCodec.buildTeacherEchoBytes(
          courseId: course.id,
          sessionId: 'session-echo-demo-1',
          bitmap8: bitmapWithBit0,
          sharedSecretHex: course.courseSecret,
        );

        final outcome = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: teacherEcho,
          rssi: -64,
          nowOverride: now,
        );

        final expectedVerifyCode = BlePacketCodec.generateAttendanceVerifyCode(
          courseId: course.id,
          studentCode: enrollment.studentCode,
          bitIndex: enrollment.bitIndex,
          timeTick: BlePacketCodec.computeTimeTick(now),
          secretHex: enrollment.deviceSecret,
        );

        expect(outcome.isConfirmed, isTrue);
        expect(outcome.isGreenSeal, isTrue);
        expect(outcome.isValid, isTrue);
        expect(outcome.verifyCode, expectedVerifyCode);
        expect(outcome.token, expectedVerifyCode);
        expect(outcome.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
        expect(outcome.bitmapHex, '0100000000000000');
        expect(outcome.bitIndex, 0);
        expect(outcome.rssi, -64);
        expect(outcome.isNearby, isTrue);
        expect(outcome.sessionPin, 42);
        expect(outcome.confirmedAt, now);
        expect(outcome.confirmedAtIso, now.toIso8601String());
        expect(outcome.failureReason, isNull);
      },
    );

    test(
      '5.2 checkTeacherEchoForStudent retorna no confirmado cuando el bit del estudiante sigue en cero',
      () async {
        final enrollment = _enrollment(student0);
        final now = DateTime.utc(2026, 11, 6, 15, 3, 0);

        // Docente emite eco con solo bitIndex 1 encendido (el bit 0 está en 0)
        final bitmapOnlyBit1 = BlePacketCodec.setStudentBit(
          BlePacketCodec.createEmptyBitmap8(),
          1,
        );
        final teacherEcho = BlePacketCodec.buildTeacherEchoBytes(
          courseId: course.id,
          sessionId: 'session-echo-demo-1',
          bitmap8: bitmapOnlyBit1,
          sharedSecretHex: course.courseSecret,
        );

        final outcome = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: teacherEcho,
          rssi: -64,
          nowOverride: now,
        );

        expect(outcome.isConfirmed, isFalse);
        expect(outcome.isGreenSeal, isFalse);
        expect(outcome.verifyCode, isNull);
        expect(
          outcome.failureReason,
          contains('El docente aún no ha marcado al estudiante como presente'),
        );
        expect(outcome.bitmapHex, '0200000000000000');
        expect(outcome.bitIndex, 0);
      },
    );

    test(
      '5.3 checkTeacherEchoForStudent rechaza ecos con firma HMAC adulterada o curso incorrecto',
      () async {
        final enrollment = _enrollment(student0);
        final now = DateTime.utc(2026, 11, 6, 15, 3, 0);
        final bitMap = BlePacketCodec.setStudentBit(
          BlePacketCodec.createEmptyBitmap8(),
          0,
        );
        final validTeacherEcho = BlePacketCodec.buildTeacherEchoBytes(
          courseId: course.id,
          sessionId: 'session-echo-demo-1',
          bitmap8: bitMap,
          sharedSecretHex: course.courseSecret,
        );

        // 1. Eco adulterado en la firma
        final tamperedEcho = Uint8List.fromList(validTeacherEcho);
        tamperedEcho[12] ^= 0x01;

        final tamperedOutcome = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: tamperedEcho,
          rssi: -60,
          nowOverride: now,
        );
        expect(tamperedOutcome.isConfirmed, isFalse);
        expect(
          tamperedOutcome.failureReason,
          contains('La firma HMAC del eco no es válida'),
        );

        // 2. Eco de otro curso
        final foreignCourseEcho = BlePacketCodec.buildTeacherEchoBytes(
          courseId: 'otro-curso-xyz',
          sessionId: 'session-echo-demo-1',
          bitmap8: bitMap,
          sharedSecretHex: course.courseSecret,
        );
        final foreignOutcome = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: foreignCourseEcho,
          rssi: -60,
          nowOverride: now,
        );
        expect(foreignOutcome.isConfirmed, isFalse);
        expect(
          foreignOutcome.failureReason,
          contains('El eco pertenece a otro curso'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // 6. Cierre de sesión y firma criptográfica del Acta (closeAndSignSession)
    // -------------------------------------------------------------------------
    test(
      '6.1 closeAndSignSession firma criptográficamente el acta y cuadra matemáticamente presentes y ausentes',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final bleNow = DateTime.utc(2026, 11, 6, 15, 2, 0);

        // 1. Estudiante 0 se registra por BLE
        final packet0 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: BlePacketCodec.computeTimeTick(bleNow),
        );
        await controller.processIncomingStudentPacket(
          packet16: packet0,
          rssi: -62,
          nowOverride: bleNow,
        );

        // 2. Estudiante 1 se registra por Lista Invertida
        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: true,
          observation: 'Asistencia manual verificada',
        );

        // Estudiantes 2 y 63 quedan sin marcar (deben quedar contabilizados como ausentes)
        final closedAt = DateTime.utc(2026, 11, 6, 16, 0, 0);
        final acta = await controller.closeAndSignSession(
          closedAtOverride: closedAt,
        );

        // Verificación de cabecera y conteos
        expect(acta.sessionId, state.session.id);
        expect(acta.courseId, course.id);
        expect(acta.courseCode, 'SIST-301');
        expect(acta.courseName, 'Sistemas Distribuidos');
        expect(acta.sessionPin, '42');
        expect(acta.startedAtIso, state.session.startedAt);
        expect(acta.closedAtIso, closedAt.toIso8601String());

        expect(acta.totalEnrolled, 4);
        expect(acta.presentBleCount, 1);
        expect(acta.presentManualCount, 1);
        expect(acta.absentCount, 2);

        // Invariante matemático absoluto
        expect(
          acta.presentBleCount + acta.presentManualCount + acta.absentCount,
          acta.totalEnrolled,
        );

        // Bitmap final con bits 0 y 1 encendidos
        expect(acta.bitmapHex, '0300000000000000');

        // Verificación de registros ordenados por bitIndex
        expect(acta.records, hasLength(4));
        expect(
          acta.records.map((SessionActaRecord r) => r.bitIndex).toList(),
          <int>[0, 1, 2, 63],
        );

        // Estudiante 0: Presente BLE
        final r0 = acta.records[0];
        expect(r0.bitIndex, 0);
        expect(r0.studentCode, student0.studentCode);
        expect(r0.status, AppConstants.attendanceStatusPresent);
        expect(r0.method, AppConstants.attendanceMethodBleHmac);
        expect(r0.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
        expect(r0.rssi, -62);
        expect(r0.isPresent, isTrue);
        expect(r0.isAbsent, isFalse);

        // Estudiante 1: Presente Manual Invertido
        final r1 = acta.records[1];
        expect(r1.bitIndex, 1);
        expect(r1.studentCode, student1.studentCode);
        expect(r1.status, AppConstants.attendanceStatusPresent);
        expect(r1.method, AppConstants.attendanceMethodManualInverted);
        expect(r1.verifyCode, isNull);
        expect(r1.rssi, isNull);
        expect(r1.isPresent, isTrue);

        // Estudiante 2: Ausente
        final r2 = acta.records[2];
        expect(r2.bitIndex, 2);
        expect(r2.studentCode, student2.studentCode);
        expect(r2.status, AppConstants.attendanceStatusAbsent);
        expect(r2.method, isNull);
        expect(r2.verifyCode, isNull);
        expect(r2.rssi, isNull);
        expect(r2.isPresent, isFalse);
        expect(r2.isAbsent, isTrue);

        // Estudiante 63: Ausente
        final r63 = acta.records[3];
        expect(r63.bitIndex, 63);
        expect(r63.studentCode, student63.studentCode);
        expect(r63.status, AppConstants.attendanceStatusAbsent);
        expect(r63.method, isNull);
        expect(r63.verifyCode, isNull);
        expect(r63.isPresent, isFalse);
        expect(r63.isAbsent, isTrue);

        // Verificación criptográfica de la firma HMAC-SHA256 del acta
        expect(acta.actaHmacSignature, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(acta.signature, acta.actaHmacSignature);
        final expectedHmac = Hmac(
          sha256,
          utf8.encode(course.courseSecret),
        ).convert(utf8.encode(acta.canonicalJson)).toString();
        expect(acta.actaHmacSignature, expectedHmac);
        expect(acta.verifySignature(course.courseSecret), isTrue);
        expect(acta.verifySignature('clave-falsa-adulterada-0000000000000000'), isFalse);

        // Verificación en base de datos SQLite
        final storedSession = await database.getSessionById(state.session.id);
        expect(storedSession!.closedAt, closedAt.toIso8601String());
        expect(storedSession.bitmapHex, '0300000000000000');
        expect(storedSession.actHash, hasLength(64));

        final storedActaJson = await database.getSessionActaJson(state.session.id);
        expect(storedActaJson, isNotNull);
        final decoded = jsonDecode(storedActaJson!) as Map<String, dynamic>;
        expect(decoded['actaHmacSignature'], acta.actaHmacSignature);
        expect(decoded['records'], hasLength(4));

        final storedSignature = await database.getSessionActaSignature(state.session.id);
        expect(storedSignature, acta.actaHmacSignature);

        // Verificación del ciclo de hardware BLE al cerrar
        expect(ble.lifecycle, contains('scan-stop'));
        expect(ble.lifecycle, contains('ad-stop'));
        expect(state.isClosed, isTrue);
        expect(state.isOpen, isFalse);

        // Idempotencia: llamar a closeAndSignSession nuevamente retorna la misma instancia
        final repeated = await controller.closeAndSignSession();
        expect(identical(repeated, acta), isTrue);
      },
    );

    test(
      '6.2 rechaza modificaciones sobre una sesión cerrada',
      () async {
        await controller.startTeacherSession(course: course, customPin: 42);
        await controller.closeAndSignSession();

        // Procesar paquete BLE en sesión cerrada falla con motivo descriptivo
        final now = DateTime.now();
        final packet = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: BlePacketCodec.computeTimeTick(now),
        );
        final outcome = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -60,
        );
        expect(outcome.isAccepted, isFalse);
        expect(outcome.failureReason, contains('No hay una sesión docente abierta'));

        // Toggle manual en sesión cerrada lanza StateError
        await expectLater(
          controller.toggleManualAttendance(
            studentId: student0.id,
            isPresent: true,
          ),
          throwsStateError,
        );
      },
    );

    // -------------------------------------------------------------------------
    // 7. Ingesta automática mediante Stream de eventos BLE
    // -------------------------------------------------------------------------
    test(
      '7.1 procesa automáticamente anuncios entrantes desde el Stream reactivo BLE',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );
        final now = DateTime.now();
        final packet = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 42,
          secretHex: student0.personalSecret,
          timeTick: BlePacketCodec.computeTimeTick(now),
        );

        expect(ble.injectSimulatedPacket(packet16: packet, rssi: -59), isTrue);

        await _waitUntil(() async {
          final records = await database.getAttendanceRecordsBySession(
            state.session.id,
          );
          return records.isNotEmpty;
        });

        expect(controller.lastDetectionOutcome?.isAccepted, isTrue);
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 0), isTrue);

        final records = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(records, hasLength(1));
        expect(records.first.studentId, student0.id);
        expect(records.first.method, AppConstants.attendanceMethodBleHmac);
      },
    );

    // -------------------------------------------------------------------------
    // 8. Ciclo de vida y liberación de recursos (dispose)
    // -------------------------------------------------------------------------
    test(
      '8.1 dispose libera timers, suscripciones BLE e impide operaciones posteriores',
      () async {
        await controller.startTeacherSession(course: course, customPin: 42);
        await controller.dispose();

        expect(controller.state, isNull);
        expect(ble.lifecycle, contains('scan-stop'));
        expect(ble.lifecycle, contains('ad-stop'));

        expect(
          () => controller.startTeacherSession(course: course, customPin: 42),
          throwsStateError,
        );
        expect(
          () => controller.processIncomingStudentPacket(
            packet16: Uint8List(16),
            rssi: -60,
          ),
          throwsStateError,
        );
        expect(
          () => controller.toggleManualAttendance(
            studentId: student0.id,
            isPresent: true,
          ),
          throwsStateError,
        );
        expect(
          () => controller.closeAndSignSession(),
          throwsStateError,
        );

        // Múltiples dispose son idempotentes y no lanzan error
        await expectLater(controller.dispose(), completes);
      },
    );
  });
}
