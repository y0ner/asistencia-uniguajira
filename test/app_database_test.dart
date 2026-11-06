import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _courseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _personalSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

CourseModel _course({String id = 'course-1'}) {
  return CourseModel(
    id: id,
    code: 'ING-101',
    name: 'Introducción a la Ingeniería',
    groupCode: '01',
    semester: '2026-2',
    courseSecret: _courseSecret,
    spreadsheetId: 'sheet-abc123',
    createdAt: '2026-11-06T08:00:00.000-05:00',
  );
}

StudentModel _student({
  required String id,
  required String studentCode,
  required int bitIndex,
  String courseId = 'course-1',
}) {
  return StudentModel(
    id: id,
    courseId: courseId,
    studentCode: studentCode,
    fullName: 'Estudiante $studentCode',
    email: '$studentCode${AppConstants.institutionalDomain}',
    bitIndex: bitIndex,
    personalSecret: _personalSecret,
    enrolledAt: '2026-11-06T08:02:00.000-05:00',
  );
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('cursos', () {
    test('crea un curso y lo recupera con su contrato completo', () async {
      final course = _course();

      await database.insertCourse(course);

      final stored = await database.getCourseById(course.id);
      expect(stored, isNotNull);
      expect(stored!.toMap(), equals(course.toMap()));
      expect(await database.getAllCourses(), hasLength(1));
      expect(await database.getCourseById('curso-inexistente'), isNull);
    });
  });

  group('estudiantes', () {
    test('asigna bitIndex y rechaza duplicados de (course_id, bit_index)',
        () async {
      final course = _course();
      await database.insertCourse(course);

      final first = _student(
        id: 'student-1',
        studentCode: '0182120016',
        bitIndex: 0,
      );
      final second = _student(
        id: 'student-2',
        studentCode: '0182110072',
        bitIndex: 1,
      );
      await database.insertStudent(first);
      await database.insertStudent(second);

      final stored = await database.getStudentsByCourse(course.id);
      expect(stored.map((StudentModel student) => student.bitIndex),
          <int>[0, 1]);
      expect(
        stored.map((StudentModel student) => student.studentCode),
        <String>['0182120016', '0182110072'],
      );
      expect(
        await database.getStudentByCode(
          courseId: course.id,
          studentCode: '0182110072',
        ),
        isNotNull,
      );

      final duplicateBit = _student(
        id: 'student-3',
        studentCode: '0182120099',
        bitIndex: 1,
      );
      await expectLater(
        database.insertStudent(duplicateBit),
        throwsA(isA<DatabaseException>()),
      );

      final duplicateCode = _student(
        id: 'student-4',
        studentCode: '0182120016',
        bitIndex: 2,
      );
      await expectLater(
        database.insertStudent(duplicateCode),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('rechaza bitIndex fuera del rango 0..63', () async {
      await database.insertCourse(_course());

      await expectLater(
        database.insertStudent(
          _student(id: 'student-64', studentCode: '0182120064', bitIndex: 64),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        database.insertStudent(
          _student(id: 'student--1', studentCode: '0182120065', bitIndex: -1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exige un curso existente con la clave foránea activa', () async {
      final orphan = _student(
        id: 'student-orphan',
        studentCode: '0182120098',
        bitIndex: 5,
        courseId: 'curso-inexistente',
      );

      await expectLater(
        database.insertStudent(orphan),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('sesiones y asistencia', () {
    test('crea la sesión con PIN de 2 dígitos y actualiza attendance_records',
        () async {
      final course = _course();
      await database.insertCourse(course);
      final first = _student(
        id: 'student-1',
        studentCode: '0182120016',
        bitIndex: 0,
      );
      final second = _student(
        id: 'student-2',
        studentCode: '0182110072',
        bitIndex: 1,
      );
      await database.insertStudent(first);
      await database.insertStudent(second);

      const session = SessionModel(
        id: 'session-1',
        courseId: 'course-1',
        startedAt: '2026-11-06T08:05:00.000-05:00',
        roomPin: '42',
      );
      await database.insertSession(session);

      final storedSession = await database.getSessionById(session.id);
      expect(storedSession, isNotNull);
      expect(storedSession!.roomPin, '42');
      expect(storedSession.bitmapHex, AppConstants.emptyBitmapHex);
      expect(storedSession.closedAt, isNull);

      await database.insertAttendanceRecord(
        AttendanceRecordModel(
          id: 'record-1',
          sessionId: session.id,
          studentId: first.id,
          bitIndex: first.bitIndex,
          method: AppConstants.attendanceMethodBleHmac,
          rssiAvg: -62.5,
          recordedAt: '2026-11-06T08:06:00.000-05:00',
          hmacTag: 'a1b2c3d4',
        ),
      );
      await database.insertAttendanceRecord(
        AttendanceRecordModel(
          id: 'record-2',
          sessionId: session.id,
          studentId: second.id,
          bitIndex: second.bitIndex,
          method: AppConstants.attendanceMethodManualInverted,
          recordedAt: '2026-11-06T08:07:00.000-05:00',
        ),
      );

      final records =
          await database.getAttendanceRecordsBySession(session.id);
      expect(records, hasLength(2));
      expect(records.first.method, AppConstants.attendanceMethodBleHmac);
      expect(records.first.rssiAvg, -62.5);
      expect(records.last.method, AppConstants.attendanceMethodManualInverted);
      expect(records.last.rssiAvg, isNull);

      await database.updateSessionBitmap(
        sessionId: session.id,
        bitmapHex: '0000000000000003',
      );
      final updated = await database.getSessionById(session.id);
      expect(updated!.bitmapHex, '0000000000000003');

      await database.closeSession(
        sessionId: session.id,
        closedAt: '2026-11-06T09:00:00.000-05:00',
        actHash: 'hash-del-acta',
      );
      final closed = await database.getSessionById(session.id);
      expect(closed!.closedAt, '2026-11-06T09:00:00.000-05:00');
      expect(closed.actHash, 'hash-del-acta');
      expect(await database.getSessionsByCourse(course.id), hasLength(1));
    });

    test('rechaza PIN, Bitmap o método de registro inválidos', () async {
      await database.insertCourse(_course());

      await expectLater(
        database.insertSession(
          const SessionModel(
            id: 'session-pin-corto',
            courseId: 'course-1',
            startedAt: '2026-11-06T08:05:00.000-05:00',
            roomPin: '4',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        database.insertSession(
          const SessionModel(
            id: 'session-bitmap-invalido',
            courseId: 'course-1',
            startedAt: '2026-11-06T08:05:00.000-05:00',
            roomPin: '42',
            bitmapHex: 'XYZ',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      await database.insertSession(
        const SessionModel(
          id: 'session-1',
          courseId: 'course-1',
          startedAt: '2026-11-06T08:05:00.000-05:00',
          roomPin: '42',
        ),
      );
      await database.insertStudent(
        _student(id: 'student-1', studentCode: '0182120016', bitIndex: 0),
      );

      await expectLater(
        database.insertAttendanceRecord(
          const AttendanceRecordModel(
            id: 'record-invalido',
            sessionId: 'session-1',
            studentId: 'student-1',
            bitIndex: 0,
            method: 'QR',
            recordedAt: '2026-11-06T08:06:00.000-05:00',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rechaza registros duplicados de (session_id, student_id)', () async {
      await database.insertCourse(_course());
      await database.insertStudent(
        _student(id: 'student-1', studentCode: '0182120016', bitIndex: 0),
      );
      await database.insertSession(
        const SessionModel(
          id: 'session-1',
          courseId: 'course-1',
          startedAt: '2026-11-06T08:05:00.000-05:00',
          roomPin: '42',
        ),
      );

      const record = AttendanceRecordModel(
        id: 'record-1',
        sessionId: 'session-1',
        studentId: 'student-1',
        bitIndex: 0,
        method: AppConstants.attendanceMethodManualInverted,
        recordedAt: '2026-11-06T08:06:00.000-05:00',
      );
      await database.insertAttendanceRecord(record);

      await expectLater(
        database.insertAttendanceRecord(
          record.copyWith(id: 'record-2'),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
