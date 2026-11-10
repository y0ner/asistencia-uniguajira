import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'primitives.dart';

/// Tokens semánticos de color (Tier 2).
///
/// Los widgets y vistas consumen ÚNICAMENTE estos slots semánticos mediante
/// `AppColors.of(context)`, desacoplando la lógica de la paleta física y
/// garantizando soporte integral para temas Claro y Oscuro.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerLow,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.outline,
    required this.outlineVariant,
    required this.statusNormal,
    required this.onStatusNormal,
    required this.statusNormalContainer,
    required this.onStatusNormalContainer,
    required this.statusAlerta,
    required this.onStatusAlerta,
    required this.statusAlertaContainer,
    required this.onStatusAlertaContainer,
    required this.statusPerdida,
    required this.onStatusPerdida,
    required this.statusPerdidaContainer,
    required this.onStatusPerdidaContainer,
    required this.bleAccent,
    required this.onBleAccent,
    required this.bleAccentContainer,
    required this.onBleAccentContainer,
    required this.manualAccent,
    required this.onManualAccent,
    required this.manualAccentContainer,
    required this.onManualAccentContainer,
    required this.cardGradientStart,
    required this.cardGradientEnd,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.divider,
    required this.hairlineWidth,
  });

  final Color surface;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerLow;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color outline;
  final Color outlineVariant;

  final Color statusNormal;
  final Color onStatusNormal;
  final Color statusNormalContainer;
  final Color onStatusNormalContainer;

  final Color statusAlerta;
  final Color onStatusAlerta;
  final Color statusAlertaContainer;
  final Color onStatusAlertaContainer;

  final Color statusPerdida;
  final Color onStatusPerdida;
  final Color statusPerdidaContainer;
  final Color onStatusPerdidaContainer;

  final Color bleAccent;
  final Color onBleAccent;
  final Color bleAccentContainer;
  final Color onBleAccentContainer;

  final Color manualAccent;
  final Color onManualAccent;
  final Color manualAccentContainer;
  final Color onManualAccentContainer;

  final Color cardGradientStart;
  final Color cardGradientEnd;
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final Color divider;
  final double hairlineWidth;

  /// Obtiene la instancia de [AppColors] vinculada al contexto actual.
  ///
  /// Falla ruidosamente con una aserción clara si el tema no ha sido inyectado
  /// con [buildLightTheme] o [buildDarkTheme].
  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    assert(
      ext != null,
      'AppColors no encontrado en el contexto. Asegúrate de configurar MaterialApp '
      'con buildLightTheme() y buildDarkTheme().',
    );
    return ext!;
  }

  @override
  AppColors copyWith({
    Color? surface,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerLow,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? outline,
    Color? outlineVariant,
    Color? statusNormal,
    Color? onStatusNormal,
    Color? statusNormalContainer,
    Color? onStatusNormalContainer,
    Color? statusAlerta,
    Color? onStatusAlerta,
    Color? statusAlertaContainer,
    Color? onStatusAlertaContainer,
    Color? statusPerdida,
    Color? onStatusPerdida,
    Color? statusPerdidaContainer,
    Color? onStatusPerdidaContainer,
    Color? bleAccent,
    Color? onBleAccent,
    Color? bleAccentContainer,
    Color? onBleAccentContainer,
    Color? manualAccent,
    Color? onManualAccent,
    Color? manualAccentContainer,
    Color? onManualAccentContainer,
    Color? cardGradientStart,
    Color? cardGradientEnd,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    Color? divider,
    double? hairlineWidth,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      statusNormal: statusNormal ?? this.statusNormal,
      onStatusNormal: onStatusNormal ?? this.onStatusNormal,
      statusNormalContainer: statusNormalContainer ?? this.statusNormalContainer,
      onStatusNormalContainer: onStatusNormalContainer ?? this.onStatusNormalContainer,
      statusAlerta: statusAlerta ?? this.statusAlerta,
      onStatusAlerta: onStatusAlerta ?? this.onStatusAlerta,
      statusAlertaContainer: statusAlertaContainer ?? this.statusAlertaContainer,
      onStatusAlertaContainer: onStatusAlertaContainer ?? this.onStatusAlertaContainer,
      statusPerdida: statusPerdida ?? this.statusPerdida,
      onStatusPerdida: onStatusPerdida ?? this.onStatusPerdida,
      statusPerdidaContainer: statusPerdidaContainer ?? this.statusPerdidaContainer,
      onStatusPerdidaContainer: onStatusPerdidaContainer ?? this.onStatusPerdidaContainer,
      bleAccent: bleAccent ?? this.bleAccent,
      onBleAccent: onBleAccent ?? this.onBleAccent,
      bleAccentContainer: bleAccentContainer ?? this.bleAccentContainer,
      onBleAccentContainer: onBleAccentContainer ?? this.onBleAccentContainer,
      manualAccent: manualAccent ?? this.manualAccent,
      onManualAccent: onManualAccent ?? this.onManualAccent,
      manualAccentContainer: manualAccentContainer ?? this.manualAccentContainer,
      onManualAccentContainer: onManualAccentContainer ?? this.onManualAccentContainer,
      cardGradientStart: cardGradientStart ?? this.cardGradientStart,
      cardGradientEnd: cardGradientEnd ?? this.cardGradientEnd,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      divider: divider ?? this.divider,
      hairlineWidth: hairlineWidth ?? this.hairlineWidth,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh: Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerLow: Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      secondaryContainer: Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      onSecondaryContainer: Color.lerp(onSecondaryContainer, other.onSecondaryContainer, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      statusNormal: Color.lerp(statusNormal, other.statusNormal, t)!,
      onStatusNormal: Color.lerp(onStatusNormal, other.onStatusNormal, t)!,
      statusNormalContainer: Color.lerp(statusNormalContainer, other.statusNormalContainer, t)!,
      onStatusNormalContainer: Color.lerp(onStatusNormalContainer, other.onStatusNormalContainer, t)!,
      statusAlerta: Color.lerp(statusAlerta, other.statusAlerta, t)!,
      onStatusAlerta: Color.lerp(onStatusAlerta, other.onStatusAlerta, t)!,
      statusAlertaContainer: Color.lerp(statusAlertaContainer, other.statusAlertaContainer, t)!,
      onStatusAlertaContainer: Color.lerp(onStatusAlertaContainer, other.onStatusAlertaContainer, t)!,
      statusPerdida: Color.lerp(statusPerdida, other.statusPerdida, t)!,
      onStatusPerdida: Color.lerp(onStatusPerdida, other.onStatusPerdida, t)!,
      statusPerdidaContainer: Color.lerp(statusPerdidaContainer, other.statusPerdidaContainer, t)!,
      onStatusPerdidaContainer: Color.lerp(onStatusPerdidaContainer, other.onStatusPerdidaContainer, t)!,
      bleAccent: Color.lerp(bleAccent, other.bleAccent, t)!,
      onBleAccent: Color.lerp(onBleAccent, other.onBleAccent, t)!,
      bleAccentContainer: Color.lerp(bleAccentContainer, other.bleAccentContainer, t)!,
      onBleAccentContainer: Color.lerp(onBleAccentContainer, other.onBleAccentContainer, t)!,
      manualAccent: Color.lerp(manualAccent, other.manualAccent, t)!,
      onManualAccent: Color.lerp(onManualAccent, other.onManualAccent, t)!,
      manualAccentContainer: Color.lerp(manualAccentContainer, other.manualAccentContainer, t)!,
      onManualAccentContainer: Color.lerp(onManualAccentContainer, other.onManualAccentContainer, t)!,
      cardGradientStart: Color.lerp(cardGradientStart, other.cardGradientStart, t)!,
      cardGradientEnd: Color.lerp(cardGradientEnd, other.cardGradientEnd, t)!,
      heroGradientStart: Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      hairlineWidth: lerpDouble(hairlineWidth, other.hairlineWidth, t)!,
    );
  }
}

