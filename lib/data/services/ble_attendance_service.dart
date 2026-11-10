import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';

/// Categoría de una anomalía o falla en tiempo de ejecución del radar BLE.
enum BleRuntimeIssueType {
  /// Falla al iniciar, reconfigurar o detener la emisión BLE.
  advertising,

  /// Falla en el escáner central o recepción de paquetes.
  scan,

  /// El adaptador Bluetooth del dispositivo está apagado o no disponible.
  adapterOff,

  /// Faltan permisos del sistema para operar el transceptor BLE.
  permission,
}

/// Incidencia en tiempo de ejecución de BLE con mensaje legible en español.
class BleRuntimeIssue {
  const BleRuntimeIssue({
    required this.type,
    required this.message,
    this.cause,
  });

  /// Tipo de falla ocurrida.
  final BleRuntimeIssueType type;

  /// Explicación clara en español para banners de usuario o depuración.
  final String message;

  /// Causa técnica subyacente (excepción o estado), si existe.
  final Object? cause;

  @override
  String toString() => '$message${cause != null ? " ($cause)" : ""}';
}

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
/// Service UUID de 128 bits, serializando las llamadas y deteniendo anuncios
/// previos para evitar agotar anunciantes nativos en Android.
/// En recepción usa `flutter_blue_plus`, descarta anuncios por debajo de
/// [minRssiDbm] y emite los paquetes válidos por un [Stream].
class BleAttendanceService {
  BleAttendanceService({
    FlutterBlePeripheral? peripheral,
    this.minRssiDbm = AppConstants.minRssiDbm,
  }) : _peripheral = peripheral ?? FlutterBlePeripheral();

  final FlutterBlePeripheral _peripheral;
  final StreamController<BlePacketEvent> _packetController =
      StreamController<BlePacketEvent>.broadcast();
  final StreamController<BleRuntimeIssue> _issuesController =
      StreamController<BleRuntimeIssue>.broadcast();

  /// Umbral mínimo de RSSI aceptado por el radar.
  final int minRssiDbm;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  bool _isAdvertising = false;
  Uint8List? _lastAdvertisedPacket;
  Future<void> _adQueue = Future<void>.value();
  bool _disposed = false;

  /// Eventos BLE validados, con su RSSI original.
  Stream<BlePacketEvent> get packetEvents => _packetController.stream;

  /// Paquetes BLE validados, sin metadatos de recepción.
  Stream<Uint8List> get packetStream =>
      _packetController.stream.map((BlePacketEvent event) => event.packet16);

  /// Alias corto de [packetStream] para consumidores del radar.
  Stream<Uint8List> get packets => packetStream;

  /// Canal de incidencias y errores en español generados por el runtime BLE.
  Stream<BleRuntimeIssue> get issues => _issuesController.stream;

  /// Alias de conveniencia para [issues].
  Stream<BleRuntimeIssue> get runtimeIssues => _issuesController.stream;

  /// Indica si este servicio mantiene una escucha de escaneo activa.
  bool get isScanning => _scanSubscription != null;

