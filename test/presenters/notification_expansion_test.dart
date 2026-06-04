// Tests for Plan 027 — Notification Expansion.
//
// Covers all 11 scenarios specified in the plan:
//   1.  addXp() level-up    → showLevelUpNotification called once
//   2.  Level-up rank cross → showRankPromotionNotification, NOT level-up
//   3.  levelUpEnabled=false → neither notification called
//   4.  logWeight()          → cancelWeightReminder called
//   5.  weightReminderEnabled=true → scheduleWeightReminder on init
//   6.  Food entry pushes calories >= goal → showCalorieGoalNotification once
//   7.  Same food entry again (already over) → notification not called again
//   8.  calorieGoalEnabled=false → no notification even when goal met
//   9.  Budget crosses 80% → showBudgetWarning called
//  10.  Budget drops below 80% → warning cleared (re-fires on next cross)
//  11.  budgetWarningEnabled=false → no warning called

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_meal_estimate.dart';
import 'package:intermittent_fasting/models/ai_parsed_food.dart';
import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/estimation_source.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/food_parse_result.dart';
import 'package:intermittent_fasting/models/food_search_candidate.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

// ── Minimal no-op AiCoachService for NutritionPresenter tests ────────────────

class _NoOpAiCoach implements AiCoachService {
  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  bool get isAvailable => false;

  @override
  int? get downloadProgress => null;

  @override
  Future<void> downloadModel({void Function(int progress)? onProgress}) async {}

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async =>
      null;

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {}

  @override
  Future<FoodParseResult?> parseFood(String description) async => null;

  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async => null;

  @override
  Future<ParseFoodResult?> parseFoodWithCandidates(
    String text,
    List<FoodSearchCandidate> candidates,
  ) async =>
      null;

  @override
  Future<PhotoParseResult> parseFoodFromImage(
    Uint8List imageBytes,
    String mimeType,
    String? caption,
  ) async =>
      const PhotoParseResult(PhotoParseStatus.unavailable);

  @override
  Future<AiMealEstimate?> estimateMacros(String description) async => null;

  @override
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
          List<AiParsedFood> items) async =>
      null;

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(
          List<String> fragments) async =>
      null;

  @override
  Future<FoodDisambiguation?> disambiguateFood(
    String query,
    List<FoodSearchCandidate> candidates,
  ) async =>
      null;

  @override
  void dispose() {}
}

// ── Test helpers ──────────────────────────────────────────────────────────────

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

