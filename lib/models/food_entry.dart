import 'dart:math';

class FoodEntry {
  final String id;
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? grams;       // stored for reference (from food DB lookup)
  final bool aiEstimated;    // true → show ~ prefix in UI
  final DateTime loggedAt;

  const FoodEntry({
    required this.id,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.grams,
    this.aiEstimated = false,
    required this.loggedAt,
  });

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory FoodEntry.fromJson(Map<String, dynamic> json) => FoodEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        calories: json['calories'] as int,
        protein: (json['protein'] as num?)?.toDouble(),
        carbs: (json['carbs'] as num?)?.toDouble(),
        fat: (json['fat'] as num?)?.toDouble(),
        grams: (json['grams'] as num?)?.toDouble(),
        aiEstimated: json['aiEstimated'] as bool? ?? false,
        loggedAt: DateTime.parse(json['loggedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'grams': grams,
        'aiEstimated': aiEstimated,
        'loggedAt': loggedAt.toIso8601String(),
      };

  FoodEntry copyWith({
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? grams,
    bool? aiEstimated,
  }) =>
      FoodEntry(
        id: id,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        grams: grams ?? this.grams,
        aiEstimated: aiEstimated ?? this.aiEstimated,
        loggedAt: loggedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodEntry &&
          id == other.id &&
          name == other.name &&
          calories == other.calories &&
          protein == other.protein &&
          carbs == other.carbs &&
          fat == other.fat &&
          grams == other.grams &&
          aiEstimated == other.aiEstimated &&
          loggedAt == other.loggedAt;

  @override
  int get hashCode => Object.hash(
      id, name, calories, protein, carbs, fat, grams, aiEstimated, loggedAt);
}
