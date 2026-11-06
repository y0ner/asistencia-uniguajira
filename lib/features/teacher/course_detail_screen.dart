import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/roster_import_service.dart';
import 'roster_import_modal.dart';

/// Detalle del curso seleccionado por el docente:
/// - Muestra la capacidad del Bitmap de 64 bits.
/// - Ingesta masiva o manual de estudiantes.
/// - Roster de estudiantes ordenados por Bit Index.
/// - Modal con código QR para enrolamiento individual.
/// - Botón para iniciar sesión BLE (reservado Etapa 3).
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({
    super.key,
    required this.course,
    this.database,
    this.rosterService,
  });

  final CourseModel course;
  final AppDatabase? database;
  final RosterImportService? rosterService;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final AppDatabase _database;
  late final RosterImportService _rosterService;

  bool _isLoading = true;
  List<StudentModel> _students = <StudentModel>[];

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _rosterService = widget.rosterService ?? RosterImportService();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final list = await _database.getStudentsByCourse(widget.course.id);
      if (mounted) {
        setState(() {
          _students = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar la lista de estudiantes: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openImportModal() async {
    final changed = await RosterImportModal.show(context, widget.course);
    if (changed == true) {
      await _loadStudents();
    }
  }

  void _showStudentQrDialog(StudentModel student) {
    final payload = _rosterService.generateEnrollmentQrPayload(
      course: widget.course,
      student: student,
    );

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);
        final bitPadded = student.bitIndex.toString().padLeft(2, '0');

        return AlertDialog(
          title: Row(
            children: <Widget>[
              Icon(Icons.qr_code_2, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Credencial de Enrolamiento',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Bit #$bitPadded en el Bitmap',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  student.fullName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Código: ${student.studentCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 1.1,
                  ),
                ),
                if (student.email != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    student.email!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pide al estudiante escanear este código desde el "Modo Estudiante" '
                  'para guardar su secreto HMAC único en su teléfono.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _onStartBleSession() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La emisión BLE y el radar en vivo se conectarán en la Etapa 3.',
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _students.length;
    final maxBits = AppConstants.bitmapBitCount;
    final fraction = count / maxBits;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar lista',
            onPressed: _loadStudents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                // Tarjeta de cabecera: Datos del curso y capacidad de Bitmap
                _buildCourseHeaderCard(theme, count, maxBits, fraction),

                // Botón destacado: Cargar / Agregar Estudiantes
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: count >= maxBits ? null : _openImportModal,
                      icon: const Icon(Icons.group_add_outlined),
                      label: Text(
                        count >= maxBits
                            ? 'Capacidad Completa (64/64)'
                            : 'Cargar / Agregar Estudiantes',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),

                // Encabezado de la lista
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Roster de Estudiantes ($count)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Ordenado por Bit Index',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // Listado de estudiantes
                Expanded(
                  child: _students.isEmpty
                      ? _buildEmptyRosterView(theme)
                      : RefreshIndicator(
                          onRefresh: _loadStudents,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            itemCount: _students.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (BuildContext context, int index) {
                              final student = _students[index];
                              return _buildStudentTile(theme, student);
                            },
                          ),
                        ),
                ),

                // Botón inferior persistente: Iniciar sesión BLE
                _buildBottomBleBar(theme),
              ],
            ),
    );
  }

  Widget _buildCourseHeaderCard(
    ThemeData theme,
    int count,
    int maxBits,
    double fraction,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.course.code,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Grupo ${widget.course.groupCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  'Semestre ${widget.course.semester}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Capacidad del Bitmap',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$count ocupados / $maxBits bits disponibles',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: count == maxBits
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  count == maxBits
                      ? theme.colorScheme.error
                      : (theme.colorScheme.secondary),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${maxBits - count} cupos restantes para esta sección académica.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRosterView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.group_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay estudiantes inscritos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Utiliza el botón superior para importar estudiantes desde un archivo '
              'Excel (.xlsx), CSV, texto pegado del SMA o mediante registro manual.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(ThemeData theme, StudentModel student) {
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        onTap: () => _showStudentQrDialog(student),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        leading: Container(
          width: 52,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '#$bitPadded',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
        title: Text(
          student.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cód: ${student.studentCode}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
            if (student.email != null)
              Text(
                student.email!,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.qr_code_2),
          tooltip: 'Ver QR de enrolamiento',
          color: theme.colorScheme.primary,
          onPressed: () => _showStudentQrDialog(student),
        ),
      ),
    );
  }

  Widget _buildBottomBleBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _onStartBleSession,
            icon: const Icon(Icons.sensors),
            label: const Text('Iniciar Sesión de Asistencia BLE'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0033A0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
