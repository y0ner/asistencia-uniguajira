import 'dart:typed_data';

import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _packet([int seed = 0]) {
  return Uint8List.fromList(
    List<int>.generate(16, (int index) => (index + seed) & 0xFF),
  );
}

class _RecordingFakePeripheral implements FlutterBlePeripheral {
  final List<String> calls = <String>[];
  bool isAdvertisingState = false;
  PeripheralBluetoothState startReturnState = PeripheralBluetoothState.ready;
  Object? errorToThrow;

  @override
  Future<PeripheralBluetoothState> start({
    required AdvertiseDataCore advertiseData,
    GattServerSettings? gattServer,
    AndroidAdvertiseSettings? androidSettings,
    DarwinAdvertiseSettings? darwinSettings,
    WindowsAdvertiseSettings? windowsSettings,
  }) async {
    calls.add('start');
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    isAdvertisingState = startReturnState == PeripheralBluetoothState.ready;
    return startReturnState;
  }

  @override
  Future<PeripheralBluetoothState> stop() async {
    calls.add('stop');
    isAdvertisingState = false;
    return PeripheralBluetoothState.ready;
  }

  @override
  Future<bool> get isAdvertising async => isAdvertisingState;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('BleAttendanceService - Pruebas base', () {
    test('inyecta paquetes simulados y los publica con su RSSI', () async {
      final service = BleAttendanceService();
      addTearDown(service.dispose);

      final eventFuture = service.packetEvents.first;
      final bytesFuture = service.packetStream.first;
      final packet = _packet();

      expect(service.injectSimulatedPacket(packet16: packet, rssi: -60), isTrue);

      final event = await eventFuture;
      final bytes = await bytesFuture;
      expect(event.packet16, packet);
      expect(event.rssi, -60);
      expect(bytes, packet);
    });

    test('descarta por RSSI mínimo y acepta el valor límite', () async {
      final service = BleAttendanceService();
      addTearDown(service.dispose);

      final received = <Uint8List>[];
      final subscription = service.packets.listen(received.add);
      addTearDown(subscription.cancel);

      expect(
        service.injectSimulatedPacket(packet16: _packet(), rssi: -76),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);

      expect(
        service.injectSimulatedPacket(packet16: _packet(), rssi: -75),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
    });

    test('permite configurar un umbral de proximidad distinto', () {
      final service = BleAttendanceService(minRssiDbm: -90);
      addTearDown(service.dispose);

      expect(service.minRssiDbm, -90);
      expect(
        service.injectSimulatedPacket(packet16: _packet(), rssi: -85),
        isTrue,
      );
    });

    test('rechaza paquetes que no miden 16 bytes', () async {
      final service = BleAttendanceService();
      addTearDown(service.dispose);

      expect(
        service.injectSimulatedPacket(packet16: Uint8List(15), rssi: -50),
        isFalse,
      );
      await expectLater(
        service.startAdvertisingPacket(Uint8List(15)),
        throwsArgumentError,
      );
    });

    test('dispose cierra el Stream de eventos e incidencias', () async {
      final service = BleAttendanceService();
      await service.dispose();

      await expectLater(service.packetEvents, emitsDone);
      await expectLater(service.issues, emitsDone);
      expect(
        service.injectSimulatedPacket(packet16: _packet(), rssi: -40),
        isFalse,
      );
    });
  });

  group('BleAttendanceService - Criterios de Aceptación Brief O1-A', () {
    test(
      '50 llamadas seguidas a startAdvertisingPacket con paquetes distintos '
      'producen en el peripheral falso el patrón exacto stop -> start sin dos start seguidos',
      () async {
        final peripheral = _RecordingFakePeripheral();
        final service = BleAttendanceService(peripheral: peripheral);
        addTearDown(service.dispose);

        // Disparamos 50 llamadas de anuncio en concurrencia / secuencia encolada
        final futures = <Future<void>>[];
        for (var i = 0; i < 50; i++) {
          futures.add(service.startAdvertisingPacket(_packet(i)));
        }
        await Future.wait(futures);

        expect(peripheral.calls.first, 'start');
        final afterFirst = peripheral.calls.sublist(1);

        // Tras el primer start, las siguientes 49 llamadas deben producir [stop, start]
        expect(afterFirst.length, 49 * 2);
        for (var i = 0; i < afterFirst.length; i += 2) {
          expect(
            afterFirst[i],
            'stop',
            reason: 'El índice $i tras el primer start debe ser stop',
          );
          expect(
            afterFirst[i + 1],
            'start',
            reason: 'El índice ${i + 1} tras stop debe ser start',
          );
        }

        // Validación estricta: nunca debe haber dos 'start' seguidos
        for (var i = 0; i < peripheral.calls.length - 1; i++) {
          final pair = <String>[peripheral.calls[i], peripheral.calls[i + 1]];
          expect(
            pair,
            isNot(<String>['start', 'start']),
            reason: 'Se detectaron dos llamadas a start seguidas en índice $i',
          );
        }
      },
    );

    test('reanunciar el mismo paquete no llama a start() otra vez', () async {
      final peripheral = _RecordingFakePeripheral();
      final service = BleAttendanceService(peripheral: peripheral);
      addTearDown(service.dispose);

      final packet = _packet(123);
      await service.startAdvertisingPacket(packet);

      expect(peripheral.calls, <String>['start']);

      // Llamamos múltiples veces con el paquete idéntico
      for (var i = 0; i < 10; i++) {
        await service.startAdvertisingPacket(packet);
      }

      // Debe permanecer exactamente con un solo start
      expect(peripheral.calls, <String>['start']);
      expect(service.isAdvertising, isTrue);
    });

    test(
      'un fallo de start() llega al Stream de problemas con un mensaje en español',
      () async {
        final peripheral = _RecordingFakePeripheral();
        peripheral.errorToThrow = Exception(
          'ADVERTISE_FAILED_TOO_MANY_ADVERTISERS',
        );
        final service = BleAttendanceService(peripheral: peripheral);
        addTearDown(service.dispose);

        final issueFuture = service.issues.first;

        await expectLater(
          service.startAdvertisingPacket(_packet(1)),
          throwsA(isA<Exception>()),
        );

        final issue = await issueFuture;
        expect(issue.type, BleRuntimeIssueType.advertising);
        expect(
          issue.message,
          contains('Fallo al iniciar el anuncio BLE'),
        );
        expect(
          issue.message,
          contains('ADVERTISE_FAILED_TOO_MANY_ADVERTISERS'),
        );
      },
    );
  });
}
