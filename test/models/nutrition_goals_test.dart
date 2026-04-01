import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';

void main() {
  group('NutritionGoals', () {
    test('initial() has 2000 kcal default', () {
      expect(NutritionGoals.initial().dailyCalories, 2000);
    });

    test('fromJson/toJson round-trip', () {
      final goals = NutritionGoals(
        mode: TrackingMode.standard,
        dailyCalories: 1800,
        proteinGrams: 150.0,
        ifSyncEnabled: true,
        overshootPenaltyEnabled: true,
      );
      final restored = NutritionGoals.fromJson(goals.toJson());
      expect(restored.dailyCalories, goals.dailyCalories);
      expect(restored.proteinGrams, goals.proteinGrams);
      expect(restored.ifSyncEnabled, goals.ifSyncEnabled);
      expect(restored.overshootPenaltyEnabled, goals.overshootPenaltyEnabled);
    });

    test('copyWith preserves unchanged fields', () {
      final goals = NutritionGoals.initial();
      final updated = goals.copyWith(dailyCalories: 1500, ifSyncEnabled: true);
      expect(updated.dailyCalories, 1500);
      expect(updated.ifSyncEnabled, true);
      expect(updated.mode, goals.mode);
    });

    test('fromJson defaults overshootPenaltyEnabled to false', () {
      final goals = NutritionGoals.fromJson({'dailyCalories': 2000});
      expect(goals.overshootPenaltyEnabled, false);
    });
  });
}
