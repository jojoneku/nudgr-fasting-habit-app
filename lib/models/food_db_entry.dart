import 'estimation_source.dart';
import 'food_entry.dart';

class FoodDbEntry {
  final String id;
  final String name;
  final double caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final String? category;

  const FoodDbEntry({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.category,
  });

  factory FoodDbEntry.fromRow(Map<String, dynamic> row) => FoodDbEntry(
        id: row['id'] as String,
        name: row['name'] as String,
        caloriesPer100g: (row['cal'] as num).toDouble(),
        proteinPer100g: (row['protein'] as num?)?.toDouble(),
        carbsPer100g: (row['carbs'] as num?)?.toDouble(),
        fatPer100g: (row['fat'] as num?)?.toDouble(),
        category: row['category'] as String?,
      );

  FoodEntry toFoodEntry(double grams) {
    final factor = grams / 100.0;
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: name,
      calories: (caloriesPer100g * factor).round(),
      protein: proteinPer100g != null ? proteinPer100g! * factor : null,
      carbs: carbsPer100g != null ? carbsPer100g! * factor : null,
      fat: fatPer100g != null ? fatPer100g! * factor : null,
      grams: grams,
      estimationSource: EstimationSource.db,
      loggedAt: DateTime.now(),
    );
  }

  /// Display string for calorie density, e.g. "165 kcal / 100g"
  String get densityLabel => '${caloriesPer100g.round()} kcal / 100g';
}
