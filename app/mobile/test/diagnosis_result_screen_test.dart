import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_agri/screens/diagnosis_result_screen.dart';
import 'package:smart_agri/services/diagnosis_api.dart';

void main() {
  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/XioAAAAASUVORK5CYII=',
  );

  testWidgets('separates the result, assistant conversation, and sources', (
    tester,
  ) async {
    final api = DiagnosisApi(
      endpoint: Uri.parse('https://api.example.test/predict'),
      client: MockClient((request) async {
        expect(request.url.path, '/agent/chat');
        return http.Response(
          jsonEncode({
            'session_id': 'session-1',
            'message': 'Keep monitoring the affected leaves.',
            'sources': [
              {
                'title': 'IRRI Rice Knowledge Bank',
                'url': 'https://example.test/rice',
              },
            ],
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosisResultScreen(
          diagnosis: const DiagnosisResult(
            disease: 'Leaf Blast',
            confidence: 87.4,
            agent: AgentReply(
              sessionId: 'session-1',
              message: 'Check the leaf symptoms and field conditions.',
              sources: [
                KnowledgeSource(
                  title: 'Initial source',
                  url: 'https://example.test/initial',
                ),
              ],
            ),
          ),
          imageBytes: Uint8List.fromList(imageBytes),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Leaf Blast'), findsOneWidget);
    expect(find.text('87.4%'), findsOneWidget);
    expect(
      find.text('Check the leaf symptoms and field conditions.'),
      findsNothing,
    );

    await tester.tap(find.text('Rice Care'));
    await tester.pumpAndSettle();
    expect(
      find.text('Check the leaf symptoms and field conditions.'),
      findsOneWidget,
    );
    expect(find.text('Initial source'), findsNothing);

    await tester.enterText(find.byType(TextField), 'What should I monitor?');
    await tester.tap(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(find.text('What should I monitor?'), findsOneWidget);
    expect(find.text('Keep monitoring the affected leaves.'), findsOneWidget);

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('IRRI Rice Knowledge Bank'), findsOneWidget);
    expect(find.text('https://example.test/rice'), findsOneWidget);
    expect(find.text('Keep monitoring the affected leaves.'), findsNothing);
  });
}
