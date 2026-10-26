import 'dart:typed_data';

class DiagnosisRecord {
  const DiagnosisRecord({
    required this.id,
    required this.disease,
    required this.confidence,
    required this.createdAt,
    required this.imageBytes,
  });

  final int id;
  final String disease;
  final double confidence;
  final DateTime createdAt;
  final Uint8List imageBytes;

  factory DiagnosisRecord.fromMap(Map<String, Object?> map) {
    return DiagnosisRecord(
      id: map['id']! as int,
      disease: map['disease']! as String,
      confidence: (map['confidence']! as num).toDouble(),
      createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
      imageBytes: Uint8List.fromList(map['image']! as List<int>),
    );
  }
}
