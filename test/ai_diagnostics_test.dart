import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/services/ai_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('pasted header formatting is normalized and wrong provider is rejected locally', () async {
    expect(AiService.normalizeKey(' Bearer "gsk_ab\u200Bcd"\n'), 'gsk_abcd');
    final ai = AiService(
      client: MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(
      ai.testConnection(
        provider: 'gemini',
        apiKey: 'gsk_example',
        model: 'gemini-2.5-flash',
      ),
      throwsA(predicate((e) => e.toString().contains('otro proveedor'))),
    );
    ai.dispose();
  });

  test(
    'Gemini catalog follows pagination, filters and strips resource prefix',
    () async {
      var calls = 0;
      final ai = AiService(
        client: MockClient((request) async {
          expect(request.url.queryParameters.containsKey('key'), isFalse);
          expect(request.headers['x-goog-api-key'], 'test-key');
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'models': [
                  {
                    'name': 'models/gemini-2.5-flash',
                    'supportedGenerationMethods': ['generateContent'],
                  },
                  {
                    'name': 'models/embedding',
                    'supportedGenerationMethods': ['embedContent'],
                  },
                ],
                'nextPageToken': 'next',
              }),
              200,
            );
          }
          expect(request.url.queryParameters['pageToken'], 'next');
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash-lite',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(await ai.listModels(provider: 'gemini', apiKey: 'test-key'), [
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
      ]);
      ai.dispose();
    },
  );

  test(
    'Gemini test reserves output and disables optional thinking for Flash',
    () async {
      final ai = AiService(
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/v1beta/models/gemini-2.5-flash:generateContent',
          );
          final body = jsonDecode(request.body);
          expect(body['generationConfig']['maxOutputTokens'], 1024);
          expect(
            body['generationConfig']['thinkingConfig']['thinkingBudget'],
            0,
          );
          return http.Response(
            '{"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}',
            200,
          );
        }),
      );
      await ai.testConnection(
        provider: 'gemini',
        apiKey: 'test-key',
        model: 'models/gemini-2.5-flash',
      );
      ai.dispose();
    },
  );

  for (final example in [
    (
      401,
      '{"error":{"code":"invalid_api_key","message":"SECRET"}}',
      'Clave inválida',
    ),
    (
      403,
      '{"error":{"message":"SECRET","status":"PERMISSION_DENIED"}}',
      'denegó el permiso',
    ),
    (403, '<html>SECRET</html>', 'red o la protección'),
    (
      400,
      '{"error":{"details":[{"reason":"API_KEY_INVALID"}]}}',
      'Clave inválida',
    ),
    (
      403,
      '{"error":{"details":[{"reason":"API_KEY_HTTP_REFERRER_BLOCKED"}]}}',
      'restricciones',
    ),
    (404, '{"error":{"message":"SECRET"}}', 'Modelo retirado'),
    (429, '{"error":{"message":"SECRET"}}', 'cuota'),
  ]) {
    test(
      'diagnostic ${example.$1} ${example.$3} is actionable and sanitized',
      () async {
        final ai = AiService(
          client: MockClient(
            (_) async => http.Response(example.$2, example.$1),
          ),
        );
        await expectLater(
          ai.testConnection(
            provider: 'gemini',
            apiKey: 'SECRET',
            model: 'test',
          ),
          throwsA(
            predicate(
              (e) =>
                  e.toString().contains('HTTP ${example.$1}') &&
                  e.toString().contains(example.$3) &&
                  !e.toString().contains('SECRET'),
            ),
          ),
        );
        ai.dispose();
      },
    );
  }
}
