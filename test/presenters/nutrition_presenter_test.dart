import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import '../mocks.mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;
  late MockFastingPresenter mockFasting;
  late MockAiCoachService mockAi;
  late NutritionPresenter presenter;

  final today = _todayKey();

  FoodEntry makeEntry(
          {int calories = 500, double protein = 0, String name = 'Food'}) =>
      FoodEntry(
        id: FoodEntry.generateId(),
        name: name,
        calories: calories,
        protein: protein,
        loggedAt: DateTime.now(),
      );

  setUp(() async {
    mockStorage = MockStorageService();
    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    mockStats = MockStatsPresenter();
    mockFasting = MockFastingPresenter();
    mockAi = MockAiCoachService();

    // Default storage stubs
    when(mockStorage.loadTodayNutritionLog())
        .thenAnswer((_) async => DailyNutritionLog.empty(today));
    when(mockStorage.loadNutritionGoals())
        .thenAnswer((_) async => NutritionGoals.initial());
    when(mockStorage.loadNutritionHistory()).thenAnswer((_) async => []);
    when(mockStorage.loadTdeeProfile()).thenAnswer((_) async => null);
    when(mockStorage.loadFoodLibrary()).thenAnswer((_) async => []);
    when(mockStorage.loadNutritionStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
    when(mockStorage.loadLogStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadLogStreakDate()).thenAnswer((_) async => null);
    when(mockStorage.saveNutritionLog(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionGoals(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionStreak(any)).thenAnswer((_) async {});
    when(mockStorage.saveNutritionGoalMetDate(any)).thenAnswer((_) async {});
    when(mockStorage.saveLogStreak(any)).thenAnswer((_) async {});
    when(mockStorage.saveLogStreakDate(any)).thenAnswer((_) async {});
    when(mockStorage.loadCalorieGoalCreditedDates())
        .thenAnswer((_) async => <String>{});
    when(mockStorage.loadProteinGoalCreditedDates())
        .thenAnswer((_) async => <String>{});
    when(mockStorage.loadStreakMilestonePaid()).thenAnswer((_) async => 0);
    when(mockStorage.saveCalorieGoalCreditedDates(any))
        .thenAnswer((_) async {});
    when(mockStorage.saveProteinGoalCreditedDates(any))
        .thenAnswer((_) async {});
    when(mockStorage.saveStreakMilestonePaid(any)).thenAnswer((_) async {});
    when(mockStorage.loadPersonalDict()).thenAnswer((_) async => []);
    when(mockStorage.loadFoodFeedback()).thenAnswer((_) async => []);
    when(mockStorage.saveFoodFeedback(any)).thenAnswer((_) async {});
    when(mockStorage.loadChatMessagesRaw(any)).thenAnswer((_) async => []);
    when(mockStorage.loadWeightLog()).thenAnswer((_) async => []);
    when(mockStorage.loadBodyMeasurements()).thenAnswer((_) async => []);
    when(mockStorage.loadMeasurementUnit())
        .thenAnswer((_) async => MeasurementUnit.metric);
    when(mockStorage.loadLastRecompXpDate()).thenAnswer((_) async => null);
    when(mockStorage.loadNutritionLogForDate(any))
        .thenAnswer((_) async => DailyNutritionLog.empty('2026-05-27'));

    // Stats stubs
    when(mockStats.stats).thenReturn(UserStats.initial());
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.modifyHp(any)).thenAnswer((_) async {});
    when(mockStats.awardStat(any)).thenAnswer((_) async {});

    // Fasting stubs — not fasting by default
    when(mockFasting.isFasting).thenReturn(false);

    // AI stubs — unavailable by default
    when(mockAi.isAvailable).thenReturn(false);
    when(mockAi.downloadProgress).thenReturn(null);

    presenter = NutritionPresenter(
      statsPresenter: mockStats,
      fastingPresenter: mockFasting,
      storage: mockStorage,
      foodDb: MockFoodDbService(),
      aiCoach: mockAi,
    );
    await Future.delayed(Duration.zero);
  });

  // ── Calorie tracking ─────────────────────────────────────────────────────────

  group('calorie tracking', () {
    test('adding entry increases todayCalories', () async {
      await presenter.addFoodEntry(makeEntry(calories: 600), MealSlot.meal);
      expect(presenter.todayCalories, 600);
    });

    test('summaryLabel includes total and goal', () async {
      await presenter.addFoodEntry(makeEntry(calories: 500), MealSlot.meal);
      expect(presenter.summaryLabel, contains('500'));
      expect(presenter.summaryLabel, contains('2,000'));
    });

    test('calorieProgress is 0 when no entries', () {
      expect(presenter.calorieProgress, 0.0);
    });

    test('isCalorieGoalMet false when under goal', () async {
      await presenter.addFoodEntry(makeEntry(calories: 1000), MealSlot.meal);
      expect(presenter.isCalorieGoalMet, false);
    });
  });

  // ── RPG: calorie goal XP ─────────────────────────────────────────────────────

  group('RPG — calorie goal', () {
    test('awards 30 XP first time goal is met today', () async {
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);
      verify(mockStats.addXp(30)).called(1);
    });

    test('does not double-award XP when goal already met today', () async {
      when(mockStorage.loadNutritionGoalMetDate())
          .thenAnswer((_) async => today);
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);
      verifyNever(mockStats.addXp(30));
    });

    test('awards +10 XP bonus when IF sync is enabled', () async {
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, ifSyncEnabled: true));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);
      // Should receive 30 + 10 = two separate addXp calls
      verify(mockStats.addXp(30)).called(1);
      verify(mockStats.addXp(10)).called(1);
    });
  });

  // ── RPG: protein goal ────────────────────────────────────────────────────────

  group('RPG — protein goal', () {
    setUp(() async {
      when(mockStorage.loadNutritionGoals()).thenAnswer(
          (_) async => NutritionGoals(dailyCalories: 2000, proteinGrams: 150));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
    });

    test('awards 15 XP + STR when protein goal met', () async {
      await presenter.addFoodEntry(
          makeEntry(calories: 100, protein: 150), MealSlot.meal);
      verify(mockStats.addXp(15)).called(1);
      verify(mockStats.awardStat('str')).called(1);
    });

    test('does not double-award protein XP in same session', () async {
      await presenter.addFoodEntry(
          makeEntry(calories: 100, protein: 150), MealSlot.meal);
      await presenter.addFoodEntry(
          makeEntry(calories: 100, protein: 10), MealSlot.meal);
      verify(mockStats.addXp(15)).called(1); // only once
    });
  });

  // ── RPG: overshoot penalty ───────────────────────────────────────────────────

  group('RPG — overshoot penalty', () {
    setUp(() async {
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, overshootPenaltyEnabled: true));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
    });

    test('applies -5 HP when over 120% of goal', () async {
      // 2000 * 1.2 = 2400, so add 2401 kcal
      await presenter.addFoodEntry(makeEntry(calories: 2401), MealSlot.meal);
      verify(mockStats.modifyHp(-5)).called(1);
    });

    test('no penalty when under 120% threshold', () async {
      await presenter.addFoodEntry(makeEntry(calories: 2399), MealSlot.meal);
      verifyNever(mockStats.modifyHp(-5));
    });
  });

  // ── IF sync gate ─────────────────────────────────────────────────────────────

  group('IF sync', () {
    test('blocks entry during fast when ifSyncEnabled is true', () async {
      when(mockFasting.isFasting).thenReturn(true);
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, ifSyncEnabled: true));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
      await presenter.addFoodEntry(makeEntry(calories: 500), MealSlot.meal);
      expect(presenter.todayCalories, 0);
    });

    test('allows entry when not fasting with ifSyncEnabled', () async {
      when(mockFasting.isFasting).thenReturn(false);
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, ifSyncEnabled: true));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      await Future.delayed(Duration.zero);
      await presenter.addFoodEntry(makeEntry(calories: 300), MealSlot.meal);
      expect(presenter.todayCalories, 300);
    });
  });

  // ── hubSubtitle ──────────────────────────────────────────────────────────────

  group('hubSubtitle', () {
    test('returns log prompt when no entries', () {
      expect(presenter.hubSubtitle, 'Tap to log meals');
    });

    test('returns goal reached when met', () async {
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);
      expect(presenter.hubSubtitle, 'Goal reached! ✓');
    });
  });

  // ── removeFoodEntry ───────────────────────────────────────────────────────────

  group('removeFoodEntry', () {
    test('decreases calorie count', () async {
      final entry = makeEntry(calories: 300);
      await presenter.addFoodEntry(entry, MealSlot.meal);
      await presenter.removeFoodEntry(entry.id, MealSlot.meal);
      expect(presenter.todayCalories, 0);
    });
  });

  // ── Backdated (past-day) logging — Plan 037 ──────────────────────────────────

  group('backdated logging', () {
    const pastKey = '2026-05-27';

    NutritionPresenter build() {
      final p = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
      );
      return p;
    }

    setUp(() {
      // Echo the requested date so _todayLog.date matches the selected day.
      when(mockStorage.loadNutritionLogForDate(any)).thenAnswer((inv) async =>
          DailyNutritionLog.empty(inv.positionalArguments[0] as String));
    });

    test('past-day logging is allowed even while currently fasting', () async {
      when(mockFasting.isFasting).thenReturn(true);
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, ifSyncEnabled: true));
      presenter = build();
      await Future.delayed(Duration.zero);

      // Today + fasting + ifSync → gated, nothing logged.
      await presenter.addFoodEntry(makeEntry(calories: 500), MealSlot.meal);
      expect(presenter.todayCalories, 0);

      // Past day → allowed despite currently fasting.
      await presenter.setSelectedDate(DateTime.parse(pastKey));
      await presenter.addFoodEntry(makeEntry(calories: 500), MealSlot.meal);
      expect(presenter.todayCalories, 500);
    });

    test('past-day goal XP is awarded once, with no IF-sync bonus', () async {
      when(mockStorage.loadNutritionGoals()).thenAnswer((_) async =>
          NutritionGoals(dailyCalories: 2000, ifSyncEnabled: true));
      presenter = build();
      await Future.delayed(Duration.zero);

      await presenter.setSelectedDate(DateTime.parse(pastKey));
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);
      // Re-opening / adding to the same already-credited day must not re-award.
      await presenter.addFoodEntry(makeEntry(calories: 100), MealSlot.meal);

      verify(mockStats.addXp(30)).called(1);
      verifyNever(mockStats.addXp(10)); // IF-sync bonus dropped for backfills
    });

    test('backfilling a gap day repairs the log streak', () async {
      when(mockStorage.loadNutritionHistory()).thenAnswer((_) async => [
            DailyNutritionLog.empty('2026-05-25')
                .addEntry(makeEntry(calories: 500), MealSlot.meal),
            DailyNutritionLog.empty('2026-05-27')
                .addEntry(makeEntry(calories: 500), MealSlot.meal),
          ]);
      presenter = build();
      await Future.delayed(Duration.zero);

      // Backfill the missing middle day (2026-05-26).
      await presenter.setSelectedDate(DateTime.parse('2026-05-26'));
      await presenter.addFoodEntry(makeEntry(calories: 500), MealSlot.meal);

      // 25 → 26 → 27 now contiguous → run ending at the latest logged day = 3.
      expect(presenter.logStreak, 3);
    });

    test('no goal-met notification fires for a past day', () async {
      final mockNotifs = MockNotificationService();
      when(mockNotifs.showCalorieGoalNotification(any, any))
          .thenAnswer((_) async {});
      when(mockNotifs.scheduleWeightReminder(any)).thenAnswer((_) async {});
      when(mockNotifs.cancelWeightReminder()).thenAnswer((_) async {});
      when(mockStorage.loadNutritionGoals())
          .thenAnswer((_) async => NutritionGoals(dailyCalories: 2000));
      presenter = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: MockFoodDbService(),
        aiCoach: mockAi,
        notifications: mockNotifs,
      );
      await Future.delayed(Duration.zero);

      await presenter.setSelectedDate(DateTime.parse(pastKey));
      await presenter.addFoodEntry(makeEntry(calories: 2000), MealSlot.meal);

      verifyNever(mockNotifs.showCalorieGoalNotification(any, any));
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
