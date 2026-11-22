import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/data/store.dart';
import 'package:hilva/services/lan_service.dart';
import 'package:hilva/services/ai_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hilva/ui/settings.dart';
import 'package:hilva/ui/theme.dart';

void main() {
  testWidgets(
    'successful test saves typed key and activates provider; rejected key preserves saved key',
    (tester) async {
      final saved = <String, String>{};
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          if (call.method == 'write') {
            saved[call.arguments['key'] as String] =
                call.arguments['value'] as String;
          }
          if (call.method == 'read') return saved[call.arguments['key']];
          return null;
        },
      );
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('hilva-key-test'),
      ))!;
      final store = (await tester.runAsync(
        () => Store.open(directory: dir.path),
      ))!;
      final lan = LanService(store);
      var allowed = true;
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPanel(
              store: store,
              lan: lan,
              mode: ThemeMode.light,
              onTheme: (_) {},
              onMessage: (_) {},
              onSync: () {},
              aiFactory: () => AiService(
                client: MockClient((request) async {
                  expect(
                    request.headers['x-goog-api-key'],
                    allowed ? 'valid-test' : 'bad-test',
                  );
                  return allowed
                      ? http.Response(
                          '{"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}',
                          200,
                        )
                      : http.Response(
                          '{"error":{"status":"UNAUTHENTICATED"}}',
                          401,
                        );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'API key de Gemini'),
        ' valid-test ',
      );
      await tester.tap(find.text('Probar y guardar Gemini'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(saved['geminiKey'], 'valid-test');
      expect(await tester.runAsync(() => store.setting('provider')), 'gemini');
      allowed = false;
      await tester.enterText(
        find.widgetWithText(TextField, 'API key de Gemini'),
        'bad-test',
      );
      await tester.tap(find.text('Probar y guardar Gemini'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(saved['geminiKey'], 'valid-test');
      expect(find.textContaining('HTTP 401'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      lan.dispose();
      await tester.runAsync(() async {
        await store.close();
        await dir.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'settings show local pairing and key tests on mobile and desktop',
    (tester) async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
      await font.load();
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
        expect(find.text('Probar y guardar Groq'), findsOneWidget);
        expect(find.text('Probar y guardar Gemini'), findsOneWidget);
        expect(find.text('Conectar con Google'), findsNothing);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/settings-${width.toInt()}.png'),
        );
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
