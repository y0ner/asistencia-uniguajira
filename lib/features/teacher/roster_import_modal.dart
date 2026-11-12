import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/course_model.dart';
import '../../data/services/roster_import_service.dart';
import '../../ui/ui.dart';

/// Modal para agregar estudiantes a una clase mediante tres vías:
/// 1) Pegar lista desde el portapapeles.
/// 2) Desde archivo (.csv / .xlsx).
/// 3) Uno por uno (individual).
class RosterImportModal extends StatefulWidget {
  const RosterImportModal({
    super.key,
    required this.course,
    this.rosterService,
  });

  final CourseModel course;
  final RosterImportService? rosterService;

  /// Abre la hoja modal y devuelve `true` si se agregó algún estudiante.
  static Future<bool?> show(BuildContext context, CourseModel course) {
    return showUiSheet<bool>(
      context,
      builder: (_) => RosterImportModal(course: course),
    );
  }

  @override
  State<RosterImportModal> createState() => _RosterImportModalState();
}

enum _ImportOption { clipboard, file, manual }

class _RosterImportModalState extends State<RosterImportModal> {
  late final RosterImportService _rosterService;

  _ImportOption _selectedOption = _ImportOption.clipboard;
  bool _isLoading = false;
  bool _hasChanges = false;

  // Pegar lista
  final TextEditingController _clipboardController = TextEditingController();

  // Desde archivo
  PlatformFile? _selectedFile;
  int? _selectedFileSize;

