import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/course_model.dart';
import '../../data/local/app_database.dart';
import '../../ui/ui.dart';
import '../shared/hardware_diagnostic_dialog.dart';
import 'course_detail_screen.dart';

typedef _Palette = UiColors;

/// Panel principal de gestión de clases para el docente:
/// - Lista de clases guardadas en base de datos con conteo de estudiantes.
/// - Creación de clases mediante hoja modal con clave secreta aleatoria.
/// - Eliminación de clases con confirmación y borrado en cascada.
/// - Navegación al detalle de la clase para gestión y asistencia.
class CoursesDashboardScreen extends StatefulWidget {
  const CoursesDashboardScreen({
    super.key,
    this.database,
  });

  final AppDatabase? database;

  @override
  State<CoursesDashboardScreen> createState() => _CoursesDashboardScreenState();
}

class _CoursesDashboardScreenState extends State<CoursesDashboardScreen> {
  late final AppDatabase _database;

  bool _isLoading = true;
  String? _errorMessage;
  List<CourseModel> _courses = <CourseModel>[];
  Map<String, int> _studentCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final courses = await _database.getAllCourses();
      final counts = <String, int>{};

      for (final course in courses) {
        final students = await _database.getStudentsByCourse(course.id);
        counts[course.id] = students.length;
      }

      if (mounted) {
        setState(() {
          _courses = courses;
          _studentCounts = counts;
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

  Future<void> _showCourseOptionsSheet(CourseModel course) async {
    await showUiSheet<void>(
      context,
      builder: (sheetContext) {
        final c = _Palette.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.sm),
            Text(
              course.name,
              style: UiText.h2.copyWith(color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: UiSpace.xs),
            Text(
              'Grupo ${course.groupCode} · ${course.code}',
              style: UiText.label.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.lg),
            InkWell(
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDeleteCourse(course);
              },
              borderRadius: BorderRadius.circular(UiRadius.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: UiSize.touch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: UiSpace.sm),
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: c.absentText),
                      const SizedBox(width: UiSpace.md),
                      Text(
                        'Eliminar clase',
                        style: UiText.bodyStrong.copyWith(color: c.absentText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteCourse(CourseModel course) async {
    final confirmed = await showUiConfirm(
      context,
      title: '¿Eliminar esta clase?',
      message:
          'Se borran sus estudiantes y sus sesiones. No se puede deshacer.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );

    if (confirmed == true) {
      try {
        await _database.deleteCourse(course.id);
        await _loadCourses();
        if (mounted) {
          showUiSnack(context, 'Clase eliminada.');
        }
      } catch (e) {
        if (mounted) {
          showUiSnack(context, 'No se pudo eliminar la clase.');
        }
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

  Widget _buildCourseCard(CourseModel course) {
    final colors = _Palette.of(context);
    final studentCount = _studentCounts[course.id] ?? 0;
    final hasStudents = studentCount > 0;
    final subtitle = hasStudents
        ? 'Grupo ${course.groupCode} · ${UiFormat.count(studentCount, 'estudiante', 'estudiantes')}'
        : 'Grupo ${course.groupCode} · Falta agregar estudiantes';

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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: UiText.label.copyWith(color: colors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: UiSpace.sm),
          if (!hasStudents) ...[
            const UiPill(label: 'Nueva', tone: UiTone.manual),
            const SizedBox(width: UiSpace.sm),
          ],
          UiRoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Opciones de la clase',
            onPressed: () => _showCourseOptionsSheet(course),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

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
    } else if (_courses.isEmpty) {
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
          itemCount: _courses.length + 2,
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return UiPageHeading(
                overline: UiFormat.longDate(now),
                title: '${UiFormat.greeting(now)}, profe',
              );
            }
            if (index == 1) {
              return const UiSectionTitle('Tus clases');
            }
            final course = _courses[index - 2];
            return Padding(
              padding:
                  const EdgeInsets.fromLTRB(UiSpace.page, 0, UiSpace.page, 10),
              child: _buildCourseCard(course),
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
      bottom: _isLoading || _errorMessage != null || _courses.isEmpty
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
    final c = _Palette.of(context);
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
