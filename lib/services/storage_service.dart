import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_goals.dart';
import '../models/activity_log.dart';
import '../models/daily_nutrition_log.dart';
import '../models/fasting_log.dart';
import '../models/food_template.dart';
import '../models/habit_routine.dart';
import '../models/nutrition_goals.dart';
import '../models/quest.dart';
import '../models/quest_achievement.dart';
import '../models/tdee_profile.dart';
import '../models/user_stats.dart';
import '../models/finance/bill.dart';
import '../models/finance/budget.dart';
import '../models/finance/installment.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/monthly_summary.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';

class StorageService {
  static const String keyIsFasting = 'isFasting';
  static const String keyStartTime = 'startTime';
  static const String keyEatingStartTime = 'eatingStartTime';
  static const String keyElapsedSeconds = 'elapsedSeconds';
  static const String keyFastingGoalHours = 'fastingGoalHours';
  static const String keyHistory = 'history';
  static const String keyQuests = 'quests';
  static const String keyUserStats = 'userStats';
  static const String keyLastPenaltyCheckDate = 'lastPenaltyCheckDate';
  static const String keyQuestRoutines = 'quest_routines';
  static const String keyQuestAchievements = 'quest_achievements';
  static const String keyQuestPenaltyCheckDate = 'questPenaltyCheckDate';

