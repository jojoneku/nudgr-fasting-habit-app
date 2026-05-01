import 'dart:math';

import 'estimation_source.dart';

class FoodEntry {
  final String id;
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? grams;
  final EstimationSource estimationSource;
  final double? confidence; // 0.0–1.0; set for aiPerItem estimates
  final DateTime loggedAt;

  const FoodEntry({
    required this.id,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.grams,
    this.estimationSource = EstimationSource.db,
    this.confidence,
    required this.loggedAt,
  });

  /// Backward-compat helper. Views that used aiEstimated should use !isTrusted.
  bool get aiEstimated => !estimationSource.isTrusted;

  /// Expose whether the estimate needs user confirmation. Triggered for any
  /// low-confidence entry regardless of source — covers AI estimates, keyword
  /// density fallbacks, AND weak DB matches that didn't pass isLearnableMatch.
  bool get needsConfirmation => (confidence ?? 1.0) < 0.6;

  static String generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  factory FoodEntry.fromJson(Map<String, dynamic> json) {
    final legacyAiEstimated = json['aiEstimated'] as bool? ?? false;
    return FoodEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      calories: json['calories'] as int,
      protein: (json['protein'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      grams: (json['grams'] as num?)?.toDouble(),
      estimationSource: json['estimationSource'] != null
          ? EstimationSource.fromJson(json['estimationSource'] as String?)
          : (legacyAiEstimated
              ? EstimationSource.aiPerItem
              : EstimationSource.db),
      confidence: (json['confidence'] as num?)?.toDouble(),
      loggedAt: DateTime.parse(json['loggedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'grams': grams,
        'estimationSource': estimationSource.name,
        'aiEstimated': aiEstimated, // keep for backward compat
        'confidence': confidence,
        'loggedAt': loggedAt.toIso8601String(),
      };

  FoodEntry copyWith({
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? grams,
    EstimationSource? estimationSource,
    double? confidence,
  }) =>
      FoodEntry(
        id: id,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        grams: grams ?? this.grams,
        estimationSource: estimationSource ?? this.estimationSource,
        confidence: confidence ?? this.confidence,
        loggedAt: loggedAt,
      );
}
