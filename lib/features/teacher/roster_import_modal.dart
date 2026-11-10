import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/course_model.dart';
import '../../data/services/roster_import_service.dart';
import '../../theme/theme.dart';

/// Modal institucional con 3 pestañas para la ingesta de estudiantes a un curso:
/// 1) Pegar lista desde el portapapeles.
/// 2) Importar archivo (.csv / .xlsx).
/// 3) Registro manual individual.
class RosterImportModal extends StatefulWidget {
  const RosterImportModal({
    super.key,
    required this.course,
    this.rosterService,
  });

  final CourseModel course;
  final RosterImportService? rosterService;

  /// Abre el modal inferior responsivo y devuelve `true` si se importó algún registro.
  static Future<bool?> show(BuildContext context, CourseModel course) {
    final radii = AppRadii.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: radii.modalShape(),
      builder: (BuildContext ctx) => RosterImportModal(course: course),
    );
  }

  @override
  State<RosterImportModal> createState() => _RosterImportModalState();
}

class _RosterImportModalState extends State<RosterImportModal> {
  late final RosterImportService _rosterService;

  bool _isLoading = false;
  bool _hasChanges = false;

  // Controladores de Pestaña 1 (Portapapeles)
  final TextEditingController _clipboardController = TextEditingController();

  // Estado de Pestaña 2 (Archivo)
  PlatformFile? _selectedFile;
  int? _selectedFileSize;

