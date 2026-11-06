import 'package:flutter/material.dart';

/// Punto de entrada del panel docente.
///
/// En la Etapa 1 se construyen encima de esta pantalla la ingesta de cursos,
/// el radar BLE en vivo y el acta de la sesión.
class TeacherPlaceholderScreen extends StatelessWidget {
  const TeacherPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo Docente'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.co_present_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Panel docente',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Base lista para la Etapa 1: ingesta de cursos, radar BLE '
                'y lista invertida de excepción.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
