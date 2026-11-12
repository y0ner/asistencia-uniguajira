import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/course_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/course_overview_service.dart';
import '../../ui/ui.dart';
import '../shared/hardware_diagnostic_dialog.dart';
import 'course_detail_screen.dart';
import 'live_attendance_session_screen.dart';

/// Panel principal de gestión de clases para el docente:
/// - Lista de clases guardadas en base de datos con conteo de estudiantes y asistencia.
/// - Tarjeta hero "Sesión en curso" cuando hay una sesión activa.
/// - Creación de clases mediante hoja modal con clave secreta aleatoria.
/// - Navegación al detalle de la clase y a la sesión de asistencia en vivo.
class CoursesDashboardScreen extends StatefulWidget {
  const CoursesDashboardScreen({
    super.key,
    this.database,
    this.overviewService,
  });

  final AppDatabase? database;
  final CourseOverviewService? overviewService;

  @override
  State<CoursesDashboardScreen> createState() => _CoursesDashboardScreenState();
}

class _CoursesDashboardScreenState extends State<CoursesDashboardScreen> {
  late final AppDatabase _database;
  late final CourseOverviewService _overviewService;

  bool _isLoading = true;
  String? _errorMessage;
  List<CourseOverview> _overviews = <CourseOverview>[];

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _overviewService = widget.overviewService ??
        CourseOverviewService(database: _database);
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final overviews = await _overviewService.loadAll();
      if (mounted) {
        setState(() {
          _overviews = overviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No se pudieron cargar tus clases.';
        });
      }
    }
  }

  CourseOverview? _findMostRecentOpenSession(List<CourseOverview> overviews) {
    CourseOverview? selected;
    DateTime? selectedStarted;

    for (final overview in overviews) {
      final open = overview.openSession;
      if (open != null) {
        final started = DateTime.tryParse(open.session.startedAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (selected == null ||
            selectedStarted == null ||
            started.isAfter(selectedStarted)) {
          selected = overview;
          selectedStarted = started;
        }
      }
    }
    return selected;
  }

  String _generateRandomSecretHex() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<void> _showCreateCourseSheet() async {
    final created = await showUiSheet<bool>(
      context,
      builder: (_) => _CreateCourseSheet(
        database: _database,
        secretGenerator: _generateRandomSecretHex,
      ),
    );

    if (created == true) {
      await _loadCourses();
      if (mounted) {
        showUiSnack(context, 'Clase creada.');
      }
    }
  }

  void _navigateToCourseDetail(CourseModel course) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => CourseDetailScreen(course: course),
          ),
        )
        .then((_) => _loadCourses());
  }

  void _navigateToLiveSession(CourseModel course) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => LiveAttendanceSessionScreen(
              course: course,
              database: _database,
            ),
          ),
        )
        .then((_) => _loadCourses());
  }

  Widget _buildHeroCard(CourseOverview overview) {
    final openSession = overview.openSession!;
    final presentCount = openSession.presentCount;
    final studentCount = overview.studentCount;
    final c = UiColors.of(context);

    final String arrivalText;
    if (presentCount == 0) {
      arrivalText = 'Aún no llega nadie';
    } else if (studentCount == 1) {
      arrivalText = '1 estudiante ya llegó';
    } else {
      arrivalText = '$presentCount de $studentCount estudiantes ya llegaron';
    }

    return UiHeroCard(
      onTap: () => _navigateToLiveSession(overview.course),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          UiPill(
            label: 'Sesión en curso',
            dot: true,
            background: c.veil,
            foreground: c.onPrimary,
          ),
          const SizedBox(height: UiSpace.md),
          Text(
            overview.course.name,
            style: UiText.h2,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            arrivalText,
            style: UiText.label,
          ),
          const SizedBox(height: UiSpace.md),
          UiProgressBar(
            value: openSession.ratio,
            onHero: true,
            semanticLabel: '$presentCount de $studentCount presentes',
          ),
          const SizedBox(height: UiSpace.lg),
          UiButton(
            label: 'Volver a la sesión',
            variant: UiButtonVariant.onHero,
            trailingIcon: Icons.arrow_forward_rounded,
            compact: true,
            onPressed: () => _navigateToLiveSession(overview.course),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(CourseOverview overview) {
    final course = overview.course;
    final colors = UiColors.of(context);
    final hasStudents = overview.hasStudents;
    final subtitle = hasStudents
        ? 'Grupo ${course.groupCode} · ${UiFormat.count(overview.studentCount, 'estudiante', 'estudiantes')}'
        : 'Grupo ${course.groupCode} · Falta agregar estudiantes';

    final Widget rightWidget;
    if (!hasStudents) {
      rightWidget = const UiPill(label: 'Nueva', tone: UiTone.manual);
    } else if (overview.attendancePercent != null) {
      rightWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${overview.attendancePercent!.round()} %',
            style: UiText.title.copyWith(color: colors.ink),
          ),
          Text(
            'asistencia',
            style: UiText.label.copyWith(color: colors.muted),
          ),
        ],
      );
    } else {
      rightWidget = Text(
        'Sin sesiones',
        style: UiText.label.copyWith(color: colors.muted),
      );
    }

    return UiCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: UiSpace.md),
      onTap: () => _navigateToCourseDetail(course),
      child: Row(
        children: [
          UiAvatar(name: course.name, square: true),
          const SizedBox(width: UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  course.name,
                  style: UiText.title.copyWith(color: colors.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: UiText.label.copyWith(color: colors.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: UiSpace.md),
          rightWidget,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mostRecentOpen = _findMostRecentOpenSession(_overviews);
    final hasOpenSession = mostRecentOpen != null;
    final headerCount = hasOpenSession ? 3 : 2;

    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
          child: UiBanner(
            tone: UiBannerTone.error,
            message: _errorMessage!,
            actionLabel: 'Volver a intentar',
            onAction: _loadCourses,
          ),
        ),
      );
    } else if (_overviews.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiPageHeading(
            overline: UiFormat.longDate(now),
            title: '${UiFormat.greeting(now)}, profe',
          ),
          Expanded(
            child: UiEmptyState(
              icon: Icons.school_outlined,
              title: 'Aún no tienes clases',
              message: 'Crea tu primera clase para empezar a tomar asistencia.',
              actionLabel: 'Crear mi primera clase',
              onAction: _showCreateCourseSheet,
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _loadCourses,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: UiSpace.xxl),
          itemCount: _overviews.length + headerCount,
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return UiPageHeading(
                overline: UiFormat.longDate(now),
                title: '${UiFormat.greeting(now)}, profe',
              );
            }
            if (hasOpenSession && index == 1) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
                child: _buildHeroCard(mostRecentOpen),
              );
            }
            if (index == headerCount - 1) {
              return const UiSectionTitle('Tus clases');
            }
            final overview = _overviews[index - headerCount];
            return Padding(
              padding:
                  const EdgeInsets.fromLTRB(UiSpace.page, 0, UiSpace.page, 10),
              child: _buildCourseCard(overview),
            );
          },
        ),
      );
    }

    return UiPage(
      header: UiBrandHeader(
        trailing: UiRoundIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Ajustes y diagnóstico',
          onPressed: () => showHardwareDiagnosticDialog(context),
        ),
      ),
      bottom: _isLoading || _errorMessage != null || _overviews.isEmpty
          ? null
          : UiButton(
              label: 'Nueva clase',
              icon: Icons.add_rounded,
              variant: UiButtonVariant.outline,
              onPressed: _showCreateCourseSheet,
            ),
      body: body,
    );
  }
}