  /// Indica si hay una emisión publicitaria BLE activa.
  bool get isAdvertising => _isAdvertising;

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
        _reportIssue(
          BleRuntimeIssue(
            type: BleRuntimeIssueType.scan,
            message: 'Error en la recepción del escaneo BLE: $error',
            cause: error,
          ),
        );
        if (!_packetController.isClosed) {
          _packetController.addError(error, stackTrace);
        }
      },
    );

    _listenAdapterState();

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
      );
    } catch (error) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _reportIssue(
        BleRuntimeIssue(
          type: BleRuntimeIssueType.scan,
          message: 'Fallo al iniciar el escaneo BLE: $error',
          cause: error,
        ),
      );
      rethrow;
    }
  }

  /// Detiene el escaneo y libera la suscripción al radar.
  Future<void> stopScan() async {
    final subscription = _scanSubscription;
    _scanSubscription = null;
    await subscription?.cancel();
    if (subscription != null) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (error) {
        _reportIssue(
          BleRuntimeIssue(
            type: BleRuntimeIssueType.scan,
            message: 'Error al detener el escaneo BLE: $error',
            cause: error,
          ),
        );
      }
    }
  }

  /// Publica un paquete de 16 bytes como Service UUID de 128 bits.
  ///
  /// Serializa todas las solicitudes en una cola para evitar concurrencia en el
  /// periférico. Si ya hay un anuncio activo, lo detiene y espera antes de
  /// iniciar el siguiente. Si el paquete es idéntico al anunciado actualmente,
  /// no reinicia el anuncio.
  Future<void> startAdvertisingPacket(Uint8List packet16) {
    _ensureNotDisposed();
    _validatePacket(packet16);

    final targetPacket = Uint8List.fromList(packet16);
    final completer = Completer<void>();

    _adQueue = _adQueue.then((_) async {
      try {
        await _executeAdvertisingPacket(targetPacket);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<void> _executeAdvertisingPacket(Uint8List packet16) async {
    _ensureNotDisposed();

    // 2. Reemitir solo si cambia algo:
    // Si el paquete es idéntico al que ya se está anunciando, no reiniciar.
    if (_isAdvertising &&
        _lastAdvertisedPacket != null &&
        _areBytesEqual(_lastAdvertisedPacket!, packet16)) {
      return;
    }

    // 1. Anuncio sin fugas:
    // Si ya hay un anuncio activo, detenlo y espera antes de iniciar el siguiente.
    if (_isAdvertising) {
      try {
        await _peripheral.stop();
      } catch (error) {
        _reportIssue(
          BleRuntimeIssue(
            type: BleRuntimeIssueType.advertising,
            message: 'Error al detener anuncio BLE anterior: $error',
            cause: error,
          ),
        );
      } finally {
        _isAdvertising = false;
        _lastAdvertisedPacket = null;
      }
    }

    try {
      final state = await _peripheral.start(
        advertiseData: AdvertiseDataCore(
          serviceUuid: BlePacketCodec.bytes16ToUuid(packet16),
        ),
      );

      // Confirmar que el periférico quedó activo
      if (state != PeripheralBluetoothState.ready) {
        final issue = BleRuntimeIssue(
          type: BleRuntimeIssueType.advertising,
          message:
              'No se pudo activar el anuncio BLE (estado: ${state.name}).',
          cause: state,
        );
        _reportIssue(issue);
        throw StateError(issue.message);
      }

      _isAdvertising = true;
      _lastAdvertisedPacket = packet16;
    } catch (error) {
      _isAdvertising = false;
      _lastAdvertisedPacket = null;
      _reportIssue(
        BleRuntimeIssue(
          type: BleRuntimeIssueType.advertising,
          message: 'Fallo al iniciar el anuncio BLE: $error',
          cause: error,
        ),
      );
      rethrow;
    }
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

  /// Detiene el anuncio BLE activo esperando a que la cola complete.
  Future<void> stopAdvertising() {
    final completer = Completer<void>();
    _adQueue = _adQueue.then((_) async {
      try {
        if (_isAdvertising) {
          try {
            await _peripheral.stop();
          } catch (error) {
            _reportIssue(
              BleRuntimeIssue(
                type: BleRuntimeIssueType.advertising,
                message: 'Error al detener anuncio BLE: $error',
                cause: error,
              ),
            );
          } finally {
            _isAdvertising = false;
            _lastAdvertisedPacket = null;
          }
        }
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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

  /// Detiene emisión y escaneo, y cierra los Streams de eventos e incidencias.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stopScan();
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    try {
      await stopAdvertising();
    } finally {
      await _packetController.close();
      await _issuesController.close();
    }
  }

  void _listenAdapterState() {
    if (_adapterSubscription != null) return;
    try {
      _adapterSubscription = FlutterBluePlus.adapterState.listen(
        (BluetoothAdapterState state) {
          if (state != BluetoothAdapterState.on) {
            _reportIssue(
              BleRuntimeIssue(
                type: BleRuntimeIssueType.adapterOff,
                message:
                    'El adaptador Bluetooth no está encendido ($state).',
                cause: state,
              ),
            );
          }
        },
        onError: (Object error) {
          _reportIssue(
            BleRuntimeIssue(
              type: BleRuntimeIssueType.adapterOff,
              message:
                  'Error al monitorear el adaptador Bluetooth: $error',
              cause: error,
            ),
          );
        },
      );
    } catch (_) {
      // Ignorar fallo de escucha de adaptador en entornos sin implementación nativa
    }
  }

  void _reportIssue(BleRuntimeIssue issue) {
    if (!_issuesController.isClosed) {
      _issuesController.add(issue);
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

  static bool _areBytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
