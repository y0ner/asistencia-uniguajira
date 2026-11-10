import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'primitives.dart';

/// Constructor centralizado de [ThemeData] para Asistencia Uniguajira.
///
/// Implementa Material Design 3 con ColorScheme completamente artesanal
/// (sin derivaciones automáticas de `fromSeed`), garantizando contraste AA
/// para la identidad institucional y los estados de asistencia offline.
abstract final class AppTheme {
  /// Construye el tema en modo claro.
  static ThemeData buildLightTheme() {
    return _buildTheme(Brightness.light, lightAppColors);
  }

  /// Construye el tema en modo oscuro.
  static ThemeData buildDarkTheme() {
    return _buildTheme(Brightness.dark, darkAppColors);
  }

  static ThemeData _buildTheme(Brightness brightness, AppColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      tertiary: c.bleAccent,
      onTertiary: c.onBleAccent,
      tertiaryContainer: c.bleAccentContainer,
      onTertiaryContainer: c.onBleAccentContainer,
      error: c.statusPerdida,
      onError: c.onStatusPerdida,
      errorContainer: c.statusPerdidaContainer,
      onErrorContainer: c.onStatusPerdidaContainer,
      surface: c.surface,
      onSurface: c.onSurface,
      surfaceContainer: c.surfaceContainer,
      surfaceContainerHigh: c.surfaceContainerHigh,
      surfaceContainerHighest: c.surfaceContainerHigh,
      surfaceContainerLow: c.surfaceContainerLow,
      surfaceContainerLowest: c.surface,
      outline: c.outline,
      outlineVariant: c.outlineVariant,
      shadow: Primitives.neutral000.withValues(alpha: 0.15),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surface,
      dividerColor: c.divider,
      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: c.hairlineWidth,
        space: 1.0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: c.onSurface),
      ),
      cardTheme: CardThemeData(
        color: c.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: defaultAppRadii.borderLg,
          side: BorderSide(color: c.outlineVariant, width: c.hairlineWidth),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          elevation: 0,
          shape: defaultAppRadii.buttonShape(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          elevation: 0,
          side: BorderSide(color: c.outline, width: c.hairlineWidth),
          shape: defaultAppRadii.buttonShape(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: defaultAppRadii.buttonShape(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: defaultAppRadii.borderLg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: defaultAppRadii.borderMd,
          borderSide: BorderSide(color: c.outlineVariant, width: c.hairlineWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: defaultAppRadii.borderMd,
          borderSide: BorderSide(color: c.outlineVariant, width: c.hairlineWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: defaultAppRadii.borderMd,
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: defaultAppRadii.borderMd,
          borderSide: BorderSide(color: c.statusPerdida, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainer,
        elevation: 6,
        shape: defaultAppRadii.dialogShape(),
        titleTextStyle: TextStyle(
          color: c.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: c.onSurfaceMuted,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceContainer,
        elevation: 8,
        shape: defaultAppRadii.modalShape(),
        showDragHandle: true,
        dragHandleColor: c.outline,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      // Adjuntar todas las extensiones a ambas brightness
      extensions: [
        c,
        defaultAppSpacing,
        defaultAppRadii,
        defaultAppMotion,
      ],
    );
  }
}
