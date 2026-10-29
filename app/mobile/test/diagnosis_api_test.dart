import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_agri/services/diagnosis_api.dart';

void main() {
  final endpoint = Uri.parse('https://api.example.test/predict');
  final sampleImage = Uint8List.fromList([1, 2, 3]);

  test(
    'returns disease and confidence without interpreting severity',
    () async {
      final api = DiagnosisApi(
        endpoint: endpoint,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'disease': 'Leaf Blast',
              'confidence': 92.5,
              'severity': 'Severe',
            }),
            200,
          ),
        ),
      );

      final result = await api.analyzeImage(sampleImage);

      expect(result.disease, 'Leaf Blast');
      expect(result.confidence, 92.5);
    },
  );

  test('keeps the assistant response returned with a diagnosis', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'disease': 'Leaf Blast',
            'confidence': 92.5,
            'agent': {
              'session_id': 'session-1',
              'message': 'Keep the leaf dry and monitor the next growth stage.',
              'sources': [
                {
                  'title': 'IRRI Rice Knowledge Bank',
                  'url': 'https://www.knowledgebank.irri.org/',
                },
              ],
            },
          }),
          200,
        ),
      ),
    );

    final result = await api.analyzeImage(sampleImage);

    expect(result.agent?.sessionId, 'session-1');
    expect(result.agent?.message, contains('Keep the leaf dry'));
    expect(result.agent?.sources.single.title, 'IRRI Rice Knowledge Bank');
  });

  test('sends farm context as JSON with the image upload', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient((request) async {
        expect(request.body, contains('name="farm_context"'));
        expect(request.body, contains('"age_days":35'));
        expect(request.body, contains('"growth_stage":"tillering"'));
        return http.Response(
          jsonEncode({'disease': 'Leaf Blast', 'confidence': 92.5}),
          200,
        );
      }),
    );

    await api.analyzeImage(
      sampleImage,
      farmContext: const {'age_days': 35, 'growth_stage': 'tillering'},
    );
  });

  test('uses the ngrok host for prediction and agent chat', () async {
    final api = DiagnosisApi(
      endpoint: Uri.parse('https://rice-demo.ngrok-free.app/predict'),
      client: MockClient((request) async {
        expect(request.url.host, 'rice-demo.ngrok-free.app');
        expect(request.headers['ngrok-skip-browser-warning'], 'true');
        if (request.url.path == '/predict') {
          expect(request.body, contains('name="file"'));
          return http.Response(
            jsonEncode({
              'disease': 'Leaf Blast',
              'confidence': 92.5,
              'agent': {
                'session_id': 'session-1',
                'message': 'Check the field conditions.',
              },
            }),
            200,
          );
        }
        expect(request.url.path, '/agent/chat');
        return http.Response(
          jsonEncode({
            'session_id': 'session-1',
            'message': 'I will use the same API host.',
          }),
          200,
        );
      }),
    );

    final diagnosis = await api.analyzeImage(sampleImage);
    final reply = await api.sendAgentMessage(
      sessionId: diagnosis.agent!.sessionId,
      message: 'What next?',
    );

    expect(reply.message, 'I will use the same API host.');
  });

  test('sends a follow-up question to the assistant endpoint', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient((request) async {
        expect(request.url.path, '/agent/chat');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['session_id'], 'session-1');
        expect(body['message'], 'How should I water it?');
        return http.Response(
          jsonEncode({
            'session_id': 'session-1',
            'message': 'Water according to the field stage and soil condition.',
            'sources': <dynamic>[],
          }),
          200,
        );
      }),
    );

    final reply = await api.sendAgentMessage(
      sessionId: 'session-1',
      message: 'How should I water it?',
    );

    expect(reply.message, contains('soil condition'));
  });

  test('uses the structured API error message for failed requests', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'invalid_image',
              'message': 'The uploaded file is not a valid image.',
            },
          }),
          400,
        ),
      ),
    );

    await expectLater(
      api.analyzeImage(sampleImage),
      throwsA(
        isA<DiagnosisApiException>().having(
          (error) => error.message,
          'message',
          'The uploaded file is not a valid image.',
        ),
      ),
    );
  });

  test('maps an oversized upload response to an actionable message', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient((_) async => http.Response('not json', 413)),
    );

    await expectLater(
      api.analyzeImage(sampleImage),
      throwsA(
        isA<DiagnosisApiException>().having(
          (error) => error.message,
          'message',
          'The image is too large. Choose an image under 10 MB.',
        ),
      ),
    );
  });

  test('rejects malformed successful responses', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'disease': '', 'confidence': 'high'}),
          200,
        ),
      ),
    );

    await expectLater(
      api.analyzeImage(sampleImage),
      throwsA(isA<DiagnosisApiException>()),
    );
  });

  test('rejects confidence values outside the percentage range', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'disease': 'Leaf Blast', 'confidence': 120}),
          200,
        ),
      ),
    );

    await expectLater(
      api.analyzeImage(sampleImage),
      throwsA(
        isA<DiagnosisApiException>().having(
          (error) => error.message,
          'message',
          'The analysis service returned an invalid confidence value.',
        ),
      ),
    );
  });

  test('maps network errors to a connection message', () async {
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient((_) async {
        throw http.ClientException('connection refused');
      }),
    );

    await expectLater(
      api.analyzeImage(sampleImage),
      throwsA(
        isA<DiagnosisApiException>().having(
          (error) => error.message,
          'message',
          'Unable to connect to the analysis service. Please try again later.',
        ),
      ),
    );
  });

  test('does not send an empty image', () async {
    var requestSent = false;
    final api = DiagnosisApi(
      endpoint: endpoint,
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.analyzeImage(Uint8List(0)),
      throwsA(isA<DiagnosisApiException>()),
    );
    expect(requestSent, isFalse);
  });
}
