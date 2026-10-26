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
