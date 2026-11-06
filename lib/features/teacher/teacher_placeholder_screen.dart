import 'package:flutter/material.dart';

import 'courses_dashboard_screen.dart';

/// Punto de entrada del panel docente.
///
/// Conecta la selección de rol directamente con el panel de cursos e ingesta
/// de estudiantes en SQLite.
class TeacherPlaceholderScreen extends StatelessWidget {
  const TeacherPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CoursesDashboardScreen();
  }
}