  // Controladores de Pestaña 3 (Manual)
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Texto pegado desde el portapapeles.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El portapapeles está vacío o no contiene texto.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _processClipboard() async {
    final rawText = _clipboardController.text.trim();
    if (rawText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa o pega las filas de estudiantes antes de procesar.'),
          duration: Duration(seconds: 2),
        ),
      );
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
      _showSummaryDialog(
        title: 'Importación desde Portapapeles',
        result: result,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al procesar el texto: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar archivo: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _processFile() async {
    final file = _selectedFile;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero selecciona un archivo .csv o .xlsx.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = (file.extension ?? '').toLowerCase();

      RosterImportResult result;
      if (ext == 'xlsx') {
        result = await _rosterService.importFromExcelBytes(widget.course.id, bytes);
      } else if (ext == 'csv') {
        final csvString = utf8.decode(bytes, allowMalformed: true);
        result = await _rosterService.importFromCsvString(widget.course.id, csvString);
      } else {
        throw FormatException('Formato .$ext no soportado. Debe ser .csv o .xlsx');
      }

      _hasChanges = true;
      if (!mounted) return;
      _showSummaryDialog(
        title: 'Importación desde Archivo',
        result: result,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al importar el archivo: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitManual() async {
    if (!_manualFormKey.currentState!.validate()) return;

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
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estudiante ${student.fullName} registrado en Bit #${student.bitIndex.toString().padLeft(2, '0')}.',
          ),
          backgroundColor: colors.statusNormal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar estudiante: $e'),
          backgroundColor: colors.statusPerdida,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSummaryDialog({
    required String title,
    required RosterImportResult result,
  }) {
    final colors = AppColors.of(context);
    final radii = AppRadii.of(context);
    final spacing = AppSpacing.of(context);

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: radii.dialogShape(),
          title: Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, color: colors.statusNormal),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Resumen de procesamiento:',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              SizedBox(height: spacing.sm),
              _ResultRow(
                icon: Icons.check,
                color: colors.statusNormal,
                label: 'Estudiantes insertados:',
                value: '${result.insertedCount}',
              ),
              SizedBox(height: spacing.xs),
              _ResultRow(
                icon: Icons.copy,
                color: colors.statusAlerta,
                label: 'Duplicados omitidos:',
                value: '${result.duplicatesSkipped}',
              ),
              SizedBox(height: spacing.xs),
              _ResultRow(
                icon: Icons.cancel_outlined,
                color: colors.statusPerdida,
                label: 'Filas inválidas / sin cupo:',
                value: '${result.invalidRowsSkipped}',
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              style: FilledButton.styleFrom(shape: radii.buttonShape()),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(_hasChanges);
              },
              child: const Text('Cerrar y Ver Roster'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: spacing.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: <Widget>[
              // Barra de arrastre y título
              Padding(
                padding: spacing.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.xs),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceMuted.withValues(alpha: 0.4),
                        borderRadius: radii.borderXs,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: spacing.symmetric(horizontal: spacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Cargar Estudiantes',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                          Text(
                            '${widget.course.name} (${widget.course.code} - G${widget.course.groupCode})',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(_hasChanges),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.xs),

              // Pestañas
              TabBar(
                labelColor: colors.primary,
                unselectedLabelColor: colors.onSurfaceMuted,
                indicatorColor: colors.primary,
                tabs: const <Widget>[
                  Tab(
                    icon: Icon(Icons.content_paste_outlined),
                    text: 'Pegar Lista',
                  ),
                  Tab(
                    icon: Icon(Icons.upload_file_outlined),
                    text: 'Archivo',
                  ),
                  Tab(
                    icon: Icon(Icons.person_add_alt_1_outlined),
                    text: 'Manual',
                  ),
                ],
              ),

              // Contenido de las pestañas
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const CircularProgressIndicator(),
                            SizedBox(height: spacing.md),
                            const Text('Procesando datos del curso...'),
                          ],
                        ),
                      )
                    : TabBarView(
                        children: <Widget>[
                          _buildClipboardTab(theme),
                          _buildFileTab(theme),
                          _buildManualTab(theme),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipboardTab(ThemeData theme) {
    return Builder(
      builder: (BuildContext context) {
        final colors = AppColors.of(context);
        final spacing = AppSpacing.of(context);
        final radii = AppRadii.of(context);

        return SingleChildScrollView(
          padding: spacing.insetsCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: spacing.insetsSm,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: radii.borderMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: colors.primary,
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        'Pega filas copiadas de Excel o SMA. Se admiten columnas separadas '
                        'por tabulador, punto y coma, coma o guion. La fila de títulos se '
                        'detecta automáticamente.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(shape: radii.buttonShape()),
                    onPressed: _pasteFromSystemClipboard,
                    icon: const Icon(Icons.paste, size: 18),
                    label: const Text('Pegar Portapapeles'),
                  ),
                ],
              ),
              SizedBox(height: spacing.xs),
              TextField(
                controller: _clipboardController,
                maxLines: 8,
                minLines: 5,
                decoration: InputDecoration(
                  hintText: 'Ejemplo:\n0123456789\tPEREZ JUAN\tjperez@uniguajira.edu.co\n'
                      '0987654321\tGOMEZ MARIA\tmgomez@uniguajira.edu.co',
                  border: OutlineInputBorder(
                    borderRadius: radii.borderMd,
                  ),
                  filled: true,
                ),
              ),
              SizedBox(height: spacing.md),
              FilledButton.icon(
                onPressed: _processClipboard,
                icon: const Icon(Icons.bolt),
                label: const Text('Procesar e Importar Roster'),
                style: FilledButton.styleFrom(
                  padding: spacing.insetsVMd,
                  shape: radii.buttonShape(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileTab(ThemeData theme) {
    return Builder(
      builder: (BuildContext context) {
        final colors = AppColors.of(context);
        final spacing = AppSpacing.of(context);
        final radii = AppRadii.of(context);
        final file = _selectedFile;
        final size = _selectedFileSize;

        return SingleChildScrollView(
          padding: spacing.insetsCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: spacing.insetsSm,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: radii.borderMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: colors.primary,
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        'Carga una lista en formato CSV (.csv) o un libro de Excel (.xlsx). '
                        'Los códigos de estudiante conservan los ceros iniciales intactos.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.lg),

              // Selector visual de archivo
              InkWell(
                onTap: _pickFile,
                borderRadius: radii.borderLg,
                child: Container(
                  padding: spacing.symmetric(vertical: spacing.lg, horizontal: spacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: file != null
                          ? colors.primary
                          : colors.outlineVariant,
                      width: 2,
                    ),
                    borderRadius: radii.borderLg,
                    color: file != null
                        ? colors.primaryContainer.withValues(alpha: 0.2)
                        : colors.surface,
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        file != null
                            ? Icons.insert_drive_file
                            : Icons.cloud_upload_outlined,
                        size: 48,
                        color: file != null
                            ? colors.primary
                            : colors.onSurfaceMuted,
                      ),
                      SizedBox(height: spacing.sm),
                      Text(
                        file != null ? file.name : 'Toca para seleccionar archivo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        file != null && size != null
                            ? '${(size / 1024).toStringAsFixed(1)} KB'
                            : 'Formatos admitidos: .csv, .xlsx',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.lg),

              FilledButton.icon(
                onPressed: file != null ? _processFile : null,
                icon: const Icon(Icons.file_download_done),
                label: const Text('Importar Archivo'),
                style: FilledButton.styleFrom(
                  padding: spacing.insetsVMd,
                  shape: radii.buttonShape(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManualTab(ThemeData theme) {
    return Builder(
      builder: (BuildContext context) {
        final colors = AppColors.of(context);
        final spacing = AppSpacing.of(context);
        final radii = AppRadii.of(context);

        return SingleChildScrollView(
          padding: spacing.insetsCard,
          child: Form(
            key: _manualFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Registra individualmente a un estudiante. El sistema le asignará '
                  'automáticamente el siguiente bit libre (0..63) y su secreto HMAC.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.md),
                TextFormField(
                  controller: _manualCodeController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Código Estudiantil *',
                    hintText: '0123456789 (preserva ceros)',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(borderRadius: radii.borderMd),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El código es obligatorio';
                    }
                    return null;
                  },
                ),
                SizedBox(height: spacing.md),
                TextFormField(
                  controller: _manualNameController,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Nombre Completo *',
                    hintText: 'Ej. ALVARO JOSE LOPEZ GUERRA',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: radii.borderMd),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                SizedBox(height: spacing.md),
                TextFormField(
                  controller: _manualEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo Institucional (Opcional)',
                    hintText: 'usuario@uniguajira.edu.co',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: radii.borderMd),
                  ),
                ),
                SizedBox(height: spacing.lg),
                FilledButton.icon(
                  onPressed: _submitManual,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Registrar Estudiante'),
                  style: FilledButton.styleFrom(
                    padding: spacing.insetsVMd,
                    shape: radii.buttonShape(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        SizedBox(width: spacing.xs),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
