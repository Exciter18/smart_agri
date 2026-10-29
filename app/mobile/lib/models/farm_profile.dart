import 'dart:convert';

class FarmProfile {
  const FarmProfile({
    this.name = '',
    this.riceVariety = '',
    this.growthStage = '',
    this.areaHa,
    this.ageDays,
    this.recentWeather = '',
    this.waterCondition = '',
    this.nitrogenUse = '',
    this.previousAction = '',
  });

  final String name;
  final String riceVariety;
  final String growthStage;
  final double? areaHa;
  final int? ageDays;
  final String recentWeather;
  final String waterCondition;
  final String nitrogenUse;
  final String previousAction;

  Map<String, Object> get agentContext {
    final context = <String, Object>{};
    final variety = riceVariety.trim();
    final age = ageDays;
    final stage = _growthStageIds[growthStage];
    final action = previousAction.trim();
    if (variety.isNotEmpty) context['rice_variety'] = variety;
    if (age != null) context['age_days'] = age;
    if (stage != null) context['growth_stage'] = stage;
    if (recentWeather.isNotEmpty) context['recent_weather'] = recentWeather;
    if (waterCondition.isNotEmpty) {
      context['water_condition'] = waterCondition;
    }
    if (nitrogenUse.isNotEmpty) context['nitrogen_use'] = nitrogenUse;
    if (action.isNotEmpty) context['previous_action'] = action;
    return context;
  }

  static const _growthStageIds = {
    'Seedling': 'seedling',
    'Tillering': 'tillering',
    'Panicle initiation': 'panicle_initiation',
    'Heading': 'heading',
    'Ripening': 'ripening',
  };

  String toJson() => json.encode({
    'name': name,
    'riceVariety': riceVariety,
    'growthStage': growthStage,
    'area': areaHa?.toString() ?? '',
    'ageDays': ageDays,
    'recentWeather': recentWeather,
    'waterCondition': waterCondition,
    'nitrogenUse': nitrogenUse,
    'previousAction': previousAction,
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
      ageDays: _parseAgeDays(data['ageDays']),
      recentWeather: data['recentWeather'] as String? ?? '',
      waterCondition: data['waterCondition'] as String? ?? '',
      nitrogenUse: data['nitrogenUse'] as String? ?? '',
      previousAction: data['previousAction'] as String? ?? '',
    );
  }

  static int? _parseAgeDays(Object? value) {
    final age = switch (value) {
      final num number => number.toInt(),
      final String string => int.tryParse(string),
      _ => null,
    };
    return age != null && age >= 1 && age <= 250 ? age : null;
  }
}
