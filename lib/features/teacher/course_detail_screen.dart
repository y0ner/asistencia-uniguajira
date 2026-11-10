import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/roster_import_service.dart';
import '../../theme/theme.dart';
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
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos del curso: $e'),
            backgroundColor: colors.statusPerdida,
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
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

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
          shape: radii.dialogShape(),
          title: Row(
            children: <Widget>[
              Icon(Icons.qr_code_2, color: colors.primary, size: 28),
              SizedBox(width: spacing.xs),
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
                  padding: spacing.symmetric(
                    horizontal: spacing.sm,
                    vertical: spacing.xxs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: radii.borderPill,
                  ),
                  child: Text(
                    'Bit #$bitPadded en el Bitmap',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onPrimaryContainer,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(height: spacing.sm),
                Text(
                  student.fullName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  'Código: ${student.studentCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                    letterSpacing: 1.1,
                  ),
                ),
                if (student.email != null) ...<Widget>[
                  SizedBox(height: spacing.xxs / 2),
                  Text(
                    student.email!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
                SizedBox(height: spacing.md),
                Container(
                  padding: spacing.insetsSm,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: radii.borderLg,
                    border: Border.all(
                      color: colors.outlineVariant,
                    ),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 200.0,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: colors.onSurface,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                SizedBox(height: spacing.sm),
                Text(
                  'Pide al estudiante escanear este código desde el "Modo Estudiante" '
                  'para guardar su secreto HMAC único en su teléfono.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
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
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al consultar el acta: $e'),
          backgroundColor: colors.statusPerdida,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final count = _students.length;
    final maxBits = AppConstants.bitmapBitCount;
    final fraction = count / maxBits;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.course.name),
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
            indicatorColor: colors.primary,
            labelColor: colors.primary,
            unselectedLabelColor: colors.onSurfaceMuted,
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
                  _buildRosterTab(count, maxBits, fraction),

                  // Pestaña 2: Historial de Sesiones SQLite
                  _buildSessionsHistoryTab(),
                ],
              ),
        bottomNavigationBar: _buildBottomBleBar(),
      ),
    );
  }

  Widget _buildRosterTab(
    int count,
    int maxBits,
    double fraction,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Column(
      children: <Widget>[
        // Tarjeta de cabecera: Datos del curso y capacidad de Bitmap
        _buildCourseHeaderCard(count, maxBits, fraction),

        // Botonera de acciones: Cargar Estudiantes y Reportes/Excel (.xlsx)
        Padding(
          padding: spacing.only(
            left: spacing.md,
            right: spacing.md,
            bottom: spacing.xs,
          ),
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
                    padding: spacing.symmetric(vertical: spacing.sm),
                    shape: radii.buttonShape(),
                  ),
                ),
              ),
              SizedBox(width: spacing.xs),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _openReportsScreen,
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('Reportes'),
                  style: OutlinedButton.styleFrom(
                    padding: spacing.symmetric(vertical: spacing.sm),
                    shape: radii.buttonShape(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Encabezado de la lista
        Padding(
          padding: spacing.symmetric(
            horizontal: spacing.md,
            vertical: spacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Text(
                'Roster de Estudiantes ($count)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                'Ordenado por Bit Index',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),

        // Listado de estudiantes
        Expanded(
          child: _students.isEmpty
              ? _buildEmptyRosterView()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.separated(
                    padding: spacing.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.xxs,
                    ),
                    itemCount: _students.length,
                    separatorBuilder: (_, _) => SizedBox(height: spacing.xs),
                    itemBuilder: (BuildContext context, int index) {
                      final student = _students[index];
                      return _buildStudentTile(student);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSessionsHistoryTab() {
    final spacing = AppSpacing.of(context);

    if (_sessions.isEmpty) {
      return _buildEmptySessionsView();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: spacing.insetsCard,
        itemCount: _sessions.length,
        separatorBuilder: (_, _) => SizedBox(height: spacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final session = _sessions[index];
          return _buildSessionCard(session);
        },
      ),
    );
  }

  Widget _buildSessionCard(SessionModel session) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final isClosed = session.closedAt != null;
    final dateDisplay = session.startedAt.replaceAll('T', ' ').split('.').first;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: radii.cardShape(
        side: BorderSide(
          color: isClosed
              ? colors.statusNormal.withValues(alpha: 0.5)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: spacing.insetsCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xs,
                    vertical: spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: isClosed
                        ? colors.statusNormalContainer
                        : colors.bleAccentContainer,
                    borderRadius: radii.borderXs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isClosed ? Icons.verified : Icons.timelapse,
                        size: 14,
                        color: isClosed
                            ? colors.onStatusNormalContainer
                            : colors.onBleAccentContainer,
                      ),
                      SizedBox(width: spacing.xxs),
                      Text(
                        isClosed ? 'CERRADA Y FIRMADA' : 'SESIÓN ABIERTA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isClosed
                              ? colors.onStatusNormalContainer
                              : colors.onBleAccentContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xs,
                    vertical: spacing.xxs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: radii.borderXs,
                  ),
                  child: Text(
                    'PIN: ${session.roomPin}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs + 2),
            Row(
              children: <Widget>[
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: colors.onSurfaceMuted,
                ),
                SizedBox(width: spacing.xxs + 2),
                Text(
                  'Inicio: $dateDisplay',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
            if (session.closedAt != null) ...<Widget>[
              SizedBox(height: spacing.xxs),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 14,
                    color: colors.onSurfaceMuted,
                  ),
                  SizedBox(width: spacing.xxs + 2),
                  Text(
                    'Cierre: ${session.closedAt!.replaceAll('T', ' ').split('.').first}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: spacing.xs),
            Row(
              children: <Widget>[
                Text(
                  'Bitmap: ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurfaceMuted,
                  ),
                ),
                Text(
                  '0x${session.bitmapHex}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isClosed ? colors.statusNormal : colors.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (isClosed)
                  OutlinedButton.icon(
                    onPressed: () => _viewSessionActa(session),
                    icon: const Icon(Icons.verified_user_outlined, size: 16),
                    label: const Text('Ver Acta Firmada'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _onStartBleSession,
                    icon: const Icon(Icons.sensors, size: 16),
                    label: const Text('Reanudar Sesión'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySessionsView() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Center(
      child: Padding(
        padding: spacing.insetsXl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.history_toggle_off,
              size: 56,
              color: colors.onSurfaceMuted.withValues(alpha: 0.6),
            ),
            SizedBox(height: spacing.md),
            Text(
              'No hay sesiones registradas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Inicia una sesión de asistencia con el botón inferior para comenzar '
              'a tomar asistencia en el aula mediante Bluetooth Low Energy.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeaderCard(
    int count,
    int maxBits,
    double fraction,
  ) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Card(
      margin: spacing.insetsCard,
      elevation: 0,
      shape: radii.cardShape(side: BorderSide(color: colors.outlineVariant)),
      child: Padding(
        padding: spacing.insetsCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xs + 2,
                    vertical: spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: radii.borderSm,
                  ),
                  child: Text(
                    widget.course.code,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
                SizedBox(width: spacing.xs),
                Text(
                  'Grupo ${widget.course.groupCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  'Semestre ${widget.course.semester}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm + 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Capacidad del Bitmap',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  '$count ocupados / $maxBits bits disponibles',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: count == maxBits
                        ? colors.statusPerdida
                        : colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            ClipRRect(
              borderRadius: radii.borderXs,
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: colors.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(
                  count == maxBits
                      ? colors.statusPerdida
                      : colors.secondary,
                ),
              ),
            ),
            SizedBox(height: spacing.xxs + 2),
            Text(
              '${maxBits - count} cupos restantes para esta sección académica.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRosterView() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Center(
      child: Padding(
        padding: spacing.insetsXl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.group_off_outlined,
              size: 56,
              color: colors.onSurfaceMuted.withValues(alpha: 0.6),
            ),
            SizedBox(height: spacing.md),
            Text(
              'No hay estudiantes inscritos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            SizedBox(height: spacing.xs),
            Text(
              'Utiliza el botón superior para importar estudiantes desde un archivo '
              'Excel (.xlsx), CSV, texto pegado del SMA o mediante registro manual.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(StudentModel student) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: radii.cardShape(side: BorderSide(color: colors.outlineVariant)),
      child: ListTile(
        onTap: () => _showStudentQrDialog(student),
        contentPadding: spacing.symmetric(
          horizontal: spacing.sm + 2,
          vertical: spacing.xxs,
        ),
        leading: Container(
          width: 52,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: radii.borderSm,
          ),
          child: Text(
            '#$bitPadded',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.onPrimaryContainer,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
        title: Text(
          student.fullName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cód: ${student.studentCode}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: colors.primary,
              ),
            ),
            if (student.email != null)
              Text(
                student.email!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.qr_code_2),
          tooltip: 'Ver QR de enrolamiento',
          color: colors.primary,
          onPressed: () => _showStudentQrDialog(student),
        ),
      ),
    );
  }

  Widget _buildBottomBleBar() {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.only(
        left: spacing.md,
        top: spacing.sm,
        right: spacing.md,
        bottom: spacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
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
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              padding: spacing.symmetric(vertical: spacing.sm),
              shape: radii.buttonShape(),
            ),
          ),
        ),
      ),
    );
  }
}
