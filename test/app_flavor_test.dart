import 'package:asistencia_uniguajira/app/app_flavor.dart';
import 'package:asistencia_uniguajira/app/asistencia_app.dart';
import 'package:asistencia_uniguajira/features/shared/hardware_diagnostic_dialog.dart';
import 'package:asistencia_uniguajira/features/student/student_courses_screen.dart';
import 'package:asistencia_uniguajira/features/teacher/courses_dashboard_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Pruebas de AppFlavor y Puntos de Entrada', () {
    test('AppFlavor define títulos y pantallas correctas', () {
      expect(AppFlavor.docente.title, 'Asistencia Docente');
      expect(AppFlavor.estudiante.title, 'Asistencia Estudiante');

      expect(AppFlavor.docente.homeScreen, isA<CoursesDashboardScreen>());
      expect(AppFlavor.estudiante.homeScreen, isA<StudentCoursesScreen>());
    });

    testWidgets(
      'Flavor Docente monta CoursesDashboardScreen con icono de diagnóstico',
      (WidgetTester tester) async {
        await tester.pumpWidget(const AsistenciaApp(flavor: AppFlavor.docente));
        await tester.pump();

        expect(find.byType(CoursesDashboardScreen), findsOneWidget);
        expect(find.byType(StudentCoursesScreen), findsNothing);
        expect(find.text('Asistencia'), findsOneWidget);
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Flavor Estudiante monta StudentCoursesScreen con icono de diagnóstico',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const AsistenciaApp(flavor: AppFlavor.estudiante),
        );
        await tester.pump();

        expect(find.byType(StudentCoursesScreen), findsOneWidget);
        expect(find.byType(CoursesDashboardScreen), findsNothing);
        expect(find.text('Asistencia'), findsOneWidget);
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'Icono de diagnóstico abre DesktopHardwareDiagnosticDialog en escritorio',
      (WidgetTester tester) async {
        await tester.pumpWidget(const AsistenciaApp(flavor: AppFlavor.docente));
        await tester.pump();

        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DesktopHardwareDiagnosticDialog), findsOneWidget);
        expect(find.text('Permisos del celular'), findsOneWidget);
        expect(find.text('Entendido'), findsOneWidget);

        await tester.tap(find.text('Entendido'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DesktopHardwareDiagnosticDialog), findsNothing);
      },
    );
  });

  group('Pruebas de HardwareDiagnosticDialog (Filtro Android 12+)', () {
    testWidgets(
      'HardwareDiagnosticDialog excluye ubicación en Android 12 o superior',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: UiTheme.light(),
            home: Scaffold(
              body: HardwareDiagnosticDialog(
                isAndroid12OrHigherOverride: true,
                permissionChecker: (_) async => PermissionStatus.granted,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Buscar celulares cercanos'), findsOneWidget);
        expect(find.text('Avisar a celulares cercanos'), findsOneWidget);
        expect(find.text('Conectar con celulares cercanos'), findsOneWidget);
        expect(find.textContaining('Cámara ('), findsOneWidget);
        expect(find.textContaining('Ubicación'), findsNothing);
      },
    );

    testWidgets(
      'HardwareDiagnosticDialog incluye ubicación en Android 11 o inferior',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: UiTheme.light(),
            home: Scaffold(
              body: HardwareDiagnosticDialog(
                isAndroid12OrHigherOverride: false,
                permissionChecker: (_) async => PermissionStatus.granted,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Buscar celulares cercanos'), findsOneWidget);
        expect(find.text('Avisar a celulares cercanos'), findsOneWidget);
        expect(find.text('Conectar con celulares cercanos'), findsOneWidget);
        expect(find.textContaining('Cámara ('), findsOneWidget);
        expect(find.textContaining('Ubicación'), findsOneWidget);
      },
    );
  });
}
