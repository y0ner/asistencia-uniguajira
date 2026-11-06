import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'features/student/student_placeholder_screen.dart';
import 'features/teacher/teacher_placeholder_screen.dart';

/// Verde institucional de la Universidad de La Guajira.
const Color _uniguajiraGreen = Color(0xFF00843D);

/// Azul institucional de la Universidad de La Guajira.
const Color _uniguajiraBlue = Color(0xFF0033A0);

void main() {
  runApp(const AsistenciaUniguajiraApp());
}

/// Raíz de la aplicación y punto de entrada del selector de rol.
class AsistenciaUniguajiraApp extends StatelessWidget {
  const AsistenciaUniguajiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _uniguajiraGreen,
    ).copyWith(secondary: _uniguajiraBlue);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: colorScheme),
      home: const RoleSelectorScreen(),
    );
  }
}

/// Selector de rol: abre el panel docente o el panel estudiante.
class RoleSelectorScreen extends StatelessWidget {
  const RoleSelectorScreen({super.key});

  void _openRole(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(
                    Icons.school_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Universidad de La Guajira · Registro Offline-First',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    icon: Icons.co_present_outlined,
                    title: 'Modo Docente',
                    subtitle: 'Cursos, radar BLE y acta de sesión',
                    highlighted: true,
                    onTap: () => _openRole(
                      context,
                      const TeacherPlaceholderScreen(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    icon: Icons.qr_code_scanner,
                    title: 'Modo Estudiante',
                    subtitle: 'Enrolamiento por QR y sello de asistencia',
                    highlighted: false,
                    onTap: () => _openRole(
                      context,
                      const StudentPlaceholderScreen(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        highlighted ? colorScheme.onPrimary : colorScheme.onSecondaryContainer;
    final background =
        highlighted ? colorScheme.primary : colorScheme.secondaryContainer;
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        iconColor: foreground,
        textColor: foreground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        leading: Icon(icon, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: foreground),
      ),
    );
  }
}
