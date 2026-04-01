import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';

void main() {
  late StorageService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = StorageService();
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
      final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
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

    test('saveActivityGoalMetDate / loadActivityGoalMetDate round-trip', () async {
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
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
