import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class KnowledgeSource {
  const KnowledgeSource({required this.title, required this.url});

  final String title;
  final String url;
}

class AgentReply {
  const AgentReply({
    required this.sessionId,
    required this.message,
    this.sources = const [],
  });

  final String sessionId;
  final String message;
  final List<KnowledgeSource> sources;
}

class DiagnosisResult {
  const DiagnosisResult({
    required this.disease,
    required this.confidence,
    this.agent,
    this.agentError,
  });

  final String disease;
  final double confidence;
  final AgentReply? agent;
  final String? agentError;
}

class DiagnosisApiException implements Exception {
  const DiagnosisApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DiagnosisApi {
  DiagnosisApi({required this.endpoint, http.Client? client})
    : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  static const _requestTimeout = Duration(seconds: 120);

  Map<String, String> get _ngrokHeaders => endpoint.host.contains('ngrok')
      ? const {'ngrok-skip-browser-warning': 'true'}
      : const {};

  Future<DiagnosisResult> analyzeImage(
    Uint8List imageBytes, {
    Map<String, Object> farmContext = const {},
  }) async {
    if (imageBytes.isEmpty) {
      throw const DiagnosisApiException('Choose a valid image and try again.');
    }

    final request = http.MultipartRequest('POST', endpoint)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'upload.jpg',
        ),
      );
    if (farmContext.isNotEmpty) {
      request.fields['farm_context'] = jsonEncode(farmContext);
    }

    request.headers.addAll(_ngrokHeaders);

    try {
      final streamedResponse = await _client
          .send(request)
          .timeout(_requestTimeout);
      final responseBody = await streamedResponse.stream
          .bytesToString()
          .timeout(_requestTimeout);
      final decoded = _decodeJson(responseBody, streamedResponse.statusCode);

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        throw DiagnosisApiException(
          _errorMessage(decoded, streamedResponse.statusCode),
        );
      }

      if (decoded is! Map<String, dynamic> ||
          decoded['disease'] is! String ||
          (decoded['disease'] as String).trim().isEmpty ||
          decoded['confidence'] is! num) {
        throw const DiagnosisApiException(
          'The analysis service returned an invalid response. Please try again later.',
        );
      }

      final confidence = (decoded['confidence'] as num).toDouble();
      if (!confidence.isFinite || confidence < 0 || confidence > 100) {
        throw const DiagnosisApiException(
          'The analysis service returned an invalid confidence value.',
        );
      }

      return DiagnosisResult(
        disease: (decoded['disease'] as String).trim(),
        confidence: confidence,
        agent: _parseAgent(decoded['agent']),
        agentError: decoded['agent_error'] is String
            ? (decoded['agent_error'] as String).trim()
            : null,
      );
    } on DiagnosisApiException {
      rethrow;
    } on TimeoutException {
      throw const DiagnosisApiException(
        'The analysis is taking too long. Check your connection and try again.',
      );
    } on SocketException {
      throw const DiagnosisApiException(
        'Unable to reach the analysis service. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const DiagnosisApiException(
        'Unable to connect to the analysis service. Please try again later.',
      );
    }
  }

  Future<AgentReply> sendAgentMessage({
    required String sessionId,
    required String message,
  }) async {
    final cleanedMessage = message.trim();
    if (cleanedMessage.isEmpty) {
      throw const DiagnosisApiException('Enter a question before sending.');
    }

    try {
      final response = await _client
          .post(
            endpoint.resolve('/agent/chat'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              ..._ngrokHeaders,
            },
            body: jsonEncode({
              'session_id': sessionId,
              'message': cleanedMessage,
            }),
          )
          .timeout(_requestTimeout);
      final decoded = _decodeJson(response.body, response.statusCode);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DiagnosisApiException(
          _errorMessage(decoded, response.statusCode),
        );
      }

      final reply = _parseAgent(decoded);
      if (reply == null) {
        throw const DiagnosisApiException(
          'The assistant returned an invalid response.',
        );
      }
      return reply;
    } on DiagnosisApiException {
      rethrow;
    } on TimeoutException {
      throw const DiagnosisApiException(
        'The assistant is taking too long to respond. Please try again.',
      );
    } on SocketException {
      throw const DiagnosisApiException(
        'Unable to reach the assistant service. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const DiagnosisApiException(
        'Unable to connect to the assistant service. Please try again later.',
      );
    }
  }

  AgentReply? _parseAgent(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final sessionId = value['session_id'];
    final message = value['message'];
    if (sessionId is! String ||
        sessionId.trim().isEmpty ||
        message is! String ||
        message.trim().isEmpty) {
      return null;
    }

    final sources = <KnowledgeSource>[];
    final rawSources = value['sources'];
    if (rawSources is List) {
      for (final item in rawSources) {
        if (item is Map<String, dynamic> &&
            item['title'] is String &&
            item['url'] is String) {
          sources.add(
            KnowledgeSource(
              title: (item['title'] as String).trim(),
              url: (item['url'] as String).trim(),
            ),
          );
        }
      }
    }

    return AgentReply(
      sessionId: sessionId.trim(),
      message: message.trim(),
      sources: sources,
    );
  }

  dynamic _decodeJson(String body, int statusCode) {
    try {
      return jsonDecode(body);
    } on FormatException {
      if (statusCode < 200 || statusCode >= 300) return null;
      throw const DiagnosisApiException(
        'The analysis service returned an invalid response. Please try again later.',
      );
    }
  }

  String _errorMessage(dynamic body, int statusCode) {
    if (body is Map<String, dynamic>) {
      if (body['error'] is Map<String, dynamic> &&
          (body['error'] as Map<String, dynamic>)['message'] is String) {
        return (body['error'] as Map<String, dynamic>)['message'] as String;
      }
      if (body['detail'] is String &&
          (body['detail'] as String).trim().isNotEmpty) {
        return body['detail'] as String;
      }
    }

    return switch (statusCode) {
      413 => 'The image is too large. Choose an image under 10 MB.',
      415 => 'This image format is not supported. Choose another image.',
      429 => 'The service is busy. Please wait a moment and try again.',
      >= 500 => 'The analysis service is temporarily unavailable. Please try again later.',
      _ => 'The image could not be analyzed (status code: $statusCode).',
    };
  }
}
