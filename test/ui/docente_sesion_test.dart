import 'dart:io';

import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:asistencia_uniguajira/data/services/ble_permission_service.dart';
import 'package:asistencia_uniguajira/features/teacher/live_attendance_session_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<bool> get enabled async => true;

  @override
  Future<void> toggle({required bool enable}) async {}
}

class _FakeAppDatabase extends AppDatabase {
  final Map<String, CourseModel> courses = <String, CourseModel>{};
  final Map<String, StudentModel> students = <String, StudentModel>{};
  final Map<String, SessionModel> sessions = <String, SessionModel>{};
  final Map<String, AttendanceRecordModel> records =
      <String, AttendanceRecordModel>{};

  @override
  Future<void> insertCourse(CourseModel course) async {
    courses[course.id] = course;
  }

  @override
  Future<void> insertStudent(StudentModel student) async {
    students[student.id] = student;
  }

  @override
  Future<List<StudentModel>> getStudentsByCourse(String courseId) async {
    return students.values.where((s) => s.courseId == courseId).toList();
  }

  @override
  Future<void> upsertSession(SessionModel session) async {
    sessions[session.id] = session;
  }

  @override
  Future<List<AttendanceRecordModel>> getAttendanceRecordsBySession(
    String sessionId,
  ) async {
    return records.values.where((r) => r.sessionId == sessionId).toList();
  }

  @override
  Future<void> upsertAttendanceRecord(
    AttendanceRecordModel record, {
    String? bitmapHex,
  }) async {
    records['${record.sessionId}_${record.studentId}'] = record;
  }

  @override
  Future<int> deleteAttendanceRecord({
    required String sessionId,
    required String studentId,
    String? bitmapHex,
  }) async {
    final removed = records.remove('${sessionId}_$studentId');
    return removed != null ? 1 : 0;
  }

  @override
  Future<void> closeSessionWithActa({
    required String sessionId,
    required String closedAt,
    required String bitmapHex,
    required String actaJson,
    required String actaHmacSignature,
    String? actHash,
  }) async {
    final session = sessions[sessionId];
    if (session != null) {
      sessions[sessionId] = session.copyWith(
        closedAt: closedAt,
        bitmapHex: bitmapHex,
      );
    }
  }

  @override
  Future<void> close() async {}
}

const String _courseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _personalSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

CourseModel _testCourse() {
  return const CourseModel(
    id: 'course-test-1',
    code: 'INF-201',
    name: 'Bases de Datos II',
    groupCode: '01',
    semester: '2026-2',
    courseSecret: _courseSecret,
    createdAt: '2026-11-11T08:00:00.000Z',
  );
}

StudentModel _testStudent(String id, String code, String name, int bitIndex) {
  return StudentModel(
    id: id,
    courseId: 'course-test-1',
    studentCode: code,
    fullName: name,
    email: '$code@uniguajira.edu.co',
    bitIndex: bitIndex,
    personalSecret: _personalSecret,
    enrolledAt: '2026-11-11T08:01:00.000Z',
  );
}

class _FakeBleAttendanceService extends BleAttendanceService {
  @override
  Future<void> startScan({Duration? timeout}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> startAdvertisingPacket(List<int> packet16) async {}

  @override
  Future<void> stopAdvertising() async {}
}

BlePermissionService _createBluetoothOffPermissionService() {
  return BlePermissionService(
    androidSdkVersionProvider: () => 33,
    permissionStatusChecker: (Permission p) async => PermissionStatus.granted,
    permissionRequester: (List<Permission> list) async =>
        <Permission, PermissionStatus>{
          for (final p in list) p: PermissionStatus.granted,
        },
    bluetoothAdapterStateProvider: () =>
        Stream<BluetoothAdapterState>.value(BluetoothAdapterState.off),
    bluetoothTurnOnAction: () async => true,
  );
}

BlePermissionService _createReadyPermissionService() {
  return BlePermissionService(
    androidSdkVersionProvider: () => 33,
    permissionStatusChecker: (Permission p) async => PermissionStatus.granted,
    permissionRequester: (List<Permission> list) async =>
        <Permission, PermissionStatus>{
          for (final p in list) p: PermissionStatus.granted,
        },
    bluetoothAdapterStateProvider: () =>
        Stream<BluetoothAdapterState>.value(BluetoothAdapterState.on),
    bluetoothTurnOnAction: () async => true,
  );
}

Future<void> _loadFigtree() async {
  final loader = FontLoader(UiText.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFigtree();
    final fakeWakelock = _FakeWakelockPlusPlatform();
    WakelockPlusPlatformInterface.instance = fakeWakelock;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  setUp(() {
    final fakeWakelock = _FakeWakelockPlusPlatform();
    WakelockPlusPlatformInterface.instance = fakeWakelock;
    wakelockPlusPlatformInstance = fakeWakelock;
  });

  group('Sesión Docente en Vivo UI', () {
    testWidgets(
      '(a) con Bluetooth apagado muestra "El Bluetooth está apagado" y "Encender Bluetooth" en claro',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _testCourse();
        await database.insertCourse(course);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: LiveAttendanceSessionScreen(
              course: course,
              database: database,
              permissionService: _createBluetoothOffPermissionService(),
              bleService: _FakeBleAttendanceService(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('El Bluetooth está apagado'), findsOneWidget);
        expect(find.text('Encender Bluetooth'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '(a) con Bluetooth apagado muestra "El Bluetooth está apagado" y "Encender Bluetooth" en oscuro',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _testCourse();
        await database.insertCourse(course);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: LiveAttendanceSessionScreen(
              course: course,
              database: database,
              permissionService: _createBluetoothOffPermissionService(),
              bleService: _FakeBleAttendanceService(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('El Bluetooth está apagado'), findsOneWidget);
        expect(find.text('Encender Bluetooth'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '(b) con todo listo y 3 estudiantes muestra el PIN, "Todos 3" y un botón "Marcar" por estudiante en claro',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _testCourse();
        await database.insertCourse(course);

        final student1 = _testStudent('st-1', '101', 'Ana Pérez', 0);
        final student2 = _testStudent('st-2', '102', 'Carlos Iguarán', 1);
        final student3 = _testStudent('st-3', '103', 'María Epieyú', 2);

        await database.insertStudent(student1);
        await database.insertStudent(student2);
        await database.insertStudent(student3);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: LiveAttendanceSessionScreen(
              course: course,
              database: database,
              permissionService: _createReadyPermissionService(),
              bleService: _FakeBleAttendanceService(),
              customPin: 47,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Todos 3'), findsOneWidget);
        expect(find.byType(UiPinDisplay), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('Marcar'), findsNWidgets(3));

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '(b) con todo listo y 3 estudiantes muestra el PIN, "Todos 3" y un botón "Marcar" por estudiante en oscuro',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _testCourse();
        await database.insertCourse(course);

        final student1 = _testStudent('st-1', '101', 'Ana Pérez', 0);
        final student2 = _testStudent('st-2', '102', 'Carlos Iguarán', 1);
        final student3 = _testStudent('st-3', '103', 'María Epieyú', 2);

        await database.insertStudent(student1);
        await database.insertStudent(student2);
        await database.insertStudent(student3);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: LiveAttendanceSessionScreen(
              course: course,
              database: database,
              permissionService: _createReadyPermissionService(),
              bleService: _FakeBleAttendanceService(),
              customPin: 47,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Todos 3'), findsOneWidget);
        expect(find.byType(UiPinDisplay), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('Marcar'), findsNWidgets(3));

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
