class PersonalFoodEntry {
  final String key;
  final String name;
  final double kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final int hits;
  final DateTime lastUsedAt;

  const PersonalFoodEntry({
    required this.key,
    required this.name,
    required this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.hits = 1,
    required this.lastUsedAt,
  });

  factory PersonalFoodEntry.fromJson(Map<String, dynamic> json) =>
      PersonalFoodEntry(
        key: json['key'] as String,
        name: json['name'] as String,
        kcalPer100g: (json['kcalPer100g'] as num).toDouble(),
        proteinPer100g: (json['proteinPer100g'] as num?)?.toDouble(),
        carbsPer100g: (json['carbsPer100g'] as num?)?.toDouble(),
        fatPer100g: (json['fatPer100g'] as num?)?.toDouble(),
        hits: json['hits'] as int? ?? 1,
        lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'kcalPer100g': kcalPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
        'hits': hits,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };
}
