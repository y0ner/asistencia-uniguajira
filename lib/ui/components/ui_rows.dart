import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';
import 'ui_status.dart';

/// Tarjeta que agrupa filas y les pone un separador fino entre una y otra.
class UiListGroup extends StatelessWidget {
  const UiListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiRadius.lg),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) Divider(height: 1, thickness: 1, color: c.line),
          ],
        ],
      ),
    );
  }
}

/// Fila de una persona: avatar con iniciales, nombre, detalle y algo a la
/// derecha (una [UiStatusChip] o un botón "Marcar").
class UiPersonRow extends StatelessWidget {
  const UiPersonRow({
    super.key,
    required this.name,
    this.subtitle,
    this.avatarTone = UiTone.tint,
    this.trailing,
    this.highlighted = false,
    this.onTap,
  });

  final String name;
  final String? subtitle;
  final UiTone avatarTone;
  final Widget? trailing;

  /// Resalta la fila (el que acaba de llegar).
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: UiSize.row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.md, vertical: UiSpace.sm),
        child: Row(
          children: [
            UiAvatar(name: name, tone: highlighted ? UiTone.primary : avatarTone),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiText.bodyStrong.copyWith(color: c.ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiText.caption.copyWith(
                        color: highlighted ? c.tintText : c.muted,
                        fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: UiSpace.sm), trailing!],
          ],
        ),
      ),
    );
    return AnimatedContainer(
      duration: UiMotion.base,
      color: highlighted ? c.tint : c.surface,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// Fila "etiqueta → valor" para resúmenes (Clase, Fecha y hora, Confirmó).
class UiInfoRow extends StatelessWidget {
  const UiInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: UiSpace.sm),
        child: Row(
          children: [
            Text(label, style: UiText.label.copyWith(color: c.muted)),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: UiText.bodyStrong.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila que lleva a otra pantalla: título, detalle opcional y algo a la derecha.
class UiNavRow extends StatelessWidget {
  const UiNavRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Por defecto, una flecha.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: UiSpace.sm),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: UiSpace.md)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiText.bodyStrong.copyWith(color: c.ink),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiText.label.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: UiSpace.sm),
              trailing ?? Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ficha de un dato: cifra grande y su nombre debajo.
class UiStatTile extends StatelessWidget {
  const UiStatTile({super.key, required this.value, required this.label, this.tone});

  final String value;
  final String label;

  /// Con [UiTone.absent] la ficha se pinta en coral (dato que preocupa).
  final UiTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final pair = tone == null ? null : c.tone(tone!);
    return Semantics(
      label: '$value $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: pair?.background ?? c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pair?.background ?? c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fichas angostas (tres por fila): con letra grande se encogen
              // en vez de partir la cifra o la palabra en varias líneas.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: UiText.numberMd.copyWith(color: pair?.foreground ?? c.ink),
                ),
              ),
              const SizedBox(height: UiSpace.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: UiText.label.copyWith(
                    color: pair?.foreground ?? c.muted,
                    fontWeight: pair == null ? FontWeight.w500 : FontWeight.w600,
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

/// Una opción de [UiFilterPills].
@immutable
class UiFilterOption<T> {
  const UiFilterOption({required this.value, required this.label});

  final T value;

  /// Texto completo, p. ej. "Faltan 13".
  final String label;
}

/// Filtros en pastillas (uno activo). Se desplaza de lado si no caben.
class UiFilterPills<T> extends StatelessWidget {
  const UiFilterPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<UiFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            _pill(c, options[i]),
            if (i < options.length - 1) const SizedBox(width: UiSpace.sm),
          ],
        ],
      ),
    );
  }

  Widget _pill(UiColors c, UiFilterOption<T> option) {
    final active = option.value == selected;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? c.ink : c.surface,
        shape: StadiumBorder(side: active ? BorderSide.none : BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onSelected(option.value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: UiSize.touch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  option.label,
                  style: UiText.label.copyWith(
                    color: active ? c.background : c.ink,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