MockStorageService _makeStorage({
  UserStats? stats,
  NotificationPreferences? notifPrefs,
  NutritionGoals? goals,
  DailyNutritionLog? log,
}) {
  final s = MockStorageService();
  when(s.loadUserStats()).thenAnswer((_) async => stats ?? UserStats.initial());
  when(s.saveUserStats(any)).thenAnswer((_) async {});
  when(s.loadNotificationPreferences()).thenAnswer(
      (_) async => notifPrefs ?? NotificationPreferences.defaults());
  when(s.saveNotificationPreferences(any)).thenAnswer((_) async {});
  when(s.loadNutritionGoals()).thenAnswer(
      (_) async => goals ?? const NutritionGoals(dailyCalories: 2000));
  when(s.saveNutritionGoals(any)).thenAnswer((_) async {});
  when(s.loadTodayNutritionLog())
      .thenAnswer((_) async => log ?? DailyNutritionLog.empty(_today()));
  when(s.loadNutritionHistory()).thenAnswer((_) async => []);
  when(s.loadTdeeProfile()).thenAnswer((_) async => null);
  when(s.loadFoodLibrary()).thenAnswer((_) async => []);
  when(s.loadNutritionStreak()).thenAnswer((_) async => 0);
  when(s.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
  when(s.loadLogStreak()).thenAnswer((_) async => 0);
  when(s.loadLogStreakDate()).thenAnswer((_) async => null);
  when(s.loadFoodFeedback()).thenAnswer((_) async => []);
  when(s.loadWeightLog()).thenAnswer((_) async => []);
  when(s.saveWeightLog(any)).thenAnswer((_) async {});
  when(s.loadBodyMeasurements()).thenAnswer((_) async => []);
  when(s.loadMeasurementUnit()).thenAnswer((_) async => MeasurementUnit.metric);
  when(s.loadLastRecompXpDate()).thenAnswer((_) async => null);
  when(s.loadNutritionLogForDate(any))
      .thenAnswer((_) async => DailyNutritionLog.empty('2026-05-27'));
  when(s.loadChatMessagesRaw(any)).thenAnswer((_) async => []);
  when(s.saveNutritionLog(any)).thenAnswer((_) async {});
  when(s.saveFoodFeedback(any)).thenAnswer((_) async {});
  when(s.saveNutritionStreak(any)).thenAnswer((_) async {});
  when(s.saveNutritionGoalMetDate(any)).thenAnswer((_) async {});
  when(s.saveLogStreak(any)).thenAnswer((_) async {});
  when(s.saveLogStreakDate(any)).thenAnswer((_) async {});
  when(s.saveChatMessages(any, any)).thenAnswer((_) async {});
  when(s.loadBudgets()).thenAnswer((_) async => []);
  when(s.saveBudgets(any)).thenAnswer((_) async {});
  when(s.loadFinanceCategories()).thenAnswer((_) async => []);
  when(s.loadTransactions()).thenAnswer((_) async => []);
  when(s.loadAccounts()).thenAnswer((_) async => []);
  when(s.loadPersonalDict()).thenAnswer((_) async => []);
  when(s.savePersonalDict(any)).thenAnswer((_) async {});
  return s;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ─── StatsPresenter ──────────────────────────────────────────────────────────

  group('StatsPresenter — notification on level-up', () {
    test('1. level-up (no rank change) fires showLevelUpNotification',
        () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(
          levelUpEnabled: true,
          rankPromotionEnabled: true,
        ),
      );
      final notifications = MockNotificationService();
      final presenter = StatsPresenter(storage, notifications: notifications);

      // Wait for async _init().
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Level 1 → 2 requires 100 XP.
      await presenter.addXp(100);

      verify(notifications.showLevelUpNotification(2, 'E')).called(1);
      verifyNever(notifications.showRankPromotionNotification(any, any));
    });

    test('2. rank boundary cross fires showRankPromotionNotification',
        () async {
      // Level 10 (rank E) → 11 (rank D).
      final storage = _makeStorage(
        stats: const UserStats(
          name: 'Shadow',
          level: 10,
          currentXp: 0,
          currentHp: 100,
          statPoints: 0,
          streak: 0,
          attributes: (str: 1, vit: 1, agi: 1, intl: 1, sen: 1),
        ),
        notifPrefs: const NotificationPreferences(
          levelUpEnabled: true,
          rankPromotionEnabled: true,
        ),
      );
      final notifications = MockNotificationService();
      final presenter = StatsPresenter(storage, notifications: notifications);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Level 10 requires 10*10*100 = 10,000 XP to advance.
      await presenter.addXp(10000);

      verify(notifications.showRankPromotionNotification('E', 'D')).called(1);
      verifyNever(notifications.showLevelUpNotification(any, any));
    });

    test('3. levelUpEnabled=false → no notification on level-up', () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(
          levelUpEnabled: false,
          rankPromotionEnabled: false,
        ),
      );
      final notifications = MockNotificationService();
      final presenter = StatsPresenter(storage, notifications: notifications);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await presenter.addXp(100);

      verifyNever(notifications.showLevelUpNotification(any, any));
      verifyNever(notifications.showRankPromotionNotification(any, any));
    });
  });

  // ─── NutritionPresenter — weight reminder ────────────────────────────────────

  group('NutritionPresenter — weight reminder', () {
    NutritionPresenter buildPresenter({
      required MockNotificationService notifications,
      required MockStorageService storage,
    }) {
      final stats = MockStatsPresenter();
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.awardStat(any)).thenAnswer((_) async {});
      when(stats.modifyHp(any)).thenAnswer((_) async {});

      final fasting = MockFastingPresenter();
      when(fasting.isFasting).thenReturn(false);

      return NutritionPresenter(
        statsPresenter: stats,
        fastingPresenter: fasting,
        storage: storage,
        foodDb: MockFoodDbService(),
        aiCoach: _NoOpAiCoach(),
        notifications: notifications,
      );
    }

    test('4. logWeight() calls cancelWeightReminder', () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(weightReminderEnabled: true),
      );
      final notifications = MockNotificationService();
      when(notifications.cancelWeightReminder()).thenAnswer((_) async {});
      when(notifications.scheduleWeightReminder(any)).thenAnswer((_) async {});

      final presenter =
          buildPresenter(notifications: notifications, storage: storage);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await presenter.logWeight(72.5);

      verify(notifications.cancelWeightReminder())
          .called(greaterThanOrEqualTo(1));
    });

    test(
        '5. weightReminderEnabled=true → scheduleWeightReminder called on init',
        () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(
          weightReminderEnabled: true,
          weightReminderTime: TimeOfDay(hour: 8, minute: 0),
        ),
      );
      final notifications = MockNotificationService();
      when(notifications.scheduleWeightReminder(any)).thenAnswer((_) async {});
      when(notifications.cancelWeightReminder()).thenAnswer((_) async {});

      buildPresenter(notifications: notifications, storage: storage);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(notifications.scheduleWeightReminder(any)).called(1);
    });
  });

  // ─── NutritionPresenter — calorie goal ───────────────────────────────────────

  group('NutritionPresenter — calorie goal notification', () {
    NutritionPresenter buildPresenter({
      required MockNotificationService notifications,
      required MockStorageService storage,
    }) {
      final stats = MockStatsPresenter();
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.awardStat(any)).thenAnswer((_) async {});
      when(stats.modifyHp(any)).thenAnswer((_) async {});

      final fasting = MockFastingPresenter();
      when(fasting.isFasting).thenReturn(false);

      return NutritionPresenter(
        statsPresenter: stats,
        fastingPresenter: fasting,
        storage: storage,
        foodDb: MockFoodDbService(),
        aiCoach: _NoOpAiCoach(),
        notifications: notifications,
      );
    }

    test('6. food entry hits calorie goal → showCalorieGoalNotification once',
        () async {
      final storage = _makeStorage(
        goals: const NutritionGoals(dailyCalories: 2000),
        log: DailyNutritionLog.empty(_today()),
        notifPrefs: const NotificationPreferences(calorieGoalEnabled: true),
      );
      final notifications = MockNotificationService();
      when(notifications.showCalorieGoalNotification(any, any))
          .thenAnswer((_) async {});
      when(notifications.cancelWeightReminder()).thenAnswer((_) async {});
      when(notifications.scheduleWeightReminder(any)).thenAnswer((_) async {});

      final presenter =
          buildPresenter(notifications: notifications, storage: storage);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final entry = FoodEntry(
        id: 'e1',
        name: 'Test Food',
        calories: 2000,
        loggedAt: DateTime.now(),
        estimationSource: EstimationSource.userManual,
      );
      await presenter.addFoodEntry(entry, MealSlot.meal);

      verify(notifications.showCalorieGoalNotification(2000, 2000)).called(1);
    });

    test(
        '7. second food entry when already over goal → notification not called again',
        () async {
      final storage = _makeStorage(
        goals: const NutritionGoals(dailyCalories: 2000),
        log: DailyNutritionLog.empty(_today()),
        notifPrefs: const NotificationPreferences(calorieGoalEnabled: true),
      );
      final notifications = MockNotificationService();
      when(notifications.showCalorieGoalNotification(any, any))
          .thenAnswer((_) async {});
      when(notifications.cancelWeightReminder()).thenAnswer((_) async {});
      when(notifications.scheduleWeightReminder(any)).thenAnswer((_) async {});

      final presenter =
          buildPresenter(notifications: notifications, storage: storage);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final entry1 = FoodEntry(
        id: 'e1',
        name: 'Food A',
        calories: 2000,
        loggedAt: DateTime.now(),
        estimationSource: EstimationSource.userManual,
      );
      final entry2 = FoodEntry(
        id: 'e2',
        name: 'Food B',
        calories: 100,
        loggedAt: DateTime.now(),
        estimationSource: EstimationSource.userManual,
      );
      await presenter.addFoodEntry(entry1, MealSlot.meal);
      await presenter.addFoodEntry(entry2, MealSlot.meal);

      // Should fire exactly once.
      verify(notifications.showCalorieGoalNotification(any, any)).called(1);
    });

    test('8. calorieGoalEnabled=false → no notification when goal met',
        () async {
      final storage = _makeStorage(
        goals: const NutritionGoals(dailyCalories: 2000),
        log: DailyNutritionLog.empty(_today()),
        notifPrefs: const NotificationPreferences(calorieGoalEnabled: false),
      );
      final notifications = MockNotificationService();
      when(notifications.showCalorieGoalNotification(any, any))
          .thenAnswer((_) async {});
      when(notifications.cancelWeightReminder()).thenAnswer((_) async {});
      when(notifications.scheduleWeightReminder(any)).thenAnswer((_) async {});

      final presenter =
          buildPresenter(notifications: notifications, storage: storage);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final entry = FoodEntry(
        id: 'e1',
        name: 'Test Food',
        calories: 2000,
        loggedAt: DateTime.now(),
        estimationSource: EstimationSource.userManual,
      );
      await presenter.addFoodEntry(entry, MealSlot.meal);

      verifyNever(notifications.showCalorieGoalNotification(any, any));
    });
  });

  // ─── BudgetPresenter — budget warnings ──────────────────────────────────────

  group('BudgetPresenter — budget over-threshold warnings', () {
    const catId = 'cat-food';
    const budgetId = 'bud-1';
    const month = '2026-05';

    Budget makeBudget(double amount) => Budget(
          id: budgetId,
          categoryId: catId,
          month: month,
          allocatedAmount: amount,
          group: BudgetGroup.variableOptional,
          budgetType: BudgetType.monthly,
        );

    TransactionRecord makeTxn(double amount) => TransactionRecord(
          id: 'txn-1',
          accountId: 'acc-1',
          categoryId: catId,
          amount: amount,
          type: TransactionType.outflow,
          date: DateTime(2026, 5, 10),
          month: month,
          description: 'Test spend',
        );

    FinanceCategory makeCat() => FinanceCategory(
          id: catId,
          name: 'Food',
          type: CategoryType.expense,
          icon: 'food',
          colorHex: '#FF9800',
        );

    test('9. budget crosses 80% → showBudgetWarning called', () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(
          budgetWarningEnabled: true,
          budgetWarningPercent: 80,
        ),
      );
      when(storage.loadBudgets()).thenAnswer((_) async => [makeBudget(100)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [makeCat()]);
      when(storage.loadTransactions())
          .thenAnswer((_) async => [makeTxn(85)]); // 85% spent
      when(storage.loadAccounts()).thenAnswer((_) async => []);

      final notifications = MockNotificationService();
      when(notifications.showBudgetWarning(any, any, any, any, any))
          .thenAnswer((_) async {});

      final stats = MockStatsPresenter();
      when(stats.addXp(any)).thenAnswer((_) async {});

      final presenter = BudgetPresenter(storage, stats, null, notifications);
      presenter.setMonth(month);
      await presenter.load();

      verify(notifications.showBudgetWarning(
        budgetId,
        'Food',
        85.0,
        100.0,
        80,
      )).called(1);
    });

    test('10. budget drops below 80% → warning cleared, re-fires on next cross',
        () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(
          budgetWarningEnabled: true,
          budgetWarningPercent: 80,
        ),
      );
      when(storage.loadBudgets()).thenAnswer((_) async => [makeBudget(100)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [makeCat()]);
      // First load: 85% (crosses threshold).
      when(storage.loadTransactions()).thenAnswer((_) async => [makeTxn(85)]);
      when(storage.loadAccounts()).thenAnswer((_) async => []);

      final notifications = MockNotificationService();
      when(notifications.showBudgetWarning(any, any, any, any, any))
          .thenAnswer((_) async {});

      final stats = MockStatsPresenter();
      when(stats.addXp(any)).thenAnswer((_) async {});

      final presenter = BudgetPresenter(storage, stats, null, notifications);
      presenter.setMonth(month);
      await presenter.load(); // fires warning #1

      // Drop below threshold → clears the warning.
      when(storage.loadTransactions()).thenAnswer((_) async => [makeTxn(50)]);
      await presenter.load();

      // Cross again → fires warning #2.
      when(storage.loadTransactions()).thenAnswer((_) async => [makeTxn(90)]);
      await presenter.load();

      verify(notifications.showBudgetWarning(any, any, any, any, any))
          .called(2);
    });

    test('11. budgetWarningEnabled=false → no warning called', () async {
      final storage = _makeStorage(
        notifPrefs: const NotificationPreferences(budgetWarningEnabled: false),
      );
      when(storage.loadBudgets()).thenAnswer((_) async => [makeBudget(100)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [makeCat()]);
      when(storage.loadTransactions())
          .thenAnswer((_) async => [makeTxn(95)]); // 95% spent
      when(storage.loadAccounts()).thenAnswer((_) async => []);

      final notifications = MockNotificationService();
      final stats = MockStatsPresenter();
      when(stats.addXp(any)).thenAnswer((_) async {});

      final presenter = BudgetPresenter(storage, stats, null, notifications);
      presenter.setMonth(month);
      await presenter.load();

      verifyNever(notifications.showBudgetWarning(any, any, any, any, any));
    });
  });
}
