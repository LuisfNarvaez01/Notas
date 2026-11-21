import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hilva/services/ai_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'connection test is a small real model request with no user notes',
    () async {
      final service = AiService(
        client: MockClient((request) async {
          final data = jsonDecode(request.body);
          expect(data['max_completion_tokens'], 32);
          expect(
            data['messages'][1]['content'],
            contains('Prueba de conexión'),
          );
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
          );
        }),
      );
      await service.testConnection(
        provider: 'groq',
        apiKey: 'test',
        model: 'test',
      );
      service.dispose();
    },
  );

  test('Groq sends original as data and extracts response', () async {
    final service = AiService(
      client: MockClient((request) async {
        expect(request.url.host, 'api.groq.com');
        expect(request.headers['authorization'], 'Bearer secret');
        final body = jsonDecode(request.body);
        expect(body['messages'][1]['content'], contains('original'));
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Resultado'},
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(
      await service.run(
        provider: 'Groq',
        apiKey: 'secret',
        model: 'test',
        instruction: 'Organiza',
        text: 'original',
      ),
      'Resultado',
    );
  });
  test('Gemini keeps key out of URL and joins text parts', () async {
    final service = AiService(
      client: MockClient((request) async {
        expect(request.url.query, isEmpty);
        expect(request.headers['x-goog-api-key'], 'secret');
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Uno'},
                    {'text': 'Dos'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(
      await service.run(
        provider: 'Gemini',
        apiKey: 'secret',
        model: 'test',
        instruction: 'Organiza',
        text: 'original',
      ),
      'Uno\nDos',
    );
  });
  test('quota error never leaks provider response or secrets', () async {
    final service = AiService(
      client: MockClient(
        (_) async => http.Response('secret private note', 429),
      ),
    );
    await expectLater(
      service.run(
        provider: 'Groq',
        apiKey: 'secret',
        model: 'test',
        instruction: 'x',
        text: 'y',
      ),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('cuota') &&
              !e.toString().contains('secret'),
        ),
      ),
    );
  });
  test('rejects oversized input before sending', () async {
    final service = AiService(
      client: MockClient((_) async => throw StateError('must not send')),
    );
    await expectLater(
      service.run(
        provider: 'Groq',
        apiKey: 's',
        model: 'test',
        instruction: 'x',
        text: 'x' * 40001,
      ),
      throwsA(predicate((e) => e.toString().contains('límite'))),
    );
  });
  test('malformed successful response cannot become note content', () async {
    final service = AiService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      service.run(
        provider: 'Groq',
        apiKey: 's',
        model: 'test',
        instruction: 'x',
        text: 'y',
      ),
      throwsA(predicate((e) => e.toString().contains('respuesta'))),
    );
  });
}
