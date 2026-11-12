import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/course_overview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _secret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

CourseModel _course(String id, String name) => CourseModel(
      id: id,
      code: 'SIST-$id',
      name: name,
      groupCode: '01',
      semester: '2026-2',
      courseSecret: _secret,
      createdAt: '2026-11-01T08:00:00.000-05:00',
    );

StudentModel _student(String courseId, int bit) => StudentModel(
      id: '$courseId-s$bit',
      courseId: courseId,
      studentCode: '01821200${bit.toString().padLeft(2, '0')}',
      fullName: 'Estudiante $bit',
      bitIndex: bit,
      personalSecret: _secret,
      enrolledAt: '2026-11-01T08:00:00.000-05:00',
    );

AttendanceRecordModel _record(String sessionId, StudentModel s, {bool manual = false}) =>
    AttendanceRecordModel(
      id: '$sessionId-${s.id}',
      sessionId: sessionId,
      studentId: s.id,
      bitIndex: s.bitIndex,
      method: manual ? AppConstants.attendanceMethodManualInverted : AppConstants.attendanceMethodBleHmac,
      recordedAt: '2026-11-02T08:10:00.000-05:00',
    );

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late CourseOverviewService service;

  setUp(() {
    db = AppDatabase(factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    service = CourseOverviewService(database: db);
  });

  tearDown(() => db.close());

  test('clase nueva: sin estudiantes, sin sesiones y sin porcentaje', () async {
    await db.insertCourse(_course('c1', 'Redes'));
    final o = await service.load('c1');
    expect(o.studentCount, 0);
    expect(o.hasStudents, isFalse);
    expect(o.closedSessionCount, 0);
    expect(o.attendancePercent, isNull);
    expect(o.openSession, isNull);
    expect(o.recentSessions, isEmpty);
  });

  test('calcula porcentaje, en riesgo, sesión abierta y llegados por sesión', () async {
    await db.insertCourse(_course('c1', 'Bases de Datos II'));
    final s = [for (var i = 0; i < 4; i++) _student('c1', i)];
    for (final st in s) {
      await db.insertStudent(st);
    }
    // Tres sesiones cerradas y una abierta (la más reciente).
    for (var n = 1; n <= 3; n++) {
      final id = 'ses$n';
      await db.insertSession(SessionModel(
        id: id,
        courseId: 'c1',
        startedAt: '2026-11-0${n + 1}T08:00:00.000-05:00',
        roomPin: '4$n',
      ));
      // s0 y s1 van siempre; s2 solo a la primera (s1 a mano en la segunda); s3 nunca.
      await db.insertAttendanceRecord(_record(id, s[0]));
      await db.insertAttendanceRecord(_record(id, s[1], manual: n == 2));
      if (n == 1) await db.insertAttendanceRecord(_record(id, s[2]));
      await db.closeSession(sessionId: id, closedAt: '2026-11-0${n + 1}T09:00:00.000-05:00');
    }
    await db.insertSession(const SessionModel(
      id: 'abierta',
      courseId: 'c1',
      startedAt: '2026-11-09T08:00:00.000-05:00',
      roomPin: '47',
    ));
    await db.insertAttendanceRecord(_record('abierta', s[0]));

    final o = await service.load('c1');
    expect(o.studentCount, 4);
    expect(o.closedSessionCount, 3);
    // s0 100, s1 100, s2 33.33, s3 0 → promedio 58.3
    expect(o.attendancePercent, 58.3);
    // Fallas: s2 66 % y s3 100 % → ambos en riesgo (≥ 30 %).
    expect(o.atRiskCount, 2);
    expect(o.inAlertCount, 0);
    expect(o.openSession, isNotNull);
    expect(o.openSession!.session.id, 'abierta');
    expect(o.openSession!.presentCount, 1);
    expect(o.recentSessions.first.session.id, 'abierta');
    expect(o.recentSessions.map((r) => r.presentCount).toList(), [1, 2, 2, 3]);
    expect(o.recentSessions.last.ratio, 0.75);
  });

  test('loadAll devuelve un resumen por clase', () async {
    await db.insertCourse(_course('c1', 'A'));
    await db.insertCourse(_course('c2', 'B'));
    final all = await service.loadAll();
    expect(all.map((o) => o.course.id).toSet(), {'c1', 'c2'});
  });
}
