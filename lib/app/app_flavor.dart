import 'package:flutter/material.dart';

import '../features/student/student_courses_screen.dart';
import '../features/teacher/courses_dashboard_screen.dart';

/// Define los sabores (flavors) y roles disponibles de la aplicación institucional.
enum AppFlavor {
  docente,
  estudiante;

  /// Título institucional oficial de la aplicación según el rol.
  String get title {
    switch (this) {
      case AppFlavor.docente:
        return 'Asistencia Docente';
      case AppFlavor.estudiante:
        return 'Asistencia Estudiante';
    }
  }

  /// Pantalla de inicio raíz asignada para este rol.
  Widget get homeScreen {
    switch (this) {
      case AppFlavor.docente:
        return const CoursesDashboardScreen();
      case AppFlavor.estudiante:
        return const StudentCoursesScreen();
    }
  }
}
