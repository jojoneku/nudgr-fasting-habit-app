import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/insight_snapshot_builder.dart';

void main() {
  final fixedNow = DateTime(2026, 7, 12, 21, 30); // evening, so hour = 21

  group('InsightSnapshotBuilder.build — maps inputs to sections', () {
    test('fasting section carries isFasting/streak/goalHours + localHour',
        () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          isFasting: false,
          fastingStreak: 5,
          fastingGoalHours: 16,
        ),
        fixedNow,
      );
      expect(snapshot.fasting.markers['isFasting'], false);
      expect(snapshot.fasting.markers['streak'], 5);
      expect(snapshot.fasting.markers['goalHours'], 16);
      expect(snapshot.fasting.markers['localHour'], 21);
    });

    test('nutrition section carries all provided markers', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          todayCalories: 2200,
          effectiveGoal: 2000,
          sevenDayAvgCalories: 2100,
          proteinHitRate7d: 0.6,
          loggingConsistency7d: 0.85,
          logStreak: 4,
          goalStreak: 2,
        ),
        fixedNow,
      );
      expect(snapshot.nutrition.markers, {
        'todayCalories': 2200,
        'effectiveGoal': 2000,
        'sevenDayAvgCalories': 2100,
        'proteinHitRate7d': 0.6,
        'loggingConsistency7d': 0.85,
        'logStreak': 4,
        'goalStreak': 2,
      });
    });

    test('finance section rounds currency and bakes in date facts', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          monthSpent: 15000.6,
          monthBudget: 20000.2,
          billImminent: true,
          anyCategoryOverBudget: false,
          netCashFlow: -500.0,
        ),
        fixedNow,
      );
      expect(snapshot.finance.markers['monthSpent'], 15001);
      expect(snapshot.finance.markers['monthBudget'], 20000);
      expect(snapshot.finance.markers['billImminent'], true);
      expect(snapshot.finance.markers['anyCategoryOverBudget'], false);
      expect(snapshot.finance.markers['netCashFlowSign'], -1);
      expect(snapshot.finance.markers['dayOfMonth'], 12);
      expect(snapshot.finance.markers['daysInMonth'], 31);
    });

    test('nutrition section rounds fat markers to whole grams', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          sevenDayAvgFatGrams: 89.6,
          fatTargetGrams: 70.4,
        ),
        fixedNow,
      );
      expect(snapshot.nutrition.markers['sevenDayAvgFatGrams'], 90);
      expect(snapshot.nutrition.markers['fatTargetGrams'], 70);
    });

    test('body section rounds weight to 1 decimal', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          latestWeightKg: 70.143,
          daysSinceLastWeightLog: 2,
        ),
        fixedNow,
      );
      expect(snapshot.body.markers['latestWeightKg'], closeTo(70.1, 1e-9));
      expect(snapshot.body.markers['daysSinceLastWeightLog'], 2);
    });

    test('rpg section carries level/xp/hp', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(level: 12, xp: 340, hp: 88),
        fixedNow,
      );
      expect(snapshot.rpg.markers, {'level': 12, 'xp': 340, 'hp': 88});
    });

    test('quests and activity sections carry provided markers', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          questsDueTodayCount: 3,
          hasUrgentQuest: true,
          stepsToday: 8000,
          steps7dAvg: 7000,
        ),
        fixedNow,
      );
      expect(snapshot.quests.markers, {'dueTodayCount': 3, 'hasUrgent': true});
      expect(snapshot.activity.markers,
          {'stepsToday': 8000, 'steps7dAvg': 7000});
    });
  });

  group('InsightSnapshotBuilder.build — null inputs omit markers', () {
    test('all-null inputs leave optional sections empty', () {
      final snapshot =
          InsightSnapshotBuilder.build(const InsightSnapshotInputs(), fixedNow);
      expect(snapshot.nutrition.markers, isEmpty);
      expect(snapshot.finance.markers, {
        // Date facts are always present — they come from `now`, not from
        // presenter data, so they're never null.
        'dayOfMonth': 12,
        'daysInMonth': 31,
      });
      expect(snapshot.quests.markers, isEmpty);
      expect(snapshot.activity.markers, isEmpty);
      expect(snapshot.body.markers, isEmpty);
      expect(snapshot.rpg.markers, isEmpty);
      // Fasting always carries localHour (also a `now`-derived fact).
      expect(snapshot.fasting.markers, {'localHour': 21});
    });

    test('a single missing field is dropped, not stored as null', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(todayCalories: 1800),
        fixedNow,
      );
      expect(snapshot.nutrition.markers.containsKey('todayCalories'), isTrue);
      expect(snapshot.nutrition.markers.containsKey('effectiveGoal'), isFalse);
    });
  });

  group('section hash changes only when that section\'s data changes', () {
    test('changing nutrition input changes only the nutrition hash', () {
      const baseInputs = InsightSnapshotInputs(
        isFasting: true,
        fastingStreak: 4,
        fastingGoalHours: 16,
        todayCalories: 1800,
        effectiveGoal: 2000,
        level: 10,
        xp: 50,
        hp: 90,
      );
      final before = InsightSnapshotBuilder.build(baseInputs, fixedNow);

      const changedInputs = InsightSnapshotInputs(
        isFasting: true,
        fastingStreak: 4,
        fastingGoalHours: 16,
        todayCalories: 2500, // only this changed
        effectiveGoal: 2000,
        level: 10,
        xp: 50,
        hp: 90,
      );
      final after = InsightSnapshotBuilder.build(changedInputs, fixedNow);

      expect(before.nutrition.hash, isNot(after.nutrition.hash));
      expect(before.fasting.hash, after.fasting.hash);
      expect(before.rpg.hash, after.rpg.hash);
    });

    test('identical inputs at the same instant produce identical hashes',
        () {
      const inputs = InsightSnapshotInputs(
        isFasting: false,
        fastingStreak: 2,
        stepsToday: 5000,
      );
      final a = InsightSnapshotBuilder.build(inputs, fixedNow);
      final b = InsightSnapshotBuilder.build(inputs, fixedNow);
      expect(a.sectionHashes, b.sectionHashes);
    });
  });

  group('toPromptDigest', () {
    test('marks changed sections with [NEW] and stays compact', () {
      final snapshot = InsightSnapshotBuilder.build(
        const InsightSnapshotInputs(
          isFasting: true,
          fastingStreak: 4,
          todayCalories: 1800,
        ),
        fixedNow,
      );
      final digest =
          snapshot.toPromptDigest(changedSections: {'nutrition'});
      final lines = digest.split('\n');
      expect(lines.length, snapshot.sections.length);
      expect(lines.any((l) => l.startsWith('Nutrition [NEW]:')), isTrue);
      expect(lines.any((l) => l.startsWith('Fasting:')), isTrue);
    });
  });
}
