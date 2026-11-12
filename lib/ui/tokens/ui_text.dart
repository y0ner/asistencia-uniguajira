import 'package:flutter/painting.dart';

/// Estilos de texto (Figtree). No llevan color: lo heredan del tema o se
/// ajusta con `.copyWith(color: …)` usando `UiColors`.
abstract final class UiText {
  static const String family = 'Figtree';

  static const _tabular = [FontFeature.tabularFigures()];

  /// Momento grande: "¡Presente!".
  static const display = TextStyle(
    fontFamily: family, fontSize: 54, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: -1.6);

  /// Título de pantalla.
  static const h1 = TextStyle(
    fontFamily: family, fontSize: 30, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -0.6);

  /// Título de tarjeta destacada o de barra superior.
  static const h2 = TextStyle(
    fontFamily: family, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.4);

  /// Título de fila, tarjeta o sección.
  static const title = TextStyle(
    fontFamily: family, fontSize: 17, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.2);

  static const body = TextStyle(
    fontFamily: family, fontSize: 15, height: 1.45, fontWeight: FontWeight.w400);

  static const bodyStrong = TextStyle(
    fontFamily: family, fontSize: 15, height: 1.3, fontWeight: FontWeight.w600);

  /// Texto de apoyo de una fila o etiqueta de un dato.
  static const label = TextStyle(
    fontFamily: family, fontSize: 13, height: 1.3, fontWeight: FontWeight.w500);

  /// Pastillas y textos muy pequeños.
  static const caption = TextStyle(
    fontFamily: family, fontSize: 12, height: 1.3, fontWeight: FontWeight.w700);

  static const button = TextStyle(
    fontFamily: family, fontSize: 16, height: 1.2, fontWeight: FontWeight.w700);

  /// Dígitos del PIN.
  static const numberXl = TextStyle(
    fontFamily: family, fontSize: 64, height: 1.0, fontWeight: FontWeight.w800,
    letterSpacing: -1.2, fontFeatures: _tabular);

  /// Conteo dentro del anillo.
  static const numberLg = TextStyle(
    fontFamily: family, fontSize: 38, height: 1.0, fontWeight: FontWeight.w800,
    letterSpacing: -1.0, fontFeatures: _tabular);

  /// Cifra de una ficha de estadística.
  static const numberMd = TextStyle(
    fontFamily: family, fontSize: 26, height: 1.0, fontWeight: FontWeight.w800,
    letterSpacing: -0.5, fontFeatures: _tabular);
}
