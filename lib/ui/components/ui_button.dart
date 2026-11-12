import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';

/// Variantes de [UiButton].
enum UiButtonVariant {
  /// Acción principal de la pantalla (una sola por pantalla).
  primary,

  /// Acción secundaria con fondo suave.
  tonal,

  /// Acción alterna con borde.
  outline,

  /// Botón claro para usar dentro de una [UiHeroCard].
  onHero,
}

/// Botón del sistema. Mide 56 de alto (48 en `compact`) y ocupa todo el ancho
/// salvo que `expand` sea falso. Con `onPressed` nulo queda deshabilitado.
class UiButton extends StatelessWidget {
  const UiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = UiButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.expand = true,
    this.compact = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final UiButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expand;
  final bool compact;

  /// Muestra un indicador de progreso y bloquea el toque.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      UiButtonVariant.primary => (c.primary, c.onPrimary, BorderSide.none),
      UiButtonVariant.tonal => (c.tint, c.tintText, BorderSide.none),
      UiButtonVariant.outline => (
          Colors.transparent,
          c.primaryText,
          BorderSide(color: c.primary, width: 1.5),
        ),
      UiButtonVariant.onHero => (c.onPrimary, c.primary, BorderSide.none),
    };
    final enabled = onPressed != null && !loading;
    final height = compact ? UiSize.buttonCompact : UiSize.button;
    final radius = BorderRadius.circular(compact ? UiRadius.sm + 2 : UiRadius.md + 2);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (loading || icon != null) const SizedBox(width: UiSpace.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiText.button.copyWith(color: fg),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: UiSpace.sm),
          Icon(trailingIcon, size: 20, color: fg),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: radius, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height, minWidth: UiSize.touch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón redondo de ícono (44 × 44) para barras superiores.
class UiRoundIconButton extends StatelessWidget {
  const UiRoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;

  /// Texto para lectores de pantalla y pulsación larga. Obligatorio.
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: UiSize.touch,
            height: UiSize.touch,
            child: Icon(icon, size: 20, color: c.ink, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}
