import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';

/// Evento BLE validado que contiene un paquete de 16 bytes y su RSSI.
class BlePacketEvent {
  const BlePacketEvent({required this.packet16, required this.rssi});

  /// Paquete binario completo del protocolo.
  final Uint8List packet16;

  /// Potencia recibida del anuncio, en dBm.
  final int rssi;
}

/// Transceptor BLE del proyecto.
///
/// En emisión usa `flutter_ble_peripheral` y publica los 16 bytes dentro de un
/// Service UUID de 128 bits, evitando el límite de 31 bytes del advertising
/// Legacy de Android. En recepción usa `flutter_blue_plus`, descarta anuncios
/// por debajo de [minRssiDbm] y emite los paquetes válidos por un [Stream].
class BleAttendanceService {
  BleAttendanceService({
    FlutterBlePeripheral? peripheral,
    this.minRssiDbm = AppConstants.minRssiDbm,
  }) : _peripheral = peripheral ?? FlutterBlePeripheral();

  final FlutterBlePeripheral _peripheral;
  final StreamController<BlePacketEvent> _packetController =
      StreamController<BlePacketEvent>.broadcast();

  /// Umbral mínimo de RSSI aceptado por el radar.
  final int minRssiDbm;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isAdvertising = false;
  bool _disposed = false;

  /// Eventos BLE validados, con su RSSI original.
  Stream<BlePacketEvent> get packetEvents => _packetController.stream;

  /// Paquetes BLE validados, sin metadatos de recepción.
  Stream<Uint8List> get packetStream =>
      _packetController.stream.map((BlePacketEvent event) => event.packet16);

  /// Alias corto de [packetStream] para consumidores del radar.
  Stream<Uint8List> get packets => packetStream;

  /// Indica si este servicio mantiene una escucha de escaneo activa.
  bool get isScanning => _scanSubscription != null;

  /// Inicia el escaneo BLE y publica cada paquete de 16 bytes recibido.
  ///
  /// [timeout] se delega a `flutter_blue_plus`; `null` deja el escaneo activo
  /// hasta llamar a [stopScan].
  Future<void> startScan({Duration? timeout}) async {
    _ensureNotDisposed();
    if (_scanSubscription != null) {
      return;
    }

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult result in results) {
          _processScanResult(result);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_packetController.isClosed) {
          _packetController.addError(error, stackTrace);
        }
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
      );
    } catch (_) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      rethrow;
    }
  }

  /// Detiene el escaneo y libera la suscripción al radar.
  Future<void> stopScan() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    if (subscription != null) {
      await FlutterBluePlus.stopScan();
    }
  }

  /// Publica un paquete de 16 bytes como Service UUID de 128 bits.
  ///
  /// No se configura `localName`, por lo que el nombre del dispositivo no se
  /// incluye en el anuncio y el payload queda limitado a 16 bytes.
  Future<void> startAdvertisingPacket(Uint8List packet16) async {
    _ensureNotDisposed();
    _validatePacket(packet16);
    await _peripheral.start(
      advertiseData: AdvertiseDataCore(
        serviceUuid: BlePacketCodec.bytes16ToUuid(packet16),
      ),
    );
    _isAdvertising = true;
  }

  /// Construye y anuncia el paquete de estudiante para la sesión actual.
  Future<void> startStudentBeacon({
    required String courseId,
    required int bitIndex,
    required int sessionPin,
    required String secretHex,
    int? timeTick,
  }) {
    final packet = BlePacketCodec.buildStudentBeaconBytes(
      courseId: courseId,
      bitIndex: bitIndex,
      sessionPin: sessionPin,
      secretHex: secretHex,
      timeTick: timeTick ?? BlePacketCodec.computeTimeTick(DateTime.now()),
    );
    return startAdvertisingPacket(packet);
  }

  /// Construye y anuncia el eco del docente con el Bitmap de la sesión.
  Future<void> startTeacherEcho({
    required String courseId,
    required String sessionId,
    required Uint8List bitmap8,
    required String sharedSecretHex,
  }) {
    final packet = BlePacketCodec.buildTeacherEchoBytes(
      courseId: courseId,
      sessionId: sessionId,
      bitmap8: bitmap8,
      sharedSecretHex: sharedSecretHex,
    );
    return startAdvertisingPacket(packet);
  }

  /// Detiene el anuncio BLE activo.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      return;
    }
    try {
      await _peripheral.stop();
    } finally {
      _isAdvertising = false;
    }
  }

  /// Inyecta un paquete simulado para pruebas deterministas sin hardware BLE.
  ///
  /// Devuelve `true` solo si el paquete mide 16 bytes y supera el umbral RSSI.
  bool injectSimulatedPacket({required Uint8List packet16, required int rssi}) {
    if (_disposed || packet16.length != BlePacketCodec.packetLength) {
      return false;
    }
    return _emitIfNearby(packet16, rssi);
  }

  /// Detiene emisión y escaneo, y cierra el Stream de eventos.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stopScan();
    try {
      await stopAdvertising();
    } finally {
      await _packetController.close();
    }
  }

  void _processScanResult(ScanResult result) {
    if (result.rssi < minRssiDbm) {
      return;
    }
    for (final Guid serviceUuid in result.advertisementData.serviceUuids) {
      final packet = BlePacketCodec.tryUuidToBytes16(serviceUuid.toString());
      if (packet == null) {
        continue;
      }
      _emitIfNearby(packet, result.rssi);
      return;
    }
  }

  bool _emitIfNearby(Uint8List packet16, int rssi) {
    if (_disposed ||
        packet16.length != BlePacketCodec.packetLength ||
        rssi < minRssiDbm) {
      return false;
    }
    _packetController.add(
      BlePacketEvent(packet16: Uint8List.fromList(packet16), rssi: rssi),
    );
    return true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BleAttendanceService ya fue liberado.');
    }
  }

  void _validatePacket(Uint8List packet16) {
    if (packet16.length != BlePacketCodec.packetLength) {
      throw ArgumentError.value(
        packet16.length,
        'packet16',
        'El paquete BLE debe tener exactamente '
            '${BlePacketCodec.packetLength} bytes.',
      );
    }
  }
}
