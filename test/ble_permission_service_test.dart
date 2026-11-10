import 'package:asistencia_uniguajira/data/services/ble_permission_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('BlePermissionService', () {
    test('1. Todo concedido en Android 12+ (SDK >= 31)', () async {
      final requestedList = <Permission>[];
      final service = BlePermissionService(
        androidSdkVersionProvider: () => 33,
        permissionStatusChecker: (Permission p) async =>
            PermissionStatus.granted,
        permissionRequester: (List<Permission> list) async {
          requestedList.addAll(list);
          return <Permission, PermissionStatus>{
            for (final p in list) p: PermissionStatus.granted,
          };
        },
        bluetoothAdapterStateProvider: () =>
            Stream<BluetoothAdapterState>.value(BluetoothAdapterState.on),
      );

      final result = await service.ensureReady();

      expect(result.isReady, isTrue);
      expect(result.missingPermissions, isEmpty);
      expect(result.permanentlyDeniedPermissions, isEmpty);
      expect(result.isBluetoothTurnedOn, isTrue);
      expect(result.requiresAppSettings, isFalse);
      expect(result.failureMessage, isNull);
      expect(requestedList, isEmpty);
    });

    test('2. Uno denegado (no permanente)', () async {
      final service = BlePermissionService(
        androidSdkVersionProvider: () => 31,
        permissionStatusChecker: (Permission p) async {
          if (p == Permission.bluetoothScan) {
            return PermissionStatus.denied;
          }
          return PermissionStatus.granted;
        },
        permissionRequester: (List<Permission> list) async {
          return <Permission, PermissionStatus>{
            for (final p in list) p: PermissionStatus.denied,
          };
        },
        bluetoothAdapterStateProvider: () =>
            Stream<BluetoothAdapterState>.value(BluetoothAdapterState.on),
      );

      final result = await service.ensureReady();

      expect(result.isReady, isFalse);
      expect(result.missingPermissions, contains(Permission.bluetoothScan));
      expect(result.permanentlyDeniedPermissions, isEmpty);
      expect(result.requiresAppSettings, isFalse);
      expect(
        result.failureMessage,
        contains('Faltan permisos de Bluetooth necesarios'),
      );
    });

    test('3. Denegado de forma permanente', () async {
      final service = BlePermissionService(
        androidSdkVersionProvider: () => 33,
        permissionStatusChecker: (Permission p) async {
          if (p == Permission.bluetoothScan) {
            return PermissionStatus.permanentlyDenied;
          }
          return PermissionStatus.granted;
        },
        permissionRequester: (List<Permission> list) async {
          return <Permission, PermissionStatus>{
            for (final p in list) p: PermissionStatus.permanentlyDenied,
          };
        },
        bluetoothAdapterStateProvider: () =>
            Stream<BluetoothAdapterState>.value(BluetoothAdapterState.on),
      );

      final result = await service.ensureReady();

      expect(result.isReady, isFalse);
      expect(
        result.permanentlyDeniedPermissions,
        contains(Permission.bluetoothScan),
      );
      expect(result.requiresAppSettings, isTrue);
      expect(
        result.failureMessage,
        contains('Abre los ajustes para concederlos'),
      );
    });

    test('4. Adaptador apagado con permisos concedidos', () async {
      final service = BlePermissionService(
        androidSdkVersionProvider: () => 33,
        permissionStatusChecker: (Permission p) async =>
            PermissionStatus.granted,
        permissionRequester: (List<Permission> list) async =>
            <Permission, PermissionStatus>{},
        bluetoothAdapterStateProvider: () =>
            Stream<BluetoothAdapterState>.value(BluetoothAdapterState.off),
      );

      final result = await service.ensureReady();

      expect(result.isReady, isFalse);
      expect(result.missingPermissions, isEmpty);
      expect(result.isBluetoothTurnedOn, isFalse);
      expect(result.onlyBluetoothOff, isTrue);
      expect(result.failureMessage, contains('El Bluetooth está apagado'));
    });

    test('5. Android 11 o inferior (SDK <= 30) pide ubicación', () async {
      final requestedList = <Permission>[];
      final checkedList = <Permission>[];

      final service = BlePermissionService(
        androidSdkVersionProvider: () => 30,
        permissionStatusChecker: (Permission p) async {
          checkedList.add(p);
          return PermissionStatus.denied;
        },
        permissionRequester: (List<Permission> list) async {
          requestedList.addAll(list);
          return <Permission, PermissionStatus>{
            for (final p in list) p: PermissionStatus.granted,
          };
        },
        bluetoothAdapterStateProvider: () =>
            Stream<BluetoothAdapterState>.value(BluetoothAdapterState.on),
      );

      final result = await service.ensureReady();

      expect(checkedList, contains(Permission.locationWhenInUse));
      expect(checkedList, isNot(contains(Permission.bluetoothScan)));
      expect(requestedList, contains(Permission.locationWhenInUse));
      expect(result.isReady, isTrue);
    });

    test('6. Delegaciones de turnOnBluetooth y openAppSettings', () async {
      var turnedOn = false;
      var openedSettings = false;

      final service = BlePermissionService(
        bluetoothTurnOnAction: () async {
          turnedOn = true;
        },
        openAppSettingsAction: () async {
          openedSettings = true;
          return true;
        },
      );

      await service.turnOnBluetooth();
      final opened = await service.openAppSettings();

      expect(turnedOn, isTrue);
      expect(openedSettings, isTrue);
      expect(opened, isTrue);
    });
  });
}
