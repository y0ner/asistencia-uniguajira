import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';
import '../../ui/ui.dart';

/// Pantalla para unirse a una clase mediante código QR o pegando el código.
///
/// Dispone de:
/// 1. Escaneo en vivo con cámara usando [MobileScanner] y marco guía.
/// 2. Ingreso manual mediante hoja inferior para pegar el código.
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

class _StudentQrEnrollmentScreenState extends State<StudentQrEnrollmentScreen> {
  late final MobileScannerController _scannerController;
  late final StudentEnrollmentService _enrollmentService;
  late final TextEditingController _manualCodeController;

  bool _isProcessing = false;
  bool _isTorchOn = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase.instance;
    _enrollmentService =
        widget.enrollmentService ?? StudentEnrollmentService(db);
    _manualCodeController = TextEditingController();

    _scannerController = MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
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
    } catch (e, st) {
      debugPrint('No se pudo cambiar la linterna: $e\n$st');
      if (mounted) {
        showUiSnack(context, 'No se pudo activar la linterna.');
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _scannerController.switchCamera();
    } catch (e, st) {
      debugPrint('No se pudo cambiar de cámara: $e\n$st');
      if (mounted) {
        showUiSnack(context, 'No se pudo cambiar de cámara.');
      }
    }
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

  Future<void> _processEnrollmentPayload(String rawPayload) async {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _errorMessage =
            'Ese código no es de una clase. Pídele a tu profesor que te lo muestre de nuevo.';
      });
      return;
    }

    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final enrollment = await _enrollmentService.enrollFromQrPayload(trimmed);
      if (!mounted) return;

      _manualCodeController.clear();
      await _showEnrollmentSuccessDialog(enrollment);
      if (!mounted) return;

      Navigator.of(context).pop(enrollment);
    } catch (e, st) {
      debugPrint('Error al procesar código de clase: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage =
            'Ese código no es de una clase. Pídele a tu profesor que te lo muestre de nuevo.';
      });
    }
  }

  Future<void> _showEnrollmentSuccessDialog(
    StudentEnrollmentModel enrollment,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
          child: UiHeroCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: UiSpace.sm),
                Text(
                  '¡Listo!',
                  style: UiText.display,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: UiSpace.sm),
                Text(
                  'Ya estás en ${enrollment.courseName}',
                  style: UiText.bodyStrong,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: UiSpace.xxl),
                UiButton(
                  label: 'Ir a mis clases',
                  variant: UiButtonVariant.onHero,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showManualPasteSheet() async {
    await showUiSheet<void>(
      context,
      builder: (sheetContext) {
        final c = UiColors.of(sheetContext);
        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            final hasText = _manualCodeController.text.trim().isNotEmpty;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: UiSpace.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Código de la clase',
                      style: UiText.h2.copyWith(color: c.ink),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        final text = data?.text;
                        if (!sheetContext.mounted) return;
                        if (text != null && text.trim().isNotEmpty) {
                          _manualCodeController.text = text.trim();
                          setSheetState(() {});
                          showUiSnack(
                            sheetContext,
                            'Código pegado desde el portapapeles.',
                          );
                        } else {
                          showUiSnack(
                            sheetContext,
                            'El portapapeles está vacío.',
                          );
                        }
                      },
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('Pegar'),
                    ),
                  ],
                ),
                const SizedBox(height: UiSpace.sm),
                TextField(
                  controller: _manualCodeController,
                  maxLines: 4,
                  minLines: 3,
                  autofocus: true,
                  onChanged: (_) => setSheetState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Código de la clase',
                    hintText: 'Pega el código que te compartió tu profesor',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: UiSpace.lg),
                UiButton(
                  label: 'Unirme',
                  variant: UiButtonVariant.primary,
                  onPressed: hasText
                      ? () {
                          Navigator.of(sheetContext).pop();
                          _processEnrollmentPayload(
                            _manualCodeController.text,
                          );
                        }
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCameraErrorView(
    BuildContext context,
    MobileScannerException error,
  ) {
    debugPrint('Error de cámara: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpace.md),
        child: UiBanner(
          tone: UiBannerTone.warning,
          title: 'Cámara no disponible',
          message:
              'No se pudo acceder a la cámara. Revisa los permisos o pega el código directamente.',
          actionLabel: 'Pegar el código',
          onAction: _showManualPasteSheet,
        ),
      ),
    );
  }

  Widget _buildCameraBox(BuildContext context) {
    final c = UiColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(UiRadius.xxl),
            border: Border.all(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _handleBarcodeDetected,
                errorBuilder: (context, error) {
                  return _buildCameraErrorView(context, error);
                },
              ),
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(UiRadius.lg),
                    border: Border.all(
                      color: c.primary,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 44,
                      color: c.primary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              if (_isProcessing)
                Container(
                  color: c.veil,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(color: c.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);

    return UiPage(
      header: UiTopBar(
        title: 'Unirme a una clase',
        onBack: () => Navigator.of(context).pop(),
      ),
      bottom: UiButton(
        label: 'Pegar el código',
        variant: UiButtonVariant.outline,
        onPressed: _showManualPasteSheet,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              UiBanner(
                tone: UiBannerTone.error,
                message: _errorMessage!,
              ),
              const SizedBox(height: UiSpace.md),
            ],
            _buildCameraBox(context),
            const SizedBox(height: UiSpace.md),
            Text(
              'Apunta al código QR que te muestra tu profesor.',
              textAlign: TextAlign.center,
              style: UiText.body.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                UiRoundIconButton(
                  icon: _isTorchOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  tooltip:
                      _isTorchOn ? 'Apagar linterna' : 'Encender linterna',
                  onPressed: _toggleTorch,
                ),
                const SizedBox(width: UiSpace.md),
                UiRoundIconButton(
                  icon: Icons.cameraswitch_rounded,
                  tooltip: 'Cambiar cámara',
                  onPressed: _switchCamera,
                ),
              ],
            ),
            const SizedBox(height: UiSpace.lg),
          ],
        ),
      ),
    );
  }
}
