import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';

void main() {
  group('ActivityLog', () {
    test('empty() has zero steps and correct date', () {
      final log = ActivityLog.empty('2026-03-25');
      expect(log.steps, 0);
      expect(log.date, '2026-03-25');
      expect(log.isManualEntry, false);
    });

    test('fromJson/toJson round-trip', () {
      final log = ActivityLog(
        date: '2026-03-25',
        steps: 6240,
        activeCalories: 340.5,
        distanceMeters: 4800.0,
        isManualEntry: true,
      );
      final restored = ActivityLog.fromJson(log.toJson());
      expect(restored.date, log.date);
      expect(restored.steps, log.steps);
      expect(restored.activeCalories, log.activeCalories);
      expect(restored.distanceMeters, log.distanceMeters);
      expect(restored.isManualEntry, log.isManualEntry);
    });

    test('fromJson handles missing optional fields', () {
      final log = ActivityLog.fromJson({'date': '2026-03-25', 'steps': 1000});
      expect(log.activeCalories, isNull);
      expect(log.distanceMeters, isNull);
      expect(log.isManualEntry, false);
    });

    test('copyWith preserves unchanged fields', () {
      final log = ActivityLog(date: '2026-03-25', steps: 100, isManualEntry: false);
      final updated = log.copyWith(steps: 5000, isManualEntry: true);
      expect(updated.steps, 5000);
      expect(updated.isManualEntry, true);
      expect(updated.date, '2026-03-25');
    });
  });

  group('ActivityGoals', () {
    test('initial() has 8000 step goal', () {
      expect(ActivityGoals.initial().dailyStepGoal, 8000);
    });

    test('fromJson/toJson round-trip', () {
      final goals = ActivityGoals(dailyStepGoal: 10000);
      final restored = ActivityGoals.fromJson(goals.toJson());
      expect(restored.dailyStepGoal, 10000);
    });

    test('fromJson defaults to 8000 when field missing', () {
      final goals = ActivityGoals.fromJson({});
      expect(goals.dailyStepGoal, 8000);
    });

    test('copyWith updates goal', () {
      final goals = ActivityGoals(dailyStepGoal: 8000);
      expect(goals.copyWith(dailyStepGoal: 12000).dailyStepGoal, 12000);
    });
  });
}
