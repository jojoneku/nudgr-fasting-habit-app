import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/presenters/activity_presenter.dart';
import 'package:intermittent_fasting/models/activity_log.dart';
import 'package:intermittent_fasting/models/activity_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late MockHealthService mockHealth;
  late MockStatsPresenter mockStats;
  late ActivityPresenter presenter;

  final today = _todayKey();

  setUp(() async {
    mockStorage = MockStorageService();
    mockHealth = MockHealthService();
    mockStats = MockStatsPresenter();

    // Default storage stubs
    when(mockStorage.loadTodayActivityLog())
        .thenAnswer((_) async => ActivityLog.empty(today));
    when(mockStorage.loadActivityGoals())
        .thenAnswer((_) async => ActivityGoals.initial());
    when(mockStorage.loadActivityHistory()).thenAnswer((_) async => []);
    when(mockStorage.loadActivityGoalMetDate()).thenAnswer((_) async => null);
    when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 0);
    when(mockStorage.saveActivityLog(any)).thenAnswer((_) async {});
    when(mockStorage.saveActivityGoals(any)).thenAnswer((_) async {});
    when(mockStorage.saveActivityGoalMetDate(any)).thenAnswer((_) async {});
    when(mockStorage.saveActivityStreak(any)).thenAnswer((_) async {});

    // Default stats stubs
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});
    when(mockStats.stats).thenReturn(UserStats.initial());

    // Default health stubs — unavailable by default
    when(mockHealth.isAvailable()).thenAnswer((_) async => false);
    when(mockHealth.hasPermissions()).thenAnswer((_) async => false);

    presenter = ActivityPresenter(
      statsPresenter: mockStats,
      healthService: mockHealth,
      storage: mockStorage,
    );
    // Wait for loadState to complete
    await Future.delayed(Duration.zero);
  });

  // ── Computed getters ────────────────────────────────────────────────────────

  group('computed getters', () {
    test('stepProgress is 0 with no steps', () {
      expect(presenter.stepProgress, 0.0);
    });

    test('isGoalMet is false when below goal', () {
      expect(presenter.isGoalMet, false);
    });

    test('summaryLabel formats correctly', () {
      expect(presenter.summaryLabel, contains('8,000 steps'));
    });

    test('hubSubtitle shows connect prompt when no HC permission', () {
      expect(presenter.hubSubtitle, 'Tap to connect Health');
    });
  });

  // ── Manual steps + RPG awards ───────────────────────────────────────────────

  group('setManualSteps — XP and AGI', () {
    test('awards 25 XP first time goal is met today', () async {
      await presenter.setManualSteps(8000);
      verify(mockStats.addXp(25)).called(1);
    });

    test('does not award XP when steps below goal', () async {
      await presenter.setManualSteps(4000);
      verifyNever(mockStats.addXp(any));
    });

    test('does not double-award XP if goal already met today', () async {
      when(mockStorage.loadActivityGoalMetDate())
          .thenAnswer((_) async => today);
      // Recreate presenter with updated stub
      presenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);
      await presenter.setManualSteps(9000);
      verifyNever(mockStats.addXp(any));
    });

    test('awards AGI on 5-day streak', () async {
      when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 4);
      presenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);
      await presenter.setManualSteps(8000);
      // _updateStreakAndAwardAgi is unawaited — give it a microtask to complete
      await Future.delayed(Duration.zero);
      verify(mockStats.awardStat('agi')).called(1);
    });

    test('does not award AGI on non-5-day streak', () async {
      when(mockStorage.loadActivityStreak()).thenAnswer((_) async => 3);
      presenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);
      await presenter.setManualSteps(8000);
      verifyNever(mockStats.awardStat(any));
    });

    test('marks entry as manual', () async {
      await presenter.setManualSteps(5000);
      expect(presenter.todayLog.isManualEntry, true);
    });

    test('updates todaySteps correctly', () async {
      await presenter.setManualSteps(6240);
      expect(presenter.todaySteps, 6240);
    });
  });

  // ── Goal update ─────────────────────────────────────────────────────────────

  group('updateGoals', () {
    test('updates daily step goal', () async {
      await presenter.updateGoals(const ActivityGoals(dailyStepGoal: 10000));
      expect(presenter.goals.dailyStepGoal, 10000);
      verify(mockStorage.saveActivityGoals(any)).called(1);
    });
  });

  // ── Health Connect ──────────────────────────────────────────────────────────

  group('Health Connect', () {
    test('syncFromHealthConnect does nothing if no permission', () async {
      await presenter.syncFromHealthConnect();
      verifyNever(mockHealth.readTodaySteps());
    });

    test('syncFromHealthConnect reads steps when permitted', () async {
      when(mockHealth.isAvailable()).thenAnswer((_) async => true);
      when(mockHealth.hasPermissions()).thenAnswer((_) async => true);
      when(mockHealth.readTodaySteps()).thenAnswer((_) async => 7500);
      when(mockHealth.readTodayActiveCalories()).thenAnswer((_) async => null);
      when(mockHealth.readTodayDistance()).thenAnswer((_) async => null);

      presenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);
      await presenter.syncFromHealthConnect();
      expect(presenter.todaySteps, 7500);
    });

    test('requestHealthPermission syncs after grant', () async {
      when(mockHealth.isAvailable()).thenAnswer((_) async => true);
      when(mockHealth.hasPermissions()).thenAnswer((_) async => false);
      when(mockHealth.requestPermissions()).thenAnswer((_) async => true);
      when(mockHealth.readTodaySteps()).thenAnswer((_) async => 3000);
      when(mockHealth.readTodayActiveCalories()).thenAnswer((_) async => null);
      when(mockHealth.readTodayDistance()).thenAnswer((_) async => null);

      presenter = ActivityPresenter(
        statsPresenter: mockStats,
        healthService: mockHealth,
        storage: mockStorage,
      );
      await Future.delayed(Duration.zero);
      await presenter.requestHealthPermission();
      expect(presenter.hasHealthPermission, true);
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
