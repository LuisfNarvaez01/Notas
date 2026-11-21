import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/data/store.dart';
import 'package:hilva/services/lan_service.dart';
import 'package:hilva/ui/settings.dart';
import 'package:hilva/ui/theme.dart';

void main() {
  testWidgets(
    'settings show local pairing and key tests on mobile and desktop',
    (tester) async {
      final font=FontLoader('Manrope')..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));await font.load();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('hilva-ui'),
      ))!;
      final store = (await tester.runAsync(
        () => Store.open(directory: dir.path),
      ))!;
      final lan = LanService(store);
      for (final width in [390.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: hilvaTheme(false),
            home: Scaffold(
              body: SettingsPanel(
                store: store,
                lan: lan,
                mode: ThemeMode.light,
                onTheme: (_) {},
                onMessage: (_) {},
                onSync: () {},
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Probar conexión de Groq'), findsOneWidget);
        expect(find.text('Probar conexión de Gemini'), findsOneWidget);
        expect(find.text('Conectar con Google'), findsNothing);
        expect(tester.takeException(), isNull);
      await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/settings-${width.toInt()}.png'));
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      lan.dispose();
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
