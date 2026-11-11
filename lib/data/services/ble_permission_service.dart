import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart' as ph
    show openAppSettings;

import '../../core/platform/android_sdk.dart';

/// Tipos funcionales para inyección de dependencias en [BlePermissionService].
typedef AndroidSdkVersionProvider = FutureOr<int> Function();
typedef PermissionStatusChecker =
    Future<PermissionStatus> Function(Permission permission);
typedef PermissionRequester =
    Future<Map<Permission, PermissionStatus>> Function(
      List<Permission> permissions,
    );
typedef BluetoothAdapterStateProvider =
    Stream<BluetoothAdapterState> Function();
typedef BluetoothTurnOnAction = Future<void> Function();
typedef OpenAppSettingsAction = Future<bool> Function();

/// Diagnóstico de permisos y disponibilidad del adaptador BLE.
class BlePermissionResult {
  const BlePermissionResult({
    required this.isReady,
    required this.missingPermissions,
    required this.permanentlyDeniedPermissions,
    required this.isBluetoothTurnedOn,
    this.failureMessage,
  });

  /// `true` si todos los permisos requeridos están otorgados y el Bluetooth está encendido.
  final bool isReady;

  /// Permisos que no están concedidos.
  final List<Permission> missingPermissions;

  /// Permisos denegados permanentemente (requieren abrir ajustes).
  final List<Permission> permanentlyDeniedPermissions;

  /// Indica si el adaptador Bluetooth está encendido.
  final bool isBluetoothTurnedOn;

  /// Mensaje explicativo en español de qué falta para que el hardware esté listo.
  final String? failureMessage;

  /// Indica si al menos un permiso requiere abrir la configuración del sistema.
  bool get requiresAppSettings => permanentlyDeniedPermissions.isNotEmpty;

  /// Indica si el único problema pendiente es encender el adaptador Bluetooth.
  bool get onlyBluetoothOff =>
      missingPermissions.isEmpty && !isBluetoothTurnedOn;
}

/// Servicio encargado de solicitar y validar permisos de Bluetooth y estado del adaptador.
///
/// Soporta:
/// - Android 12 o superior (API >= 31): `bluetoothScan`, `bluetoothAdvertise`, `bluetoothConnect`.
/// - Android 11 o inferior (API <= 30): `locationWhenInUse`.
/// - Verificación del adaptador Bluetooth encendido mediante [FlutterBluePlus].
class BlePermissionService {
  BlePermissionService({
    AndroidSdkVersionProvider? androidSdkVersionProvider,
    PermissionStatusChecker? permissionStatusChecker,
    PermissionRequester? permissionRequester,
    BluetoothAdapterStateProvider? bluetoothAdapterStateProvider,
    BluetoothTurnOnAction? bluetoothTurnOnAction,
    OpenAppSettingsAction? openAppSettingsAction,
  }) : _androidSdkVersionProvider =
           androidSdkVersionProvider ?? _defaultAndroidSdkVersion,
       _permissionStatusChecker =
           permissionStatusChecker ?? _defaultCheckStatus,
       _permissionRequester = permissionRequester ?? _defaultRequestPermissions,
       _bluetoothAdapterStateProvider =
           bluetoothAdapterStateProvider ?? _defaultAdapterStateStream,
       _bluetoothTurnOnAction =
           bluetoothTurnOnAction ?? _defaultTurnOnBluetooth,
       _openAppSettingsAction =
           openAppSettingsAction ?? _defaultOpenAppSettings;

  final AndroidSdkVersionProvider _androidSdkVersionProvider;
  final PermissionStatusChecker _permissionStatusChecker;
  final PermissionRequester _permissionRequester;
  final BluetoothAdapterStateProvider _bluetoothAdapterStateProvider;
  final BluetoothTurnOnAction _bluetoothTurnOnAction;
  final OpenAppSettingsAction _openAppSettingsAction;

