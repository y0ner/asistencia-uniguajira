import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';

/// Dibujo de dos celulares con ondas de señal entre ellos.
///
/// Explica el gesto de acercar el celular. `signal` va de 0 (sin señal) a 3
/// (muy cerca). Mientras busca, las ondas se encienden una tras otra; con
/// "reducir movimiento" activado se quedan quietas.
class UiTwoPhones extends StatefulWidget {
  const UiTwoPhones({
    super.key,
    this.signal = 2,
    this.searching = true,
    this.leftLabel = 'Tú',
    this.rightLabel = 'Profesor',
  });

  final int signal;
  final bool searching;
  final String leftLabel;
  final String rightLabel;

  @override
  State<UiTwoPhones> createState() => _UiTwoPhonesState();
}

class _UiTwoPhonesState extends State<UiTwoPhones> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(UiTwoPhones oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.searching && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: 'Tu celular enviando señal al celular del profesor',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _phone(c, label: widget.leftLabel, filled: false),
            const SizedBox(width: UiSpace.md),
            Padding(
              padding: const EdgeInsets.only(bottom: UiSpace.xxl),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: const Size(64, 72),
                  painter: _WavesPainter(
                    signal: widget.signal.clamp(0, 3),
                    phase: _controller.isAnimating ? _controller.value : null,
                    on: c.primary,
                    off: c.line,
                  ),
                ),
              ),
            ),
            const SizedBox(width: UiSpace.md),
            _phone(c, label: widget.rightLabel, filled: true),
          ],
        ),
      ),
    );
  }

  Widget _phone(UiColors c, {required String label, required bool filled}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 108,
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: UiSpace.sm),
          decoration: BoxDecoration(
            color: filled ? c.primary : c.surface,
            borderRadius: BorderRadius.circular(UiRadius.md),
            border: filled ? null : Border.all(color: c.ink, width: 2.5),
          ),
          child: Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(
              color: filled ? c.onPrimary : c.ink,
              borderRadius: BorderRadius.circular(UiRadius.pill),
            ),
          ),
        ),
        const SizedBox(height: UiSpace.sm),
        Text(label, style: UiText.label.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _WavesPainter extends CustomPainter {
  const _WavesPainter({required this.signal, required this.phase, required this.on, required this.off});

  final int signal;

  /// De 0 a 1 mientras se anima; nulo si está quieto.
  final double? phase;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final origin = Offset(-4, size.height / 2);
    const radii = [16.0, 30.0, 46.0];
    for (var i = 0; i < radii.length; i++) {
      var color = i < signal ? on : off;
      if (phase != null && i < signal) {
        // Cada onda se atenúa a su turno para dar sensación de pulso.
        final local = (phase! * radii.length - i) % radii.length;
        final strength = local < 1 ? 1.0 : 0.45;
        color = on.withValues(alpha: strength);
      }
      paint.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radii[i]),
        -math.pi / 3.2,
        2 * math.pi / 3.2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) =>
      old.signal != signal || old.phase != phase || old.on != on || old.off != off;
}
