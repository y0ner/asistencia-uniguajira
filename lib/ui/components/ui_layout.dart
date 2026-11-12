import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';
import 'ui_button.dart';

/// Ruta del escudo institucional empaquetado en la app.
const String uiBrandEmblemAsset = 'assets/brand/escudo_uniguajira.png';

/// Estructura de toda pantalla: encabezado fijo, cuerpo y zona inferior para
/// la acción principal (al alcance del pulgar).
class UiPage extends StatelessWidget {
  const UiPage({super.key, this.header, required this.body, this.bottom});

  /// [UiBrandHeader] en las pantallas de inicio; [UiTopBar] en las demás.
  final Widget? header;

  /// Contenido. Si debe desplazarse, pasa un `ListView` o `SingleChildScrollView`.
  final Widget body;

  /// Acción principal o barra de acciones. Lleva su propio margen.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.of(context).background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            Expanded(child: body),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(UiSpace.page, UiSpace.md, UiSpace.page, UiSpace.xxl),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

/// Encabezado de las pantallas de inicio: escudo, nombre de la app y una acción.
class UiBrandHeader extends StatelessWidget {
  const UiBrandHeader({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.page, 14, UiSpace.page, 10),
      child: Row(
        children: [
          Container(
            width: UiSize.touch,
            height: UiSize.touch,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Image.asset(
              uiBrandEmblemAsset,
              width: 24,
              height: 32,
              fit: BoxFit.contain,
              semanticLabel: 'Escudo de la Universidad de La Guajira',
            ),
          ),
          const SizedBox(width: UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asistencia', style: UiText.title.copyWith(color: c.ink)),
                Text(
                  'Universidad de La Guajira',
                  style: UiText.caption.copyWith(color: c.muted, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Barra superior de las pantallas internas.
class UiTopBar extends StatelessWidget {
  const UiTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.close = false,
    this.backTooltip,
    this.trailing,
    this.below,
    this.titleMaxLines = 2,
  });

  final String title;

  /// Líneas del título. Usa 1 en pantallas que necesitan todo el alto
  /// (p. ej. el teclado del PIN).
  final int titleMaxLines;
  final String? subtitle;

  /// Si es nulo, no se muestra el botón de volver.
  final VoidCallback? onBack;

  /// Muestra una X en vez de la flecha (para flujos que se cancelan).
  final bool close;
  final String? backTooltip;
  final Widget? trailing;

  /// Widget bajo el título (p. ej. [UiStepBar]).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.page, 14, UiSpace.page, 10),
      child: Row(
        children: [
          if (onBack != null) ...[
            UiRoundIconButton(
              icon: close ? Icons.close_rounded : Icons.arrow_back_rounded,
              tooltip: backTooltip ?? (close ? 'Cerrar' : 'Volver'),
              onPressed: onBack,
            ),
            const SizedBox(width: UiSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: UiText.h2.copyWith(color: c.ink),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: UiText.label.copyWith(color: c.muted),
                  ),
                if (below != null) Padding(padding: const EdgeInsets.only(top: 6), child: below),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: UiSpace.md), trailing!],
        ],
      ),
    );
  }
}

/// Saludo o pregunta grande al inicio de una pantalla.
class UiPageHeading extends StatelessWidget {
  const UiPageHeading({super.key, this.overline, required this.title});

  /// Línea pequeña sobre el título (fecha, saludo).
  final String? overline;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.page, 14, UiSpace.page, UiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overline != null)
            Padding(
              padding: const EdgeInsets.only(bottom: UiSpace.xs),
              child: Text(overline!, style: UiText.label.copyWith(color: c.muted)),
            ),
          Semantics(header: true, child: Text(title, style: UiText.h1.copyWith(color: c.ink))),
        ],
      ),
    );
  }
}

/// Título de una sección dentro de la pantalla.
class UiSectionTitle extends StatelessWidget {
  const UiSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.page, UiSpace.xl, UiSpace.page, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: UiText.title.copyWith(color: c.ink)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
