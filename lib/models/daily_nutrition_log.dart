import 'food_entry.dart';
import 'meal_slot.dart';

class DailyNutritionLog {
  final String date; // 'yyyy-MM-dd'
  final Map<MealSlot, List<FoodEntry>> meals;

  const DailyNutritionLog({
    required this.date,
    required this.meals,
  });

  factory DailyNutritionLog.empty(String date) =>
      DailyNutritionLog(date: date, meals: const {});

  // ── Totals ───────────────────────────────────────────────────────────────────

  List<FoodEntry> get allEntries =>
      meals.values.expand((entries) => entries).toList();

  int get totalCalories => allEntries.fold(0, (s, e) => s + e.calories);
  double get totalProtein =>
      allEntries.fold(0.0, (s, e) => s + (e.protein ?? 0.0));
  double get totalCarbs => allEntries.fold(0.0, (s, e) => s + (e.carbs ?? 0.0));
  double get totalFat => allEntries.fold(0.0, (s, e) => s + (e.fat ?? 0.0));

  bool get hasMacros => allEntries
      .any((e) => e.protein != null || e.carbs != null || e.fat != null);

  int caloriesForSlot(MealSlot slot) =>
      (meals[slot] ?? []).fold(0, (s, e) => s + e.calories);

  List<FoodEntry> entriesForSlot(MealSlot slot) => meals[slot] ?? [];

  // ── Serialization ─────────────────────────────────────────────────────────────

  factory DailyNutritionLog.fromJson(Map<String, dynamic> json) {
    // Migration v1: legacy flat list → meal slot
    if (json.containsKey('entries')) {
      final entries = (json['entries'] as List<dynamic>)
          .map((e) => FoodEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return DailyNutritionLog(
        date: json['date'] as String,
        meals: {MealSlot.meal: entries},
      );
    }

    final mealsJson = json['meals'] as Map<String, dynamic>? ?? {};

    // Migration v2: merge old breakfast/lunch/dinner/snack slots → meal slot
    final allEntries = <FoodEntry>[];
    bool needsMigration = false;
    for (final entry in mealsJson.entries) {
      final slot = MealSlot.fromJson(entry.key);
      final entries = (entry.value as List<dynamic>)
          .map((e) => FoodEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      if (slot != MealSlot.meal) needsMigration = true;
      allEntries.addAll(entries);
    }

    if (needsMigration) {
      return DailyNutritionLog(
        date: json['date'] as String,
        meals: allEntries.isEmpty ? {} : {MealSlot.meal: allEntries},
      );
    }

    return DailyNutritionLog(
      date: json['date'] as String,
      meals: {MealSlot.meal: allEntries},
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'meals': {
          for (final entry in meals.entries)
            entry.key.jsonKey: entry.value.map((e) => e.toJson()).toList(),
        },
      };

  // ── Mutation helpers ──────────────────────────────────────────────────────────

  DailyNutritionLog addEntry(FoodEntry entry, MealSlot slot) {
    final updated = Map<MealSlot, List<FoodEntry>>.from(
      meals.map((k, v) => MapEntry(k, List<FoodEntry>.from(v))),
    );
    updated[slot] = [...(updated[slot] ?? []), entry];
    return DailyNutritionLog(date: date, meals: updated);
  }

  DailyNutritionLog removeEntry(String entryId, MealSlot slot) {
    final updated = Map<MealSlot, List<FoodEntry>>.from(
      meals.map((k, v) => MapEntry(k, List<FoodEntry>.from(v))),
    );
    updated[slot] =
        (updated[slot] ?? []).where((e) => e.id != entryId).toList();
    return DailyNutritionLog(date: date, meals: updated);
  }

  DailyNutritionLog addEntries(List<FoodEntry> entries, MealSlot slot) {
    final updated = Map<MealSlot, List<FoodEntry>>.from(
      meals.map((k, v) => MapEntry(k, List<FoodEntry>.from(v))),
    );
    updated[slot] = [...(updated[slot] ?? []), ...entries];
    return DailyNutritionLog(date: date, meals: updated);
  }
}
