import 'dart:io';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
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
        expect(find.widgetWithText(UiButton, 'Enviar Excel'), findsOneWidget);
        expect(find.byTooltip('Opciones de la clase'), findsOneWidget);
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
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Enviar Excel'), findsOneWidget);
        expect(find.byTooltip('Opciones de la clase'), findsOneWidget);
      },
    );
  });

  group('Detalle de clase - Con 2 estudiantes, 1 sesión cerrada y 1 abierta', () {
    Future<void> seedScenario() async {
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

      // Sesión 1: cerrada, sólo asistió Juan Pérez (1 de 2)
      await database.insertSession(SessionModel(
        id: 'ses-closed',
        courseId: course.id,
        startedAt: '2026-11-02T08:00:00.000-05:00',
        roomPin: '41',
      ));
      await database.insertAttendanceRecord(AttendanceRecordModel(
        id: 'rec-1',
        sessionId: 'ses-closed',
        studentId: 'std-1',
        bitIndex: 0,
        method: AppConstants.attendanceMethodBleHmac,
        recordedAt: '2026-11-02T08:10:00.000-05:00',
      ));
      await database.closeSession(
        sessionId: 'ses-closed',
        closedAt: '2026-11-02T09:00:00.000-05:00',
      );

      // Sesión 2: abierta (en vivo)
      await database.insertSession(const SessionModel(
        id: 'ses-open',
        courseId: 'course-bd2',
        startedAt: '2026-11-09T08:00:00.000-05:00',
        roomPin: '42',
      ));
    }

    testWidgets(
      'muestra "1 de 2", "En vivo", ficha "en riesgo", "Enviar Excel", y opciones con "Eliminar clase" y confirmación (tema claro)',
      (tester) async {
        await tester.runAsync(seedScenario);

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);

        // Tarjeta principal indica volver a la sesión abierta y conteo de estudiantes
        expect(find.text('Volver a la sesión'), findsOneWidget);
        expect(find.text('2 estudiantes'), findsOneWidget);

        // Fichas estadísticas (incluye la ficha en riesgo)
        expect(find.text('en riesgo'), findsOneWidget);
        expect(find.text('sesiones'), findsOneWidget);
        expect(find.text('asistencia'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Ver reportes',
          ),
          findsOneWidget,
        );

        // Últimas sesiones: muestra "1 de 2" y "En vivo"
        expect(find.text('1 de 2'), findsOneWidget);
        expect(find.text('En vivo'), findsOneWidget);

        // Botones inferiores
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Enviar Excel'), findsOneWidget);

        // Opciones de la clase en la barra superior
        final optionsButton = find.byTooltip('Opciones de la clase');
        expect(optionsButton, findsOneWidget);
        await tester.tap(optionsButton);
        await tester.pumpAndSettle();

        expect(find.text('Agregar estudiantes'), findsOneWidget);
        final deleteRow = find.text('Eliminar clase');
        expect(deleteRow, findsOneWidget);

        // Toca Eliminar clase para verificar el diálogo de confirmación
        await tester.tap(deleteRow);
        await tester.pumpAndSettle();

        expect(find.text('¿Eliminar esta clase?'), findsOneWidget);
        expect(
          find.text('Se borran sus estudiantes y sus sesiones. No se puede deshacer.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Eliminar'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Cancelar'), findsOneWidget);

        // Cancela la eliminación para no alterar la pantalla
        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'muestra "1 de 2", "En vivo", ficha "en riesgo", "Enviar Excel", y opciones con "Eliminar clase" y confirmación (tema oscuro)',
      (tester) async {
        await tester.runAsync(seedScenario);

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          course: course,
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CourseDetailScreen), findsOneWidget);

        // Tarjeta principal y conteos
        expect(find.text('Volver a la sesión'), findsOneWidget);
        expect(find.text('2 estudiantes'), findsOneWidget);

        // Fichas y sesiones
        expect(find.text('en riesgo'), findsOneWidget);
        expect(find.text('1 de 2'), findsOneWidget);
        expect(find.text('En vivo'), findsOneWidget);

        // Botones inferiores
        expect(find.widgetWithText(UiButton, 'Estudiantes'), findsOneWidget);
        expect(find.widgetWithText(UiButton, 'Enviar Excel'), findsOneWidget);

        // Opciones de la clase
        await tester.tap(find.byTooltip('Opciones de la clase'));
        await tester.pumpAndSettle();

        expect(find.text('Eliminar clase'), findsOneWidget);
        await tester.tap(find.text('Eliminar clase'));
        await tester.pumpAndSettle();

        expect(find.text('¿Eliminar esta clase?'), findsOneWidget);
        expect(
          find.text('Se borran sus estudiantes y sus sesiones. No se puede deshacer.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Eliminar'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
