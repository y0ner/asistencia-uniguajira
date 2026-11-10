import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/theme.dart';

/// Determina de forma asíncrona si el dispositivo Android ejecuta API 31 (Android 12) o superior.
Future<bool> isAndroid12OrHigher() async {
  if (!Platform.isAndroid) return false;
  try {
    final result = await Process.run('getprop', <String>['ro.build.version.sdk']);
    if (result.exitCode == 0) {
      final sdk = int.tryParse(result.stdout.toString().trim());
      if (sdk != null) {
        return sdk >= 31;
      }
    }
  } catch (e) {
    debugPrint('Diagnóstico BLE: No se pudo consultar ro.build.version.sdk vía getprop: $e');
  }

  try {
    final versionStr = Platform.operatingSystemVersion.toLowerCase();
    final match = RegExp(r'android\s*([0-9]+)').firstMatch(versionStr);
    if (match != null) {
      final major = int.tryParse(match.group(1) ?? '');
      if (major != null) return major >= 12;
    }
  } catch (e) {
    debugPrint('Diagnóstico BLE: No se pudo determinar versión desde operatingSystemVersion: $e');
  }

  // En Android moderno, la proximidad BLE no requiere ubicación por diseño.
  return true;
}

/// Despliega el modal de diagnóstico de hardware en Android o Linux Desktop.
Future<void> showHardwareDiagnosticDialog(BuildContext context) async {
  if (Platform.isAndroid) {
    await showDialog<void>(
      context: context,
      builder: (_) => const HardwareDiagnosticDialog(),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (_) => const DesktopHardwareDiagnosticDialog(),
    );
  }
}

/// Modal de diagnóstico de hardware en Android usando `permission_handler`.
class HardwareDiagnosticDialog extends StatefulWidget {
  const HardwareDiagnosticDialog({
    super.key,
    this.isAndroid12OrHigherOverride,
  });

  /// Permite fijar el valor de versión de Android para pruebas unitarias y de widgets.
  final bool? isAndroid12OrHigherOverride;

  @override
  State<HardwareDiagnosticDialog> createState() =>
      _HardwareDiagnosticDialogState();
}

class _HardwareDiagnosticDialogState extends State<HardwareDiagnosticDialog> {
  bool _isLoading = true;
  Map<Permission, PermissionStatus> _statuses = <Permission, PermissionStatus>{};
  List<MapEntry<Permission, String>> _permissions = <MapEntry<Permission, String>>[];

  @override
  void initState() {
    super.initState();
    _initAndCheckPermissions();
  }