  /// Evalúa los permisos requeridos según la versión de Android y el estado del Bluetooth.
  ///
  /// Si [requestIfNotGranted] es `true`, solicita los permisos faltantes antes de reportar el resultado.
  Future<BlePermissionResult> ensureReady({
    bool requestIfNotGranted = true,
  }) async {
    final sdkVersion = await _androidSdkVersionProvider();
    final requiredPermissions = sdkVersion >= 31
        ? const <Permission>[
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
            Permission.bluetoothConnect,
          ]
        : const <Permission>[
            Permission.locationWhenInUse,
          ];

    final statuses = <Permission, PermissionStatus>{};
    for (final permission in requiredPermissions) {
      statuses[permission] = await _permissionStatusChecker(permission);
    }

    var missing = requiredPermissions
        .where((Permission p) => statuses[p] != PermissionStatus.granted)
        .toList(growable: false);

    if (missing.isNotEmpty && requestIfNotGranted) {
      final toRequest = missing
          .where(
            (Permission p) =>
                statuses[p] != PermissionStatus.permanentlyDenied,
          )
          .toList(growable: false);

      if (toRequest.isNotEmpty) {
        final requestResults = await _permissionRequester(toRequest);
        statuses.addAll(requestResults);
      }

      missing = requiredPermissions
          .where((Permission p) => statuses[p] != PermissionStatus.granted)
          .toList(growable: false);
    }

    final permanentlyDenied = missing
        .where(
          (Permission p) => statuses[p] == PermissionStatus.permanentlyDenied,
        )
        .toList(growable: false);

    var isBtOn = false;
    try {
      final state = await _bluetoothAdapterStateProvider()
          .first
          .timeout(const Duration(seconds: 2));
      isBtOn = state == BluetoothAdapterState.on;
    } catch (error) {
      debugPrint(
        'No se pudo leer el estado del adaptador en 2 s: $error; se asume apagado.',
      );
      isBtOn = false;
    }

    final isReady = missing.isEmpty && isBtOn;
    String? failureMessage;

    if (permanentlyDenied.isNotEmpty) {
      failureMessage =
          'Permisos de Bluetooth denegados permanentemente. '
          'Abre los ajustes para concederlos.';
    } else if (missing.isNotEmpty) {
      failureMessage =
          'Faltan permisos de Bluetooth necesarios para operar en el aula.';
    } else if (!isBtOn) {
      failureMessage =
          'El Bluetooth está apagado. Enciéndelo para operar en el aula.';
    }

    return BlePermissionResult(
      isReady: isReady,
      missingPermissions: missing,
      permanentlyDeniedPermissions: permanentlyDenied,
      isBluetoothTurnedOn: isBtOn,
      failureMessage: failureMessage,
    );
  }

  /// Solicita el encendido del adaptador Bluetooth en Android.
  Future<void> turnOnBluetooth() => _bluetoothTurnOnAction();

  /// Abre la pantalla de ajustes de la aplicación.
  Future<bool> openAppSettings() => _openAppSettingsAction();

  static Future<int> _defaultAndroidSdkVersion() async {
    try {
      final sdk = await androidSdkInt();
      if (sdk != null) {
        return sdk;
      }
      return 33;
    } catch (error) {
      debugPrint(
        'No se pudo determinar el SDK de Android: $error; '
        'se asume Android 12+ (SDK 31).',
      );
      return 31;
    }
  }

  static Future<PermissionStatus> _defaultCheckStatus(
    Permission permission,
  ) => permission.status;

  static Future<Map<Permission, PermissionStatus>> _defaultRequestPermissions(
    List<Permission> permissions,
  ) => permissions.request();

  static Stream<BluetoothAdapterState> _defaultAdapterStateStream() =>
      FlutterBluePlus.adapterState;

  static Future<void> _defaultTurnOnBluetooth() => FlutterBluePlus.turnOn();

  static Future<bool> _defaultOpenAppSettings() =>
      ph.openAppSettings();
}
