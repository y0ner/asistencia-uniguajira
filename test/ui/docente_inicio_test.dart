import 'dart:io';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/features/teacher/courses_dashboard_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _loadFigtree() async {
  final loader = FontLoader(UiText.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _waitForDb(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ThemeData theme,
  required AppDatabase database,
  Size size = const Size(360, 640),
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: CoursesDashboardScreen(database: database),
    ),
  );
  await _waitForDb(tester);
}

CourseModel _sampleCourse({
  String id = 'course-bd2',
  String name = 'Bases de Datos II',
  String code = 'SIST-401',
  String groupCode = '01',
  String semester = '2026-2',
}) {
  return CourseModel(
    id: id,
    code: code,
    name: name,
    groupCode: groupCode,
    semester: semester,
    courseSecret:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    spreadsheetId: null,
    createdAt: '2026-11-11T08:00:00.000Z',
  );
}

StudentModel _sampleStudent({
  required String id,
  required String courseId,
  required String code,
  required String name,
  required int bitIndex,
}) {
  return StudentModel(
    id: id,
    courseId: courseId,
    studentCode: code,
    fullName: name,
    bitIndex: bitIndex,
    personalSecret:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    enrolledAt: '2026-11-11T08:00:00.000Z',
  );
}

AttendanceRecordModel _sampleRecord({
  required String id,
  required String sessionId,
  required String studentId,
  required int bitIndex,
}) {
  return AttendanceRecordModel(
    id: id,
    sessionId: sessionId,
    studentId: studentId,
    bitIndex: bitIndex,
    method: AppConstants.attendanceMethodBleHmac,
    recordedAt: '2026-11-11T08:05:00.000Z',
  );
}

