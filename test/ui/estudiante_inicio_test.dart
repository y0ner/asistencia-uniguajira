import 'dart:io';

import 'package:asistencia_uniguajira/core/models/student_enrollment_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/features/student/student_courses_screen.dart';
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
      home: StudentCoursesScreen(database: database),
    ),
  );
  await _waitForDb(tester);
}

StudentEnrollmentModel _sampleEnrollment({
  String id = 'course-bd2_0182120016',
  String courseId = 'course-bd2',
  String courseCode = 'SIST-401',
  String courseName = 'Bases de Datos II',
  String studentId = 'student-1',
  String studentCode = '0182120016',
  String fullName = 'Ana Lucía Pérez',
  int bitIndex = 5,
  String deviceSecret =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
  String sharedSecret =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  int enrolledAtEpochMs = 1700000000000,
}) {
  return StudentEnrollmentModel(
    id: id,
    courseId: courseId,
    courseCode: courseCode,
    courseName: courseName,
    studentId: studentId,
    studentCode: studentCode,
    fullName: fullName,
    bitIndex: bitIndex,
    deviceSecret: deviceSecret,
    sharedSecret: sharedSecret,
    enrolledAtEpochMs: enrolledAtEpochMs,
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

  group('Inicio del estudiante - Estado vacío', () {
    testWidgets(
      'muestra "Aún no estás en ninguna clase" en tema claro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(StudentCoursesScreen), findsOneWidget);
        expect(find.byType(UiBrandHeader), findsOneWidget);
        expect(find.byTooltip('Ajustes y diagnóstico'), findsOneWidget);
        expect(find.text('¿A qué clase llegaste?'), findsOneWidget);
        expect(find.text('Aún no estás en ninguna clase'), findsOneWidget);
        expect(
          find.text('Pídele a tu profesor el código QR de la clase y únete.'),
          findsOneWidget,
        );
        expect(find.text('Unirme a una clase'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra "Aún no estás en ninguna clase" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(StudentCoursesScreen), findsOneWidget);
        expect(find.text('¿A qué clase llegaste?'), findsOneWidget);
        expect(find.text('Aún no estás en ninguna clase'), findsOneWidget);
        expect(find.text('Unirme a una clase'), findsOneWidget);
      },
    );
  });

  group('Inicio del estudiante - Con clases', () {
    testWidgets(
      'muestra el nombre de la clase y "Marcar asistencia" en tema claro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() async {
          await database.upsertStudentEnrollment(_sampleEnrollment());
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(StudentCoursesScreen), findsOneWidget);
        expect(find.text('Hola, Ana'), findsOneWidget);
        expect(find.text('¿A qué clase llegaste?'), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('SIST-401'), findsOneWidget);
        expect(find.text('Marcar asistencia'), findsOneWidget);
        expect(find.text('Unirme a una clase'), findsOneWidget);
        expect(find.byTooltip('Opciones de la clase'), findsOneWidget);
      },
    );

    testWidgets(
      'muestra el nombre de la clase y "Marcar asistencia" en tema oscuro a 360x640 con letra 130%',
      (tester) async {
        await tester.runAsync(() async {
          await database.upsertStudentEnrollment(_sampleEnrollment());
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.dark(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(StudentCoursesScreen), findsOneWidget);
        expect(find.text('Bases de Datos II'), findsOneWidget);
        expect(find.text('Marcar asistencia'), findsOneWidget);
      },
    );

    testWidgets(
      'con dos clases: primer botón es primary y segundo es tonal',
      (tester) async {
        await tester.runAsync(() async {
          await database.upsertStudentEnrollment(_sampleEnrollment());
          await database.upsertStudentEnrollment(
            _sampleEnrollment(
              id: 'course-is_0182120016',
              courseId: 'course-is',
              courseCode: 'SIST-402',
              courseName: 'Ingeniería de Software',
            ),
          );
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        expect(tester.takeException(), isNull);
        final buttons = tester
            .widgetList<UiButton>(find.byType(UiButton))
            .where((b) => b.label == 'Marcar asistencia')
            .toList();
        expect(buttons.length, 2);
        expect(buttons[0].variant, UiButtonVariant.primary);
        expect(buttons[1].variant, UiButtonVariant.tonal);
      },
    );

    testWidgets(
      'opciones de la clase abre confirmación de salir y cancela correctamente',
      (tester) async {
        await tester.runAsync(() async {
          await database.upsertStudentEnrollment(_sampleEnrollment());
        });

        await _pumpScreen(
          tester,
          theme: UiTheme.light(),
          database: database,
        );

        await tester.tap(find.byTooltip('Opciones de la clase'));
        await tester.pumpAndSettle();

        expect(find.text('Salir de esta clase'), findsOneWidget);

        await tester.tap(find.text('Salir de esta clase'));
        await tester.pumpAndSettle();

        expect(find.text('¿Salir de esta clase?'), findsOneWidget);
        expect(
          find.text('Para volver tendrás que pedirle el código a tu profesor.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(find.text('Bases de Datos II'), findsOneWidget);
      },
    );
  });
}
