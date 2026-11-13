import 'dart:async';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';

/// "Aire" simulado: lo que un celular anuncia lo oyen los demás que escanean.
///
/// Reproduce lo esencial del Bluetooth real para las pruebas: un anuncio se
/// repite mientras esté activo y cada celular solo anuncia un paquete a la vez.
class BleAir {
  BleAir({this.tick = const Duration(milliseconds: 3)});

  final Duration tick;
  final List<AirBle> _nodes = <AirBle>[];
  Timer? _timer;

  /// Crea un celular conectado a este aire.
  AirBle node({int rssi = -60}) {
    final ble = AirBle._(this, rssi);
    _nodes.add(ble);
    _timer ??= Timer.periodic(tick, (_) => _deliver());
    return ble;
  }

  void _deliver() {
    for (final sender in _nodes) {
      final packet = sender._current;
      if (packet == null) continue;
      for (final receiver in _nodes) {
        if (identical(receiver, sender) || !receiver._scanning) continue;
        receiver._receive(packet, sender._rssi);
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    for (final node in _nodes) {
      await node._controller.close();
    }
    _nodes.clear();
  }
}

/// Servicio Bluetooth falso de un celular dentro de un [BleAir].
class AirBle extends BleAttendanceService {
  AirBle._(this._air, this._rssi);

  // ignore: unused_field
  final BleAir _air;
  final int _rssi;
  final StreamController<BlePacketEvent> _controller = StreamController<BlePacketEvent>.broadcast();

  Uint8List? _current;
  bool _scanning = false;

  /// Cuántas veces se cambió el paquete anunciado (para medir la rotación).
  int advertiseCalls = 0;

  void _receive(Uint8List packet, int rssi) {
    if (!_controller.isClosed) {
      _controller.add(BlePacketEvent(packet16: Uint8List.fromList(packet), rssi: rssi));
    }
  }

  @override
  Stream<BlePacketEvent> get packetEvents => _controller.stream;

  @override
  bool get isScanning => _scanning;

  @override
  bool get isAdvertising => _current != null;

  @override
  Future<void> startScan({Duration? timeout}) async => _scanning = true;

  @override
  Future<void> stopScan() async => _scanning = false;

  @override
  Future<void> startAdvertisingPacket(Uint8List packet16) async {
    advertiseCalls++;
    _current = Uint8List.fromList(packet16);
  }

  @override
  Future<void> stopAdvertising() async => _current = null;
}