Future<void> _seedCourseWithOpenAndClosedSessions(AppDatabase db) async {
  final course = _sampleCourse(id: 'c1', name: 'Bases de Datos II');
  await db.insertCourse(course);

  final s1 = _sampleStudent(
    id: 'c1-s1',
    courseId: 'c1',
    code: '0182120001',
    name: 'Estudiante Uno',
    bitIndex: 0,
  );
  final s2 = _sampleStudent(
    id: 'c1-s2',
    courseId: 'c1',
    code: '0182120002',
    name: 'Estudiante Dos',
    bitIndex: 1,
  );
  await db.insertStudent(s1);
  await db.insertStudent(s2);

  // Sesión 1: cerrada, ambos asistieron (100 % de asistencia).
  const closedId = 'ses-closed';
  await db.insertSession(const SessionModel(
    id: closedId,
    courseId: 'c1',
    startedAt: '2026-11-10T08:00:00.000Z',
    closedAt: '2026-11-10T09:00:00.000Z',
    roomPin: '41',
  ));
  await db.insertAttendanceRecord(_sampleRecord(
    id: 'rec-c-1',
    sessionId: closedId,
    studentId: s1.id,
    bitIndex: s1.bitIndex,
  ));
  await db.insertAttendanceRecord(_sampleRecord(
    id: 'rec-c-2',
    sessionId: closedId,
    studentId: s2.id,
    bitIndex: s2.bitIndex,
  ));

  // Sesión 2: abierta, solo s1 llegó (1 de 2 estudiantes ya llegaron).
  const openId = 'ses-open';
  await db.insertSession(const SessionModel(
    id: openId,
    courseId: 'c1',
    startedAt: '2026-11-11T08:00:00.000Z',
    closedAt: null,
    roomPin: '47',
  ));
  await db.insertAttendanceRecord(_sampleRecord(
    id: 'rec-o-1',
    sessionId: openId,
    studentId: s1.id,
    bitIndex: s1.bitIndex,
  ));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    return _loadFigtree();
  });

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

  group('Inicio del docente - Estado vacío', () {
    testWidgets(
      'muestra "Aún no tienes clases" en tema claro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.byType(UiBrandHeader), findsOneWidget);
        expect(find.byTooltip('Ajustes y diagnóstico'), findsOneWidget);
        expect(find.text('Aún no tienes clases'), findsOneWidget);
        expect(
          find.text('Crea tu primera clase para empezar a tomar asistencia.'),
          findsOneWidget,
        );
        expect(find.text('Crear mi primera clase'), findsOneWidget);
        expect(find.text('Tus clases'), findsNothing);
        expect(find.text('Nueva clase'), findsNothing);
      },
    );

    testWidgets(
      'muestra "Aún no tienes clases" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.text('Aún no tienes clases'), findsOneWidget);
        expect(find.text('Crear mi primera clase'), findsOneWidget);
      },
    );
  });

  group('Inicio del docente - Con sesión en curso y sesión cerrada (Criterios a y b)', () {
    testWidgets(
      'muestra "Sesión en curso", "1 de 2 estudiantes ya llegaron", "Volver a la sesión", '
      'porcentaje y "asistencia" en tema claro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() => _seedCourseWithOpenAndClosedSessions(database));

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);

        // Tarjeta "Sesión en curso" (Hero Card)
        expect(find.text('Sesión en curso'), findsOneWidget);
        expect(find.text('1 de 2 estudiantes ya llegaron'), findsOneWidget);
        expect(find.text('Volver a la sesión'), findsOneWidget);

        // Lista "Tus clases"
        expect(find.text('Tus clases'), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsNWidgets(2)); // Hero y tarjeta de clase
        expect(find.text('Grupo 01 · 2 estudiantes'), findsOneWidget);
        expect(find.text('100 %'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
        expect(find.text('Nueva clase'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra "Sesión en curso", "1 de 2 estudiantes ya llegaron", "Volver a la sesión", '
      'porcentaje y "asistencia" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() => _seedCourseWithOpenAndClosedSessions(database));

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.text('Sesión en curso'), findsOneWidget);
        expect(find.text('1 de 2 estudiantes ya llegaron'), findsOneWidget);
        expect(find.text('Volver a la sesión'), findsOneWidget);
        expect(find.text('100 %'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
      },
    );
  });

  group('Inicio del docente - Sin sesión en curso (Criterio c)', () {
    testWidgets(
      'sin sesión abierta no aparece "Sesión en curso" y muestra porcentaje en tema claro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() async {
          final course = _sampleCourse(id: 'c1', name: 'Bases de Datos II');
          await database.insertCourse(course);
          final s1 = _sampleStudent(
            id: 'c1-s1',
            courseId: 'c1',
            code: '0182120001',
            name: 'Estudiante Uno',
            bitIndex: 0,
          );
          await database.insertStudent(s1);

          const closedId = 'ses-closed';
          await database.insertSession(const SessionModel(
            id: closedId,
            courseId: 'c1',
            startedAt: '2026-11-10T08:00:00.000Z',
            closedAt: '2026-11-10T09:00:00.000Z',
            roomPin: '41',
          ));
          await database.insertAttendanceRecord(_sampleRecord(
            id: 'rec-c-1',
            sessionId: closedId,
            studentId: s1.id,
            bitIndex: s1.bitIndex,
          ));
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.text('Sesión en curso'), findsNothing);
        expect(find.text('Volver a la sesión'), findsNothing);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Grupo 01 · 1 estudiante'), findsOneWidget);
        expect(find.text('100 %'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
      },
    );

    testWidgets(
      'sin sesión abierta no aparece "Sesión en curso" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() async {
          final course = _sampleCourse(id: 'c1', name: 'Bases de Datos II');
          await database.insertCourse(course);
          final s1 = _sampleStudent(
            id: 'c1-s1',
            courseId: 'c1',
            code: '0182120001',
            name: 'Estudiante Uno',
            bitIndex: 0,
          );
          await database.insertStudent(s1);

          const closedId = 'ses-closed';
          await database.insertSession(const SessionModel(
            id: closedId,
            courseId: 'c1',
            startedAt: '2026-11-10T08:00:00.000Z',
            closedAt: '2026-11-10T09:00:00.000Z',
            roomPin: '41',
          ));
          await database.insertAttendanceRecord(_sampleRecord(
            id: 'rec-c-1',
            sessionId: closedId,
            studentId: s1.id,
            bitIndex: s1.bitIndex,
          ));
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Sesión en curso'), findsNothing);
        expect(find.text('Volver a la sesión'), findsNothing);
        expect(find.text('100 %'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
      },
    );
  });

  group('Inicio del docente - Estados de clase (Nueva y Sin sesiones)', () {
    testWidgets(
      'clase sin estudiantes muestra pastilla "Nueva" a la derecha y aviso en subtítulo',
      (tester) async {
        await tester.runAsync(() async {
          await database.insertCourse(_sampleCourse());
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Grupo 01 · Falta agregar estudiantes'), findsOneWidget);
        expect(find.text('Nueva'), findsOneWidget);
        expect(find.text('Sesión en curso'), findsNothing);
      },
    );

    testWidgets(
      'clase con estudiantes pero sin sesiones cerradas muestra "Sin sesiones"',
      (tester) async {
        await tester.runAsync(() async {
          final course = _sampleCourse(id: 'c1', name: 'Bases de Datos II');
          await database.insertCourse(course);
          final s1 = _sampleStudent(
            id: 'c1-s1',
            courseId: 'c1',
            code: '0182120001',
            name: 'Estudiante Uno',
            bitIndex: 0,
          );
          await database.insertStudent(s1);
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Grupo 01 · 1 estudiante'), findsOneWidget);
        expect(find.text('Sin sesiones'), findsOneWidget);
        expect(find.text('Nueva'), findsNothing);
        expect(find.text('Sesión en curso'), findsNothing);
      },
    );

    testWidgets(
      'con múltiples sesiones abiertas selecciona la más reciente para la tarjeta destacada',
      (tester) async {
        await tester.runAsync(() async {
          final c1 = _sampleCourse(id: 'c1', name: 'Bases de Datos II');
          final c2 = _sampleCourse(id: 'c2', name: 'Redes de Computadores');
          await database.insertCourse(c1);
          await database.insertCourse(c2);

          // Sesión abierta antigua para c1 (08:00)
          await database.insertSession(const SessionModel(
            id: 'open-1',
            courseId: 'c1',
            startedAt: '2026-11-11T08:00:00.000Z',
            closedAt: null,
            roomPin: '41',
          ));

          // Sesión abierta más reciente para c2 (10:00)
          await database.insertSession(const SessionModel(
            id: 'open-2',
            courseId: 'c2',
            startedAt: '2026-11-11T10:00:00.000Z',
            closedAt: null,
            roomPin: '42',
          ));
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Sesión en curso'), findsOneWidget);
        expect(find.text('Aún no llega nadie'), findsOneWidget);

        // La tarjeta destacada tiene a Redes de Computadores (la más reciente)
        final heroFinder = find.byType(UiHeroCard);
        expect(heroFinder, findsOneWidget);
        expect(
          find.descendant(of: heroFinder, matching: find.text('Redes de Computadores')),
          findsOneWidget,
        );
      },
    );
  });

  group('Flujos de acción', () {
    testWidgets(
      'crear clase abre hoja modal, valida y agrega la clase',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        await tester.tap(find.text('Crear mi primera clase'));
        await tester.pumpAndSettle();

        expect(find.text('Nueva clase'), findsOneWidget);

        // Intenta enviar vacío para comprobar validación
        await tester.tap(find.widgetWithText(UiButton, 'Crear clase'));
        await tester.pump();
        expect(find.text('Escribe el nombre de la clase'), findsOneWidget);

        // Llena el formulario
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nombre de la clase'),
          'Ingeniería de Software',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Código'),
          'SIST-301',
        );
        await tester.pump();

        await tester.tap(find.widgetWithText(UiButton, 'Crear clase'));
        await _waitForDb(tester);
        await tester.pumpAndSettle();

        expect(find.text('Clase creada.'), findsOneWidget);
        expect(find.text('Ingeniería de Software'), findsOneWidget);
        expect(find.text('Tus clases'), findsOneWidget);

        final stored = await tester.runAsync(() => database.getAllCourses());
        expect(stored, hasLength(1));
        expect(stored!.first.name, 'Ingeniería de Software');
        expect(stored.first.code, 'SIST-301');
        expect(stored.first.spreadsheetId, isNull);
      },
    );
  });
}
