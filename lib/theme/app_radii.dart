import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Tokens de curvatura y siluetas geométricas (Tier 2).
///
/// Los componentes solicitan siluetas y radios nominales en lugar de valores
/// numéricos arbitrarios.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  const AppRadii({
    this.xs = 4.0,
    this.sm = 8.0,
    this.md = 12.0,
    this.lg = 16.0,
    this.xl = 24.0,
    this.pill = 999.0,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double pill;

  Radius get radiusXs => Radius.circular(xs);
  Radius get radiusSm => Radius.circular(sm);
  Radius get radiusMd => Radius.circular(md);
  Radius get radiusLg => Radius.circular(lg);
  Radius get radiusXl => Radius.circular(xl);
  Radius get radiusPill => Radius.circular(pill);

  BorderRadius get borderXs => BorderRadius.circular(xs);
  BorderRadius get borderSm => BorderRadius.circular(sm);
  BorderRadius get borderMd => BorderRadius.circular(md);
  BorderRadius get borderLg => BorderRadius.circular(lg);
  BorderRadius get borderXl => BorderRadius.circular(xl);
  BorderRadius get borderPill => BorderRadius.circular(pill);

  BorderRadius get borderTopMd => BorderRadius.vertical(top: radiusMd);
  BorderRadius get borderTopLg => BorderRadius.vertical(top: radiusLg);
  BorderRadius get borderTopXl => BorderRadius.vertical(top: radiusXl);

  // Siluetas estandarizadas
  RoundedRectangleBorder cardShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: borderLg, side: side);

  RoundedRectangleBorder buttonShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: borderMd, side: side);

  RoundedRectangleBorder dialogShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: borderXl, side: side);

  RoundedRectangleBorder modalShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: borderTopXl, side: side);

  RoundedRectangleBorder pillShape({BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: borderPill, side: side);

  /// Obtiene la instancia de [AppRadii] vinculada al contexto actual.
  static AppRadii of(BuildContext context) {
    final ext = Theme.of(context).extension<AppRadii>();
    assert(
      ext != null,
      'AppRadii no encontrado en el contexto. Asegúrate de configurar MaterialApp '
      'con buildLightTheme() y buildDarkTheme().',
    );
    return ext!;
  }

  @override
  AppRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? pill,
  }) {
    return AppRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(covariant AppRadii? other, double t) {
    if (other == null) return this;
    return AppRadii(
      xs: lerpDouble(xs, other.xs, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}

const defaultAppRadii = AppRadii();
