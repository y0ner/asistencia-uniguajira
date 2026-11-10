import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'app_flavor.dart';

/// Raíz institucional de la aplicación con soporte para sabores de rol (Docente y Estudiante).
class AsistenciaApp extends StatelessWidget {
  const AsistenciaApp({
    super.key,
    required this.flavor,
  });

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.title,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildLightTheme(),
      darkTheme: AppTheme.buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: flavor.homeScreen,
    );
  }
}
