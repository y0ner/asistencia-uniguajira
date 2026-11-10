import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Retorna la versión del SDK de Android (`sdkInt`) usando [DeviceInfoPlugin].
///
/// Devuelve `(await DeviceInfoPlugin().androidInfo).version.sdkInt` en Android
/// y `null` en cualquier otra plataforma.
Future<int?> androidSdkInt({DeviceInfoPlugin? deviceInfoPlugin}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  final plugin = deviceInfoPlugin ?? DeviceInfoPlugin();
  final androidInfo = await plugin.androidInfo;
  return androidInfo.version.sdkInt;
}
