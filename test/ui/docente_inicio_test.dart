import 'dart:io';

import 'package:asistencia_uniguajira/core/models/course_model.dart';
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

  group('Inicio del docente - Con clases', () {
    testWidgets(
      'muestra el nombre de la clase y "Tus clases" en tema claro a 360x640 con letra 130%',
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
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Tus clases'), findsOneWidget);
        expect(
          find.text('Grupo 01 · Falta agregar estudiantes'),
          findsOneWidget,
        );
        expect(find.text('Nueva'), findsOneWidget);
        expect(find.text('Nueva clase'), findsOneWidget);
        expect(find.byTooltip('Opciones de la clase'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra el nombre de la clase y "Tus clases" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() async {
          await database.insertCourse(_sampleCourse());
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Tus clases'), findsOneWidget);
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

    testWidgets(
      'eliminar clase muestra hoja, confirmación destructiva y borra',
      (tester) async {
        final course = _sampleCourse();
        await tester.runAsync(() => database.insertCourse(course));

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(find.text('Bases de Datos II'), findsOneWidget);

        await tester.tap(find.byTooltip('Opciones de la clase'));
        await tester.pumpAndSettle();

        expect(find.text('Eliminar clase'), findsOneWidget);

        await tester.tap(find.text('Eliminar clase'));
        await tester.pumpAndSettle();

        expect(find.text('¿Eliminar esta clase?'), findsOneWidget);
        expect(
          find.text(
            'Se borran sus estudiantes y sus sesiones. No se puede deshacer.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await _waitForDb(tester);
        await tester.pumpAndSettle();

        expect(find.text('Clase eliminada.'), findsOneWidget);
        expect(find.text('Aún no tienes clases'), findsOneWidget);
        final remaining = await tester.runAsync(() => database.getAllCourses());
        expect(remaining, isEmpty);
      },
    );
  });
}
