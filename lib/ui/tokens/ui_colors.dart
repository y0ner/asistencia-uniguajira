import 'package:flutter/material.dart';

/// Tono semántico de una superficie pequeña (pastilla, avatar, ficha).
///
/// Cada tono resuelve un par fondo/texto con contraste AA en claro y oscuro.
enum UiTone { neutral, tint, primary, manual, absent }

/// Par de colores fondo/texto que devuelve [UiColors.tone].
@immutable
class UiTonePair {
  const UiTonePair(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Colores del sistema de diseño de Asistencia Uniguajira.
///
/// Salen del escudo de la Universidad de La Guajira: turquesa (acción y
/// presente), ocre (marcado a mano o atención) y coral (falta o riesgo).
/// Las pantallas leen estos colores con `UiColors.of(context)`; ningún widget
/// de `lib/features` debe escribir un `Color(0x…)`.
@immutable
class UiColors extends ThemeExtension<UiColors> {
  const UiColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.primary,
    required this.onPrimary,
    required this.primaryText,
    required this.veil,
    required this.tint,
    required this.tintText,
    required this.manualBg,
    required this.manualText,
    required this.absentBg,
    required this.absentText,
    required this.presentDot,
    required this.manualDot,
    required this.absentDot,
  });

  /// Fondo de la pantalla.
  final Color background;

  /// Fondo de tarjetas, listas y campos.
  final Color surface;

  /// Texto principal.
  final Color ink;

  /// Texto secundario (contraste AA sobre [background] y [surface]).
  final Color muted;

  /// Bordes finos y separadores.
  final Color line;

  /// Turquesa de acción: botones principales y tarjetas destacadas.
  final Color primary;

  /// Texto e íconos sobre [primary].
  final Color onPrimary;

  /// Turquesa legible como texto sobre [background] o [surface].
  final Color primaryText;

  /// Velo translúcido sobre [primary] (pastillas y pistas de progreso).
  final Color veil;

  /// Turquesa muy suave para fondos de apoyo.
  final Color tint;

  /// Texto sobre [tint].
  final Color tintText;

  /// Ocre suave: "marcado a mano" o algo que requiere atención.
  final Color manualBg;
  final Color manualText;

  /// Coral suave: falta o estudiante en riesgo.
  final Color absentBg;
  final Color absentText;

  /// Colores puros del escudo, para puntos e ilustraciones (no para texto).
  final Color presentDot;
  final Color manualDot;
  final Color absentDot;

  static UiColors of(BuildContext context) {
    final colors = Theme.of(context).extension<UiColors>();
    assert(colors != null, 'UiColors no está en el tema: usa UiTheme.light()/dark().');
    return colors!;
  }

  /// Par fondo/texto de un [UiTone].
  UiTonePair tone(UiTone tone) {
    return switch (tone) {
      UiTone.neutral => UiTonePair(background, muted),
      UiTone.tint => UiTonePair(tint, tintText),
      UiTone.primary => UiTonePair(primary, onPrimary),
      UiTone.manual => UiTonePair(manualBg, manualText),
      UiTone.absent => UiTonePair(absentBg, absentText),
    };
  }

  static const light = UiColors(
    background: Color(0xFFF3F6F6),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF10262B),
    muted: Color(0xFF51666B),
    line: Color(0xFFDDE5E6),
    primary: Color(0xFF1F7A87),
    onPrimary: Color(0xFFFFFFFF),
    primaryText: Color(0xFF17616C),
    veil: Color(0x38FFFFFF),
    tint: Color(0xFFE3F1F3),
    tintText: Color(0xFF17616C),
    manualBg: Color(0xFFFCF1DD),
    manualText: Color(0xFF7A4E08),
    absentBg: Color(0xFFFBE9E6),
    absentText: Color(0xFFA23A2B),
    presentDot: Color(0xFF4CA4B0),
    manualDot: Color(0xFFE8A44C),
    absentDot: Color(0xFFD46454),
  );

  static const dark = UiColors(
    background: Color(0xFF0C1719),
    surface: Color(0xFF142326),
    ink: Color(0xFFEEF5F6),
    muted: Color(0xFF9DB3B7),
    line: Color(0xFF24383C),
    primary: Color(0xFF4CA4B0),
    onPrimary: Color(0xFF06181B),
    primaryText: Color(0xFF7CC7D1),
    veil: Color(0x2906181B),
    tint: Color(0xFF18363B),
    tintText: Color(0xFF8BD0DA),
    manualBg: Color(0xFF3A2C12),
    manualText: Color(0xFFF0BE72),
    absentBg: Color(0xFF3B1E19),
    absentText: Color(0xFFF0958A),
    presentDot: Color(0xFF4CA4B0),
    manualDot: Color(0xFFE8A44C),
    absentDot: Color(0xFFD46454),
  );

  @override
  UiColors copyWith() => this;

  @override
  UiColors lerp(ThemeExtension<UiColors>? other, double t) {
    if (other is! UiColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return UiColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryText: mix(primaryText, other.primaryText),
      veil: mix(veil, other.veil),
      tint: mix(tint, other.tint),
      tintText: mix(tintText, other.tintText),
      manualBg: mix(manualBg, other.manualBg),
      manualText: mix(manualText, other.manualText),
      absentBg: mix(absentBg, other.absentBg),
      absentText: mix(absentText, other.absentText),
      presentDot: mix(presentDot, other.presentDot),
      manualDot: mix(manualDot, other.manualDot),
      absentDot: mix(absentDot, other.absentDot),
    );
  }
}
