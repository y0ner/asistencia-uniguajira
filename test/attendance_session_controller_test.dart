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
      for (final StudentModel student in <StudentModel>[
        student0,
        student1,
        student2,
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

    test(
      'inicia una sesión con PIN, roster, Bitmap vacío y radar BLE',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );

        expect(state.pin, 42);
        expect(state.session.roomPin, '42');
        expect(state.session.closedAt, isNull);
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(state.students, hasLength(3));
        expect(state.secretHexByBitIndex[0], _studentSecret0);
        expect(state.studentById[student1.id]!.studentCode, '0182120017');
        expect(ble.lifecycle, contains('scan-start'));
        expect(ble.advertisements, isNotEmpty);

        final stored = await database.getSessionById(state.session.id);
        expect(stored, isNotNull);
        expect(stored!.roomPin, '42');
        expect(stored.bitmapHex, AppConstants.emptyBitmapHex);
        expect(await database.getSessionsByCourse(course.id), hasLength(1));
      },
    );

    test('rechaza un PIN personalizado fuera del rango 10..99', () async {
      await expectLater(
        controller.startTeacherSession(course: course, customPin: 9),
        throwsArgumentError,
      );
      expect(await database.getSessionsByCourse(course.id), isEmpty);
    });

    test(
      'valida el anuncio BLE, persiste y actualiza el eco docente',
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
        final initialAdvertisements = ble.advertisements.length;

        final outcome = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -61,
          nowOverride: now,
        );

        expect(outcome.isAccepted, isTrue);
        expect(outcome.isValid, isTrue);
        expect(outcome.student?.id, student0.id);
        expect(outcome.bitIndex, 0);
        expect(outcome.rssi, -61);
        expect(outcome.timeTick, tick);
        expect(outcome.record?.method, AppConstants.attendanceMethodBleHmac);
        expect(outcome.record?.timeTick, tick);
        expect(outcome.record?.rssiAvg, -61.0);
        expect(outcome.verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
        expect(outcome.bitmapHex, '0100000000000000');
        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 0), isTrue);
        expect(state.session.bitmapHex, '0100000000000000');
        expect(ble.advertisements.length, greaterThan(initialAdvertisements));

        final echo = BlePacketCodec.verifyTeacherEchoBytes(
          packet16: ble.advertisements.last,
          expectedCourseId: course.id,
          sharedSecretHex: course.courseSecret,
        );
        expect(echo.isValid, isTrue);
        expect(BlePacketCodec.isStudentBitSet(echo.bitmap8!, 0), isTrue);

        final storedSession = await database.getSessionById(state.session.id);
        expect(storedSession!.bitmapHex, '0100000000000000');
        final records = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(records, hasLength(1));
        expect(records.first.studentId, student0.id);
        expect(records.first.hmacTag, outcome.verifyCode);
        expect(records.first.timeTick, tick);

        await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -60,
          nowOverride: now,
        );
        final updatedRecords = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(updatedRecords, hasLength(1));
        expect(updatedRecords.first.rssiAvg, -60.0);
      },
    );

    test(
      'rechaza RSSI bajo y firmas adulteradas sin escribir asistencia',
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

        final weak = await controller.processIncomingStudentPacket(
          packet16: packet,
          rssi: -76,
          nowOverride: now,
        );
        expect(weak.isAccepted, isFalse);
        expect(weak.failureReason, contains('RSSI'));

        final tampered = Uint8List.fromList(packet);
        tampered[8] ^= 0x01;
        final invalid = await controller.processIncomingStudentPacket(
          packet16: tampered,
          rssi: -60,
          nowOverride: now,
        );
        expect(invalid.isAccepted, isFalse);
        expect(invalid.failureReason, contains('firma HMAC'));
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
      },
    );

    test(
      'lista invertida enciende y apaga el bit y persiste la observación',
      () async {
        final state = await controller.startTeacherSession(
          course: course,
          customPin: 42,
        );

        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: true,
          observation: '  Sin celular  ',
        );

        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isTrue);
        expect(state.bitmapHex, '0200000000000000');
        expect(state.session.bitmapHex, '0200000000000000');
        final records = await database.getAttendanceRecordsBySession(
          state.session.id,
        );
        expect(records, hasLength(1));
        expect(
          records.first.method,
          AppConstants.attendanceMethodManualInverted,
        );
        expect(records.first.observation, 'Sin celular');
        expect(records.first.hmacTag, isNull);
        expect(records.first.timeTick, isNotNull);

        final echo = BlePacketCodec.verifyTeacherEchoBytes(
          packet16: ble.advertisements.last,
          expectedCourseId: course.id,
          sharedSecretHex: course.courseSecret,
        );
        expect(echo.isValid, isTrue);
        expect(BlePacketCodec.isStudentBitSet(echo.bitmap8!, 1), isTrue);

        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: false,
        );

        expect(BlePacketCodec.isStudentBitSet(state.bitmap8, 1), isFalse);
        expect(state.bitmapHex, AppConstants.emptyBitmapHex);
        expect(
          await database.getAttendanceRecordsBySession(state.session.id),
          isEmpty,
        );
        final stored = await database.getSessionById(state.session.id);
        expect(stored!.bitmapHex, AppConstants.emptyBitmapHex);

        await expectLater(
          controller.toggleManualAttendance(
            studentId: 'student-inexistente',
            isPresent: true,
          ),
          throwsArgumentError,
        );
      },
    );

    test('cierra, firma y persiste el acta con presentes y ausentes', () async {
      final state = await controller.startTeacherSession(
        course: course,
        customPin: 42,
      );
      final bleNow = DateTime.utc(2026, 11, 6, 15, 2, 0);
      final packet = BlePacketCodec.buildStudentBeaconBytes(
        courseId: course.id,
        bitIndex: student0.bitIndex,
        sessionPin: 42,
        secretHex: student0.personalSecret,
        timeTick: BlePacketCodec.computeTimeTick(bleNow),
      );
      await controller.processIncomingStudentPacket(
        packet16: packet,
        rssi: -62,
        nowOverride: bleNow,
      );
      await controller.toggleManualAttendance(
        studentId: student1.id,
        isPresent: true,
        observation: 'Participó sin teléfono',
      );

      final closedAt = DateTime.utc(2026, 11, 6, 16, 0, 0);
      final acta = await controller.closeAndSignSession(
        closedAtOverride: closedAt,
      );

      expect(acta.sessionId, state.session.id);
      expect(acta.courseId, course.id);
      expect(acta.courseCode, 'SIST-301');
      expect(acta.courseName, 'Sistemas Distribuidos');
      expect(acta.sessionPin, '42');
      expect(acta.startedAtIso, state.session.startedAt);
      expect(acta.closedAtIso, closedAt.toIso8601String());
      expect(acta.totalEnrolled, 3);
      expect(acta.presentBleCount, 1);
      expect(acta.presentManualCount, 1);
      expect(acta.absentCount, 1);
      expect(acta.bitmapHex, '0300000000000000');
      expect(acta.records, hasLength(3));
      expect(
        acta.records.map((SessionActaRecord record) => record.bitIndex),
        <int>[0, 1, 2],
      );
      expect(acta.records[0].status, AppConstants.attendanceStatusPresent);
      expect(acta.records[0].method, AppConstants.attendanceMethodBleHmac);
      expect(acta.records[0].verifyCode, matches(RegExp(r'^UG-[0-9A-F]{8}$')));
      expect(acta.records[0].rssi, -62);
      expect(acta.records[1].status, AppConstants.attendanceStatusPresent);
      expect(
        acta.records[1].method,
        AppConstants.attendanceMethodManualInverted,
      );
      expect(acta.records[1].verifyCode, isNull);
      expect(acta.records[1].rssi, isNull);
      expect(acta.records[2].status, AppConstants.attendanceStatusAbsent);
      expect(acta.records[2].method, isNull);
      expect(acta.records[2].verifyCode, isNull);
      expect(acta.records[2].rssi, isNull);
      expect(acta.actaHmacSignature, matches(RegExp(r'^[0-9a-f]{64}$')));
      final expectedSignature = Hmac(
        sha256,
        utf8.encode(course.courseSecret),
      ).convert(utf8.encode(acta.canonicalJson)).toString();
      expect(acta.actaHmacSignature, expectedSignature);
      expect(acta.verifySignature(course.courseSecret), isTrue);

      final stored = await database.getSessionById(state.session.id);
      expect(stored!.closedAt, closedAt.toIso8601String());
      expect(stored.bitmapHex, '0300000000000000');
      expect(stored.actHash, hasLength(64));
      expect(state.isClosed, isTrue);
      expect(ble.lifecycle, contains('scan-stop'));
      expect(ble.lifecycle, contains('ad-stop'));

      final storedJson = await database.getSessionActaJson(state.session.id);
      expect(storedJson, isNotNull);
      final decoded = jsonDecode(storedJson!) as Map<String, dynamic>;
      expect(decoded['actaHmacSignature'], acta.actaHmacSignature);
      expect(decoded['records'], hasLength(3));
      expect(
        await database.getSessionActaSignature(state.session.id),
        acta.actaHmacSignature,
      );

      final repeated = await controller.closeAndSignSession();
      expect(identical(repeated, acta), isTrue);
    });

    test(
      'el estudiante obtiene el Sello Verde solo si su bit está encendido',
      () async {
        final enrollment = _enrollment(student0);
        final now = DateTime.utc(2026, 11, 6, 15, 3, 0);
        final bitMap = BlePacketCodec.setStudentBit(
          BlePacketCodec.createEmptyBitmap8(),
          0,
        );
        final teacherPacket = BlePacketCodec.buildTeacherEchoBytes(
          courseId: course.id,
          sessionId: 'session-echo-1',
          bitmap8: bitMap,
          sharedSecretHex: course.courseSecret,
        );

        final confirmation = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: teacherPacket,
          rssi: -63,
          nowOverride: now,
        );

        final expectedToken = BlePacketCodec.generateAttendanceVerifyCode(
          courseId: course.id,
          studentCode: enrollment.studentCode,
          bitIndex: enrollment.bitIndex,
          timeTick: BlePacketCodec.computeTimeTick(now),
          secretHex: enrollment.deviceSecret,
        );
        expect(confirmation.isConfirmed, isTrue);
        expect(confirmation.isGreenSeal, isTrue);
        expect(confirmation.verifyCode, expectedToken);
        expect(confirmation.bitmapHex, '0100000000000000');
        expect(confirmation.bitIndex, 0);
        expect(confirmation.rssi, -63);
        expect(confirmation.sessionPin, 42);
        expect(confirmation.confirmedAt, isNotNull);
        expect(confirmation.confirmedAt!.isAtSameMomentAs(now), isTrue);
        expect(confirmation.isNearby, isTrue);

        final emptyEcho = BlePacketCodec.buildTeacherEchoBytes(
          courseId: course.id,
          sessionId: 'session-echo-1',
          bitmap8: BlePacketCodec.createEmptyBitmap8(),
          sharedSecretHex: course.courseSecret,
        );
        final pending = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: emptyEcho,
          rssi: -63,
          nowOverride: now,
        );
        expect(pending.isConfirmed, isFalse);
        expect(pending.failureReason, contains('aún no ha marcado'));
        expect(pending.bitmapHex, AppConstants.emptyBitmapHex);

        final tampered = Uint8List.fromList(teacherPacket);
        tampered[12] ^= 0x01;
        final invalid = await controller.checkTeacherEchoForStudent(
          enrollment: enrollment,
          sessionPin: 42,
          teacherPacket16: tampered,
          rssi: -63,
          nowOverride: now,
        );
        expect(invalid.isConfirmed, isFalse);
        expect(invalid.failureReason, contains('firma HMAC'));
      },
    );

    test('procesa automáticamente los paquetes del Stream BLE', () async {
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

      expect(ble.injectSimulatedPacket(packet16: packet, rssi: -60), isTrue);
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
      expect(records.first.method, AppConstants.attendanceMethodBleHmac);
    });
  });
}
