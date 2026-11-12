import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';

/// Estados de asistencia que se muestran al usuario.
enum UiStatus {
  /// Confirmado por Bluetooth.
  present,

  /// Marcado a mano por el docente.
  manual,

  /// No asistió (sesión cerrada).
  absent,

  /// Aún no llega (sesión abierta).
  pending,
}

/// Pastilla de estado: siempre lleva ícono **y** palabra (nunca solo color).
class UiStatusChip extends StatelessWidget {
  const UiStatusChip({super.key, required this.status, this.label, this.solid = false});

  final UiStatus status;

  /// Texto alterno. Por defecto: "Presente", "A mano", "Falta", "Aún no llega".
  final String? label;

  /// Fondo turquesa pleno, para resaltar al que acaba de llegar.
  final bool solid;

  static String defaultLabel(UiStatus status) => switch (status) {
        UiStatus.present => 'Presente',
        UiStatus.manual => 'A mano',
        UiStatus.absent => 'Falta',
        UiStatus.pending => 'Aún no llega',
      };

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final (UiTone tone, IconData icon) = switch (status) {
      UiStatus.present => (solid ? UiTone.primary : UiTone.tint, Icons.check_rounded),
      UiStatus.manual => (UiTone.manual, Icons.edit_rounded),
      UiStatus.absent => (UiTone.absent, Icons.close_rounded),
      UiStatus.pending => (UiTone.neutral, Icons.schedule_rounded),
    };
    final pair = c.tone(tone);
    return UiPill(
      label: label ?? defaultLabel(status),
      icon: icon,
      background: pair.background,
      foreground: pair.foreground,
    );
  }
}

/// Pastilla genérica (etiquetas como "Nueva", "En vivo · 08:42", "PIN 47").
class UiPill extends StatelessWidget {
  const UiPill({
    super.key,
    required this.label,
    this.icon,
    this.dot = false,
    this.tone = UiTone.tint,
    this.background,
    this.foreground,
  });

  final String label;
  final IconData? icon;

  /// Punto a la izquierda (indicador "en vivo").
  final bool dot;
  final UiTone tone;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final pair = UiColors.of(context).tone(tone);
    final bg = background ?? pair.background;
    final fg = foreground ?? pair.foreground;
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(UiRadius.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              DecoratedBox(
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                child: const SizedBox(width: 7, height: 7),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: UiSpace.xs),
            ],
            Text(label, style: UiText.caption.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Círculo (o ficha cuadrada) con las iniciales de una persona o clase.
class UiAvatar extends StatelessWidget {
  const UiAvatar({
    super.key,
    required this.name,
    this.tone = UiTone.tint,
    this.square = false,
    this.size,
  });

  final String name;
  final UiTone tone;

  /// Ficha cuadrada redondeada: para clases. Círculo: para personas.
  final bool square;
  final double? size;

  /// Palabras que no aportan inicial ("Ingeniería de Software" → "IS").
  static const _connectors = {'de', 'del', 'la', 'las', 'los', 'el', 'y', 'e', 'en', 'a', 'para'};

  /// Iniciales de las dos primeras palabras con contenido ("Ana Lucía Pérez" → "AL").
  static String initialsOf(String name) {
    final all = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final meaningful = all.where((w) => !_connectors.contains(w.toLowerCase())).toList();
    final words = meaningful.isEmpty ? all : meaningful;
    if (words.isEmpty) return '?';
    final first = words.first.characters.first;
    final second = words.length > 1 ? words[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final pair = UiColors.of(context).tone(tone);
    final side = size ?? (square ? UiSize.badge : UiSize.avatar);
    return ExcludeSemantics(
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pair.background,
          borderRadius: BorderRadius.circular(square ? 14 : UiRadius.pill),
        ),
        child: Text(
          initialsOf(name),
          style: UiText.label.copyWith(color: pair.foreground, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Fila de puntos con el historial de asistencia (turquesa = fue, coral = faltó).
class UiHistoryDots extends StatelessWidget {
  const UiHistoryDots({super.key, required this.attended});

  /// Una entrada por clase, de la más antigua a la más reciente.
  final List<bool> attended;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final went = attended.where((a) => a).length;
    return Semantics(
      label: '$went de ${attended.length} clases asistidas',
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final a in attended)
            DecoratedBox(
              decoration: BoxDecoration(
                color: a ? c.presentDot : c.absentDot,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 12, height: 12),
            ),
        ],
      ),
    );
  }
}
