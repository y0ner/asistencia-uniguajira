import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/course_model.dart';
import '../../data/services/roster_import_service.dart';

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
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estudiante ${student.fullName} registrado en Bit #${student.bitIndex.toString().padLeft(2, '0')}.',
          ),
          backgroundColor: const Color(0xFF00843D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar estudiante: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
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
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline, color: Color(0xFF00843D)),
              const SizedBox(width: 8),
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
              const SizedBox(height: 12),
              _ResultRow(
                icon: Icons.check,
                color: const Color(0xFF00843D),
                label: 'Estudiantes insertados:',
                value: '${result.insertedCount}',
              ),
              const SizedBox(height: 8),
              _ResultRow(
                icon: Icons.copy,
                color: Colors.orange.shade800,
                label: 'Duplicados omitidos:',
                value: '${result.duplicatesSkipped}',
              ),
              const SizedBox(height: 8),
              _ResultRow(
                icon: Icons.cancel_outlined,
                color: Theme.of(ctx).colorScheme.error,
                label: 'Filas inválidas / sin cupo:',
                value: '${result.invalidRowsSkipped}',
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
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
    final viewInsets = MediaQuery.of(context).viewInsets;

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: <Widget>[
              // Barra de arrastre y título
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            '${widget.course.name} (${widget.course.code} - G${widget.course.groupCode})',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
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
              const SizedBox(height: 8),

              // Pestañas
              TabBar(
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                indicatorColor: theme.colorScheme.primary,
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
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Procesando datos del curso...'),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _pasteFromSystemClipboard,
                icon: const Icon(Icons.paste, size: 18),
                label: const Text('Pegar Portapapeles'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _clipboardController,
            maxLines: 8,
            minLines: 5,
            decoration: InputDecoration(
              hintText: 'Ejemplo:\n0123456789\tPEREZ JUAN\tjperez@uniguajira.edu.co\n'
                  '0987654321\tGOMEZ MARIA\tmgomez@uniguajira.edu.co',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _processClipboard,
            icon: const Icon(Icons.bolt),
            label: const Text('Procesar e Importar Roster'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileTab(ThemeData theme) {
    final file = _selectedFile;
    final size = _selectedFileSize;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
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
          const SizedBox(height: 20),

          // Selector visual de archivo
          InkWell(
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: file != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
                color: file != null
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.2)
                    : theme.colorScheme.surface,
              ),
              child: Column(
                children: <Widget>[
                  Icon(
                    file != null
                        ? Icons.insert_drive_file
                        : Icons.cloud_upload_outlined,
                    size: 48,
                    color: file != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    file != null ? file.name : 'Toca para seleccionar archivo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file != null && size != null
                        ? '${(size / 1024).toStringAsFixed(1)} KB'
                        : 'Formatos admitidos: .csv, .xlsx',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: file != null ? _processFile : null,
            icon: const Icon(Icons.file_download_done),
            label: const Text('Importar Archivo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Registra individualmente a un estudiante. El sistema le asignará '
              'automáticamente el siguiente bit libre (0..63) y su secreto HMAC.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _manualCodeController,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Código Estudiantil *',
                hintText: '0123456789 (preserva ceros)',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El código es obligatorio';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _manualNameController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre Completo *',
                hintText: 'Ej. ALVARO JOSE LOPEZ GUERRA',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es obligatorio';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _manualEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo Institucional (Opcional)',
                hintText: 'usuario@uniguajira.edu.co',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitManual,
              icon: const Icon(Icons.person_add),
              label: const Text('Registrar Estudiante'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
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
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
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