/// Instancia de tokens para Tema Claro.
const lightAppColors = AppColors(
  surface: Primitives.neutral960,
  onSurface: Primitives.neutral050,
  onSurfaceMuted: Primitives.neutral400,
  surfaceContainer: Primitives.neutral1000,
  surfaceContainerHigh: Primitives.neutral930,
  surfaceContainerLow: Primitives.neutral960,
  primary: Primitives.brandBlue700,
  onPrimary: Primitives.neutral1000,
  primaryContainer: Primitives.brandBlue50,
  onPrimaryContainer: Primitives.brandBlue900,
  secondary: Primitives.brandGold500,
  onSecondary: Primitives.neutral000,
  secondaryContainer: Primitives.brandGold100,
  onSecondaryContainer: Primitives.brandGold800,
  outline: Primitives.neutral800,
  outlineVariant: Primitives.neutral880,
  statusNormal: Primitives.statusEmerald700,
  onStatusNormal: Primitives.neutral1000,
  statusNormalContainer: Primitives.statusEmerald50,
  onStatusNormalContainer: Primitives.statusEmerald800,
  statusAlerta: Primitives.statusAmber700,
  onStatusAlerta: Primitives.neutral1000,
  statusAlertaContainer: Primitives.statusAmber50,
  onStatusAlertaContainer: Primitives.statusAmber800,
  statusPerdida: Primitives.statusRose700,
  onStatusPerdida: Primitives.neutral1000,
  statusPerdidaContainer: Primitives.statusRose50,
  onStatusPerdidaContainer: Primitives.statusRose800,
  bleAccent: Primitives.bleSky700,
  onBleAccent: Primitives.neutral1000,
  bleAccentContainer: Primitives.bleSky50,
  onBleAccentContainer: Primitives.bleSky800,
  manualAccent: Primitives.manualViolet700,
  onManualAccent: Primitives.neutral1000,
  manualAccentContainer: Primitives.manualViolet50,
  onManualAccentContainer: Primitives.manualViolet800,
  cardGradientStart: Primitives.neutral1000,
  cardGradientEnd: Primitives.neutral930,
  heroGradientStart: Primitives.brandBlue900,
  heroGradientEnd: Primitives.brandBlue700,
  divider: Primitives.neutral880,
  hairlineWidth: 1.0,
);

