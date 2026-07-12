import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/insight.dart';
import 'package:intermittent_fasting/utils/insight_snapshot_builder.dart';
import 'package:intermittent_fasting/utils/insight_triggers.dart';

void main() {
  final fixedNow = DateTime(2026, 7, 12, 21, 0); // 9pm local

  InsightTrigger triggerById(String id) =>
      allInsightTriggers.firstWhere((t) => t.id == id);

  bool fires(String id, InsightSnapshotInputs inputs, {DateTime? now}) {
    final snapshot = InsightSnapshotBuilder.build(inputs, now ?? fixedNow);
    return triggerById(id).test(snapshot);
  }

  test('trigger table has all 10 v1 triggers with unique ids', () {
    expect(allInsightTriggers.length, 10);
    expect(allInsightTriggers.map((t) => t.id).toSet().length, 10);
  });

  group('nutrition.overGoal', () {
    test('does not fire at or under the 10% threshold', () {
      expect(
        fires('nutrition.overGoal',
            const InsightSnapshotInputs(todayCalories: 2200, effectiveGoal: 2000)),
        isFalse,
      );
    });

    test('fires just over the 10% threshold', () {
      expect(
        fires('nutrition.overGoal',
            const InsightSnapshotInputs(todayCalories: 2201, effectiveGoal: 2000)),
        isTrue,
      );
    });

    test('missing data does not fire', () {
      expect(fires('nutrition.overGoal', const InsightSnapshotInputs()),
          isFalse);
    });
  });

  group('finance.spendPace', () {
    test('fires when spend outpaces prorated budget by >15%', () {
      // day 15 of a 30-day month, budget 10000 → expected pace 5000 * 1.15 = 5750
      final now = DateTime(2026, 6, 15);
      expect(
        fires(
          'finance.spendPace',
          const InsightSnapshotInputs(monthSpent: 6000, monthBudget: 10000),
          now: now,
        ),
        isTrue,
      );
    });

    test('does not fire within pace', () {
      final now = DateTime(2026, 6, 15);
      expect(
        fires(
          'finance.spendPace',
          const InsightSnapshotInputs(monthSpent: 5000, monthBudget: 10000),
          now: now,
        ),
        isFalse,
      );
    });

    test('missing budget does not fire', () {
      expect(
        fires('finance.spendPace',
            const InsightSnapshotInputs(monthSpent: 6000)),
        isFalse,
      );
    });
  });

  group('finance.categoryBlown', () {
    test('fires when any category is over budget', () {
      expect(
        fires('finance.categoryBlown',
            const InsightSnapshotInputs(anyCategoryOverBudget: true)),
        isTrue,
      );
    });

    test('does not fire when no category is over budget', () {
      expect(
        fires('finance.categoryBlown',
            const InsightSnapshotInputs(anyCategoryOverBudget: false)),
        isFalse,
      );
    });

    test('missing data does not fire', () {
      expect(fires('finance.categoryBlown', const InsightSnapshotInputs()),
          isFalse);
    });
  });

  group('finance.billImminent', () {
    test('fires when a bill is imminent', () {
      expect(
        fires('finance.billImminent',
            const InsightSnapshotInputs(billImminent: true)),
        isTrue,
      );
    });

    test('does not fire otherwise', () {
      expect(
        fires('finance.billImminent',
            const InsightSnapshotInputs(billImminent: false)),
        isFalse,
      );
    });
  });

  group('fasting.streakAtRisk', () {
    InsightSnapshotInputs inputs({
      required bool isFasting,
      required int streak,
    }) =>
        InsightSnapshotInputs(isFasting: isFasting, fastingStreak: streak);

    test('fires at streak 3, not fasting, 8pm or later', () {
      expect(
        fires('fasting.streakAtRisk', inputs(isFasting: false, streak: 3),
            now: DateTime(2026, 7, 12, 20, 0)),
        isTrue,
      );
    });

    test('does not fire before 8pm', () {
      expect(
        fires('fasting.streakAtRisk', inputs(isFasting: false, streak: 3),
            now: DateTime(2026, 7, 12, 19, 59)),
        isFalse,
      );
    });

    test('does not fire while already fasting', () {
      expect(
        fires('fasting.streakAtRisk', inputs(isFasting: true, streak: 5)),
        isFalse,
      );
    });

    test('does not fire below streak 3', () {
      expect(
        fires('fasting.streakAtRisk', inputs(isFasting: false, streak: 2)),
        isFalse,
      );
    });

    test('missing data does not fire', () {
      expect(fires('fasting.streakAtRisk', const InsightSnapshotInputs()),
          isFalse);
    });
  });

  group('body.weightStale', () {
    test('does not fire under 7 days', () {
      expect(
        fires('body.weightStale',
            const InsightSnapshotInputs(daysSinceLastWeightLog: 6)),
        isFalse,
      );
    });

    test('fires at exactly 7 days', () {
      expect(
        fires('body.weightStale',
            const InsightSnapshotInputs(daysSinceLastWeightLog: 7)),
        isTrue,
      );
    });

    test('missing data does not fire', () {
      expect(fires('body.weightStale', const InsightSnapshotInputs()),
          isFalse);
    });
  });

  group('nutrition.proteinLow', () {
    test('fires when hit rate is low and enough days logged', () {
      expect(
        fires(
          'nutrition.proteinLow',
          const InsightSnapshotInputs(
            proteinHitRate7d: 0.3,
            loggingConsistency7d: 0.85, // ~6 of 7 days
          ),
        ),
        isTrue,
      );
    });

    test('does not fire with too few logged days', () {
      expect(
        fires(
          'nutrition.proteinLow',
          const InsightSnapshotInputs(
            proteinHitRate7d: 0.3,
            loggingConsistency7d: 0.2, // ~1 of 7 days
          ),
        ),
        isFalse,
      );
    });

    test('does not fire above the 0.4 threshold', () {
      expect(
        fires(
          'nutrition.proteinLow',
          const InsightSnapshotInputs(
            proteinHitRate7d: 0.5,
            loggingConsistency7d: 1.0,
          ),
        ),
        isFalse,
      );
    });
  });

  group('positive.onFire', () {
    test('fires with 3+ green domains', () {
      expect(
        fires(
          'positive.onFire',
          const InsightSnapshotInputs(
            todayCalories: 1800,
            effectiveGoal: 2000,
            monthSpent: 4000,
            monthBudget: 10000,
            fastingStreak: 5,
            stepsToday: 3000,
            steps7dAvg: 5000,
          ),
        ),
        isTrue,
      );
    });

    test('does not fire with only 2 green domains', () {
      expect(
        fires(
          'positive.onFire',
          const InsightSnapshotInputs(
            todayCalories: 1800,
            effectiveGoal: 2000,
            monthSpent: 4000,
            monthBudget: 10000,
            fastingStreak: 1,
            stepsToday: 1000,
            steps7dAvg: 5000,
          ),
        ),
        isFalse,
      );
    });
  });

  group('always-dormant triggers (no backing data source yet)', () {
    test('nutrition.fatTrend never fires — no 7d fat marker exists', () {
      expect(
        fires(
          'nutrition.fatTrend',
          const InsightSnapshotInputs(
            todayCalories: 5000,
            effectiveGoal: 100,
          ),
        ),
        isFalse,
      );
    });

    test('quests.slipping never fires — no 7d completion-rate marker exists',
        () {
      expect(
        fires(
          'quests.slipping',
          const InsightSnapshotInputs(
            questsDueTodayCount: 5,
            hasUrgentQuest: true,
          ),
        ),
        isFalse,
      );
    });
  });

  group('evaluateTriggers — cooldowns', () {
    test('suppresses a trigger fired within its cooldown window', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(billImminent: true),
        fixedNow,
      );
      final lastFired = {
        'finance.billImminent': fixedNow.subtract(const Duration(hours: 1)),
      };
      final result = evaluateTriggers(snapshot, lastFired, fixedNow);
      expect(result.any((t) => t.id == 'finance.billImminent'), isFalse);
    });

    test('re-fires once the cooldown has elapsed', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(billImminent: true),
        fixedNow,
      );
      final lastFired = {
        'finance.billImminent':
            fixedNow.subtract(const Duration(days: 1, minutes: 1)),
      };
      final result = evaluateTriggers(snapshot, lastFired, fixedNow);
      expect(result.any((t) => t.id == 'finance.billImminent'), isTrue);
    });

    test('a trigger with no prior fire is never suppressed by cooldown', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(billImminent: true),
        fixedNow,
      );
      final result = evaluateTriggers(snapshot, {}, fixedNow);
      expect(result.any((t) => t.id == 'finance.billImminent'), isTrue);
    });

    test('fallbackText always produces non-empty System-voice text', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          todayCalories: 2500,
          effectiveGoal: 2000,
        ),
        fixedNow,
      );
      final trigger = triggerById('nutrition.overGoal');
      expect(trigger.fallbackText(snapshot), isNotEmpty);
      expect(trigger.mood, InsightMood.urgent);
    });
  });
}
