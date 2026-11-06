import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/roster_import_service.dart';
import 'course_reports_screen.dart';
import 'live_attendance_session_screen.dart';
import 'roster_import_modal.dart';
import 'signed_acta_dialog.dart';

/// Detalle del curso seleccionado por el docente:
/// - Muestra la capacidad del Bitmap de 64 bits.
/// - Ingesta masiva o manual de estudiantes.
/// - Roster de estudiantes ordenados por Bit Index con credenciales QR.
/// - Historial de sesiones registradas en SQLite y visualización de actas firmadas.
/// - Conexión directa a la Sesión de Asistencia BLE en Vivo.
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
  List<SessionModel> _sessions = <SessionModel>[];

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _rosterService = widget.rosterService ?? RosterImportService();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list = await _database.getStudentsByCourse(widget.course.id);
      final sessionList =
          await _database.getSessionsByCourse(widget.course.id);
      if (mounted) {
        setState(() {
          _students = list;
          _sessions = sessionList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos del curso: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openImportModal() async {
    final changed = await RosterImportModal.show(context, widget.course);
    if (changed == true) {
      await _loadData();
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

  Future<void> _onStartBleSession() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => LiveAttendanceSessionScreen(
          course: widget.course,
          database: _database,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openReportsScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CourseReportsScreen(
          course: widget.course,
          database: _database,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _viewSessionActa(SessionModel session) async {
    try {
      final actaJson = await _database.getSessionActaJson(session.id);
      if (!mounted) return;
      if (actaJson != null && actaJson.isNotEmpty) {
        await SignedActaDialog.showFromJson(
          context,
          actaJson: actaJson,
          courseSecretHex: widget.course.courseSecret,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el acta guardada para esta sesión.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al consultar el acta: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _students.length;
    final maxBits = AppConstants.bitmapBitCount;
    final fraction = count / maxBits;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.course.name),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.assessment_outlined),
              tooltip: 'Reportes y Excel (.xlsx)',
              onPressed: _openReportsScreen,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar datos',
              onPressed: _loadData,
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: <Widget>[
              Tab(
                icon: const Icon(Icons.people_outline),
                text: 'Roster ($count)',
              ),
              Tab(
                icon: const Icon(Icons.history),
                text: 'Historial de Sesiones (${_sessions.length})',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: <Widget>[
                  // Pestaña 1: Roster de Estudiantes e Ingesta
                  _buildRosterTab(theme, count, maxBits, fraction),

                  // Pestaña 2: Historial de Sesiones SQLite
                  _buildSessionsHistoryTab(theme),
                ],
              ),
        bottomNavigationBar: _buildBottomBleBar(theme),
      ),
    );
  }

  Widget _buildRosterTab(
    ThemeData theme,
    int count,
    int maxBits,
    double fraction,
  ) {
    return Column(
      children: <Widget>[
        // Tarjeta de cabecera: Datos del curso y capacidad de Bitmap
        _buildCourseHeaderCard(theme, count, maxBits, fraction),

        // Botonera de acciones: Cargar Estudiantes y Reportes/Excel (.xlsx)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: count >= maxBits ? null : _openImportModal,
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(
                    count >= maxBits
                        ? 'Capacidad (64/64)'
                        : 'Cargar Estudiantes',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.tonalIcon(
                  onPressed: _openReportsScreen,
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('Reportes'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
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
                  onRefresh: _loadData,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: _students.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final student = _students[index];
                      return _buildStudentTile(theme, student);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSessionsHistoryTab(ThemeData theme) {
    if (_sessions.isEmpty) {
      return _buildEmptySessionsView(theme);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          final session = _sessions[index];
          return _buildSessionCard(theme, session);
        },
      ),
    );
  }

  Widget _buildSessionCard(ThemeData theme, SessionModel session) {
    final isClosed = session.closedAt != null;
    final dateDisplay = session.startedAt.replaceAll('T', ' ').split('.').first;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isClosed
              ? Colors.green.shade300
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isClosed
                        ? Colors.green.shade100
                        : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isClosed ? Icons.verified : Icons.timelapse,
                        size: 14,
                        color: isClosed
                            ? Colors.green.shade900
                            : Colors.blue.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isClosed ? 'CERRADA Y FIRMADA' : 'SESIÓN ABIERTA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isClosed
                              ? Colors.green.shade900
                              : Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PIN: ${session.roomPin}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Inicio: $dateDisplay',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (session.closedAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cierre: ${session.closedAt!.replaceAll('T', ' ').split('.').first}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  'Bitmap: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '0x${session.bitmapHex}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isClosed ? Colors.green.shade800 : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (isClosed)
                  OutlinedButton.icon(
                    onPressed: () => _viewSessionActa(session),
                    icon: const Icon(Icons.verified_user_outlined, size: 16),
                    label: const Text('Ver Acta Firmada'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0033A0),
                      side: const BorderSide(color: Color(0xFF0033A0)),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _onStartBleSession,
                    icon: const Icon(Icons.sensors, size: 16),
                    label: const Text('Reanudar Sesión'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0033A0),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySessionsView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.history_toggle_off,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No hay sesiones registradas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inicia una sesión de asistencia con el botón inferior para comenzar '
              'a tomar asistencia en el aula mediante Bluetooth Low Energy.',
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