  Future<void> saveUserStats(UserStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = jsonEncode(stats.toJson());
    await prefs.setString(keyUserStats, statsJson);
    debugPrint('StorageService: UserStats saved. Level=${stats.level}');
  }

  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    final statsJson = prefs.getString(keyUserStats);
    if (statsJson != null) {
      try {
        return UserStats.fromJson(jsonDecode(statsJson));
      } catch (e) {
        debugPrint('StorageService: Error parsing UserStats: $e');
      }
    }
    return UserStats.initial();
  }

  Future<void> saveState({
    required bool isFasting,
    DateTime? startTime,
    DateTime? eatingStartTime,
    required int elapsedSeconds,
    required int fastingGoalHours,
    required List<FastingLog> history,
    required List<Quest> quests,
    DateTime? lastPenaltyCheckDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsFasting, isFasting);
    if (startTime != null) {
      await prefs.setString(keyStartTime, startTime.toIso8601String());
    } else {
      await prefs.remove(keyStartTime);
    }

    if (eatingStartTime != null) {
      await prefs.setString(
          keyEatingStartTime, eatingStartTime.toIso8601String());
    } else {
      await prefs.remove(keyEatingStartTime);
    }

    if (lastPenaltyCheckDate != null) {
      await prefs.setString(
          keyLastPenaltyCheckDate, lastPenaltyCheckDate.toIso8601String());
    }

    await prefs.setInt(keyElapsedSeconds, elapsedSeconds);
    await prefs.setInt(keyFastingGoalHours, fastingGoalHours);

    final historyJson = jsonEncode(history.map((e) => e.toJson()).toList());
    await prefs.setString(keyHistory, historyJson);

    final questsJson = jsonEncode(quests.map((e) => e.toJson()).toList());
    await prefs.setString(keyQuests, questsJson);
    debugPrint('StorageService: State saved. isFasting=$isFasting');
  }

  /// Saves only the quests list without touching any other state field.
  Future<void> saveQuests(List<Quest> quests) async {
    final prefs = await SharedPreferences.getInstance();
    final questsJson = jsonEncode(quests.map((e) => e.toJson()).toList());
    await prefs.setString(keyQuests, questsJson);
    debugPrint('StorageService: Quests saved (${quests.length} items)');
  }

  /// Loads only the quests list.
  Future<List<Quest>> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final questsJson = prefs.getString(keyQuests);
    if (questsJson == null) return [];
    try {
      final List<dynamic> list = jsonDecode(questsJson);
      return list
          .map((e) => Quest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading quests: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload from disk

    bool isFasting = prefs.getBool(keyIsFasting) ?? false;
    debugPrint('StorageService: Loaded isFasting=$isFasting');

    String? startTimeStr = prefs.getString(keyStartTime);
    DateTime? startTime =
        startTimeStr != null ? DateTime.parse(startTimeStr) : null;

    String? eatingStartTimeStr = prefs.getString(keyEatingStartTime);
    DateTime? eatingStartTime =
        eatingStartTimeStr != null ? DateTime.parse(eatingStartTimeStr) : null;

    String? lastPenaltyCheckDateStr = prefs.getString(keyLastPenaltyCheckDate);
    DateTime? lastPenaltyCheckDate = lastPenaltyCheckDateStr != null
        ? DateTime.parse(lastPenaltyCheckDateStr)
        : null;

    int elapsedSeconds = prefs.getInt(keyElapsedSeconds) ?? 0;
    int fastingGoalHours = prefs.getInt(keyFastingGoalHours) ?? 16;

    String? historyJson = prefs.getString(keyHistory);
    List<FastingLog> history = [];
    if (historyJson != null) {
      try {
        List<dynamic> list = jsonDecode(historyJson);
        history = list.map((e) => FastingLog.fromJson(e)).toList();
      } catch (e) {
        // Error parsing history
      }
    }

    String? questsJson = prefs.getString(keyQuests);
    List<Quest> quests = [];
    if (questsJson != null) {
      try {
        List<dynamic> list = jsonDecode(questsJson);
        quests = list.map((e) => Quest.fromJson(e)).toList();
      } catch (e) {
        // Error parsing quests
      }
    }

    return {
      'isFasting': isFasting,
      'startTime': startTime,
      'eatingStartTime': eatingStartTime,
      'elapsedSeconds': elapsedSeconds,
      'fastingGoalHours': fastingGoalHours,
      'history': history,
      'quests': quests,
      'lastPenaltyCheckDate': lastPenaltyCheckDate,
    };
  }

  // ─── Quest Routines & Achievements ───────────────────────────────────────────

  Future<void> saveRoutines(List<HabitRoutine> routines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        keyQuestRoutines, jsonEncode(routines.map((r) => r.toJson()).toList()));
  }

  Future<List<HabitRoutine>> loadRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyQuestRoutines);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HabitRoutine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading routines: $e');
      return [];
    }
  }

  Future<void> saveAchievements(List<QuestAchievement> achievements) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyQuestAchievements,
        jsonEncode(achievements.map((a) => a.toJson()).toList()));
  }

  Future<List<QuestAchievement>> loadAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyQuestAchievements);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => QuestAchievement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading achievements: $e');
      return [];
    }
  }

  Future<void> saveQuestPenaltyCheckDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyQuestPenaltyCheckDate, date.toIso8601String());
  }

  Future<DateTime?> loadQuestPenaltyCheckDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyQuestPenaltyCheckDate);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  // ─── Nutrition ───────────────────────────────────────────────────────────────

  static const String keyNutritionLogs = 'nutritionLogs';
  static const String keyNutritionGoals = 'nutritionGoals';
  static const String keyNutritionStreak = 'nutritionStreak';
  static const String keyNutritionGoalMetDate = 'nutritionGoalMetDate';

  Future<void> saveNutritionLog(DailyNutritionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionLogs);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(keyNutritionLogs, jsonEncode(all));
  }

  Future<DailyNutritionLog> loadTodayNutritionLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _loadNutritionLogForKey(prefs, todayKey);
  }

  Future<DailyNutritionLog> loadNutritionLogForDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    return _loadNutritionLogForKey(prefs, dateKey);
  }

  DailyNutritionLog _loadNutritionLogForKey(
      SharedPreferences prefs, String key) {
    final raw = prefs.getString(keyNutritionLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(key)) {
          return DailyNutritionLog.fromJson(all[key] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('StorageService: Error loading nutrition log [$key]: $e');
      }
    }
    return DailyNutritionLog.empty(key);
  }

  Future<List<DailyNutritionLog>> loadNutritionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionLogs);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = all.entries
          .where((e) => e.key != todayKey)
          .map((e) =>
              DailyNutritionLog.fromJson(e.value as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return logs.take(30).toList();
    } catch (e) {
      debugPrint('StorageService: Error loading nutrition history: $e');
      return [];
    }
  }

  Future<void> saveNutritionGoals(NutritionGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNutritionGoals, jsonEncode(goals.toJson()));
  }

  Future<NutritionGoals> loadNutritionGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyNutritionGoals);
    if (raw != null) {
      try {
        return NutritionGoals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('StorageService: Error loading nutrition goals: $e');
      }
    }
    return NutritionGoals.initial();
  }

  Future<void> saveNutritionStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyNutritionStreak, streak);
  }

  Future<int> loadNutritionStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyNutritionStreak) ?? 0;
  }

  Future<void> saveNutritionGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyNutritionGoalMetDate, date);
  }

  Future<String?> loadNutritionGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyNutritionGoalMetDate);
  }

  // ─── Nutrition v2 — TDEE, food library, log streak ───────────────────────────

  static const String keyTdeeProfile = 'tdeeProfile';
  static const String keyFoodLibrary = 'foodLibrary';
  static const String keyLogStreak = 'nutritionLogStreak';
  static const String keyLogStreakDate = 'nutritionLogStreakDate';

  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyTdeeProfile, jsonEncode(profile.toJson()));
  }

  Future<TdeeProfile?> loadTdeeProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyTdeeProfile);
    if (raw == null) return null;
    try {
      return TdeeProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('StorageService: Error loading TdeeProfile: $e');
      return null;
    }
  }

  Future<void> saveFoodLibrary(List<FoodTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(templates.map((t) => t.toJson()).toList());
    await prefs.setString(keyFoodLibrary, json);
  }

  Future<List<FoodTemplate>> loadFoodLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFoodLibrary);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FoodTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading food library: $e');
      return [];
    }
  }

  Future<void> saveLogStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLogStreak, streak);
  }

  Future<int> loadLogStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyLogStreak) ?? 0;
  }

  Future<void> saveLogStreakDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLogStreakDate, date);
  }

  Future<String?> loadLogStreakDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLogStreakDate);
  }

  // ─── Activity ────────────────────────────────────────────────────────────────

  static const String keyActivityLogs = 'activityLogs';
  static const String keyActivityGoals = 'activityGoals';
  static const String keyActivityGoalMetDate = 'activityGoalMetDate';
  static const String keyActivityStreak = 'activityStreak';
  static const String keyPreferredStepsSource = 'preferredStepsSourceId';

  Future<void> saveActivityLog(ActivityLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(keyActivityLogs, jsonEncode(all));
  }

  Future<ActivityLog> loadTodayActivityLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(keyActivityLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(todayKey)) {
          return ActivityLog.fromJson(all[todayKey] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('StorageService: Error loading today activity log: $e');
      }
    }
    return ActivityLog.empty(todayKey);
  }

  Future<List<ActivityLog>> loadActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = all.entries
          .where((e) => e.key != todayKey)
          .map((e) => ActivityLog.fromJson(e.value as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return logs.take(180).toList();
    } catch (e) {
      debugPrint('StorageService: Error loading activity history: $e');
      return [];
    }
  }

  /// Returns the set of date keys ('yyyy-MM-dd') already stored in activity logs.
  /// Used by backfill logic to skip days already present.
  Future<Set<String>> loadActivityLogKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).keys.toSet();
    } catch (e) {
      debugPrint('StorageService: Error loading activity log keys: $e');
      return {};
    }
  }

  /// Clears all historical activity logs, preserving only today's entry.
  Future<void> clearActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(keyActivityLogs);
    if (raw == null) return;
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayEntry = all[todayKey];
      await prefs.setString(
        keyActivityLogs,
        jsonEncode(todayEntry != null ? {todayKey: todayEntry} : {}),
      );
    } catch (e) {
      debugPrint('StorageService: Error clearing activity history: $e');
    }
  }

  /// Bulk upserts [logs] into activity log storage in a single read/write cycle.
  Future<void> saveActivityLogs(List<ActivityLog> logs) async {
    if (logs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityLogs);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    for (final log in logs) {
      all[log.date] = log.toJson();
    }
    await prefs.setString(keyActivityLogs, jsonEncode(all));
  }

  Future<void> saveActivityGoals(ActivityGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyActivityGoals, jsonEncode(goals.toJson()));
  }

  Future<ActivityGoals> loadActivityGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyActivityGoals);
    if (raw != null) {
      try {
        return ActivityGoals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('StorageService: Error loading activity goals: $e');
      }
    }
    return ActivityGoals.initial();
  }

  Future<String?> loadPreferredStepsSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyPreferredStepsSource);
  }

  Future<void> savePreferredStepsSource(String? sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sourceId == null) {
      await prefs.remove(keyPreferredStepsSource);
    } else {
      await prefs.setString(keyPreferredStepsSource, sourceId);
    }
  }

  Future<void> saveActivityGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyActivityGoalMetDate, date);
  }

  Future<String?> loadActivityGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyActivityGoalMetDate);
  }

  Future<void> saveActivityStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyActivityStreak, streak);
  }

  Future<int> loadActivityStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyActivityStreak) ?? 0;
  }

  // ─── Chat messages (nutrition chat feed) ────────────────────────────────────

  static const String keyChatMessages = 'nutritionChatMessages';

  /// Persist [messages] for [date] (format: 'yyyy-MM-dd').
  Future<void> saveChatMessages(
      String date, List<dynamic> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyChatMessages);
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[date] = messages.map((m) => m.toJson()).toList();
    // Keep at most 60 days of chat history to avoid storage bloat.
    if (all.length > 60) {
      final sorted = all.keys.toList()..sort();
      for (final key in sorted.take(all.length - 60)) {
        all.remove(key);
      }
    }
    await prefs.setString(keyChatMessages, jsonEncode(all));
  }

  /// Load raw JSON list for [date]. Returns empty list if no data.
  Future<List<Map<String, dynamic>>> loadChatMessagesRaw(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyChatMessages);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final list = all[date] as List?;
      if (list == null) return [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('StorageService: Error loading chat messages for $date: $e');
      return [];
    }
  }

  // ─── Finance / Treasury ──────────────────────────────────────────────────────

  static const String keyFinancialAccounts = 'finance_accounts';
  static const String keyTransactions = 'finance_transactions';
  static const String keyFinanceCategories = 'finance_categories';
  static const String keyBudgets = 'finance_budgets';
  static const String keyBudgetedExpenses = 'finance_budgeted_expenses';
  static const String keyBills = 'finance_bills';
  static const String keyReceivables = 'finance_receivables';
  static const String keyMonthlySummaries = 'finance_monthly_summaries';
  static const String keyInstallments = 'finance_installments';

  Future<void> saveAccounts(List<FinancialAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFinancialAccounts,
        jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  Future<List<FinancialAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFinancialAccounts);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => FinancialAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading accounts: $e');
      return [];
    }
  }

  Future<void> saveTransactions(List<TransactionRecord> transactions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyTransactions,
        jsonEncode(transactions.map((e) => e.toJson()).toList()));
    // TODO: migrate to SQLite when txn count > 500
  }

  Future<List<TransactionRecord>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyTransactions);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => TransactionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading transactions: $e');
      return [];
    }
  }

  Future<void> saveFinanceCategories(List<FinanceCategory> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFinanceCategories,
        jsonEncode(categories.map((e) => e.toJson()).toList()));
  }

  Future<List<FinanceCategory>> loadFinanceCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFinanceCategories);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => FinanceCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading finance categories: $e');
      return [];
    }
  }

  Future<void> saveBudgets(List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        keyBudgets, jsonEncode(budgets.map((e) => e.toJson()).toList()));
  }

  Future<List<Budget>> loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyBudgets);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Budget.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading budgets: $e');
      return [];
    }
  }

  Future<void> saveBudgetedExpenses(List<BudgetedExpense> expenses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyBudgetedExpenses,
        jsonEncode(expenses.map((e) => e.toJson()).toList()));
  }

  Future<List<BudgetedExpense>> loadBudgetedExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyBudgetedExpenses);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => BudgetedExpense.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading budgeted expenses: $e');
      return [];
    }
  }

  Future<void> saveBills(List<Bill> bills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        keyBills, jsonEncode(bills.map((e) => e.toJson()).toList()));
  }

  Future<List<Bill>> loadBills() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyBills);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Bill.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading bills: $e');
      return [];
    }
  }

  Future<void> saveReceivables(List<Receivable> receivables) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyReceivables,
        jsonEncode(receivables.map((e) => e.toJson()).toList()));
  }

  Future<List<Receivable>> loadReceivables() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyReceivables);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Receivable.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading receivables: $e');
      return [];
    }
  }

  Future<void> saveInstallments(List<Installment> installments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyInstallments,
        jsonEncode(installments.map((e) => e.toJson()).toList()));
  }

  Future<List<Installment>> loadInstallments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyInstallments);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Installment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading installments: $e');
      return [];
    }
  }

  Future<void> saveMonthlySummaries(List<MonthlySummary> summaries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyMonthlySummaries,
        jsonEncode(summaries.map((e) => e.toJson()).toList()));
  }

  Future<List<MonthlySummary>> loadMonthlySummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyMonthlySummaries);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => MonthlySummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('StorageService: Error loading monthly summaries: $e');
      return [];
    }
  }

  // ─── Export / Import ─────────────────────────────────────────────────────────

  Future<String> exportAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final allData = <String, dynamic>{};
    final keys = prefs.getKeys();

    for (String key in keys) {
      allData[key] = prefs.get(key);
    }

    return jsonEncode(allData);
  }

  Future<void> importAllData(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Clear existing first? Maybe safer to just overwrite.
      // But clearing ensures no stale keys remain.
      await prefs.clear();

      for (String key in data.keys) {
        final value = data[key];
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else if (value is List) {
          await prefs.setStringList(key, List<String>.from(value));
        }
      }
      debugPrint(
          'StorageService: Import successful. Keys: ${data.keys.toList()}');
    } catch (e) {
      debugPrint('StorageService: Import failed: $e');
      throw Exception('Invalid data format');
    }
  }
}
