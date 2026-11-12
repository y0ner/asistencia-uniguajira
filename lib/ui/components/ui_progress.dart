import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';

/// Anillo de progreso con contenido en el centro (conteo de la sesión).
class UiProgressRing extends StatelessWidget {
  const UiProgressRing({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.size = 116,
    this.strokeWidth = 11,
    this.child,
  });

  /// De 0 a 1.
  final double value;

  /// Descripción completa, p. ej. "19 de 32 estudiantes presentes".
  final String semanticLabel;
  final double size;
  final double strokeWidth;
  final Widget? child;

  /// Anillo con "N" grande y "de M" debajo.
  factory UiProgressRing.count({Key? key, required int count, required int total, double size = 116}) {
    return UiProgressRing(
      key: key,
      value: total == 0 ? 0 : count / total,
      size: size,
      semanticLabel: '$count de $total presentes',
      child: Builder(
        builder: (context) {
          final c = UiColors.of(context);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count', style: UiText.numberLg.copyWith(color: c.ink)),
              Text('de $total', style: UiText.label.copyWith(color: c.muted)),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : UiMotion.slow,
            curve: UiMotion.curve,
            builder: (context, animated, inner) => CustomPaint(
              painter: _RingPainter(
                value: animated,
                track: c.line,
                color: c.primary,
                strokeWidth: strokeWidth,
              ),
              child: inner,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.track,
    required this.color,
    required this.strokeWidth,
  });

  final double value;
  final Color track;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, base);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.color != color || old.strokeWidth != strokeWidth;
}

/// Barra de progreso redondeada.
class UiProgressBar extends StatelessWidget {
  const UiProgressBar({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.height = 8,
    this.onHero = false,
  });

  final double value;
  final String semanticLabel;
  final double height;

  /// Colores para usar dentro de una tarjeta turquesa.
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UiRadius.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: onHero ? c.veil : c.line),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0, 1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: onHero ? c.onPrimary : c.primary,
                    borderRadius: BorderRadius.circular(UiRadius.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de pasos ("Paso 2 de 3").
class UiStepBar extends StatelessWidget {
  const UiStepBar({super.key, required this.current, required this.total});

  /// Paso actual, empezando en 1.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: 'Paso $current de $total',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= total; i++) ...[
            AnimatedContainer(
              duration: UiMotion.base,
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: i <= current ? c.primary : c.line,
                borderRadius: BorderRadius.circular(UiRadius.pill),
              ),
            ),
            if (i < total) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}
