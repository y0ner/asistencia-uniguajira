import 'package:flutter/material.dart';

/// Valores estéticos crudos (Tier 1).
///
/// Este es el ÚNICO archivo del proyecto autorizado para definir literales
/// numéricos de color (Color(0x...)).
///
/// Nombrados por valor medido o identificador unívoco de escala, garantizando
/// que los tokens semánticos (Tier 2) y los temas claro/oscuro los consuman
/// de forma consistente y verificable.
abstract final class Primitives {
  // --- Colores Institucionales Uniguajira ---
  static const Color brandBlue900 = Color(0xFF001F5C);
  static const Color brandBlue700 = Color(0xFF0033A0); // Azul Oficial Uniguajira
  static const Color brandBlue600 = Color(0xFF0E4AC4);
  static const Color brandBlue500 = Color(0xFF1D58D8);
  static const Color brandBlue400 = Color(0xFF3B82F6);
  static const Color brandBlue300 = Color(0xFF6889F7);
  static const Color brandBlue100 = Color(0xFFDBEAFE);
  static const Color brandBlue50  = Color(0xFFEFF6FF);

  static const Color brandGold800 = Color(0xFF8C6400);
  static const Color brandGold700 = Color(0xFFB48200);
  static const Color brandGold500 = Color(0xFFEAAA00); // Dorado Oficial Uniguajira
  static const Color brandGold300 = Color(0xFFF7D154);
  static const Color brandGold200 = Color(0xFFFDE68A);
  static const Color brandGold100 = Color(0xFFFEF3C7);
  static const Color brandGold50  = Color(0xFFFFFBEB);

  // --- Estados de Asistencia Académica ---
  // Normal / Presente (< 15% inasistencias): Esmeralda
  static const Color statusEmerald800 = Color(0xFF065F46);
  static const Color statusEmerald700 = Color(0xFF047857);
  static const Color statusEmerald500 = Color(0xFF10B981);
  static const Color statusEmerald300 = Color(0xFF6EE7B7);
  static const Color statusEmerald100 = Color(0xFFD1FAE5);
  static const Color statusEmerald50  = Color(0xFFECFDF5);

  // Alerta (15% - 24% inasistencias): Ámbar
  static const Color statusAmber800 = Color(0xFF92400E);
  static const Color statusAmber700 = Color(0xFFB45309);
  static const Color statusAmber500 = Color(0xFFF59E0B);
  static const Color statusAmber300 = Color(0xFFFCD34D);
  static const Color statusAmber100 = Color(0xFFFEF3C7);
  static const Color statusAmber50  = Color(0xFFFFFBEB);

  // Pérdida (>= 25% inasistencias / Fallas críticas): Carmesí
  static const Color statusRose800 = Color(0xFF9F1239);
  static const Color statusRose700 = Color(0xFFBE123C);
  static const Color statusRose500 = Color(0xFFF43F5E);
  static const Color statusRose300 = Color(0xFFFDA4AF);
  static const Color statusRose100 = Color(0xFFFFE4E6);
  static const Color statusRose50  = Color(0xFFFFF1F2);

  // --- Funcionalidades Especiales ---
  // Baliza BLE / Radar de proximidad: Azul Celeste
  static const Color bleSky800 = Color(0xFF075985);
  static const Color bleSky700 = Color(0xFF0369A1);
  static const Color bleSky500 = Color(0xFF0EA5E9);
  static const Color bleSky300 = Color(0xFF7DD3FC);
  static const Color bleSky100 = Color(0xFFE0F2FE);
  static const Color bleSky50  = Color(0xFFF0F9FF);

  // Lista Invertida / Modo Manual Excepcional: Violeta
  static const Color manualViolet800 = Color(0xFF5B21B6);
  static const Color manualViolet700 = Color(0xFF6D28D9);
  static const Color manualViolet500 = Color(0xFF8B5CF6);
  static const Color manualViolet300 = Color(0xFFC4B5FD);
  static const Color manualViolet100 = Color(0xFFEDE9FE);
  static const Color manualViolet50  = Color(0xFFF5F3FF);

  // --- Neutros y Superficies (Escala Luminancia OKLCH/Slate) ---
  static const Color neutral000 = Color(0xFF000000);
  static const Color neutral030 = Color(0xFF070B14); // Fondo ultra oscuro
  static const Color neutral050 = Color(0xFF0B1120); // Fondo oscuro principal
  static const Color neutral080 = Color(0xFF131B2E); // Superficie tarjeta oscura
  static const Color neutral120 = Color(0xFF1E293B); // Contenedor oscuro alto
  static const Color neutral160 = Color(0xFF334155); // Borde / Separador oscuro
  static const Color neutral250 = Color(0xFF475569); // Texto secundario oscuro
  static const Color neutral400 = Color(0xFF64748B); // Texto atenuado claro
  static const Color neutral600 = Color(0xFF94A3B8); // Texto secundario claro / borde
  static const Color neutral800 = Color(0xFFCBD5E1); // Borde claro
  static const Color neutral880 = Color(0xFFE2E8F0); // Borde sutil
  static const Color neutral930 = Color(0xFFF1F5F9); // Fondo contenedor claro
  static const Color neutral960 = Color(0xFFF8FAFC); // Fondo pantalla claro
  static const Color neutral1000 = Color(0xFFFFFFFF); // Blanco puro
}
