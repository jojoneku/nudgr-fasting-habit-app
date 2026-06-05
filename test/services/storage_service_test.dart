import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/models/weight_entry.dart';
import 'package:intermittent_fasting/models/body_measurement_entry.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/food_feedback.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';

void main() {
  late LocalStorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = LocalStorageService();
  });

  // ── Activity ────────────────────────────────────────────────────────────────

  group('StorageService — activity', () {
    test('loadTodayActivityLog returns empty log when nothing saved', () async {
      final log = await svc.loadTodayActivityLog();
      expect(log.steps, 0);
    });

    test('saveActivityLog / loadTodayActivityLog round-trip', () async {
      final today = _todayKey();
      final log = ActivityLog(date: today, steps: 5000, isManualEntry: true);
      await svc.saveActivityLog(log);
      final loaded = await svc.loadTodayActivityLog();
      expect(loaded.steps, 5000);
      expect(loaded.isManualEntry, true);
    });

    test('loadActivityHistory excludes today', () async {
      final today = _todayKey();
      final yesterday =
          _dateKey(DateTime.now().subtract(const Duration(days: 1)));
      await svc.saveActivityLog(ActivityLog(date: today, steps: 1000));
      await svc.saveActivityLog(ActivityLog(date: yesterday, steps: 2000));
      final history = await svc.loadActivityHistory();
      expect(history.any((l) => l.date == today), false);
      expect(history.any((l) => l.date == yesterday), true);
    });

    test('loadActivityGoals returns initial when nothing saved', () async {
      final goals = await svc.loadActivityGoals();
      expect(goals.dailyStepGoal, 8000);
    });

    test('saveActivityGoals / loadActivityGoals round-trip', () async {
      await svc.saveActivityGoals(const ActivityGoals(dailyStepGoal: 12000));
      final loaded = await svc.loadActivityGoals();
      expect(loaded.dailyStepGoal, 12000);
    });

    test('saveActivityStreak / loadActivityStreak round-trip', () async {
      await svc.saveActivityStreak(7);
      expect(await svc.loadActivityStreak(), 7);
    });

    test('loadActivityStreak returns 0 when nothing saved', () async {
      expect(await svc.loadActivityStreak(), 0);
    });

    test('saveActivityGoalMetDate / loadActivityGoalMetDate round-trip',
        () async {
      await svc.saveActivityGoalMetDate('2026-03-25');
      expect(await svc.loadActivityGoalMetDate(), '2026-03-25');
    });
  });

  // ── UserStats ────────────────────────────────────────────────────────────────

  group('StorageService — user stats', () {
    test('loadUserStats returns initial when nothing saved', () async {
      final stats = await svc.loadUserStats();
      expect(stats.level, 1);
      expect(stats.currentXp, 0);
    });

    test('saveUserStats / loadUserStats round-trip', () async {
      final stats = UserStats.initial().copyWith(level: 5, currentXp: 200);
      await svc.saveUserStats(stats);
      final loaded = await svc.loadUserStats();
      expect(loaded.level, 5);
      expect(loaded.currentXp, 200);
    });
  });

  // ── Weight / body measurements sync coverage ─────────────────────────────────
  // Regression guard: these were local-only and silently lost on sign-out.
  // They must now mark the userProfile domain dirty so they reach the cloud.

  group('StorageService — weight & body sync', () {
    test('saveWeightLog marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 72.5, loggedAt: DateTime(2026, 6, 1)),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('saveBodyMeasurements marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveBodyMeasurements([
        BodyMeasurementEntry(
            id: 'b1', loggedAt: DateTime(2026, 6, 1), waistCm: 80),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('weight log round-trips through storage', () async {
      await svc.saveWeightLog([
        WeightEntry(id: 'w1', weightKg: 70, loggedAt: DateTime(2026, 5, 30)),
      ]);
      final loaded = await svc.loadWeightLog();
      expect(loaded.length, 1);
      expect(loaded.first.weightKg, 70);
    });

    test('measurementUnit marks userProfile dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveMeasurementUnit(MeasurementUnit.imperial);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('calorie-goal credit ledger marks userProfile dirty for sync',
        () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveCalorieGoalCreditedDates({'2026-06-01'});
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userProfile),
        true,
      );
    });

    test('food feedback marks userCollections dirty for sync', () async {
      final queue = SyncQueue();
      svc.setSyncQueue(queue);
      await svc.saveFoodFeedback([
        FoodFeedback(
          id: 'f1',
          timestamp: DateTime(2026, 6, 1),
          kind: FoodFeedbackKind.userDislike,
          userQuery: 'rice',
          pickedName: 'White rice',
          estimationSource: 'db',
        ),
      ]);
      expect(
        queue.entries.any((e) => e.domain == SyncDomain.userCollections),
        true,
      );
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