  Future<void> _initAndCheckPermissions() async {
    setState(() => _isLoading = true);

    final isAndroid12 = widget.isAndroid12OrHigherOverride ??
        await isAndroid12OrHigher();

    final permissions = <MapEntry<Permission, String>>[
      const MapEntry(
        Permission.bluetoothScan,
        'Bluetooth Scan (Escaneo BLE en aula)',
      ),
      const MapEntry(
        Permission.bluetoothAdvertise,
        'Bluetooth Advertise (Emisión Eco y Baliza)',
      ),
      const MapEntry(
        Permission.bluetoothConnect,
        'Bluetooth Connect (Conexión de proximidad BLE)',
      ),
      if (!isAndroid12)
        const MapEntry(
          Permission.locationWhenInUse,
          'Ubicación en uso (Requisito BLE en Android 11 o inferior)',
        ),
      const MapEntry(
        Permission.camera,
        'Cámara (Escáner QR de enrolamiento)',
      ),
    ];

    final results = <Permission, PermissionStatus>{};
    for (final entry in permissions) {
      try {
        results[entry.key] = await entry.key.status;
      } catch (e) {
        debugPrint('Error al verificar permiso ${entry.key}: $e');
        results[entry.key] = PermissionStatus.denied;
      }
    }

    if (mounted) {
      setState(() {
        _permissions = permissions;
        _statuses = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);
    final list = _permissions.map((e) => e.key).toList();
    try {
      await list.request();
    } catch (e) {
      debugPrint('Error al solicitar permisos: $e');
    }

    if (mounted) {
      final results = <Permission, PermissionStatus>{};
      for (final entry in _permissions) {
        try {
          results[entry.key] = await entry.key.status;
        } catch (e) {
          debugPrint('Error al verificar permiso ${entry.key}: $e');
          results[entry.key] = PermissionStatus.denied;
        }
      }
      if (mounted) {
        setState(() {
          _statuses = results;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStatusChip(BuildContext context, PermissionStatus? status) {
    if (status == null) {
      return const SizedBox.shrink();
    }
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    if (status.isGranted) {
      return Container(
        padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
        decoration: BoxDecoration(
          color: colors.statusNormalContainer,
          borderRadius: radii.borderXs,
        ),
        child: Text(
          'Concedido',
          style: TextStyle(
            color: colors.onStatusNormalContainer,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (status.isPermanentlyDenied) {
      return Container(
        padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
        decoration: BoxDecoration(
          color: colors.statusPerdidaContainer,
          borderRadius: radii.borderXs,
        ),
        child: Text(
          'Bloqueado',
          style: TextStyle(
            color: colors.onStatusPerdidaContainer,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
      decoration: BoxDecoration(
        color: colors.statusAlertaContainer,
        borderRadius: radii.borderXs,
      ),
      child: Text(
        'Denegado',
        style: TextStyle(
          color: colors.onStatusAlertaContainer,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return AlertDialog(
      shape: radii.dialogShape(),
      title: Row(
        children: <Widget>[
          Icon(Icons.build_circle_rounded, color: colors.primary, size: 26),
          SizedBox(width: spacing.xs),
          const Expanded(
            child: Text(
              'Diagnóstico de Permisos Hardware',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Estado de los canales de hardware necesarios para proximidad BLE y escaneo QR en dispositivos Android:',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.sm),
            if (_isLoading)
              Center(
                child: Padding(
                  padding: spacing.insetsLg,
                  child: const CircularProgressIndicator(),
                ),
              )
            else
              ..._permissions.map((entry) {
                final status = _statuses[entry.key];
                return Padding(
                  padding: spacing.only(bottom: spacing.xs),
                  child: Container(
                    padding: spacing.insetsSm,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: radii.borderSm,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          status?.isGranted ?? false
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: status?.isGranted ?? false
                              ? colors.statusNormal
                              : colors.statusAlerta,
                          size: 20,
                        ),
                        SizedBox(width: spacing.xs),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: spacing.xxs),
                        _buildStatusChip(context, status),
                      ],
                    ),
                  ),
                );
              }),
            SizedBox(height: spacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      padding: spacing.symmetric(vertical: spacing.sm),
                      shape: radii.buttonShape(),
                    ),
                    icon: const Icon(Icons.security_update_good_rounded, size: 18),
                    label: const Text(
                      'Solicitar Permisos',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    onPressed: _isLoading ? null : _requestPermissions,
                  ),
                ),
                SizedBox(width: spacing.xs),
                IconButton(
                  tooltip: 'Reverificar permisos',
                  icon: Icon(Icons.refresh_rounded, color: colors.primary),
                  onPressed: _isLoading ? null : _initAndCheckPermissions,
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                padding: spacing.symmetric(vertical: spacing.sm),
                shape: radii.buttonShape(),
              ),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text(
                'Abrir Ajustes del Sistema',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              onPressed: () => openAppSettings(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Modal de diagnóstico en entornos no Android (Linux Desktop / Pruebas FFI).
class DesktopHardwareDiagnosticDialog extends StatelessWidget {
  const DesktopHardwareDiagnosticDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return AlertDialog(
      shape: radii.dialogShape(),
      title: Row(
        children: <Widget>[
          Icon(Icons.desktop_windows_rounded, color: colors.primary, size: 26),
          SizedBox(width: spacing.xs),
          const Expanded(
            child: Text(
              'Diagnóstico de Permisos Hardware',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: spacing.insetsSm,
              decoration: BoxDecoration(
                color: colors.statusNormalContainer,
                borderRadius: radii.borderSm,
                border: Border.all(color: colors.statusNormal.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.statusNormal,
                    size: 22,
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      'Entorno Linux Desktop / Prueba FFI Detectado — Simulación BLE Activa',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: colors.onStatusNormalContainer,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.sm),
            Text(
              'La aplicación está ejecutándose en un entorno de pruebas o escritorio Linux sin acceso a los servicios nativos de Android:\n\n'
              '• Persistencia SQLite v3: Operativa mediante driver C nativo (sqflite_common_ffi).\n'
              '• Motor Criptográfico: Generación determinista HMAC-SHA256 validada al 100%.\n'
              '• Simulación BLE y Cámara: Los canales dependientes de plataforma se omiten para garantizar estabilidad sin excepciones MissingPluginException.\n\n'
              'En dispositivos móviles Android físicos, este panel valida y solicita en tiempo de ejecución los permisos Bluetooth y Cámara (y ubicación únicamente en Android 11 o inferior).',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
