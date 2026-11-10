import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Tokens de espaciado y márgenes (Tier 2).
///
/// Centraliza la métrica espacial de la aplicación eliminando los literales
/// de padding y margin dispersos en los widgets.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({
    this.xxs = 4.0,
    this.xs = 8.0,
    this.sm = 12.0,
    this.md = 16.0,
    this.lg = 24.0,
    this.xl = 32.0,
    this.xxl = 48.0,
  });

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;

  // Insets uniformes
  EdgeInsets get insetsXxs => EdgeInsets.all(xxs);
  EdgeInsets get insetsXs => EdgeInsets.all(xs);
  EdgeInsets get insetsSm => EdgeInsets.all(sm);
  EdgeInsets get insetsMd => EdgeInsets.all(md);
  EdgeInsets get insetsLg => EdgeInsets.all(lg);
  EdgeInsets get insetsXl => EdgeInsets.all(xl);

  // Insets horizontales
  EdgeInsets get insetsHXs => EdgeInsets.symmetric(horizontal: xs);
  EdgeInsets get insetsHSm => EdgeInsets.symmetric(horizontal: sm);
  EdgeInsets get insetsHMd => EdgeInsets.symmetric(horizontal: md);
  EdgeInsets get insetsHLg => EdgeInsets.symmetric(horizontal: lg);
  EdgeInsets get insetsHXl => EdgeInsets.symmetric(horizontal: xl);

  // Insets verticales
  EdgeInsets get insetsVXs => EdgeInsets.symmetric(vertical: xs);
  EdgeInsets get insetsVSm => EdgeInsets.symmetric(vertical: sm);
  EdgeInsets get insetsVMd => EdgeInsets.symmetric(vertical: md);
  EdgeInsets get insetsVLg => EdgeInsets.symmetric(vertical: lg);

  // Insets contextuales estándar
  EdgeInsets get insetsCard => EdgeInsets.all(md);
  EdgeInsets get insetsDialog => EdgeInsets.all(lg);
  EdgeInsets get insetsModal => EdgeInsets.fromLTRB(lg, sm, lg, lg);
  EdgeInsets get insetsScreen => EdgeInsets.symmetric(horizontal: md, vertical: sm);

  // Métodos factoría para combinaciones semánticas
  EdgeInsets all(double value) => EdgeInsets.all(value);

  EdgeInsets symmetric({double horizontal = 0.0, double vertical = 0.0}) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);

  EdgeInsets only({
    double left = 0.0,
    double top = 0.0,
    double right = 0.0,
    double bottom = 0.0,
  }) =>
      EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);

  EdgeInsets fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) =>
      EdgeInsets.fromLTRB(left, top, right, bottom);

  /// Obtiene la instancia de [AppSpacing] vinculada al contexto actual.
  static AppSpacing of(BuildContext context) {
    final ext = Theme.of(context).extension<AppSpacing>();
    assert(
      ext != null,
      'AppSpacing no encontrado en el contexto. Asegúrate de configurar MaterialApp '
      'con buildLightTheme() y buildDarkTheme().',
    );
    return ext!;
  }

  @override
  AppSpacing copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppSpacing lerp(covariant AppSpacing? other, double t) {
    if (other == null) return this;
    return AppSpacing(
      xxs: lerpDouble(xxs, other.xxs, t)!,
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      xxl: lerpDouble(xxl, other.xxl, t)!,
    );
  }
}

const defaultAppSpacing = AppSpacing();
