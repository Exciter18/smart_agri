import 'dart:convert';

class FarmProfile {
  const FarmProfile({
    this.name = '',
    this.riceVariety = '',
    this.growthStage = '',
    this.areaHa,
  });

  final String name;
  final String riceVariety;
  final String growthStage;
  final double? areaHa;

  String toJson() => json.encode({
    'name': name,
    'riceVariety': riceVariety,
    'growthStage': growthStage,
    'area': areaHa?.toString() ?? '',
  });

  factory FarmProfile.fromJson(String value) {
    final data = json.decode(value) as Map<String, dynamic>;
    return FarmProfile(
      name: data['name'] as String? ?? '',
      riceVariety: data['riceVariety'] as String? ?? '',
      growthStage: switch (data['growthStage'] as String? ?? '') {
        'Mới gieo' => 'Seedling',
        'Đẻ nhánh' => 'Tillering',
        'Làm đòng' => 'Panicle initiation',
        'Trổ bông' => 'Heading',
        'Chín' => 'Ripening',
        final stage => stage,
      },
      areaHa: switch (data['area']) {
        final num area => area.toDouble(),
        final String area when area.trim().isNotEmpty => double.tryParse(
          area.replaceAll(',', '.'),
        ),
        _ => null,
      },
    );
  }
}
