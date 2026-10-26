import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DiagnosisResult {
  const DiagnosisResult({required this.disease, required this.confidence});

  final String disease;
  final double confidence;
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

  static const _requestTimeout = Duration(seconds: 45);

  Future<DiagnosisResult> analyzeImage(Uint8List imageBytes) async {
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

    if (endpoint.host.endsWith('ngrok-free.dev')) {
      request.headers['ngrok-skip-browser-warning'] = 'true';
    }

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
    if (body is Map<String, dynamic> &&
        body['error'] is Map<String, dynamic> &&
        (body['error'] as Map<String, dynamic>)['message'] is String) {
      return (body['error'] as Map<String, dynamic>)['message'] as String;
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
