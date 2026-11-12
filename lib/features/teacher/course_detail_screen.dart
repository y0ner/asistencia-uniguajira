import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/roster_import_service.dart';
import '../../ui/ui.dart';
import 'course_reports_screen.dart';
import 'live_attendance_session_screen.dart';
import 'roster_import_modal.dart';
import 'signed_acta_dialog.dart';

/// Detalle de la clase seleccionada por el docente:
/// - Hero card para tomar asistencia o volver a la sesión activa.
/// - Banner informativo cuando no hay estudiantes en la clase.
/// - Métricas de la clase (sesiones y estudiantes).
/// - Historial de últimas sesiones con navegación al acta firmada.
/// - Acceso directo a la gestión de estudiantes y reportes.
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

  Future<void> _openStudentsScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _CourseStudentsScreen(
          course: widget.course,
          database: _database,
          rosterService: _rosterService,
          initialStudents: _students,
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
        showUiSnack(context, 'No se encontró el acta guardada para esta sesión.');
      }
    } catch (e) {
      if (!mounted) return;
      showUiSnack(context, 'No se pudo abrir el acta de la sesión.');
    }
  }

  int _countAttended(String bitmapHex) {
    final value = BigInt.tryParse(bitmapHex, radix: 16);
    if (value == null) return 0;
    var count = 0;
    var temp = value;
    while (temp > BigInt.zero) {
      if ((temp & BigInt.one) == BigInt.one) {
        count++;
      }
      temp = temp >> 1;
    }
    return count;
  }

  String _formatSessionDate(String startedAt) {
    final dt = DateTime.tryParse(startedAt);
    if (dt != null) {
      return UiFormat.longDate(dt.toLocal());
    }
    return startedAt;
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final hasStudents = _students.isNotEmpty;
    final hasOpenSession = _sessions.any((s) => s.closedAt == null);

    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
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
                                    _students.length,
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
              child: Row(
                children: [
                  Expanded(
                    child: UiStatTile(
                      value: '${_sessions.length}',
                      label: 'sesiones',
                    ),
                  ),
                  const SizedBox(width: UiSpace.sm),
                  Expanded(
                    child: UiStatTile(
                      value: '${_students.length}',
                      label: 'estudiantes',
                    ),
                  ),
                ],
              ),
            ),
            const UiSectionTitle('Últimas sesiones'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
              child: _sessions.isEmpty
                  ? Text(
                      'Aún no has tomado asistencia en esta clase.',
                      style: UiText.body.copyWith(color: c.muted),
                    )
                  : UiListGroup(
                      children: [
                        for (final session in _sessions)
                          UiNavRow(
                            title: _formatSessionDate(session.startedAt),
                            subtitle: session.closedAt == null
                                ? 'Sesión abierta'
                                : 'Llegaron ${_countAttended(session.bitmapHex)} de ${_students.length}',
                            onTap: () {
                              if (session.closedAt != null) {
                                _viewSessionActa(session);
                              } else {
                                _onStartBleSession();
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
      ),
      bottom: _isLoading
          ? null
          : Row(
              children: [
                Expanded(
                  child: UiButton(
                    label: 'Estudiantes',
                    icon: Icons.person_outline_rounded,
                    variant: UiButtonVariant.tonal,
                    onPressed: _openStudentsScreen,
                  ),
                ),
                const SizedBox(width: UiSpace.sm),
                Expanded(
                  child: UiButton(
                    label: 'Reportes',
                    icon: Icons.bar_chart_rounded,
                    variant: UiButtonVariant.tonal,
                    onPressed: _openReportsScreen,
                  ),
                ),
              ],
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
    this.initialStudents,
  });

  final CourseModel course;
  final AppDatabase database;
  final RosterImportService rosterService;
  final List<StudentModel>? initialStudents;

  @override
  State<_CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<_CourseStudentsScreen> {
  late bool _isLoading;
  late List<StudentModel> _students;

  @override
  void initState() {
    super.initState();
    if (widget.initialStudents != null) {
      _isLoading = false;
      _students = List<StudentModel>.from(widget.initialStudents!);
    } else {
      _isLoading = true;
      _students = <StudentModel>[];
      _loadStudents();
    }
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
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 200.0,
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
