import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';

/// Tarjeta base: superficie con borde fino y esquinas suaves.
class UiCard extends StatelessWidget {
  const UiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(UiSpace.lg),
    this.onTap,
    this.tone,
    this.radius = UiRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Si se indica, la tarjeta toma el fondo de ese tono (sin borde).
  final UiTone? tone;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final pair = tone == null ? null : c.tone(tone!);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: pair == null ? BorderSide(color: c.line) : BorderSide.none,
    );
    Widget content = Padding(padding: padding, child: child);
    if (pair != null) {
      content = DefaultTextStyle.merge(
        style: TextStyle(color: pair.foreground),
        child: IconTheme.merge(data: IconThemeData(color: pair.foreground), child: content),
      );
    }
    return Material(
      color: pair?.background ?? c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Tarjeta destacada en turquesa, con el motivo del escudo en una esquina.
///
/// Úsala para **una** cosa por pantalla: la sesión en curso, "Tomar
/// asistencia" o el resultado "¡Presente!". El texto hereda el color correcto.
class UiHeroCard extends StatelessWidget {
  const UiHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(UiSpace.xl),
    this.onTap,
    this.motifSize = 150,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double motifSize;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final content = Stack(
      children: [
        Positioned(
          right: -motifSize * 0.3,
          top: -motifSize * 0.3,
          child: ExcludeSemantics(
            child: CustomPaint(
              size: Size.square(motifSize),
              painter: UiWeaveMotifPainter(color: c.onPrimary.withValues(alpha: 0.16)),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
    return Material(
      color: c.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: c.onPrimary),
        child: IconTheme.merge(
          data: IconThemeData(color: c.onPrimary),
          child: onTap == null ? content : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// Rectángulos concéntricos inspirados en el tejido del escudo institucional.
class UiWeaveMotifPainter extends CustomPainter {
  const UiWeaveMotifPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 150;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * unit;
    const insets = [5.0, 25.0, 45.0, 63.0];
    const radii = [8.0, 6.0, 4.0, 2.0];
    for (var i = 0; i < insets.length; i++) {
      final inset = insets[i] * unit;
      final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radii[i] * unit)), paint);
    }
  }

  @override
  bool shouldRepaint(UiWeaveMotifPainter oldDelegate) => oldDelegate.color != color;
}
