import 'dart:io';

import 'package:asistencia_uniguajira/data/services/report_share_service.dart';
import 'package:asistencia_uniguajira/features/teacher/course_reports_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  group('ReportShareService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('report_share_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'archivo válido invoca la función falsa con la ruta y el mime type correctos',
      () async {
        final validFile = File('${tempDir.path}/reporte_asistencia.xlsx');
        await validFile.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);

        ShareParams? capturedParams;
        var handlerCallCount = 0;

        final service = ReportShareService(
          shareHandler: (ShareParams params) async {
            handlerCallCount++;
            capturedParams = params;
            return const ShareResult('com.whatsapp', ShareResultStatus.success);
          },
        );

        final outcome = await service.shareReport(
          filePath: validFile.path,
          courseName: 'Sistemas Distribuidos',
        );

        expect(handlerCallCount, equals(1));
        expect(capturedParams, isNotNull);
        expect(capturedParams!.files, isNotNull);
        expect(capturedParams!.files, hasLength(1));

        final sharedFile = capturedParams!.files!.first;
        expect(sharedFile.path, equals(validFile.path));
        expect(
          sharedFile.mimeType,
          equals(
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        );
        expect(capturedParams!.subject, contains('Sistemas Distribuidos'));
        expect(capturedParams!.text, contains('Sistemas Distribuidos'));

        expect(outcome.isSuccess, isTrue);
        expect(outcome.isError, isFalse);
        expect(outcome.isDismissed, isFalse);
        expect(outcome.status, equals(ReportShareStatus.success));
        expect(outcome.rawResult?.raw, equals('com.whatsapp'));
      },
    );

    test(
      'archivo inexistente devuelve error en español y no invoca la plataforma',
      () async {
        var handlerCalled = false;
        final service = ReportShareService(
          shareHandler: (ShareParams params) async {
            handlerCalled = true;
            return const ShareResult('', ShareResultStatus.success);
          },
        );

        final missingPath = '${tempDir.path}/no_existe.xlsx';
        final outcome = await service.shareReport(
          filePath: missingPath,
          courseName: 'Cálculo I',
        );

        expect(handlerCalled, isFalse);
        expect(outcome.isError, isTrue);
        expect(outcome.isSuccess, isFalse);
        expect(outcome.status, equals(ReportShareStatus.error));
        expect(outcome.errorMessage, contains('no existe'));
        expect(outcome.errorMessage, contains(missingPath));
      },
    );

    test(
      'archivo vacío devuelve error en español y no invoca la plataforma',
      () async {
        final emptyFile = File('${tempDir.path}/reporte_vacio.xlsx');
        await emptyFile.create();

        var handlerCalled = false;
        final service = ReportShareService(
          shareHandler: (ShareParams params) async {
            handlerCalled = true;
            return const ShareResult('', ShareResultStatus.success);
          },
        );

        final outcome = await service.shareReport(
          filePath: emptyFile.path,
          courseName: 'Física Mecánica',
        );

        expect(handlerCalled, isFalse);
        expect(outcome.isError, isTrue);
        expect(outcome.isSuccess, isFalse);
        expect(outcome.status, equals(ReportShareStatus.error));
        expect(outcome.errorMessage, contains('vacío (0 bytes)'));
      },
    );

    test('ruta vacía o con solo espacios devuelve error en español', () async {
      var handlerCalled = false;
      final service = ReportShareService(
        shareHandler: (ShareParams params) async {
          handlerCalled = true;
          return const ShareResult('', ShareResultStatus.success);
        },
      );

      final outcome = await service.shareReport(
        filePath: '   ',
        courseName: 'Álgebra Lineal',
      );

      expect(handlerCalled, isFalse);
      expect(outcome.isError, isTrue);
      expect(outcome.errorMessage, contains('no puede estar vacía'));
    });

    test('retorna dismissed cuando el usuario descarta la hoja de compartir', () async {
      final validFile = File('${tempDir.path}/reporte.xlsx');
      await validFile.writeAsBytes(<int>[8, 9, 10]);

      final service = ReportShareService(
        shareHandler: (ShareParams params) async {
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      );

      final outcome = await service.shareReport(
        filePath: validFile.path,
        courseName: 'Redes I',
      );

      expect(outcome.isSuccess, isFalse);
      expect(outcome.isDismissed, isTrue);
      expect(outcome.isError, isFalse);
      expect(outcome.status, equals(ReportShareStatus.dismissed));
    });

    test('retorna unavailable cuando la plataforma no tiene resultado disponible', () async {
      final validFile = File('${tempDir.path}/reporte.xlsx');
      await validFile.writeAsBytes(<int>[1, 2]);

      final service = ReportShareService(
        shareHandler: (ShareParams params) async {
          return ShareResult.unavailable;
        },
      );

      final outcome = await service.shareReport(
        filePath: validFile.path,
        courseName: 'Base de Datos',
      );

      expect(outcome.isSuccess, isFalse);
      expect(outcome.isUnavailable, isTrue);
      expect(outcome.isError, isFalse);
      expect(outcome.status, equals(ReportShareStatus.unavailable));
    });

    test('captura excepciones de la plataforma y retorna error en español', () async {
      final validFile = File('${tempDir.path}/reporte.xlsx');
      await validFile.writeAsBytes(<int>[1, 2, 3]);

      final service = ReportShareService(
        shareHandler: (ShareParams params) async {
          throw Exception('Intent chooser failure on Android');
        },
      );

      final outcome = await service.shareReport(
        filePath: validFile.path,
        courseName: 'Algoritmos',
      );

      expect(outcome.isError, isTrue);
      expect(outcome.status, equals(ReportShareStatus.error));
      expect(outcome.errorMessage, contains('Intent chooser failure'));
    });
  });

  group('CourseReportsScreen Diálogo de éxito de exportación', () {
    testWidgets(
      'muestra nombre, tamaño y los botones Compartir y Cerrar, sin huella a la vista',
      (WidgetTester tester) async {
        const testFilePath = '/storage/emulated/0/Download/Asistencia_MAT101_01.xlsx';
        const testFileSize = 24576;
        const testHmac = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

        var shareInvoked = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: UiTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) {
                  return ElevatedButton(
                    onPressed: () {
                      CourseReportsScreen.showExportSuccessDialog(
                        context: context,
                        filePath: testFilePath,
                        fileSizeBytes: testFileSize,
                        hmacSha256: testHmac,
                        onShare: () async {
                          shareInvoked = true;
                        },
                      );
                    },
                    child: const Text('Abrir Diálogo'),
                  );
                },
              ),
            ),
          ),
        );

        // Abrir el diálogo
        await tester.tap(find.text('Abrir Diálogo'));
        await tester.pumpAndSettle();

        // Verificar título e información clave
        expect(find.text('Excel listo'), findsOneWidget);
        expect(find.text('24.0 KB'), findsOneWidget);
        expect(find.text('Asistencia_MAT101_01.xlsx'), findsOneWidget);
        expect(find.text(testHmac), findsNothing);

        // Verificar acciones: Cerrar y Compartir
        final cerrarButton = find.widgetWithText(TextButton, 'Cerrar');
        final compartirButton = find.widgetWithText(FilledButton, 'Compartir');

        expect(cerrarButton, findsOneWidget);
        expect(compartirButton, findsOneWidget);

        // Al presionar Compartir, se invoca el callback onShare y se cierra el diálogo
        await tester.tap(compartirButton);
        await tester.pumpAndSettle();

        expect(shareInvoked, isTrue);
        expect(find.text('Excel listo'), findsNothing);
      },
    );

    testWidgets(
      'botón Cerrar descarta el diálogo sin invocar la acción de compartir',
      (WidgetTester tester) async {
        var shareInvoked = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: UiTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) {
                  return ElevatedButton(
                    onPressed: () {
                      CourseReportsScreen.showExportSuccessDialog(
                        context: context,
                        filePath: '/dummy/path.xlsx',
                        fileSizeBytes: 1024,
                        hmacSha256: 'deadbeef',
                        onShare: () async {
                          shareInvoked = true;
                        },
                      );
                    },
                    child: const Text('Abrir'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        final cerrarButton = find.widgetWithText(TextButton, 'Cerrar');
        await tester.tap(cerrarButton);
        await tester.pumpAndSettle();

        expect(shareInvoked, isFalse);
        expect(find.text('Excel listo'), findsNothing);
      },
    );
  });
}
