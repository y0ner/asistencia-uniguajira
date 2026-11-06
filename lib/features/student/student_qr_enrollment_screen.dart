import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado al procesar enrolamiento: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showEnrollmentSuccessDialog(
    StudentEnrollmentModel enrollment,
  ) async {
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.check_circle_rounded,
            size: 56,
            color: theme.colorScheme.primary,
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
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          enrollment.courseName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Código Asignatura: ${enrollment.courseCode}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Divider(height: 16),
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
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.tag,
                          color: theme.colorScheme.secondary,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bit Asignado en Aula: #${enrollment.bitIndex.toString().padLeft(2, '0')} (0..63)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tu semilla criptográfica individual y el secreto compartido '
                    'han sido guardados localmente en tu teléfono de forma Offline.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            FilledButton(
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrolar Curso'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(
            alpha: 0.7,
          ),
          indicatorColor: theme.colorScheme.onPrimary,
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
          _buildCameraScannerTab(theme),
          _buildManualPasteTab(theme),
        ],
      ),
    );
  }

  Widget _buildCameraScannerTab(ThemeData theme) {
    return Stack(
      children: <Widget>[
        // Visor de cámara QR
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleBarcodeDetected,
          errorBuilder: (context, error) {
            return _buildCameraErrorView(error, theme);
          },
          overlayBuilder: (context, constraints) {
            return _buildScannerGuideOverlay(constraints, theme);
          },
        ),

        // Barra flotante de controles superiores
        Positioned(
          top: 16,
          right: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FloatingActionButton.small(
                heroTag: 'fab_torch',
                backgroundColor: Colors.black.withValues(alpha: 0.6),
                foregroundColor: _isTorchOn ? Colors.amber : Colors.white,
                onPressed: _toggleTorch,
                tooltip: _isTorchOn ? 'Apagar linterna' : 'Encender linterna',
                child: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'fab_switch_camera',
                backgroundColor: Colors.black.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
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
            color: Colors.black.withValues(alpha: 0.6),
            child: Center(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
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
    BoxConstraints constraints,
    ThemeData theme,
  ) {
    final double boxSize = (constraints.maxWidth * 0.72).clamp(220.0, 300.0);

    return Stack(
      children: <Widget>[
        // Recuadro guía central
        Center(
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary,
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
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Instrucción visual inferior
        Positioned(
          left: 20,
          right: 20,
          bottom: 32,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Apunta la cámara al código QR que tu docente\nmuestra en su pantalla.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
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
    MobileScannerException error,
    ThemeData theme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.no_photography_outlined,
              size: 64,
              color: Colors.amber,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudo inicializar la cámara',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica que la aplicación tenga permisos de cámara o utiliza '
              'la pestaña de ingreso manual.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
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

  Widget _buildManualPasteTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Tarjeta informativa de respaldo
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modo de Respaldo: Si la cámara de tu teléfono presenta fallas '
                      'físicas o requieres realizar pruebas, pega directamente '
                      'aquí la cadena JSON que compone el QR del docente.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Acciones rápidas de portapapeles
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.paste_rounded, size: 18),
                    label: const Text('Pegar Portapapeles'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _manualJsonController.clear(),
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Campo de texto multilínea para el JSON
            TextField(
              controller: _manualJsonController,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                labelText: 'Contenido JSON del QR *',
                hintText:
                    '{"courseId": "...", "studentCode": "...", "bitmapIndex": 0, ...}',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Botón de procesamiento
            FilledButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _processEnrollmentPayload(_manualJsonController.text),
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_done_outlined),
              label: Text(
                _isProcessing
                    ? 'Procesando...'
                    : 'Procesar y Enrolar Credencial',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