/// Hoja modal para registrar una nueva clase.
class _CreateCourseSheet extends StatefulWidget {
  const _CreateCourseSheet({
    required this.database,
    required this.secretGenerator,
  });

  final AppDatabase database;
  final String Function() secretGenerator;

  @override
  State<_CreateCourseSheet> createState() => _CreateCourseSheetState();
}

class _CreateCourseSheetState extends State<_CreateCourseSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _groupController;
  late final TextEditingController _semesterController;
  final _uuid = const Uuid();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
    _groupController = TextEditingController(text: '01');
    _semesterController = TextEditingController(text: '2026-2');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _groupController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() => _isSaving = true);
    final newCourse = CourseModel(
      id: _uuid.v4(),
      code: _codeController.text.trim().toUpperCase(),
      name: _nameController.text.trim(),
      groupCode: _groupController.text.trim(),
      semester: _semesterController.text.trim(),
      courseSecret: widget.secretGenerator(),
      spreadsheetId: null,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    try {
      await widget.database.insertCourse(newCourse);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showUiSnack(context, 'No se pudo crear la clase.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Nueva clase', style: UiText.h2.copyWith(color: c.ink)),
                UiRoundIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: UiSpace.lg),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre de la clase',
                hintText: 'Bases de Datos II',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Escribe el nombre de la clase';
                }
                return null;
              },
            ),
            const SizedBox(height: UiSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      hintText: 'SIST-401',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Escribe el código';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: UiSpace.md),
                Expanded(
                  child: TextFormField(
                    controller: _groupController,
                    decoration: const InputDecoration(
                      labelText: 'Grupo',
                      hintText: '01',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Escribe el grupo';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: UiSpace.md),
            TextFormField(
              controller: _semesterController,
              decoration: const InputDecoration(
                labelText: 'Semestre',
                hintText: '2026-2',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Escribe el semestre';
                }
                return null;
              },
            ),
            const SizedBox(height: UiSpace.xl),
            UiButton(
              label: 'Crear clase',
              loading: _isSaving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
