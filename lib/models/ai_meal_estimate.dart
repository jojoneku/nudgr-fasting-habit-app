import 'food_entry.dart';
import 'estimation_source.dart';

class AiItemEstimate {
  final String name;
  final int calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? confidence; // per-item confidence from estimateMacrosForItems

  const AiItemEstimate({
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.confidence,
  });

  FoodEntry toFoodEntry() => FoodEntry(
        id: FoodEntry.generateId(),
        name: name,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        estimationSource: EstimationSource.aiPerItem,
        confidence: confidence,
        loggedAt: DateTime.now(),
      );

  AiItemEstimate copyWith({
    String? name,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? confidence,
  }) =>
      AiItemEstimate(
        name: name ?? this.name,
        calories: calories ?? this.calories,
        protein: protein ?? this.protein,
        carbs: carbs ?? this.carbs,
        fat: fat ?? this.fat,
        confidence: confidence ?? this.confidence,
      );
}

class AiMealEstimate {
  final int totalCalories;
  final List<AiItemEstimate> items;
  final double confidence; // 0.0–1.0

  const AiMealEstimate({
    required this.totalCalories,
    required this.items,
    required this.confidence,
  });
}
