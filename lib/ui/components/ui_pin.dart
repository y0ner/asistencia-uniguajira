import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';

/// PIN de la clase en casillas grandes (pantalla del docente).
class UiPinDisplay extends StatelessWidget {
  const UiPinDisplay({super.key, required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: 'PIN de la clase: ${pin.split('').join(' ')}',
      child: ExcludeSemantics(
        // En celulares angostos las casillas se encogen en vez de desbordarse.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pin.length; i++) ...[
                Container(
                  width: 58,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.tint,
                    borderRadius: BorderRadius.circular(UiRadius.md),
                  ),
                  child: Text(
                    pin[i],
                    style: UiText.numberLg.copyWith(color: c.ink),
                  ),
                ),
                if (i < pin.length - 1) const SizedBox(width: UiSpace.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Casillas donde el estudiante ve el PIN que va escribiendo.
class UiPinEntry extends StatelessWidget {
  const UiPinEntry({
    super.key,
    required this.value,
    this.length = 2,
    this.hasError = false,
  });

  /// Dígitos escritos hasta ahora.
  final String value;
  final int length;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      label: value.isEmpty
          ? 'PIN vacío'
          : 'PIN escrito: ${value.split('').join(' ')}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: UiMotion.fast,
                  height: 112,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      width: 2,
                      color: hasError
                          ? c.absentText
                          : i < value.length
                          ? c.primary
                          : c.line,
                    ),
                  ),
                  child: i < value.length
                      ? Text(
                          value[i],
                          style: UiText.numberXl.copyWith(color: c.ink),
                        )
                      : i == value.length
                      ? Container(
                          width: 4,
                          height: 52,
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )
                      : null,
                ),
              ),
              if (i < length - 1) const SizedBox(width: UiSpace.md),
            ],
          ],
        ),
      ),
    );
  }
}

/// Teclado numérico propio (no abre el teclado del sistema).
class UiPinKeypad extends StatelessWidget {
  const UiPinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          Expanded(child: keys[i]),
          if (i < keys.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
    Widget digit(String d) => _Key(label: d, onTap: () => onDigit(d));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        const SizedBox(height: 10),
        row([digit('4'), digit('5'), digit('6')]),
        const SizedBox(height: 10),
        row([digit('7'), digit('8'), digit('9')]),
        const SizedBox(height: 10),
        row([
          const SizedBox(height: 58),
          digit('0'),
          _Key(
            icon: Icons.backspace_outlined,
            semanticLabel: 'Borrar',
            onTap: onBackspace,
            flat: true,
          ),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.semanticLabel,
    required this.onTap,
    this.flat = false,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onTap;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Material(
        color: flat ? Colors.transparent : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: flat ? BorderSide.none : BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 58,
            child: Center(
              child: label != null
                  ? ExcludeSemantics(
                      child: Text(
                        label!,
                        style: UiText.h2.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Icon(icon, size: 22, color: c.ink),
            ),
          ),
        ),
      ),
    );
  }
}
