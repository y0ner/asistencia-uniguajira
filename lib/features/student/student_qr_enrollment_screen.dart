import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';
import '../../theme/theme.dart';

/// Pantalla de enrolamiento del estudiante mediante código QR del docente.
///
/// Dispone de dos modalidades:
/// 1. Escaneo en vivo con cámara usando [MobileScanner] y recuadro guía.
/// 2. Ingreso manual del JSON del QR como respaldo para cámaras dañadas o pruebas.
class StudentQrEnrollmentScreen extends StatefulWidget {
  const StudentQrEnrollmentScreen({
    super.key,
    this.enrollmentService,
    this.database,
  });

  final StudentEnrollmentService? enrollmentService;
  final AppDatabase? database;

  @override
  State<StudentQrEnrollmentScreen> createState() =>
      _StudentQrEnrollmentScreenState();
}

class _StudentQrEnrollmentScreenState extends State<StudentQrEnrollmentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final MobileScannerController _scannerController;
  late final StudentEnrollmentService _enrollmentService;
  late final TextEditingController _manualJsonController;

  bool _isProcessing = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase.instance;
    _enrollmentService =
        widget.enrollmentService ?? StudentEnrollmentService(db);
    _manualJsonController = TextEditingController();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    _scannerController = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      try {
        _scannerController.stop();
      } catch (_) {}
    } else if (_tabController.index == 0) {
      try {
        _scannerController.start();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _manualJsonController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
      if (mounted) {
        setState(() {
          _isTorchOn = !_isTorchOn;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    try {
      await _scannerController.switchCamera();
    } catch (_) {}
  }

  Future<void> _handleBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        await _processEnrollmentPayload(raw);
        break;
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      _manualJsonController.text = text.trim();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contenido pegado desde el portapapeles.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El portapapeles está vacío o no contiene texto.'),
          ),
        );
      }
    }
  }

  Future<void> _processEnrollmentPayload(String rawPayload) async {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El contenido de enrolamiento no puede estar vacío.'),
        ),
      );
      return;
    }

    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final enrollment = await _enrollmentService.enrollFromQrPayload(trimmed);
      if (!mounted) return;

      await _showEnrollmentSuccessDialog(enrollment);
      if (!mounted) return;

      Navigator.of(context).pop(enrollment);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: colors.statusPerdida,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado al procesar enrolamiento: $e'),
          backgroundColor: colors.statusPerdida,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showEnrollmentSuccessDialog(
    StudentEnrollmentModel enrollment,
  ) async {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: radii.dialogShape(),
          icon: Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: colors.statusNormal,
          ),
          title: const Text(
            '¡Enrolamiento Exitoso!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Te has vinculado correctamente al curso:',
                    style: theme.textTheme.bodyMedium,
                  ),
                  SizedBox(height: spacing.xs),
                  Container(
                    width: double.infinity,
                    padding: spacing.insetsMd,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: radii.borderMd,
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          enrollment.courseName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        SizedBox(height: spacing.xxs),
                        Text(
                          'Código Asignatura: ${enrollment.courseCode}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Divider(height: spacing.md),
                        Text(
                          'Estudiante: ${enrollment.fullName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Código Estudiantil: ${enrollment.studentCode}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  Container(
                    width: double.infinity,
                    padding: spacing.symmetric(
                      horizontal: spacing.sm,
                      vertical: spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: radii.borderSm,
                      border: Border.all(
                        color: colors.secondary.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.tag,
                          color: colors.secondary,
                          size: 22,
                        ),
                        SizedBox(width: spacing.xs),
                        Expanded(
                          child: Text(
                            'Bit Asignado en Aula: #${enrollment.bitIndex.toString().padLeft(2, '0')} (0..63)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    'Tu semilla criptográfica individual y el secreto compartido '
                    'han sido guardados localmente en tu teléfono de forma Offline.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              style: FilledButton.styleFrom(shape: radii.buttonShape()),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continuar a Mis Cursos'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrolar Curso'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.onPrimary,
          unselectedLabelColor: colors.onPrimary.withValues(
            alpha: 0.7,
          ),
          indicatorColor: colors.secondary,
          indicatorWeight: 3,
          tabs: const <Tab>[
            Tab(
              icon: Icon(Icons.qr_code_scanner),
              text: 'Cámara en Vivo',
            ),
            Tab(
              icon: Icon(Icons.paste_rounded),
              text: 'Pegar JSON Manual',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          _buildCameraScannerTab(context),
          _buildManualPasteTab(context),
        ],
      ),
    );
  }

  Widget _buildCameraScannerTab(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Stack(
      children: <Widget>[
        // Visor de cámara QR
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleBarcodeDetected,
          errorBuilder: (context, error) {
            return _buildCameraErrorView(context, error);
          },
          overlayBuilder: (context, constraints) {
            return _buildScannerGuideOverlay(context, constraints);
          },
        ),

        // Barra flotante de controles superiores
        Positioned(
          top: spacing.md,
          right: spacing.md,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FloatingActionButton.small(
                heroTag: 'fab_torch',
                backgroundColor: colors.surface.withValues(alpha: 0.75),
                foregroundColor: _isTorchOn ? colors.secondary : colors.onSurface,
                onPressed: _toggleTorch,
                tooltip: _isTorchOn ? 'Apagar linterna' : 'Encender linterna',
                child: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
              ),
              SizedBox(width: spacing.xs),
              FloatingActionButton.small(
                heroTag: 'fab_switch_camera',
                backgroundColor: colors.surface.withValues(alpha: 0.75),
                foregroundColor: colors.onSurface,
                onPressed: _switchCamera,
                tooltip: 'Cambiar cámara',
                child: const Icon(Icons.cameraswitch_outlined),
              ),
            ],
          ),
        ),

        // Indicador de procesamiento en curso
        if (_isProcessing)
          Container(
            color: colors.surface.withValues(alpha: 0.65),
            child: Center(
              child: Card(
                elevation: 4,
                shape: radii.cardShape(),
                child: Padding(
                  padding: spacing.symmetric(
                    horizontal: spacing.lg,
                    vertical: spacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      SizedBox(height: spacing.md),
                      const Text(
                        'Procesando credencial...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScannerGuideOverlay(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final double boxSize = (constraints.maxWidth * 0.72).clamp(220.0, 300.0);

    return Stack(
      children: <Widget>[
        // Recuadro guía central
        Center(
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              borderRadius: radii.borderXl,
              border: Border.all(
                color: colors.primary,
                width: 3,
              ),
            ),
            child: Stack(
              children: <Widget>[
                // Ícono sutil central de guía
                Center(
                  child: Icon(
                    Icons.qr_code_2,
                    size: 80,
                    color: colors.primary.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Instrucción visual inferior
        Positioned(
          left: spacing.lg,
          right: spacing.lg,
          bottom: spacing.xl,
          child: Center(
            child: Container(
              padding: spacing.symmetric(
                horizontal: spacing.md,
                vertical: spacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.85),
                borderRadius: radii.borderMd,
              ),
              child: Text(
                'Apunta la cámara al código QR que tu docente\nmuestra en su pantalla.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraErrorView(
    BuildContext context,
    MobileScannerException error,
  ) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Center(
      child: Padding(
        padding: spacing.insetsLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.no_photography_outlined,
              size: 64,
              color: colors.statusAlerta,
            ),
            SizedBox(height: spacing.md),
            Text(
              'No se pudo inicializar la cámara',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Verifica que la aplicación tenga permisos de cámara o utiliza '
              'la pestaña de ingreso manual.',
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurfaceMuted,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: spacing.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(shape: radii.buttonShape()),
              onPressed: () {
                _tabController.animateTo(1);
              },
              icon: const Icon(Icons.paste_rounded),
              label: const Text('Usar Pegado Manual de JSON'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualPasteTab(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return SingleChildScrollView(
      padding: spacing.insetsLg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Tarjeta informativa de respaldo
            Container(
              padding: spacing.insetsMd,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: radii.borderMd,
                border: Border.all(
                  color: colors.outlineVariant,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    color: colors.primary,
                    size: 22,
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      'Modo de Respaldo: Si la cámara de tu teléfono presenta fallas '
                      'físicas o requieres realizar pruebas, pega directamente '
                      'aquí la cadena JSON que compone el QR del docente.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),

            // Acciones rápidas de portapapeles
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(shape: radii.buttonShape()),
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.paste_rounded, size: 18),
                    label: const Text('Pegar Portapapeles'),
                  ),
                ),
                SizedBox(width: spacing.xs),
                TextButton.icon(
                  onPressed: () => _manualJsonController.clear(),
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),

            // Campo de texto multilínea para el JSON
            TextField(
              controller: _manualJsonController,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: InputDecoration(
                labelText: 'Contenido JSON del QR *',
                hintText:
                    '{"courseId": "...", "studentCode": "...", "bitmapIndex": 0, ...}',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: radii.borderMd),
              ),
            ),
            SizedBox(height: spacing.lg),

            // Botón de procesamiento
            FilledButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _processEnrollmentPayload(_manualJsonController.text),
              icon: _isProcessing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(
                _isProcessing
                    ? 'Procesando...'
                    : 'Procesar y Enrolar Credencial',
              ),
              style: FilledButton.styleFrom(
                padding: spacing.insetsVMd,
                shape: radii.buttonShape(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
