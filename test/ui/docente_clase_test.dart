import 'dart:io';

import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/features/teacher/course_detail_screen.dart';
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
  required CourseModel course,
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
      home: CourseDetailScreen(
        course: course,
        database: database,
      ),
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
        'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
    enrolledAt: '2026-11-11T09:00:00.000Z',
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    return _loadFigtree();
  });

  late AppDatabase database;
  late CourseModel course;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    course = _sampleCourse();
    await database.insertCourse(course);
  });

  tearDown(() async {
    await database.close();
  });

  group('Detalle de clase - Sin estudiantes', () {
    testWidgets(
      'muestra el aviso para agregar estudiantes en tema claro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(
          find.text('SIST-401 · Grupo 01 · 2026-2'),
          findsOneWidget,
        );
        expect(
          find.text('Agrega a tus estudiantes para poder tomar asistencia.'),
          findsOneWidget,
        );
        expect(find.text('Agregar estudiantes'), findsOneWidget);
        expect(find.text('Tomar asistencia'), findsNothing);
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Reportes'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra el aviso para agregar estudiantes en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);
        expect(
          find.text('Agrega a tus estudiantes para poder tomar asistencia.'),
          findsOneWidget,
        );
        expect(find.text('Agregar estudiantes'), findsOneWidget);
        expect(find.text('Tomar asistencia'), findsNothing);
      },
    );
  });

  group('Detalle de clase - Con 2 estudiantes', () {
    testWidgets(
      'muestra "Tomar asistencia", "Estudiantes", "Reportes" y al tocar "Estudiantes" aparecen los dos nombres (tema claro)',
      (tester) async {
        await tester.runAsync(() async {
          await database.insertStudent(_sampleStudent(
            id: 'std-1',
            courseId: course.id,
            code: '0123456789',
            name: 'Juan Pérez',
            bitIndex: 0,
          ));
          await database.insertStudent(_sampleStudent(
            id: 'std-2',
            courseId: course.id,
            code: '0987654321',
            name: 'María Gómez',
            bitIndex: 1,
          ));
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);
        expect(find.text('Tomar asistencia'), findsOneWidget);
        expect(find.text('2 estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Reportes'), findsOneWidget);

        // Toca en "Estudiantes"
        await tester.tap(find.widgetWithText(UiButton, 'Estudiantes'));
        await tester.pump();
        await _waitForDb(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Juan Pérez'), findsOneWidget);
        expect(find.text('María Gómez'), findsOneWidget);
        expect(find.text('0123456789'), findsOneWidget);
        expect(find.text('0987654321'), findsOneWidget);
        expect(find.byTooltip('Código para unirse'), findsNWidgets(2));
      },
    );

    testWidgets(
      'muestra "Tomar asistencia", "Estudiantes", "Reportes" y al tocar "Estudiantes" aparecen los dos nombres (tema oscuro)',
      (tester) async {
        await tester.runAsync(() async {
          await database.insertStudent(_sampleStudent(
            id: 'std-1',
            courseId: course.id,
            code: '0123456789',
            name: 'Juan Pérez',
            bitIndex: 0,
          ));
          await database.insertStudent(_sampleStudent(
            id: 'std-2',
            courseId: course.id,
            code: '0987654321',
            name: 'María Gómez',
            bitIndex: 1,
          ));
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);
        expect(find.text('Tomar asistencia'), findsOneWidget);
        expect(find.text('2 estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Reportes'), findsOneWidget);

        // Toca en "Estudiantes"
        await tester.tap(find.widgetWithText(UiButton, 'Estudiantes'));
        await tester.pump();
        await _waitForDb(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Juan Pérez'), findsOneWidget);
        expect(find.text('María Gómez'), findsOneWidget);
      },
    );
  });
}
