import 'package:flutter/material.dart';

/// Punto de entrada del panel estudiante.
///
/// En la Etapa 1 se construyen encima de esta pantalla el escáner QR de
/// enrolamiento, el PIN verbal de dos dígitos y el sello criptográfico verde.
class StudentPlaceholderScreen extends StatelessWidget {
  const StudentPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo Estudiante'),
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
                Icons.qr_code_scanner,
                size: 64,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Panel estudiante',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Base lista para la Etapa 1: enrolamiento por QR del primer '
                'día y sello de asistencia.',
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
