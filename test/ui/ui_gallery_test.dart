import 'dart:io';

import 'package:asistencia_uniguajira/ui/gallery/ui_gallery_screen.dart';
import 'package:asistencia_uniguajira/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga Figtree para que las pruebas midan el texto con la letra real.
Future<void> _loadFigtree() async {
  final loader = FontLoader(UiText.family);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Figtree-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _pumpGallery(WidgetTester tester, ThemeData theme, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: const UiGalleryScreen()),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(_loadFigtree);

  testWidgets('el muestrario se dibuja en claro sin desbordes', (tester) async {
    await _pumpGallery(tester, UiTheme.light());
    expect(tester.takeException(), isNull);
    expect(find.text('Buenos días, profe'), findsOneWidget);
    expect(find.text('Volver a la sesión'), findsOneWidget);
  });

  testWidgets('el muestrario se dibuja en oscuro sin desbordes', (tester) async {
    await _pumpGallery(tester, UiTheme.dark());
    expect(tester.takeException(), isNull);
  });

  testWidgets('el muestrario aguanta un celular angosto y letra grande', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpGallery(tester, UiTheme.light(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('los tonos cumplen contraste AA en claro y oscuro', (tester) async {
    double luminance(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final la = luminance(a), lb = luminance(b);
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final c in [UiColors.light, UiColors.dark]) {
      expect(ratio(c.ink, c.background), greaterThan(7));
      expect(ratio(c.muted, c.background), greaterThan(4.5));
      expect(ratio(c.muted, c.surface), greaterThan(4.5));
      expect(ratio(c.onPrimary, c.primary), greaterThan(4.5));
      expect(ratio(c.primaryText, c.background), greaterThan(4.5));
      expect(ratio(c.primaryText, c.surface), greaterThan(4.5));
      for (final tone in UiTone.values) {
        final pair = c.tone(tone);
        expect(ratio(pair.foreground, pair.background), greaterThan(4.5), reason: '$tone');
      }
    }
  });

  test('las iniciales salen de las dos primeras palabras', () {
    expect(UiAvatar.initialsOf('Ana Lucía Pérez'), 'AL');
    expect(UiAvatar.initialsOf('  josé  '), 'J');
    expect(UiAvatar.initialsOf(''), '?');
  });

  testWidgets('el teclado del PIN entrega dígitos y borrado', (tester) async {
    final typed = <String>[];
    var erased = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UiTheme.light(),
        home: Scaffold(
          body: UiPinKeypad(onDigit: typed.add, onBackspace: () => erased++),
        ),
      ),
    );
    await tester.tap(find.text('4'));
    await tester.tap(find.text('7'));
    await tester.tap(find.bySemanticsLabel('Borrar'));
    expect(typed, ['4', '7']);
    expect(erased, 1);
  });
}
