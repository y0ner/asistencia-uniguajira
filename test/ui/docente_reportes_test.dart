import 'dart:io';

import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/attendance_session_controller.dart';
import 'package:asistencia_uniguajira/features/teacher/course_reports_screen.dart';
import 'package:asistencia_uniguajira/features/teacher/signed_acta_dialog.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _testCourseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _testPersonalSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

class _FakeAppDatabase extends AppDatabase {
  final Map<String, CourseModel> courses = <String, CourseModel>{};
  final Map<String, StudentModel> students = <String, StudentModel>{};
  final Map<String, SessionModel> sessions = <String, SessionModel>{};
  final Map<String, AttendanceRecordModel> records =
      <String, AttendanceRecordModel>{};
  final Map<String, String> actaJsons = <String, String>{};
  final Map<String, String> actaSignatures = <String, String>{};

  @override
  Future<void> insertCourse(CourseModel course) async {
    courses[course.id] = course;
  }

  @override
  Future<CourseModel?> getCourseById(String courseId) async {
    return courses[courseId];
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
  Future<List<SessionModel>> getSessionsByCourse(String courseId) async {
    return sessions.values.where((s) => s.courseId == courseId).toList();
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
  Future<String?> getSessionActaJson(String sessionId) async {
    return actaJsons[sessionId];
  }

  @override
  Future<String?> getSessionActaSignature(String sessionId) async {
    return actaSignatures[sessionId];
  }

  @override
  Future<void> close() async {}
}

Future<void> _loadFigtree() async {
  final loader = FontLoader(UiText.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

CourseModel _buildTestCourse({String id = 'course-rep-1'}) {
  return CourseModel(
    id: id,
    code: 'INF-301',
    name: 'Sistemas Distribuidos',
    groupCode: '01',
    semester: '2026-2',
    courseSecret: _testCourseSecret,
    createdAt: '2026-11-12T08:00:00.000Z',
  );
}

StudentModel _buildTestStudent({
  required String id,
  required String code,
  required String name,
  required int bitIndex,
  String courseId = 'course-rep-1',
}) {
  return StudentModel(
    id: id,
    courseId: courseId,
    studentCode: code,
    fullName: name,
    email: '$code@uniguajira.edu.co',
    bitIndex: bitIndex,
    personalSecret: _testPersonalSecret,
    enrolledAt: '2026-11-12T08:05:00.000Z',
  );
}

SignedSessionActa _buildTestActa({
  required String courseId,
  required String courseName,
}) {
  const records = <SessionActaRecord>[
    SessionActaRecord(
      bitIndex: 0,
      studentCode: '1001',
      fullName: 'Carlos Fuentes',
      status: 'PRESENT',
      method: 'BLE_AUTOMATIC',
    ),
    SessionActaRecord(
      bitIndex: 1,
      studentCode: '1002',
      fullName: 'Diana Mendoza',
      status: 'PRESENT',
      method: 'MANUAL_INVERTED',
    ),
    SessionActaRecord(
      bitIndex: 2,
      studentCode: '1003',
      fullName: 'Esteban Morales',
      status: 'ABSENT',
    ),
  ];

  final partialActa = SignedSessionActa(
    sessionId: 'session-acta-1',
    courseId: courseId,
    courseCode: 'INF-301',
    courseName: courseName,
    sessionPin: '42',
    startedAtIso: '2026-11-12T08:00:00.000Z',
    closedAtIso: '2026-11-12T10:00:00.000Z',
    totalEnrolled: 3,
    presentBleCount: 1,
    presentManualCount: 1,
    absentCount: 1,
    bitmapHex: '0300000000000000',
    records: records,
    actaHmacSignature: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
  );

  return partialActa;
}

void main() {
  setUpAll(() async {
    await _loadFigtree();
  });

  group('Docente Reportes UI · Pantalla sin sesiones', () {
    testWidgets(
      'muestra "Aún no hay datos" en tema claro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _buildTestCourse();
        await database.insertCourse(course);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: CourseReportsScreen(
              course: course,
              database: database,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Reportes'), findsOneWidget);
        expect(find.text('Aún no hay datos'), findsOneWidget);
        expect(
          find.text('Cuando cierres tu primera sesión verás aquí el resumen de la clase.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'muestra "Aún no hay datos" en tema oscuro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _buildTestCourse();
        await database.insertCourse(course);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: CourseReportsScreen(
              course: course,
              database: database,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Reportes'), findsOneWidget);
        expect(find.text('Aún no hay datos'), findsOneWidget);
      },
    );
  });

  group('Docente Reportes UI · Diálogo de éxito de exportación', () {
    testWidgets(
      'muestra "Excel listo", botones "Compartir" y "Cerrar" en claro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        const testFilePath = '/storage/emulated/0/Download/Asistencia_INF301_01.xlsx';
        const testFileSize = 15360;
        const testHmac = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

        var shareCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    CourseReportsScreen.showExportSuccessDialog(
                      context: context,
                      filePath: testFilePath,
                      fileSizeBytes: testFileSize,
                      hmacSha256: testHmac,
                      onShare: () async {
                        shareCalled = true;
                      },
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Excel listo'), findsOneWidget);
        expect(find.text('Asistencia_INF301_01.xlsx'), findsOneWidget);
        expect(find.text('15.0 KB'), findsOneWidget);

        final compartirButton = find.widgetWithText(FilledButton, 'Compartir');
        final cerrarButton = find.widgetWithText(TextButton, 'Cerrar');

        expect(compartirButton, findsOneWidget);
        expect(cerrarButton, findsOneWidget);

        await tester.tap(compartirButton);
        await tester.pumpAndSettle();

        expect(shareCalled, isTrue);
        expect(find.text('Excel listo'), findsNothing);
      },
    );

    testWidgets(
      'botón "Cerrar" descarta el diálogo en oscuro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        var shareCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    CourseReportsScreen.showExportSuccessDialog(
                      context: context,
                      filePath: '/descargas/reporte.xlsx',
                      fileSizeBytes: 2048,
                      hmacSha256: 'deadbeef',
                      onShare: () async {
                        shareCalled = true;
                      },
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Excel listo'), findsOneWidget);

        final cerrarButton = find.widgetWithText(TextButton, 'Cerrar');
        await tester.tap(cerrarButton);
        await tester.pumpAndSettle();

        expect(shareCalled, isFalse);
        expect(find.text('Excel listo'), findsNothing);
      },
    );
  });

  group('Docente Reportes UI · Pantalla con sesiones consolidadas', () {
    testWidgets(
      'muestra estadísticas, filtros y lista de estudiantes en claro y oscuro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final database = _FakeAppDatabase();
        final course = _buildTestCourse();
        await database.insertCourse(course);

        final student1 = _buildTestStudent(
          id: 's-1',
          code: '2024001',
          name: 'Ana Pérez',
          bitIndex: 0,
        );
        final student2 = _buildTestStudent(
          id: 's-2',
          code: '2024002',
          name: 'Bernardo Gómez',
          bitIndex: 1,
        );
        await database.insertStudent(student1);
        await database.insertStudent(student2);

        const session = SessionModel(
          id: 'sess-1',
          courseId: 'course-rep-1',
          roomPin: '55',
          startedAt: '2026-11-12T08:00:00.000Z',
          closedAt: '2026-11-12T10:00:00.000Z',
          bitmapHex: '0100000000000000',
        );
        await database.upsertSession(session);

        const record1 = AttendanceRecordModel(
          id: 'rec-1',
          sessionId: 'sess-1',
          studentId: 's-1',
          bitIndex: 0,
          method: 'BLE_AUTOMATIC',
          recordedAt: '2026-11-12T08:15:00.000Z',
        );
        await database.upsertAttendanceRecord(record1);

        // Prueba en tema claro
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: CourseReportsScreen(
              course: course,
              database: database,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Reportes'), findsOneWidget);
        expect(find.text('sesiones'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
        expect(find.text('en riesgo'), findsOneWidget);
        expect(find.text('Enviar Excel'), findsOneWidget);
        expect(find.text('Ana Pérez'), findsOneWidget);
        expect(find.text('Bernardo Gómez'), findsOneWidget);
        expect(find.textContaining('Fue a 1 de 1'), findsOneWidget);
        expect(find.textContaining('Fue a 0 de 1'), findsOneWidget);

        // Prueba en tema oscuro
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: CourseReportsScreen(
              course: course,
              database: database,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.text('Reportes'), findsOneWidget);
        expect(find.text('Enviar Excel'), findsOneWidget);
      },
    );
  });

  group('Docente Reportes UI · Sesión firmada (SignedActaDialog)', () {
    testWidgets(
      'muestra métricas, lista de estudiantes y detalles de la firma en claro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final acta = _buildTestActa(
          courseId: 'course-rep-1',
          courseName: 'Sistemas Distribuidos',
        );

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    SignedActaDialog.show(
                      context,
                      acta: acta,
                      courseSecretHex: _testCourseSecret,
                    );
                  },
                  child: const Text('Ver acta'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ver acta'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Sesión firmada'), findsOneWidget);
        expect(find.text('llegaron'), findsOneWidget);
        expect(find.text('a mano'), findsOneWidget);
        expect(find.text('faltaron'), findsOneWidget);
        expect(find.text('Carlos Fuentes'), findsOneWidget);
        expect(find.text('Diana Mendoza'), findsOneWidget);
        expect(find.text('Esteban Morales'), findsOneWidget);
        expect(find.text('Detalles de la firma'), findsOneWidget);

        final cerrarButton = find.widgetWithText(UiButton, 'Cerrar');
        expect(cerrarButton, findsOneWidget);

        await tester.tap(cerrarButton);
        await tester.pumpAndSettle();

        expect(find.text('Sesión firmada'), findsNothing);
      },
    );

    testWidgets(
      'muestra banner de aviso si la firma no coincide en tema oscuro (360x640, escala 1.3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final acta = _buildTestActa(
          courseId: 'course-rep-1',
          courseName: 'Sistemas Distribuidos',
        );

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: UiTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    SignedActaDialog.show(
                      context,
                      acta: acta,
                      // Clave secreta deliberadamente incorrecta para probar validación inválida
                      courseSecretHex: '0000000000000000000000000000000000000000000000000000000000000000',
                    );
                  },
                  child: const Text('Ver acta'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ver acta'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Sesión firmada'), findsOneWidget);
        expect(
          find.text('La firma de esta sesión no coincide. Puede haber sido modificada.'),
          findsOneWidget,
        );
      },
    );
  });
}