  // Uno por uno
  final GlobalKey<FormState> _manualFormKey = GlobalKey<FormState>();
  final TextEditingController _manualCodeController = TextEditingController();
  final TextEditingController _manualNameController = TextEditingController();
  final TextEditingController _manualEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rosterService = widget.rosterService ?? RosterImportService();
  }

  @override
  void dispose() {
    _clipboardController.dispose();
    _manualCodeController.dispose();
    _manualNameController.dispose();
    _manualEmailController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromSystemClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.trim().isNotEmpty) {
      setState(() {
        _clipboardController.text = text;
      });
      if (mounted) {
        showUiSnack(context, 'Texto pegado del portapapeles.');
      }
    } else {
      if (mounted) {
        showUiSnack(context, 'El portapapeles está vacío.');
      }
    }
  }

  Future<void> _processClipboard() async {
    final rawText = _clipboardController.text.trim();
    if (rawText.isEmpty) {
      showUiSnack(context, 'Pega o escribe los datos antes de continuar.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _rosterService.importFromClipboardText(
        widget.course.id,
        rawText,
      );
      _hasChanges = true;
      if (!mounted) return;
      _showSummaryDialog(result);
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo procesar la lista.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['csv', 'xlsx'],
      );
      if (file != null) {
        final size = await file.length();
        if (mounted) {
          setState(() {
            _selectedFile = file;
            _selectedFileSize = size;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo seleccionar el archivo.');
    }
  }

  Future<void> _processFile() async {
    final file = _selectedFile;
    if (file == null) {
      showUiSnack(context, 'Selecciona un archivo .xlsx o .csv.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = (file.extension ?? '').toLowerCase();

      RosterImportResult result;
      if (ext == 'xlsx') {
        result = await _rosterService.importFromExcelBytes(
          widget.course.id,
          bytes,
        );
      } else if (ext == 'csv') {
        final csvString = utf8.decode(bytes, allowMalformed: true);
        result = await _rosterService.importFromCsvString(
          widget.course.id,
          csvString,
        );
      } else {
        throw FormatException('Formato no admitido.');
      }

      _hasChanges = true;
      if (!mounted) return;
      _showSummaryDialog(result);
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo importar el archivo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitManual() async {
    if (!_manualFormKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      final code = _manualCodeController.text.trim();
      final name = _manualNameController.text.trim();
      final email = _manualEmailController.text.trim().isEmpty
          ? null
          : _manualEmailController.text.trim();

      final student = await _rosterService.addManualStudent(
        courseId: widget.course.id,
        studentCode: code,
        fullName: name,
        email: email,
      );

      _hasChanges = true;
      _manualCodeController.clear();
      _manualNameController.clear();
      _manualEmailController.clear();

      if (!mounted) return;
      showUiSnack(context, 'Se agregó a ${student.fullName}.');
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo agregar al estudiante.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSummaryDialog(RosterImportResult result) {
    final c = UiColors.of(context);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Estudiantes agregados'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se agregaron ${result.insertedCount} estudiantes.',
                style: UiText.bodyStrong.copyWith(color: c.ink),
              ),
              if (result.duplicatesSkipped > 0) ...[
                const SizedBox(height: UiSpace.sm),
                Text(
                  'Se omitieron ${result.duplicatesSkipped} porque ya estaban en la clase.',
                  style: UiText.body.copyWith(color: c.muted),
                ),
              ],
              if (result.invalidRowsSkipped > 0) ...[
                const SizedBox(height: UiSpace.sm),
                Text(
                  'Se omitieron ${result.invalidRowsSkipped} por datos incompletos o falta de cupo.',
                  style: UiText.body.copyWith(color: c.absentText),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(_hasChanges);
              },
              child: const Text('Ver estudiantes'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildClipboardContent(UiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            UiButton(
              label: 'Pegar del portapapeles',
              icon: Icons.content_paste_rounded,
              variant: UiButtonVariant.tonal,
              compact: true,
              expand: false,
              onPressed: _pasteFromSystemClipboard,
            ),
          ],
        ),
        const SizedBox(height: UiSpace.sm),
        TextField(
          controller: _clipboardController,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: '0123456789  JUAN PEREZ  jperez@uniguajira.edu.co\n'
                '0987654321  MARIA GOMEZ  mgomez@uniguajira.edu.co',
          ),
        ),
        const SizedBox(height: UiSpace.xl),
        UiButton(
          label: 'Agregar estudiantes',
          icon: Icons.add_rounded,
          loading: _isLoading,
          onPressed: _processClipboard,
        ),
      ],
    );
  }

  Widget _buildFileContent(UiColors c) {
    final file = _selectedFile;
    final size = _selectedFileSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiCard(
          onTap: _pickFile,
          child: Column(
            children: [
              Icon(
                file != null
                    ? Icons.description_rounded
                    : Icons.cloud_upload_outlined,
                size: 40,
                color: c.primary,
              ),
              const SizedBox(height: UiSpace.sm),
              Text(
                file != null
                    ? file.name
                    : 'Toca para seleccionar archivo',
                style: UiText.bodyStrong.copyWith(color: c.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: UiSpace.xs),
              Text(
                file != null && size != null
                    ? '${(size / 1024).toStringAsFixed(1)} KB'
                    : 'Formatos admitidos: .xlsx, .csv',
                style: UiText.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: UiSpace.xl),
        UiButton(
          label: 'Agregar desde archivo',
          icon: Icons.add_rounded,
          loading: _isLoading,
          onPressed: file != null ? _processFile : null,
        ),
      ],
    );
  }

  Widget _buildManualContent(UiColors c) {
    return Form(
      key: _manualFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _manualCodeController,
            decoration: const InputDecoration(
              labelText: 'Código del estudiante',
              hintText: '0123456789',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Escribe el código';
              }
              return null;
            },
          ),
          const SizedBox(height: UiSpace.md),
          TextFormField(
            controller: _manualNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              hintText: 'Juan Pérez',
            ),
            textCapitalization: TextCapitalization.words,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Escribe el nombre';
              }
              return null;
            },
          ),
          const SizedBox(height: UiSpace.md),
          TextFormField(
            controller: _manualEmailController,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico (opcional)',
              hintText: 'usuario@uniguajira.edu.co',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: UiSpace.xl),
          UiButton(
            label: 'Agregar estudiante',
            icon: Icons.person_add_rounded,
            loading: _isLoading,
            onPressed: _submitManual,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);

    final String explanation = switch (_selectedOption) {
      _ImportOption.clipboard =>
        'Copia la lista desde Excel o el SMA y pégala aquí.',
      _ImportOption.file =>
        'Copia o selecciona una lista en formato Excel (.xlsx) o CSV.',
      _ImportOption.manual =>
        'Escribe los datos del estudiante para agregarlo a la clase.',
    };

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: UiSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Agregar estudiantes',
                  style: UiText.h2.copyWith(color: c.ink),
                ),
              ),
              UiRoundIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(_hasChanges),
              ),
            ],
          ),
          const SizedBox(height: UiSpace.md),
          UiFilterPills<_ImportOption>(
            options: const [
              UiFilterOption(
                value: _ImportOption.clipboard,
                label: 'Pegar lista',
              ),
              UiFilterOption(
                value: _ImportOption.file,
                label: 'Desde archivo',
              ),
              UiFilterOption(
                value: _ImportOption.manual,
                label: 'Uno por uno',
              ),
            ],
            selected: _selectedOption,
            onSelected: (option) {
              setState(() => _selectedOption = option);
            },
          ),
          const SizedBox(height: UiSpace.md),
          Text(
            explanation,
            style: UiText.body.copyWith(color: c.muted),
          ),
          const SizedBox(height: UiSpace.lg),
          switch (_selectedOption) {
            _ImportOption.clipboard => _buildClipboardContent(c),
            _ImportOption.file => _buildFileContent(c),
            _ImportOption.manual => _buildManualContent(c),
          },
        ],
      ),
    );
  }
}
