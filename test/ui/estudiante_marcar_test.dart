import 'dart:async';
import 'dart:io';

import 'package:asistencia_uniguajira/core/models/student_enrollment_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/attendance_session_controller.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:asistencia_uniguajira/data/services/ble_permission_service.dart';
import 'package:asistencia_uniguajira/features/student/student_live_beacon_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _loadFigtree() async {
  final loader = FontLoader(UiText.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

class _FakeBleAttendanceService extends BleAttendanceService {
  final List<Uint8List> advertisements = <Uint8List>[];
  final List<String> lifecycle = <String>[];
  final _packetController = StreamController<BlePacketEvent>.broadcast();
  final _issuesController = StreamController<BleRuntimeIssue>.broadcast();

  @override
  Stream<BlePacketEvent> get packetEvents => _packetController.stream;

  @override
  Stream<BleRuntimeIssue> get issues => _issuesController.stream;

  @override
  Future<void> startScan({Duration? timeout}) async {
    lifecycle.add('scan-start');
  }

  @override
  Future<void> stopScan() async {
    lifecycle.add('scan-stop');
  }

  @override
  Future<void> startAdvertisingPacket(Uint8List packet16) async {
    advertisements.add(Uint8List.fromList(packet16));
    lifecycle.add('ad-start');
  }

  @override
  Future<void> stopAdvertising() async {
    lifecycle.add('ad-stop');
  }

  void emitPacket(Uint8List packet16, int rssi) {
    _packetController.add(BlePacketEvent(packet16: packet16, rssi: rssi));
  }

  @override
  Future<void> dispose() async {
    await _packetController.close();
    await _issuesController.close();
  }
}

class _FakeAttendanceSessionController extends AttendanceSessionController {
  _FakeAttendanceSessionController({
    required super.database,
    required super.bleService,
  });

  StudentConfirmationOutcome? nextOutcome;

  @override
  Future<StudentConfirmationOutcome> checkTeacherEchoForStudent({
    required StudentEnrollmentModel enrollment,
    required int sessionPin,
    required Uint8List teacherPacket16,
    required int rssi,
    DateTime? nowOverride,
  }) async {
    return nextOutcome ??
        StudentConfirmationOutcome(
          isConfirmed: true,
          verifyCode: 'UG-12345678',
          confirmedAt: DateTime(2026, 11, 11, 8, 41),
          bitIndex: enrollment.bitIndex,
          sessionPin: sessionPin,
          rssi: rssi,
        );
  }

  @override
  Future<void> dispose() async {}
}

BlePermissionService _fakePermissionService({
  bool isReady = true,
  bool onlyBtOff = false,
  bool requiresSettings = false,
}) {
  return BlePermissionService(
    androidSdkVersionProvider: () => 33,
    permissionStatusChecker: (Permission p) async {
      if (!isReady && requiresSettings) return PermissionStatus.permanentlyDenied;
      if (!isReady && !onlyBtOff) return PermissionStatus.denied;
      return PermissionStatus.granted;
    },
    permissionRequester: (list) async => {
      for (final p in list)
        p: (requiresSettings
            ? PermissionStatus.permanentlyDenied
            : (isReady ? PermissionStatus.granted : PermissionStatus.denied)),
    },
    bluetoothAdapterStateProvider: () => Stream.value(
      onlyBtOff ? BluetoothAdapterState.off : BluetoothAdapterState.on,
    ),
    bluetoothTurnOnAction: () async {},
    openAppSettingsAction: () async => true,
  );
}

const _sampleEnrollment = StudentEnrollmentModel(
  id: 'course-1_20261001',
  courseId: 'course-1',
  courseCode: 'BD-201',
  courseName: 'Bases de Datos II',
  studentId: 'stud-1',
  studentCode: '20261001',
  fullName: 'Yoner Gómez',
  bitIndex: 7,
  deviceSecret:
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  sharedSecret:
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
  enrolledAtEpochMs: 1762862400000,
);

void main() {
  sqfliteFfiInit();
  setUpAll(_loadFigtree);

  // Mock wakelock_plus channel so it doesn't fail in headless test environment
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('wakelock_plus'),
    (MethodCall methodCall) async => true,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall methodCall) async => null,
  );

  late AppDatabase db;
  late _FakeBleAttendanceService bleService;
  late _FakeAttendanceSessionController sessionController;

  setUp(() {
    db = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    bleService = _FakeBleAttendanceService();
    sessionController = _FakeAttendanceSessionController(
      database: db,
      bleService: bleService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required ThemeData theme,
    Size size = const Size(360, 640),
    double textScale = 1.0,
    BlePermissionService? permService,
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: StudentLiveBeaconScreen(
          enrollment: _sampleEnrollment,
          bleService: bleService,
          sessionController: sessionController,
          permissionService: permService ?? _fakePermissionService(),
          database: db,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'Paso 1: muestra título, Continuar deshabilitado, se habilita con 4 y 7',
    (tester) async {
      await pumpScreen(tester, theme: UiTheme.light());
      expect(tester.takeException(), isNull);

      // (a) el paso 1 muestra el título
      expect(find.text('Escribe el PIN que dictó tu profesor'), findsOneWidget);
      expect(find.text('Bases de Datos II'), findsOneWidget);
      expect(find.text('Paso 1 de 3'), findsOneWidget);

      // "Continuar" deshabilitado
      final continueButton = find.widgetWithText(UiButton, 'Continuar');
      expect(continueButton, findsOneWidget);
      final buttonWidget = tester.widget<UiButton>(continueButton);
      expect(buttonWidget.onPressed, isNull);

      // Al tocar 4 y 7 se habilita
      await tester.tap(find.text('4'));
      await tester.pump(const Duration(milliseconds: 100));

      // Con 1 solo dígito sigue deshabilitado
      final buttonAfterOneDigit = tester.widget<UiButton>(continueButton);
      expect(buttonAfterOneDigit.onPressed, isNull);

      await tester.tap(find.text('7'));
      await tester.pump(const Duration(milliseconds: 100));

      // Ahora con 2 dígitos (47 >= 10) está habilitado
      final buttonAfterTwoDigits = tester.widget<UiButton>(continueButton);
      expect(buttonAfterTwoDigits.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Paso 1: con 0 y 5 muestra mensaje de error de PIN entre 10 y 99',
    (tester) async {
      await pumpScreen(tester, theme: UiTheme.light());
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('0'));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('5'));
      await tester.pump(const Duration(milliseconds: 100));

      // (b) con "0" y "5" muestra "El PIN tiene dos dígitos, entre 10 y 99."
      expect(
        find.text('El PIN tiene dos dígitos, entre 10 y 99.'),
        findsOneWidget,
      );

      // Si borramos, desaparece el error
      await tester.tap(find.bySemanticsLabel('Borrar'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('El PIN tiene dos dígitos, entre 10 y 99.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Paso 1 aguanta tema claro, 360 x 640 y letra al 130 % sin excepciones',
    (tester) async {
      await pumpScreen(
        tester,
        theme: UiTheme.light(),
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);

      expect(find.text('Escribe el PIN que dictó tu profesor'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);

      await tester.tap(find.text('4'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('7'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Paso 1 aguanta tema oscuro, 360 x 640 y letra al 130 % sin excepciones',
    (tester) async {
      await pumpScreen(
        tester,
        theme: UiTheme.dark(),
        size: const Size(360, 640),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);

      expect(find.text('Escribe el PIN que dictó tu profesor'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);

      await tester.tap(find.text('0'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('5'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('El PIN tiene dos dígitos, entre 10 y 99.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Flujo completo: Paso 1 (PIN 47) -> Paso 2 (Acercar) -> Paso 3 (¡Presente!)',
    (tester) async {
      await pumpScreen(tester, theme: UiTheme.light());

      // Paso 1: Ingreso de PIN
      await tester.tap(find.text('4'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('7'));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Continuar'));
      await tester.pump(const Duration(milliseconds: 300));

      // Paso 2: Acercar
      expect(find.text('Acerca tu celular al del profesor'), findsOneWidget);
      expect(find.text('Paso 2 de 3'), findsOneWidget);
      expect(find.text('PIN 47'), findsOneWidget);
      expect(find.text('Buscando al profesor'), findsOneWidget);
      expect(
        find.text(
          'Deja esta pantalla abierta. Te avisamos apenas quedes registrado.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cambiar PIN'), findsOneWidget);

      // Simular confirmación del profesor (eco con bit 7 encendido)
      sessionController.nextOutcome = StudentConfirmationOutcome(
        isConfirmed: true,
        verifyCode: 'UG-12345678',
        confirmedAt: DateTime(2026, 11, 11, 8, 41),
        bitIndex: 7,
        sessionPin: 47,
        rssi: -60,
      );
      bleService.emitPacket(Uint8List(16), -60);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Paso 3: ¡Presente!
      expect(find.text('¡Presente!'), findsOneWidget);
      expect(find.text('Paso 3 de 3'), findsOneWidget);
      expect(find.text('Asistencia registrada'), findsOneWidget);
      expect(find.text('Bases de Datos II'), findsNWidgets(2));
      expect(find.text('El celular del profesor'), findsOneWidget);
      expect(find.text('Ya puedes guardar el celular.'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}


