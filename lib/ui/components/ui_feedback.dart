import 'package:flutter/material.dart';

import '../tokens/ui_colors.dart';
import '../tokens/ui_metrics.dart';
import '../tokens/ui_text.dart';
import 'ui_button.dart';

/// Estado vacío: un dibujo o ícono, una frase clara y un botón para salir de ahí.
class UiEmptyState extends StatelessWidget {
  const UiEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.illustration,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;

  /// Reemplaza al ícono (p. ej. [UiTwoPhones]).
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(UiSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration ??
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(UiRadius.xxl)),
                  child: Icon(icon ?? Icons.inbox_outlined, size: 40, color: c.tintText),
                ),
            const SizedBox(height: UiSpace.xl),
            Text(title, textAlign: TextAlign.center, style: UiText.h2.copyWith(color: c.ink)),
            const SizedBox(height: UiSpace.sm),
            Text(message, textAlign: TextAlign.center, style: UiText.body.copyWith(color: c.muted)),
            if (actionLabel != null) ...[
              const SizedBox(height: UiSpace.xl),
              UiButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tono de un [UiBanner].
enum UiBannerTone { info, warning, error }

/// Aviso dentro de la pantalla: qué pasa y, si aplica, un botón para resolverlo.
class UiBanner extends StatelessWidget {
  const UiBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = UiBannerTone.warning,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final UiBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final (UiTone uiTone, IconData icon) = switch (tone) {
      UiBannerTone.info => (UiTone.tint, Icons.info_outline_rounded),
      UiBannerTone.warning => (UiTone.manual, Icons.warning_amber_rounded),
      UiBannerTone.error => (UiTone.absent, Icons.error_outline_rounded),
    };
    final pair = c.tone(uiTone);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: pair.background, borderRadius: BorderRadius.circular(18)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: pair.foreground),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(title!, style: UiText.bodyStrong.copyWith(color: pair.foreground)),
                  Text(message, style: UiText.label.copyWith(color: pair.foreground)),
                  if (actionLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: UiSpace.sm),
                      child: TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: pair.foreground,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(actionLabel!),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de confirmación. Devuelve `true` si la persona confirma.
Future<bool> showUiConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final c = UiColors.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(UiSpace.lg, 0, UiSpace.lg, UiSpace.lg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: c.absentText, foregroundColor: c.surface)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Hoja inferior con esquinas redondeadas y margen seguro.
Future<T?> showUiSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        UiSpace.page,
        0,
        UiSpace.page,
        UiSpace.xxl + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}

/// Mensaje breve en la parte inferior.
void showUiSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
