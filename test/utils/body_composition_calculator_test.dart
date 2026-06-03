import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/body_measurement_entry.dart';
import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/dashboard_status.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/tdee_profile.dart';
import 'package:intermittent_fasting/models/weight_entry.dart';
import 'package:intermittent_fasting/utils/body_composition_calculator.dart';

void main() {
  // ── Fixtures ────────────────────────────────────────────────────────────────

  WeightEntry w(double kg) =>
      WeightEntry(id: 'w$kg', weightKg: kg, loggedAt: DateTime(2026, 1, 1));

  BodyMeasurementEntry m(double? waist, {double? neck}) => BodyMeasurementEntry(
        id: 'm${waist}_$neck',
        loggedAt: DateTime(2026, 1, 1),
        waistCm: waist,
        neckCm: neck,
      );

  DailyNutritionLog log({required int calories, double protein = 0}) =>
      DailyNutritionLog(
        date: '2026-01-01',
        meals: {
          MealSlot.meal: [
            FoodEntry(
              id: FoodEntry.generateId(),
              name: 'Food',
              calories: calories,
              protein: protein,
              loggedAt: DateTime(2026, 1, 1),
            ),
          ],
        },
      );

  // ── Weight ───────────────────────────────────────────────────────────────────

  group('weightDelta', () {
    test('null when fewer than 2 entries', () {
      expect(BodyCompositionCalculator.weightDelta([]), isNull);
      expect(BodyCompositionCalculator.weightDelta([w(80)]), isNull);
    });

    test('difference of last two entries', () {
      expect(BodyCompositionCalculator.weightDelta([w(80), w(79.5)]),
          closeTo(-0.5, 1e-9));
    });
  });

  group('weightTrend', () {
    test('insufficient under 4 entries', () {
      expect(BodyCompositionCalculator.weightTrend([w(80), w(80), w(80)]),
          WeightTrendDirection.insufficient);
    });

    test('down when second half lighter', () {
      expect(
        BodyCompositionCalculator.weightTrend([w(82), w(82), w(80), w(80)]),
        WeightTrendDirection.down,
      );
    });

    test('up when second half heavier', () {
      expect(
        BodyCompositionCalculator.weightTrend([w(80), w(80), w(82), w(82)]),
        WeightTrendDirection.up,
      );
    });

    test('stable when within ±0.1', () {
      expect(
        BodyCompositionCalculator.weightTrend([w(80), w(80), w(80), w(80)]),
        WeightTrendDirection.stable,
      );
    });
  });

  // ── Waist ──────────────────────────────────────────────────────────────────

  group('waist', () {
    test('waistDelta ignores entries without waist', () {
      expect(
        BodyCompositionCalculator.waistDelta([m(90), m(null), m(88)]),
        closeTo(-2, 1e-9),
      );
    });

    test('waistTrend down when shrinking', () {
      expect(
        BodyCompositionCalculator.waistTrend([m(92), m(92), m(89), m(89)]),
        MeasurementTrendDirection.down,
      );
    });

    test('hasWaistChartData needs ≥2 waist entries', () {
      expect(BodyCompositionCalculator.hasWaistChartData([m(90)]), isFalse);
      expect(
          BodyCompositionCalculator.hasWaistChartData([m(90), m(89)]), isTrue);
    });

    test('totalWaistChangeCm is last minus first', () {
      expect(
        BodyCompositionCalculator.totalWaistChangeCm([m(95), m(92), m(90)]),
        closeTo(-5, 1e-9),
      );
    });
  });

  // ── 7-day stats ──────────────────────────────────────────────────────────────

  group('sevenDayAvgCalories', () {
    test('zero when no logged days', () {
      expect(BodyCompositionCalculator.sevenDayAvgCalories([]), 0);
      expect(
          BodyCompositionCalculator.sevenDayAvgCalories([log(calories: 0)]), 0);
    });

    test('averages only days with calories > 0', () {
      final history = [
        log(calories: 2000),
        log(calories: 0), // excluded
        log(calories: 2200),
      ];
      expect(BodyCompositionCalculator.sevenDayAvgCalories(history), 2100);
    });
  });

  group('proteinHitRate7d', () {
    final goals = const NutritionGoals(dailyCalories: 2000, proteinGrams: 150);

    test('null when no protein goal', () {
      expect(
        BodyCompositionCalculator.proteinHitRate7d(
          goals: const NutritionGoals(dailyCalories: 2000),
          history: [log(calories: 2000, protein: 200)],
        ),
        isNull,
      );
    });

    test('fraction of days meeting the protein goal', () {
      final history = [
        log(calories: 2000, protein: 160), // hit
        log(calories: 2000, protein: 100), // miss
        log(calories: 2000, protein: 150), // hit (==goal)
        log(calories: 2000, protein: 0), // miss
      ];
      expect(
        BodyCompositionCalculator.proteinHitRate7d(
            goals: goals, history: history),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('loggingConsistency7d', () {
    test('fraction of days with any calories', () {
      final history = [
        log(calories: 2000),
        log(calories: 0),
        log(calories: 0),
        log(calories: 1800),
      ];
      expect(BodyCompositionCalculator.loggingConsistency7d(history),
          closeTo(0.5, 1e-9));
    });
  });

  // ── Dashboard status ───────────────────────────────────────────────────────

  group('dashboardStatus', () {
    final cutProfile = const TdeeProfile(
      weightKg: 80,
      heightCm: 178,
      ageYears: 30,
      sex: 'male',
      activityLevel: ActivityLevel.moderatelyActive,
      goal: 'cut',
    );
    final standardGoals = const NutritionGoals(
      mode: TrackingMode.standard,
      dailyCalories: 2000,
      proteinGrams: 150,
    );

    List<DailyNutritionLog> daysAt(int kcal,
            {int count = 7, double protein = 200}) =>
        List.generate(count, (_) => log(calories: kcal, protein: protein));

    test('needsMoreData with fewer than 3 logged days', () {
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(2000, count: 2),
        profile: cutProfile,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.needsMoreData);
    });

    test('tracking active when profile null', () {
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(2000),
        profile: null,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.onTrack);
      expect(status.headline, 'Tracking active');
    });

    test('cut: too aggressive when well under target', () {
      final target = cutProfile.targetCalories;
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(target - 400),
        profile: cutProfile,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.tooAggressive);
    });

    test('cut: too high when over target', () {
      final target = cutProfile.targetCalories;
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(target + 300),
        profile: cutProfile,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.tooHigh);
    });

    test('cut: low protein when in band but protein hit-rate < 0.5', () {
      final target = cutProfile.targetCalories;
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(target, protein: 0), // protein never hits 150
        profile: cutProfile,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.lowProtein);
    });

    test('cut: on track when in band with good protein', () {
      final target = cutProfile.targetCalories;
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(target, protein: 200),
        profile: cutProfile,
        goals: standardGoals,
        weightLog: const [],
        measurementLog: const [],
      );
      expect(status.label, GoalStatusLabel.onTrack);
    });

    test('cut: recomp confirmed when weight stable ≥14 days and waist down',
        () {
      final target = cutProfile.targetCalories;
      // 14 stable weight entries.
      final weightLog = List.generate(14, (_) => w(80));
      // ≥4 waist entries trending down.
      final measurementLog = [m(92), m(92), m(89), m(89)];
      final status = BodyCompositionCalculator.dashboardStatus(
        history: daysAt(target, protein: 200),
        profile: cutProfile,
        goals: standardGoals,
        weightLog: weightLog,
        measurementLog: measurementLog,
      );
      expect(status.label, GoalStatusLabel.possibleRecomp);
      expect(status.headline, 'Recomp confirmed');
    });
  });

  // ── KPI labels ───────────────────────────────────────────────────────────────

  group('KPI labels', () {
    test('primaryKpiLabel per goal', () {
      expect(
          BodyCompositionCalculator.primaryKpiLabel('cut'), 'Average deficit');
      expect(BodyCompositionCalculator.primaryKpiLabel('bulk'),
          'Surplus adherence');
      expect(
          BodyCompositionCalculator.primaryKpiLabel(null), 'Calorie stability');
    });

    test('weightTrendLabel respects goal context', () {
      expect(
        BodyCompositionCalculator.weightTrendLabel(
            'cut', WeightTrendDirection.down),
        'Trending down ↓',
      );
      expect(
        BodyCompositionCalculator.weightTrendLabel(
            'bulk', WeightTrendDirection.up),
        'Trending up ↑',
      );
    });
  });
}
