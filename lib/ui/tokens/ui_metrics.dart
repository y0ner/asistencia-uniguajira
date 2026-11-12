import 'package:flutter/animation.dart';

/// Escala de espaciado. No uses números sueltos en `EdgeInsets` ni `SizedBox`.
abstract final class UiSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Margen lateral de todas las pantallas.
  static const double page = 20;
}

/// Radios de esquina.
abstract final class UiRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;
}

/// Tamaños fijos de controles.
abstract final class UiSize {
  /// Área táctil mínima de cualquier control.
  static const double touch = 44;
  static const double button = 56;
  static const double buttonCompact = 48;
  static const double avatar = 38;
  static const double badge = 44;
  static const double row = 62;
}

/// Duraciones y curva de las animaciones.
abstract final class UiMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve curve = Curves.easeOutCubic;
}
