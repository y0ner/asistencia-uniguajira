import 'package:flutter/material.dart';

import 'student_courses_screen.dart';

/// Punto de entrada del panel estudiante.
///
/// Conecta la selección de rol directamente con la billetera de cursos
/// enrolados y el escáner QR de credenciales.
class StudentPlaceholderScreen extends StatelessWidget {
  const StudentPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StudentCoursesScreen();
  }
}
