import 'package:flutter/material.dart';

/// Tokens de animación y movimiento (Tier 2).
///
/// Implementa soporte obligatorio para accesibilidad: ante la preferencia del
/// sistema operativo de movimiento reducido (`disableAnimationsOf`),
/// las duraciones colapsan inmediatamente a [Duration.zero].
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({
    this.fast = const Duration(milliseconds: 150),
    this.normal = const Duration(milliseconds: 250),
    this.slow = const Duration(milliseconds: 400),
    this.standard = Curves.easeInOutCubic,
    this.enter = Curves.easeOutCubic,
    this.exit = Curves.easeInCubic,
  });

  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve standard;
  final Curve enter;
  final Curve exit;

  /// Resuelve la duración considerando la accesibilidad del usuario.
  ///
  /// Si el sistema operativo tiene activada la reducción de movimiento,
  /// retorna [Duration.zero].
  static Duration resolve(BuildContext context, Duration fullDuration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : fullDuration;
  }

  /// Obtiene la instancia de [AppMotion] vinculada al contexto actual.
  static AppMotion of(BuildContext context) {
    final ext = Theme.of(context).extension<AppMotion>();
    assert(
      ext != null,
      'AppMotion no encontrado en el contexto. Asegúrate de configurar MaterialApp '
      'con buildLightTheme() y buildDarkTheme().',
    );
    return ext!;
  }

  @override
  AppMotion copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Curve? standard,
    Curve? enter,
    Curve? exit,
  }) {
    return AppMotion(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      standard: standard ?? this.standard,
      enter: enter ?? this.enter,
      exit: exit ?? this.exit,
    );
  }

  @override
  AppMotion lerp(covariant AppMotion? other, double t) {
    if (other == null) return this;
    // Las curvas y duraciones conmutan discretamente en el punto medio
    return t < 0.5 ? this : other;
  }
}

const defaultAppMotion = AppMotion();
