import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/platform/android_sdk.dart';
import '../../ui/ui.dart';

/// Indica si el dispositivo Android ejecuta API 31 (Android 12) o superior.
///
/// Desde Android 12 los permisos BLE no exigen ubicación.
Future<bool> isAndroid12OrHigher() async {
  final sdk = await androidSdkInt();
  return sdk != null && sdk >= 31;
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
    this.permissionChecker,
  });

  /// Permite fijar el valor de versión de Android para pruebas unitarias y de widgets.
  final bool? isAndroid12OrHigherOverride;

  /// Función opcional para consultar el estado de los permisos (por defecto la plataforma vía permission_handler).
  final Future<PermissionStatus> Function(Permission permission)?
      permissionChecker;

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

  Future<PermissionStatus> _checkPermission(Permission permission) async {
    if (widget.permissionChecker != null) {
      return widget.permissionChecker!(permission);
    }
    return permission.status;
  }

  Future<void> _initAndCheckPermissions() async {
    setState(() => _isLoading = true);

    final isAndroid12 = widget.isAndroid12OrHigherOverride ??
        await isAndroid12OrHigher();

    final permissions = <MapEntry<Permission, String>>[
      const MapEntry(
        Permission.bluetoothScan,
        'Buscar celulares cercanos',
      ),
      const MapEntry(
        Permission.bluetoothAdvertise,
        'Avisar a celulares cercanos',
      ),
      const MapEntry(
        Permission.bluetoothConnect,
        'Conectar con celulares cercanos',
      ),
      if (!isAndroid12)
        const MapEntry(
          Permission.locationWhenInUse,
          'Ubicación (solo en Android 11 o anterior)',
        ),
      const MapEntry(
        Permission.camera,
        'Cámara (para leer el código de la clase)',
      ),
    ];

    final results = <Permission, PermissionStatus>{};
    for (final entry in permissions) {
      try {
        results[entry.key] = await _checkPermission(entry.key);
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
          results[entry.key] = await _checkPermission(entry.key);
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

  Widget _buildStatusChip(PermissionStatus? status) {
    if (status == null) return const SizedBox.shrink();
    if (status.isGranted) {
      return const UiPill(label: 'Permitido', icon: Icons.check_rounded);
    }
    if (status.isPermanentlyDenied) {
      return const UiPill(label: 'Bloqueado', icon: Icons.block_rounded, tone: UiTone.absent);
    }
    return const UiPill(label: 'Falta', icon: Icons.warning_amber_rounded, tone: UiTone.manual);
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final allGranted = !_isLoading &&
        _permissions.every((e) => _statuses[e.key]?.isGranted ?? false);
    final anyBlocked = _statuses.values.any((s) => s.isPermanentlyDenied);

    return AlertDialog(
      title: const Text('Permisos del celular'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'La app usa el Bluetooth para tomar asistencia de cerca y la cámara para unirte a una clase.',
              style: UiText.label.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.md),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(UiSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              UiListGroup(
                children: <Widget>[
                  for (final entry in _permissions)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: UiSpace.md, vertical: UiSpace.md),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(entry.value, style: UiText.bodyStrong.copyWith(color: c.ink)),
                          ),
                          const SizedBox(width: UiSpace.sm),
                          _buildStatusChip(_statuses[entry.key]),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: UiSpace.md),
            if (allGranted)
              const UiBanner(tone: UiBannerTone.info, message: 'Todo listo: la app tiene los permisos que necesita.')
            else ...<Widget>[
              UiButton(
                label: anyBlocked ? 'Abrir ajustes' : 'Dar permisos',
                compact: true,
                onPressed: _isLoading
                    ? null
                    : anyBlocked
                        ? () => openAppSettings()
                        : _requestPermissions,
              ),
              const SizedBox(height: UiSpace.sm),
              UiButton(
                label: 'Volver a revisar',
                variant: UiButtonVariant.outline,
                compact: true,
                onPressed: _isLoading ? null : _initAndCheckPermissions,
              ),
            ],
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
    final c = UiColors.of(context);
    return AlertDialog(
      title: const Text('Permisos del celular'),
      content: Text(
        'Estás usando la app en un computador. El Bluetooth y la cámara solo funcionan en un celular Android: ahí este panel revisa y pide los permisos.',
        style: UiText.body.copyWith(color: c.muted),
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
