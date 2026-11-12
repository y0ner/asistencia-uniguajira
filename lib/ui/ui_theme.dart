import 'package:flutter/material.dart';

import 'tokens/ui_colors.dart';
import 'tokens/ui_metrics.dart';
import 'tokens/ui_text.dart';

/// Tema de la app (versión B del rediseño).
abstract final class UiTheme {
  static ThemeData light() => _build(Brightness.light, UiColors.light);

  static ThemeData dark() => _build(Brightness.dark, UiColors.dark);

  static ThemeData _build(Brightness brightness, UiColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.tint,
      onPrimaryContainer: c.tintText,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.tint,
      onSecondaryContainer: c.tintText,
      tertiary: c.manualDot,
      onTertiary: c.ink,
      tertiaryContainer: c.manualBg,
      onTertiaryContainer: c.manualText,
      error: c.absentText,
      onError: c.surface,
      errorContainer: c.absentBg,
      onErrorContainer: c.absentText,
      surface: c.background,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.tint,
      outline: c.line,
      outlineVariant: c.line,
    );

    final shapeMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiRadius.md));
    const minButton = Size(UiSize.touch, UiSize.button);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: UiText.family,
      scaffoldBackgroundColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        displaySmall: UiText.display,
        headlineMedium: UiText.h1,
        headlineSmall: UiText.h2,
        titleLarge: UiText.h2,
        titleMedium: UiText.title,
        titleSmall: UiText.bodyStrong,
        bodyLarge: UiText.body,
        bodyMedium: UiText.body,
        bodySmall: UiText.label,
        labelLarge: UiText.button,
        labelMedium: UiText.label,
        labelSmall: UiText.caption,
      ).apply(bodyColor: c.ink, displayColor: c.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: UiText.h2.copyWith(color: c.ink),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiRadius.lg),
          side: BorderSide(color: c.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiRadius.xl)),
        titleTextStyle: UiText.h2.copyWith(color: c.ink),
        contentTextStyle: UiText.body.copyWith(color: c.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(UiRadius.xxl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        contentTextStyle: UiText.bodyStrong.copyWith(color: c.background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiRadius.md)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: UiSpace.lg),
        hintStyle: UiText.body.copyWith(color: c.muted),
        labelStyle: UiText.body.copyWith(color: c.muted),
        floatingLabelStyle: UiText.label.copyWith(color: c.primaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiRadius.md),
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiRadius.md),
          borderSide: BorderSide(color: c.absentText),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UiRadius.md),
          borderSide: BorderSide(color: c.absentText, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: minButton,
          textStyle: UiText.button,
          shape: shapeMd,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: 0,
          minimumSize: minButton,
          textStyle: UiText.button,
          shape: shapeMd,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primaryText,
          minimumSize: minButton,
          textStyle: UiText.button,
          side: BorderSide(color: c.primary, width: 1.5),
          shape: shapeMd,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primaryText,
          minimumSize: const Size(UiSize.touch, UiSize.touch),
          textStyle: UiText.button,
          shape: shapeMd,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.line),
      extensions: [c],
    );
  }
}
