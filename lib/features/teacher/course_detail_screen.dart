import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/course_overview_service.dart';
import '../../data/services/roster_import_service.dart';
import '../../ui/ui.dart';
import 'course_reports_screen.dart';
import 'live_attendance_session_screen.dart';
import 'roster_import_modal.dart';
import 'signed_acta_dialog.dart';

/// Detalle de la clase seleccionada por el docente:
/// - Hero card para tomar asistencia o volver a la sesión activa.
/// - Banner informativo cuando no hay estudiantes en la clase.
/// - Métricas consolidadas (sesiones, asistencia, en riesgo) con acceso a Reportes.
/// - Historial de últimas sesiones con navegación al acta firmada o sesión en vivo.
/// - Acceso directo a la gestión de estudiantes y exportación del Excel oficial.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({
    super.key,
    required this.course,
    this.database,
    this.rosterService,
    this.overviewService,
  });

  final CourseModel course;
  final AppDatabase? database;
  final RosterImportService? rosterService;
  final CourseOverviewService? overviewService;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final AppDatabase _database;
  late final RosterImportService _rosterService;
  late final CourseOverviewService _overviewService;

  bool _isLoading = true;
  CourseOverview? _overview;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _rosterService = widget.rosterService ?? RosterImportService();
    _overviewService = widget.overviewService ??
        CourseOverviewService(database: _database);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final overview = await _overviewService.load(widget.course.id);
      if (mounted) {
        setState(() {
          _overview = overview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showUiSnack(context, 'No se pudieron cargar los datos de la clase.');
      }
    }
  }

  Future<void> _openImportModal() async {
    final changed = await RosterImportModal.show(context, widget.course);
    if (changed == true) {
      await _loadData();
    }
  }

  Future<void> _onStartBleSession() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => LiveAttendanceSessionScreen(
          course: widget.course,
          database: _database,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _openReportsScreen({bool exportOnOpen = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CourseReportsScreen(
          course: widget.course,
          database: _database,
          exportOnOpen: exportOnOpen,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _openStudentsScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _CourseStudentsScreen(
          course: widget.course,
          database: _database,
          rosterService: _rosterService,
        ),
      ),
    );
    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _showCourseOptionsSheet() async {
    final c = UiColors.of(context);
    await showUiSheet<void>(
      context,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.sm),
            UiNavRow(
              title: 'Agregar estudiantes',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openImportModal();
              },
            ),
            Theme(
              data: Theme.of(sheetContext).copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  UiColors(
                    background: c.background,
                    surface: c.surface,
                    ink: c.absentText,
                    muted: c.muted,
                    line: c.line,
                    primary: c.primary,
                    onPrimary: c.onPrimary,
                    primaryText: c.primaryText,
                    veil: c.veil,
                    tint: c.tint,
                    tintText: c.tintText,
                    manualBg: c.manualBg,
                    manualText: c.manualText,
                    absentBg: c.absentBg,
                    absentText: c.absentText,
                    presentDot: c.presentDot,
                    manualDot: c.manualDot,
                    absentDot: c.absentDot,
                  ),
                ],
              ),
              child: UiNavRow(
                title: 'Eliminar clase',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteCourse();
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteCourse() async {
    final confirmed = await showUiConfirm(
      context,
      destructive: true,
      title: '¿Eliminar esta clase?',
      message:
          'Se borran sus estudiantes y sus sesiones. No se puede deshacer.',
      confirmLabel: 'Eliminar',
    );

    if (confirmed == true) {
      try {
        await _database.deleteCourse(widget.course.id);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          showUiSnack(context, 'No se pudo eliminar la clase.');
        }
      }
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
        showUiSnack(context, 'No se encontró el acta guardada para esta sesión.');
      }
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo abrir el acta de la sesión.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final overview = _overview;

    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (overview == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpace.page),
          child: UiBanner(
            tone: UiBannerTone.error,
            message: 'No se pudieron cargar los datos de la clase.',
            actionLabel: 'Reintentar',
            onAction: _loadData,
          ),
        ),
      );
    } else {
      final hasStudents = overview.hasStudents;
      final hasOpenSession = overview.openSession != null;

      body = RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.only(bottom: UiSpace.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                UiSpace.page,
                UiSpace.sm,
                UiSpace.page,
                0,
              ),
              child: hasStudents
                  ? UiHeroCard(
                      onTap: _onStartBleSession,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  hasOpenSession
                                      ? 'Volver a la sesión'
                                      : 'Tomar asistencia',
                                  style: UiText.h2.copyWith(color: c.onPrimary),
                                ),
                                const SizedBox(height: UiSpace.xs),
                                Text(
                                  UiFormat.count(
                                    overview.studentCount,
                                    'estudiante',
                                    'estudiantes',
                                  ),
                                  style: UiText.label.copyWith(color: c.onPrimary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: UiSpace.md),
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: c.onPrimary,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: c.primary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    )
                  : UiBanner(
                      tone: UiBannerTone.info,
                      message:
                          'Agrega a tus estudiantes para poder tomar asistencia.',
                      actionLabel: 'Agregar estudiantes',
                      onAction: _openImportModal,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                UiSpace.page,
                UiSpace.md,
                UiSpace.page,
                0,
              ),
              child: Semantics(
                button: true,
                label: 'Ver reportes',
                child: InkWell(
                  onTap: () => _openReportsScreen(),
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: UiStatTile(
                          value: '${overview.closedSessionCount}',
                          label: 'sesiones',
                        ),
                      ),
                      const SizedBox(width: UiSpace.sm),
                      Expanded(
                        child: UiStatTile(
                          value: overview.attendancePercent != null
                              ? '${overview.attendancePercent!.round()} %'
                              : '—',
                          label: 'asistencia',
                        ),
                      ),
                      const SizedBox(width: UiSpace.sm),
                      Expanded(
                        child: UiStatTile(
                          value: '${overview.atRiskCount}',
                          label: 'en riesgo',
                          tone: overview.atRiskCount > 0 ? UiTone.absent : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const UiSectionTitle('Últimas sesiones'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
              child: overview.recentSessions.isEmpty
                  ? Text(
                      'Aún no has tomado asistencia en esta clase.',
                      style: UiText.body.copyWith(color: c.muted),
                    )
                  : UiListGroup(
                      children: [
                        for (final row in overview.recentSessions)
                          UiNavRow(
                            title: UiFormat.longDate(
                              DateTime.tryParse(row.session.startedAt)
                                      ?.toLocal() ??
                                  DateTime.now(),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${row.presentCount} de ${row.totalStudents}',
                                  style: UiText.label.copyWith(color: c.muted),
                                ),
                                const SizedBox(width: UiSpace.sm),
                                if (row.isOpen)
                                  const UiPill(label: 'En vivo', dot: true)
                                else
                                  SizedBox(
                                    width: 52,
                                    child: UiProgressBar(
                                      value: row.ratio,
                                      height: 6,
                                      semanticLabel:
                                          '${(row.ratio * 100).round()} por ciento',
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              if (row.isOpen) {
                                _onStartBleSession();
                              } else {
                                _viewSessionActa(row.session);
                              }
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return UiPage(
      header: UiTopBar(
        title: widget.course.name,
        subtitle:
            '${widget.course.code} · Grupo ${widget.course.groupCode} · ${widget.course.semester}',
        onBack: () => Navigator.of(context).pop(),
        trailing: UiRoundIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Opciones de la clase',
          onPressed: _showCourseOptionsSheet,
        ),
      ),
      bottom: _isLoading || overview == null
          ? null
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1.0);
                final stackVertical =
                    scale > 1.15 || constraints.maxWidth < 290;
                if (stackVertical) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UiButton(
                        label: 'Estudiantes',
                        variant: UiButtonVariant.tonal,
                        icon: Icons.person_outline_rounded,
                        onPressed: _openStudentsScreen,
                      ),
                      const SizedBox(height: UiSpace.sm),
                      UiButton(
                        label: 'Enviar Excel',
                        variant: UiButtonVariant.tonal,
                        icon: Icons.ios_share_rounded,
                        onPressed: () => _openReportsScreen(exportOnOpen: true),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: UiButton(
                        label: 'Estudiantes',
                        variant: UiButtonVariant.tonal,
                        icon: Icons.person_outline_rounded,
                        onPressed: _openStudentsScreen,
                      ),
                    ),
                    const SizedBox(width: UiSpace.sm),
                    Expanded(
                      child: UiButton(
                        label: 'Enviar Excel',
                        variant: UiButtonVariant.tonal,
                        icon: Icons.ios_share_rounded,
                        onPressed: () => _openReportsScreen(exportOnOpen: true),
                      ),
                    ),
                  ],
                );
              },
            ),
      body: body,
    );
  }
}

/// Pantalla interna para la gestión y consulta de los estudiantes de la clase.
class _CourseStudentsScreen extends StatefulWidget {
  const _CourseStudentsScreen({
    required this.course,
    required this.database,
    required this.rosterService,
  });

  final CourseModel course;
  final AppDatabase database;
  final RosterImportService rosterService;

  @override
  State<_CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<_CourseStudentsScreen> {
  bool _isLoading = true;
  List<StudentModel> _students = <StudentModel>[];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.database.getStudentsByCourse(widget.course.id);
      if (mounted) {
        setState(() {
          _students = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showUiSnack(context, 'No se pudo cargar la lista de estudiantes.');
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
    final payload = widget.rosterService.generateEnrollmentQrPayload(
      course: widget.course,
      student: student,
    );

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final c = UiColors.of(ctx);
        return AlertDialog(
          title: Text(student.fullName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(UiSpace.md),
                decoration: BoxDecoration(
                  color: UiColors.light.surface,
                  borderRadius: BorderRadius.circular(UiRadius.md),
                  border: Border.all(color: c.line),
                ),
                // Tamaño fijo: AlertDialog mide a sus hijos antes de dibujarlos y
                // QrImageView no puede dar su tamaño por adelantado (sin esto el
                // diálogo falla y no se abre).
                child: SizedBox.square(
                  dimension: 240,
                  child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 240.0,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: UiColors.light.ink,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: UiColors.light.ink,
                  ),
                ),
                ),
              ),
              const SizedBox(height: UiSpace.md),
              Text(
                'Pídele que abra Asistencia Estudiante, toque «Unirme a una clase» y apunte a este código.',
                textAlign: TextAlign.center,
                style: UiText.body.copyWith(color: c.muted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_students.isEmpty) {
      body = UiEmptyState(
        icon: Icons.group_add_outlined,
        title: 'Aún no hay estudiantes',
        message:
            'Agrégalos pegando la lista, desde un archivo o uno por uno.',
        actionLabel: 'Agregar estudiantes',
        onAction: _openImportModal,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _loadStudents,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            UiSpace.page,
            UiSpace.sm,
            UiSpace.page,
            UiSpace.xl,
          ),
          itemCount: _students.length,
          itemBuilder: (BuildContext context, int index) {
            final student = _students[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: UiSpace.sm),
              child: UiPersonRow(
                name: student.fullName,
                subtitle: student.studentCode,
                onTap: () => _showStudentQrDialog(student),
                trailing: UiRoundIconButton(
                  icon: Icons.qr_code_rounded,
                  tooltip: 'Código para unirse',
                  onPressed: () => _showStudentQrDialog(student),
                ),
              ),
            );
          },
        ),
      );
    }

    return UiPage(
      header: UiTopBar(
        title: 'Estudiantes',
        subtitle: widget.course.name,
        onBack: () => Navigator.of(context).pop(),
      ),
      bottom: UiButton(
        label: 'Agregar estudiantes',
        icon: Icons.add_rounded,
        onPressed: _openImportModal,
      ),
      body: body,
    );
  }
}
