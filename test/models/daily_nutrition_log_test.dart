import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';

FoodEntry _entry({
  String id = 'e1',
  int calories = 200,
  double? protein,
  double? carbs,
  double? fat,
}) =>
    FoodEntry(
      id: id,
      name: 'Test Food',
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      loggedAt: DateTime(2026, 3, 25, 12, 0),
    );

void main() {
  group('DailyNutritionLog', () {
    test('empty() has zero totals and no entries', () {
      final log = DailyNutritionLog.empty('2026-03-25');
      expect(log.date, '2026-03-25');
      expect(log.totalCalories, 0);
      expect(log.totalProtein, 0.0);
      expect(log.allEntries, isEmpty);
    });

    test('addEntry increases totalCalories', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(calories: 300), MealSlot.meal);
      expect(log.totalCalories, 300);
    });

    test('addEntry appends to correct slot', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'a', calories: 100), MealSlot.meal)
          .addEntry(_entry(id: 'b', calories: 200), MealSlot.meal);
      expect(log.entriesForSlot(MealSlot.meal).length, 2);
      expect(log.caloriesForSlot(MealSlot.meal), 300);
    });

    test('removeEntry removes by id', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'keep', calories: 100), MealSlot.meal)
          .addEntry(_entry(id: 'remove', calories: 200), MealSlot.meal)
          .removeEntry('remove', MealSlot.meal);
      expect(log.totalCalories, 100);
      expect(log.allEntries.length, 1);
      expect(log.allEntries.first.id, 'keep');
    });

    test('totalProtein sums protein across all entries', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'a', calories: 100, protein: 20.0), MealSlot.meal)
          .addEntry(_entry(id: 'b', calories: 100, protein: 30.0), MealSlot.meal);
      expect(log.totalProtein, 50.0);
    });

    test('hasMacros is false when no macro data', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'a', calories: 200), MealSlot.meal);
      expect(log.hasMacros, false);
    });

    test('hasMacros is true when any entry has macros', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'a', calories: 200, protein: 30.0), MealSlot.meal);
      expect(log.hasMacros, true);
    });

    test('addEntries adds multiple entries at once', () {
      final entries = [
        _entry(id: 'a', calories: 100),
        _entry(id: 'b', calories: 150),
      ];
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntries(entries, MealSlot.meal);
      expect(log.totalCalories, 250);
      expect(log.allEntries.length, 2);
    });

    test('fromJson/toJson round-trip preserves date and entries', () {
      final log = DailyNutritionLog.empty('2026-03-25')
          .addEntry(_entry(id: 'e1', calories: 500), MealSlot.meal);
      final restored = DailyNutritionLog.fromJson(log.toJson());
      expect(restored.date, '2026-03-25');
      expect(restored.totalCalories, 500);
      expect(restored.allEntries.length, 1);
      expect(restored.allEntries.first.id, 'e1');
    });

    test('fromJson migrates legacy flat entries list (v1)', () {
      final json = {
        'date': '2026-03-25',
        'entries': [
          {
            'id': 'legacy',
            'name': 'Legacy Food',
            'calories': 300,
            'loggedAt': DateTime(2026, 3, 25, 12, 0).toIso8601String(),
          }
        ],
      };
      final log = DailyNutritionLog.fromJson(json);
      expect(log.totalCalories, 300);
      expect(log.allEntries.first.id, 'legacy');
    });

    test('entriesForSlot returns empty list for unknown slot', () {
      final log = DailyNutritionLog.empty('2026-03-25');
      expect(log.entriesForSlot(MealSlot.meal), isEmpty);
    });

    test('caloriesForSlot returns zero for empty slot', () {
      final log = DailyNutritionLog.empty('2026-03-25');
      expect(log.caloriesForSlot(MealSlot.meal), 0);
    });
  });
}
