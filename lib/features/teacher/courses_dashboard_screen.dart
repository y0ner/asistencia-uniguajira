import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../data/local/app_database.dart';
import 'course_detail_screen.dart';

/// Panel principal de gestión de cursos para el docente:
/// - Lista de cursos guardados en SQLite con conteo de estudiantes (X / 64).
/// - Creación de cursos mediante formulario modal con generación de clave secreta HMAC.
/// - Eliminación de cursos con diálogo de confirmación y borrado en cascada.
/// - Navegación al detalle del curso para ingesta y enrolamiento.
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
  final Uuid _uuid = const Uuid();

  bool _isLoading = true;
  List<CourseModel> _courses = <CourseModel>[];
  Map<String, int> _studentCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoading = true);
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
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar cursos: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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

  Future<void> _showCreateCourseDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final groupController = TextEditingController(text: '01');
    final semesterController = TextEditingController(text: '2026-2');
    final sheetController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);

        return AlertDialog(
          title: Row(
            children: <Widget>[
              Icon(Icons.add_circle_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Nuevo Curso'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la Asignatura *',
                      hintText: 'Ej. Sistemas Distribuidos',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El nombre de la asignatura es obligatorio';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: codeController,
                          decoration: const InputDecoration(
                            labelText: 'Código *',
                            hintText: 'SIS-402',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Obligatorio';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: groupController,
                          decoration: const InputDecoration(
                            labelText: 'Grupo *',
                            hintText: '01',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Obligatorio';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: semesterController,
                    decoration: const InputDecoration(
                      labelText: 'Semestre / Periodo *',
                      hintText: '2026-2',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El periodo es obligatorio';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: sheetController,
                    decoration: const InputDecoration(
                      labelText: 'ID Google Sheets (Opcional)',
                      hintText: 'Hoja para sincronización SMA',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final newCourse = CourseModel(
                  id: _uuid.v4(),
                  code: codeController.text.trim().toUpperCase(),
                  name: nameController.text.trim(),
                  groupCode: groupController.text.trim(),
                  semester: semesterController.text.trim(),
                  courseSecret: _generateRandomSecretHex(),
                  spreadsheetId: sheetController.text.trim().isEmpty
                      ? null
                      : sheetController.text.trim(),
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );

                try {
                  await _database.insertCourse(newCourse);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Error al crear curso: $e'),
                        backgroundColor: theme.colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    if (created == true) {
      await _loadCourses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Curso registrado con éxito.'),
            backgroundColor: Color(0xFF00843D),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteCourse(CourseModel course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);

        return AlertDialog(
          title: const Text('¿Eliminar curso?'),
          content: Text(
            'Se eliminará "${course.name}" (${course.code} - G${course.groupCode}) '
            'junto con todos sus estudiantes matriculados y el historial de asistencias asociadas.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _database.deleteCourse(course.id);
        await _loadCourses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Curso "${course.name}" eliminado.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar curso: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Cursos'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _courses.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _loadCourses,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: _courses.length,
                    itemBuilder: (BuildContext context, int index) {
                      final course = _courses[index];
                      final studentCount = _studentCounts[course.id] ?? 0;
                      return _buildCourseCard(theme, course, studentCount);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCourseDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Curso'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.school_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'No tienes cursos registrados',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Crea tu primer curso para gestionar estudiantes, enrolar sus credenciales '
              'por QR y habilitar el radar de asistencia BLE.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showCreateCourseDialog,
              icon: const Icon(Icons.add),
              label: const Text('Crear Primer Curso'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCard(
    ThemeData theme,
    CourseModel course,
    int studentCount,
  ) {
    final isFull = studentCount >= AppConstants.bitmapBitCount;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _navigateToCourseDetail(course),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          course.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${course.code} · Grupo ${course.groupCode} · ${course.semester}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error.withValues(alpha: 0.8),
                    ),
                    tooltip: 'Eliminar curso',
                    onPressed: () => _confirmDeleteCourse(course),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isFull
                          ? theme.colorScheme.errorContainer
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$studentCount / ${AppConstants.bitmapBitCount} estudiantes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isFull
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Ver Roster',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
