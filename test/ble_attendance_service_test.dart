import 'dart:typed_data';

import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _packet([int seed = 0]) {
  return Uint8List.fromList(
    List<int>.generate(16, (int index) => (index + seed) & 0xFF),
  );
}

void main() {
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

  test('dispose cierra el Stream de eventos', () async {
    final service = BleAttendanceService();
    await service.dispose();

    await expectLater(service.packetEvents, emitsDone);
    expect(
      service.injectSimulatedPacket(packet16: _packet(), rssi: -40),
      isFalse,
    );
  });
}