/// Instancia de tokens para Tema Oscuro.
const darkAppColors = AppColors(
  surface: Primitives.neutral030,
  onSurface: Primitives.neutral930,
  onSurfaceMuted: Primitives.neutral600,
  surfaceContainer: Primitives.neutral080,
  surfaceContainerHigh: Primitives.neutral120,
  surfaceContainerLow: Primitives.neutral050,
  primary: Primitives.brandBlue400, // Luminancia elevada para AA sobre oscuro
  onPrimary: Primitives.neutral000,
  primaryContainer: Primitives.brandBlue900,
  onPrimaryContainer: Primitives.brandBlue100,
  secondary: Primitives.brandGold300,
  onSecondary: Primitives.neutral000,
  secondaryContainer: Primitives.brandGold800,
  onSecondaryContainer: Primitives.brandGold200,
  outline: Primitives.neutral160,
  outlineVariant: Primitives.neutral120,
  statusNormal: Primitives.statusEmerald500,
  onStatusNormal: Primitives.neutral000,
  statusNormalContainer: Primitives.statusEmerald800,
  onStatusNormalContainer: Primitives.statusEmerald100,
  statusAlerta: Primitives.statusAmber500,
  onStatusAlerta: Primitives.neutral000,
  statusAlertaContainer: Primitives.statusAmber800,
  onStatusAlertaContainer: Primitives.statusAmber100,
  statusPerdida: Primitives.statusRose500,
  onStatusPerdida: Primitives.neutral000,
  statusPerdidaContainer: Primitives.statusRose800,
  onStatusPerdidaContainer: Primitives.statusRose100,
  bleAccent: Primitives.bleSky500,
  onBleAccent: Primitives.neutral000,
  bleAccentContainer: Primitives.bleSky800,
  onBleAccentContainer: Primitives.bleSky100,
  manualAccent: Primitives.manualViolet500,
  onManualAccent: Primitives.neutral000,
  manualAccentContainer: Primitives.manualViolet800,
  onManualAccentContainer: Primitives.manualViolet100,
  cardGradientStart: Primitives.neutral080,
  cardGradientEnd: Primitives.neutral050,
  heroGradientStart: Primitives.neutral050,
  heroGradientEnd: Primitives.neutral080,
  divider: Primitives.neutral160,
  hairlineWidth: 1.0,
);
