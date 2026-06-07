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
import '../models/finance/finance_dict_entry.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/monthly_summary.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../models/grocery/cart_item.dart';
import '../models/grocery/remembered_price.dart';
import '../models/food_feedback.dart';
import '../models/notification_preferences.dart';
import '../models/personal_food_entry.dart';
import '../models/sync_queue_entry.dart';
import '../models/body_measurement_entry.dart';
import '../models/weight_entry.dart';
import 'storage_service.dart';
import 'sync_queue.dart';

class LocalStorageService extends StorageService {
  SyncQueue? _syncQueue;
  bool _applyingRemote = false;

  /// The signed-in user ID. All user-data prefs keys are prefixed with
  /// `u/$_userId/` to prevent cross-user data leakage on shared devices.
  String? _userId;

  // In-memory ID caches so finance save methods don't re-decode the full blob
  // just to compute the sync-queue diff. Populated by the matching load() call
  // and updated on each save. Cleared when the user namespace changes.
  Set<String>? _cachedTransactionIds;
  Set<String>? _cachedAccountIds;

  /// Scopes a prefs key to the current user. Device-level keys (theme, etc.)
  /// bypass this and use the base constant directly.
  String _k(String base) => _userId != null ? 'u/$_userId/$base' : base;

  /// Called once SyncService is ready (after auth).
  void setSyncQueue(SyncQueue queue) => _syncQueue = queue;

  /// Sets the active user ID so all subsequent reads/writes are namespaced.
  /// Called in [AppShell._initSync] immediately after sign-in.
  ///
  /// Awaits the one-time key migration so callers can safely reload presenters
  /// from the scoped namespace immediately after this returns.
  Future<void> setUserId(String userId) async {
    _userId = userId;
    await _migrateUnscopedKeys(userId);
  }

  /// One-time migration from the old unscoped key layout to `u/$userId/…`.
  /// Skips keys that already have a scoped value, so it is safe to call on
  /// every sign-in — subsequent calls after the first are nearly instant.
  Future<void> _migrateUnscopedKeys(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'u/$userId/';
    for (final base in _kUserDataKeys) {
      final scoped = '$prefix$base';
      if (prefs.containsKey(scoped)) continue; // already migrated
      if (!prefs.containsKey(base)) continue; // nothing to migrate
      final val = prefs.get(base);
      if (val is String) {
        await prefs.setString(scoped, val);
      } else if (val is int) {
        await prefs.setInt(scoped, val);
      } else if (val is bool) {
        await prefs.setBool(scoped, val);
      } else if (val is double) {
        await prefs.setDouble(scoped, val);
      }
      await prefs.remove(base);
    }
  }

  /// All user-data keys that are scoped via [_k]. Device-level keys
  /// (kThemeMode, kUseCloudAi, kAiPromptSkippedAt) are intentionally excluded.
  static const List<String> _kUserDataKeys = [
    StorageService.keyIsFasting,
    StorageService.keyStartTime,
    StorageService.keyEatingStartTime,
    StorageService.keyElapsedSeconds,
    StorageService.keyFastingGoalHours,
    StorageService.keyHistory,
    StorageService.keyQuests,
    StorageService.keyUserStats,
    StorageService.keyLastPenaltyCheckDate,
    StorageService.keyQuestRoutines,
    StorageService.keyQuestAchievements,
    StorageService.keyQuestPenaltyCheckDate,
    StorageService.keyNutritionLogs,
    StorageService.keyNutritionGoals,
    StorageService.keyNutritionStreak,
    StorageService.keyNutritionGoalMetDate,
    StorageService.keyTdeeProfile,
    StorageService.keyFoodLibrary,
    StorageService.keyLogStreak,
    StorageService.keyLogStreakDate,
    StorageService.keyActivityLogs,
    StorageService.keyActivityGoals,
    StorageService.keyActivityGoalMetDate,
    StorageService.keyActivityStreak,
    StorageService.keyPreferredStepsSource,
    StorageService.keyChatMessages,
    StorageService.keyFinancialAccounts,
    StorageService.keyTransactions,
    StorageService.keyFinanceCategories,
    StorageService.keyBudgets,
    StorageService.keyBudgetedExpenses,
    StorageService.keyBills,
    StorageService.keyReceivables,
    StorageService.keyMonthlySummaries,
    StorageService.keyInstallments,
    StorageService.keyPersonalFoodDict,
    StorageService.keyFinanceDictionary,
    StorageService.keyFoodFeedback,
    StorageService.keyWeightLog,
    StorageService.keyBodyMeasurements,
    StorageService.keyMeasurementUnit,
    StorageService.keyLastRecompXpDate,
    StorageService.keyNotificationPreferences,
    StorageService.keyGroceryCart,
    StorageService.keyGroceryPriceMemory,
    StorageService.keyGroceryBudget,
  ];

  /// Removes all `u/$userId/` prefixed prefs keys and resets the user
  /// namespace. Called by [AppShell._tearDownSync] on sign-out.
  Future<void> clearUserData() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'u/$_userId/';
    for (final key
        in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
    _userId = null;
    _syncQueue = null;
    _cachedTransactionIds = null;
    _cachedAccountIds = null;
  }

  /// Fired by SyncService after pullAll() — lets home_screen reload presenters.
  VoidCallback? onRemoteDataApplied;

  /// Fired whenever local data is marked dirty — used by SyncService to auto-push.
  VoidCallback? onDirty;

  /// Runs [block] while suppressing dirty-marking to avoid re-queuing remote data.
  Future<void> applyRemote(Future<void> Function() block) async {
    _applyingRemote = true;
    try {
      await block();
    } finally {
      _applyingRemote = false;
    }
  }

  void _markDirty(SyncDomain domain, String key, {SyncOp op = SyncOp.upsert}) {
    if (!_applyingRemote) {
      _syncQueue?.markDirty(domain, key, op: op);
      onDirty?.call();
    }
  }

  /// Lightweight helper: reads a JSON array from [key] and extracts only the
  /// `id` field of each object. Used to seed the in-memory ID caches without
  /// deserializing full model objects.
  Future<Set<String>> _loadIdSetFromKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(key));
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  // ── User Stats ───────────────────────────────────────────────────────────────

  @override
  Future<void> saveUserStats(UserStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyUserStats), jsonEncode(stats.toJson()));
    debugPrint('LocalStorageService: UserStats saved. Level=${stats.level}');
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyUserStats));
    if (raw != null) {
      try {
        return UserStats.fromJson(jsonDecode(raw));
      } catch (e) {
        debugPrint('LocalStorageService: Error parsing UserStats: $e');
      }
    }
    return UserStats.initial();
  }

  // ── Fasting State ────────────────────────────────────────────────────────────

  @override
  Future<void> saveState({
    required bool isFasting,
    DateTime? startTime,
    DateTime? eatingStartTime,
    required int elapsedSeconds,
    required int fastingGoalHours,
    required List<FastingLog> history,
    DateTime? lastPenaltyCheckDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k(StorageService.keyIsFasting), isFasting);
    if (startTime != null) {
      await prefs.setString(
          _k(StorageService.keyStartTime), startTime.toIso8601String());
    } else {
      await prefs.remove(_k(StorageService.keyStartTime));
    }
    if (eatingStartTime != null) {
      await prefs.setString(_k(StorageService.keyEatingStartTime),
          eatingStartTime.toIso8601String());
    } else {
      await prefs.remove(_k(StorageService.keyEatingStartTime));
    }
    if (lastPenaltyCheckDate != null) {
      await prefs.setString(_k(StorageService.keyLastPenaltyCheckDate),
          lastPenaltyCheckDate.toIso8601String());
    }
    await prefs.setInt(_k(StorageService.keyElapsedSeconds), elapsedSeconds);
    await prefs.setInt(
        _k(StorageService.keyFastingGoalHours), fastingGoalHours);
    await prefs.setString(_k(StorageService.keyHistory),
        jsonEncode(history.map((e) => e.toJson()).toList()));
    debugPrint('LocalStorageService: State saved. isFasting=$isFasting');
    _markDirty(SyncDomain.fastingState, 'default');
  }

  @override
  Future<Map<String, dynamic>> loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final isFasting = prefs.getBool(_k(StorageService.keyIsFasting)) ?? false;
    final startTimeStr = prefs.getString(_k(StorageService.keyStartTime));
    final eatingStartTimeStr =
        prefs.getString(_k(StorageService.keyEatingStartTime));
    final lastPenaltyStr =
        prefs.getString(_k(StorageService.keyLastPenaltyCheckDate));
    final elapsedSeconds =
        prefs.getInt(_k(StorageService.keyElapsedSeconds)) ?? 0;
    final fastingGoalHours =
        prefs.getInt(_k(StorageService.keyFastingGoalHours)) ?? 16;

    List<FastingLog> history = [];
    final historyRaw = prefs.getString(_k(StorageService.keyHistory));
    if (historyRaw != null) {
      try {
        history = (jsonDecode(historyRaw) as List)
            .map((e) => FastingLog.fromJson(e))
            .toList();
      } catch (e) {
        debugPrint('LocalStorageService: failed to parse fasting history: $e');
      }
    }

    return {
      'isFasting': isFasting,
      'startTime': startTimeStr != null ? DateTime.parse(startTimeStr) : null,
      'eatingStartTime': eatingStartTimeStr != null
          ? DateTime.parse(eatingStartTimeStr)
          : null,
      'elapsedSeconds': elapsedSeconds,
      'fastingGoalHours': fastingGoalHours,
      'history': history,
      'lastPenaltyCheckDate':
          lastPenaltyStr != null ? DateTime.parse(lastPenaltyStr) : null,
    };
  }

  // ── Quests ───────────────────────────────────────────────────────────────────

  @override
  Future<void> saveQuests(List<Quest> quests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyQuests),
        jsonEncode(quests.map((e) => e.toJson()).toList()));
    debugPrint('LocalStorageService: Quests saved (${quests.length} items)');
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<List<Quest>> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyQuests));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Quest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading quests: $e');
      return [];
    }
  }

  @override
  Future<void> saveRoutines(List<HabitRoutine> routines) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyQuestRoutines),
        jsonEncode(routines.map((r) => r.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<HabitRoutine>> loadRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyQuestRoutines));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => HabitRoutine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading routines: $e');
      return [];
    }
  }

  @override
  Future<void> saveAchievements(List<QuestAchievement> achievements) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyQuestAchievements),
        jsonEncode(achievements.map((a) => a.toJson()).toList()));
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<List<QuestAchievement>> loadAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyQuestAchievements));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => QuestAchievement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading achievements: $e');
      return [];
    }
  }

  @override
  Future<void> saveQuestPenaltyCheckDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyQuestPenaltyCheckDate), date.toIso8601String());
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<DateTime?> loadQuestPenaltyCheckDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyQuestPenaltyCheckDate));
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Nutrition ────────────────────────────────────────────────────────────────

  @override
  Future<void> saveNutritionLog(DailyNutritionLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyNutritionLogs));
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();

    // Prune entries older than 90 days so the stored blob stays bounded.
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    all.removeWhere((key, _) {
      try {
        return DateTime.parse(key).isBefore(cutoff);
      } catch (_) {
        return false;
      }
    });

    await prefs.setString(_k(StorageService.keyNutritionLogs), jsonEncode(all));
    _markDirty(SyncDomain.nutritionLog, log.date);
  }

  @override
  Future<DailyNutritionLog> loadTodayNutritionLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _loadNutritionLogForKey(prefs, todayKey);
  }

  @override
  Future<DailyNutritionLog> loadNutritionLogForDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    return _loadNutritionLogForKey(prefs, dateKey);
  }

  DailyNutritionLog _loadNutritionLogForKey(
      SharedPreferences prefs, String key) {
    final raw = prefs.getString(_k(StorageService.keyNutritionLogs));
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(key)) {
          return DailyNutritionLog.fromJson(all[key] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint(
            'LocalStorageService: Error loading nutrition log [$key]: $e');
      }
    }
    return DailyNutritionLog.empty(key);
  }

  @override
  Future<List<DailyNutritionLog>> loadNutritionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyNutritionLogs));
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
      debugPrint('LocalStorageService: Error loading nutrition history: $e');
      return [];
    }
  }

  @override
  Future<void> saveNutritionGoals(NutritionGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyNutritionGoals), jsonEncode(goals.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<NutritionGoals> loadNutritionGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyNutritionGoals));
    if (raw != null) {
      try {
        return NutritionGoals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('LocalStorageService: Error loading nutrition goals: $e');
      }
    }
    return NutritionGoals.initial();
  }

  @override
  Future<void> saveNutritionStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(StorageService.keyNutritionStreak), streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadNutritionStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_k(StorageService.keyNutritionStreak)) ?? 0;
  }

  @override
  Future<void> saveNutritionGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyNutritionGoalMetDate), date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadNutritionGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_k(StorageService.keyNutritionGoalMetDate));
  }

  @override
  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyTdeeProfile), jsonEncode(profile.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<TdeeProfile?> loadTdeeProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyTdeeProfile));
    if (raw == null) return null;
    try {
      return TdeeProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('LocalStorageService: Error loading TdeeProfile: $e');
      return null;
    }
  }

  @override
  Future<void> saveFoodLibrary(List<FoodTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyFoodLibrary),
        jsonEncode(templates.map((t) => t.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<FoodTemplate>> loadFoodLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyFoodLibrary));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FoodTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading food library: $e');
      return [];
    }
  }

  @override
  Future<void> saveLogStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(StorageService.keyLogStreak), streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadLogStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_k(StorageService.keyLogStreak)) ?? 0;
  }

  @override
  Future<void> saveLogStreakDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyLogStreakDate), date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadLogStreakDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_k(StorageService.keyLogStreakDate));
  }

  @override
  Future<Set<String>> loadCalorieGoalCreditedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
                _k(StorageService.keyCalorieGoalCreditedDates)) ??
            const [])
        .toSet();
  }

  @override
  Future<void> saveCalorieGoalCreditedDates(Set<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _k(StorageService.keyCalorieGoalCreditedDates), dates.toList());
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<Set<String>> loadProteinGoalCreditedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
                _k(StorageService.keyProteinGoalCreditedDates)) ??
            const [])
        .toSet();
  }

  @override
  Future<void> saveProteinGoalCreditedDates(Set<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _k(StorageService.keyProteinGoalCreditedDates), dates.toList());
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadStreakMilestonePaid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_k(StorageService.keyStreakMilestonePaid)) ?? 0;
  }

  @override
  Future<void> saveStreakMilestonePaid(int milestone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(StorageService.keyStreakMilestonePaid), milestone);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  // ── Activity ─────────────────────────────────────────────────────────────────

  @override
  Future<void> saveActivityLog(ActivityLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(_k(StorageService.keyActivityLogs), jsonEncode(all));
    _markDirty(SyncDomain.activityLog, log.date);
  }

  @override
  Future<ActivityLog> loadTodayActivityLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
    if (raw != null) {
      try {
        final Map<String, dynamic> all =
            jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(todayKey)) {
          return ActivityLog.fromJson(all[todayKey] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('LocalStorageService: Error loading today activity log: $e');
      }
    }
    return ActivityLog.empty(todayKey);
  }

  @override
  Future<List<ActivityLog>> loadActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
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
      debugPrint('LocalStorageService: Error loading activity history: $e');
      return [];
    }
  }

  @override
  Future<Set<String>> loadActivityLogKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).keys.toSet();
    } catch (e) {
      return {};
    }
  }

  @override
  Future<void> clearActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
    if (raw == null) return;
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayEntry = all[todayKey];
      await prefs.setString(
        _k(StorageService.keyActivityLogs),
        jsonEncode(todayEntry != null ? {todayKey: todayEntry} : {}),
      );
    } catch (e) {
      debugPrint('LocalStorageService: Error clearing activity history: $e');
    }
  }

  @override
  Future<void> saveActivityLogs(List<ActivityLog> logs) async {
    if (logs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyActivityLogs));
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    for (final log in logs) {
      all[log.date] = log.toJson();
    }
    await prefs.setString(_k(StorageService.keyActivityLogs), jsonEncode(all));
    if (!_applyingRemote) {
      for (final log in logs) {
        _syncQueue?.markDirty(SyncDomain.activityLog, log.date);
      }
    }
  }

  @override
  Future<void> saveActivityGoals(ActivityGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyActivityGoals), jsonEncode(goals.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<ActivityGoals> loadActivityGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyActivityGoals));
    if (raw != null) {
      try {
        return ActivityGoals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('LocalStorageService: Error loading activity goals: $e');
      }
    }
    return ActivityGoals.initial();
  }

  @override
  Future<String?> loadPreferredStepsSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_k(StorageService.keyPreferredStepsSource));
  }

  @override
  Future<void> savePreferredStepsSource(String? sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sourceId == null) {
      await prefs.remove(_k(StorageService.keyPreferredStepsSource));
    } else {
      await prefs.setString(
          _k(StorageService.keyPreferredStepsSource), sourceId);
    }
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<void> saveActivityGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyActivityGoalMetDate), date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadActivityGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_k(StorageService.keyActivityGoalMetDate));
  }

  @override
  Future<void> saveActivityStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(StorageService.keyActivityStreak), streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadActivityStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_k(StorageService.keyActivityStreak)) ?? 0;
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────

  @override
  Future<void> saveChatMessages(String date, List<dynamic> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyChatMessages));
    final Map<String, dynamic> all =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[date] = messages.map((m) {
      if (m is Map) return m;
      try {
        return (m as dynamic).toJson() as Map<String, dynamic>;
      } catch (_) {
        return m;
      }
    }).toList();
    if (all.length > 60) {
      final sorted = all.keys.toList()..sort();
      for (final key in sorted.take(all.length - 60)) {
        all.remove(key);
      }
    }
    await prefs.setString(_k(StorageService.keyChatMessages), jsonEncode(all));
    _markDirty(SyncDomain.nutritionLog, date);
  }

  @override
  Future<List<Map<String, dynamic>>> loadChatMessagesRaw(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyChatMessages));
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final list = all[date] as List?;
      if (list == null) return [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint(
          'LocalStorageService: Error loading chat messages for $date: $e');
      return [];
    }
  }

  // ── Finance ──────────────────────────────────────────────────────────────────

  @override
  Future<void> saveAccounts(List<FinancialAccount> accounts) async {
    if (!_applyingRemote) {
      final newIds = accounts.map((e) => e.id).toSet();
      final oldIds = _cachedAccountIds ??
          await _loadIdSetFromKey(StorageService.keyFinancialAccounts);
      final removed = oldIds.difference(newIds);
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_accounts/$id',
            op: SyncOp.delete);
      }
      for (final a in accounts) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_accounts/${a.id}');
      }
      _cachedAccountIds = newIds;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyFinancialAccounts),
        jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<FinancialAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyFinancialAccounts));
    if (raw == null) {
      _cachedAccountIds = {};
      return [];
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => FinancialAccount.fromJson(e as Map<String, dynamic>))
          .toList();
      _cachedAccountIds = list.map((e) => e.id).toSet();
      return list;
    } catch (e) {
      debugPrint('LocalStorageService: Error loading accounts: $e');
      return [];
    }
  }

  @override
  Future<void> saveTransactions(List<TransactionRecord> transactions) async {
    if (!_applyingRemote) {
      final newIds = transactions.map((e) => e.id).toSet();
      // Use in-memory cache to avoid a full re-decode just for the diff.
      // On the very first save in a session _cachedTransactionIds is null —
      // fall back to a lightweight ID-only parse (no full object construction).
      final oldIds = _cachedTransactionIds ??
          await _loadIdSetFromKey(StorageService.keyTransactions);
      final removed = oldIds.difference(newIds);
      for (final id in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_transactions/$id',
            op: SyncOp.delete);
      }
      for (final t in transactions) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_transactions/${t.id}');
      }
      _cachedTransactionIds = newIds;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyTransactions),
        jsonEncode(transactions.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<TransactionRecord>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyTransactions));
    if (raw == null) {
      _cachedTransactionIds = {};
      return [];
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => TransactionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _cachedTransactionIds = list.map((e) => e.id).toSet();
      return list;
    } catch (e) {
      debugPrint('LocalStorageService: Error loading transactions: $e');
      return [];
    }
  }

  @override
  Future<void> saveFinanceCategories(List<FinanceCategory> categories) async {
    if (!_applyingRemote) {
      final existing = await loadFinanceCategories();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(categories.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_categories/$id',
            op: SyncOp.delete);
      }
      for (final c in categories) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_categories/${c.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyFinanceCategories),
        jsonEncode(categories.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<FinanceCategory>> loadFinanceCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyFinanceCategories));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FinanceCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading finance categories: $e');
      return [];
    }
  }

  @override
  Future<void> saveBudgets(List<Budget> budgets) async {
    if (!_applyingRemote) {
      final existing = await loadBudgets();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(budgets.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_budgets/$id',
            op: SyncOp.delete);
      }
      for (final b in budgets) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_budgets/${b.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyBudgets),
        jsonEncode(budgets.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Budget>> loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyBudgets));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Budget.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading budgets: $e');
      return [];
    }
  }

  @override
  Future<void> saveBudgetedExpenses(List<BudgetedExpense> expenses) async {
    if (!_applyingRemote) {
      final existing = await loadBudgetedExpenses();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(expenses.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_budgeted_expenses/$id',
            op: SyncOp.delete);
      }
      for (final e in expenses) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_budgeted_expenses/${e.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyBudgetedExpenses),
        jsonEncode(expenses.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<BudgetedExpense>> loadBudgetedExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyBudgetedExpenses));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BudgetedExpense.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading budgeted expenses: $e');
      return [];
    }
  }

  @override
  Future<void> saveBills(List<Bill> bills) async {
    if (!_applyingRemote) {
      final existing = await loadBills();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(bills.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_bills/$id',
            op: SyncOp.delete);
      }
      for (final b in bills) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_bills/${b.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyBills),
        jsonEncode(bills.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Bill>> loadBills() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyBills));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Bill.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading bills: $e');
      return [];
    }
  }

  @override
  Future<void> saveReceivables(List<Receivable> receivables) async {
    if (!_applyingRemote) {
      final existing = await loadReceivables();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(receivables.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_receivables/$id',
            op: SyncOp.delete);
      }
      for (final r in receivables) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_receivables/${r.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyReceivables),
        jsonEncode(receivables.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Receivable>> loadReceivables() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyReceivables));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Receivable.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading receivables: $e');
      return [];
    }
  }

  @override
  Future<void> saveInstallments(List<Installment> installments) async {
    if (!_applyingRemote) {
      final existing = await loadInstallments();
      final removed = existing
          .map((e) => e.id)
          .toSet()
          .difference(installments.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_installments/$id',
            op: SyncOp.delete);
      }
      for (final i in installments) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_installments/${i.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyInstallments),
        jsonEncode(installments.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Installment>> loadInstallments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyInstallments));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Installment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading installments: $e');
      return [];
    }
  }

  @override
  Future<void> saveMonthlySummaries(List<MonthlySummary> summaries) async {
    if (!_applyingRemote) {
      final existing = await loadMonthlySummaries();
      final removed = existing
          .map((e) => e.month)
          .toSet()
          .difference(summaries.map((e) => e.month).toSet());
      for (final month in removed) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_monthly_summaries/$month',
            op: SyncOp.delete);
      }
      for (final s in summaries) {
        _syncQueue?.markDirty(
            SyncDomain.financeRecord, 'finance_monthly_summaries/${s.month}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyMonthlySummaries),
        jsonEncode(summaries.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<MonthlySummary>> loadMonthlySummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyMonthlySummaries));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MonthlySummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading monthly summaries: $e');
      return [];
    }
  }

  // ── Personal Food Dictionary ─────────────────────────────────────────────────

  @override
  Future<void> savePersonalDict(List<PersonalFoodEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyPersonalFoodDict),
        jsonEncode(entries.map((e) => e.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<PersonalFoodEntry>> loadPersonalDict() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyPersonalFoodDict));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PersonalFoodEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading personal food dict: $e');
      return [];
    }
  }

  // ── Finance Personal Dictionary (chat-logging learned tokens) ───────────────

  @override
  Future<void> saveFinanceDictionary(List<FinanceDictEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyFinanceDictionary),
        jsonEncode(entries.map((e) => e.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<FinanceDictEntry>> loadFinanceDictionary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyFinanceDictionary));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FinanceDictEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading finance dictionary: $e');
      return [];
    }
  }

  // ── Food Matcher Feedback (telemetry) ────────────────────────────────────────

  @override
  Future<void> saveFoodFeedback(List<FoodFeedback> entries) async {
    // Cap at FoodFeedback.maxStoredEntries — keep newest. The cap prevents
    // SharedPreferences from growing forever; once we add a curation UI we
    // can offer "export & clear" so older signal isn't lost.
    final capped = entries.length > FoodFeedback.maxStoredEntries
        ? entries.sublist(entries.length - FoodFeedback.maxStoredEntries)
        : entries;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _k(StorageService.keyFoodFeedback),
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<FoodFeedback>> loadFoodFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyFoodFeedback));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FoodFeedback.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading food feedback: $e');
      return [];
    }
  }

  // ── Weight Log ───────────────────────────────────────────────────────────────

  @override
  Future<void> saveWeightLog(List<WeightEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyWeightLog),
        jsonEncode(entries.map((e) => e.toJson()).toList()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<List<WeightEntry>> loadWeightLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyWeightLog));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => WeightEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading weight log: $e');
      return [];
    }
  }

  // ── Body Measurements ────────────────────────────────────────────────────────

  @override
  Future<void> saveBodyMeasurements(List<BodyMeasurementEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyBodyMeasurements),
        jsonEncode(entries.map((e) => e.toJson()).toList()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<List<BodyMeasurementEntry>> loadBodyMeasurements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyBodyMeasurements));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BodyMeasurementEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading body measurements: $e');
      return [];
    }
  }

  @override
  Future<void> saveMeasurementUnit(MeasurementUnit unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(StorageService.keyMeasurementUnit), unit.name);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<MeasurementUnit> loadMeasurementUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyMeasurementUnit));
    return raw == 'imperial'
        ? MeasurementUnit.imperial
        : MeasurementUnit.metric;
  }

  @override
  Future<void> saveLastRecompXpDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(StorageService.keyLastRecompXpDate), date.toIso8601String());
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<DateTime?> loadLastRecompXpDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyLastRecompXpDate));
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Grocery Cart (Plan 038) ──────────────────────────────────────────────────
  // Local-only for now (no SyncDomain). Keys are user-scoped via [_k] so they
  // are cleared on sign-out like other user data; cloud sync of price memory is
  // a future enhancement.

  @override
  Future<void> saveGroceryCart(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _k(StorageService.keyGroceryCart),
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<List<CartItem>> loadGroceryCart() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyGroceryCart));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error parsing grocery cart: $e');
      return [];
    }
  }

  @override
  Future<void> saveGroceryPriceMemory(List<RememberedPrice> prices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _k(StorageService.keyGroceryPriceMemory),
      jsonEncode(prices.map((e) => e.toJson()).toList()),
    );
  }

  @override
  Future<List<RememberedPrice>> loadGroceryPriceMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(StorageService.keyGroceryPriceMemory));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RememberedPrice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error parsing price memory: $e');
      return [];
    }
  }

  @override
  Future<void> saveGroceryBudget(double? budget) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _k(StorageService.keyGroceryBudget);
    if (budget == null) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, budget);
    }
  }

  @override
  Future<double?> loadGroceryBudget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_k(StorageService.keyGroceryBudget));
  }

  // ── Theme (device-level, not user-scoped) ────────────────────────────────────

  @override
  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.kThemeMode, mode);
  }

  @override
  Future<String?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageService.kThemeMode);
  }

  // ── Notification Preferences ─────────────────────────────────────────────────

  @override
  Future<void> saveNotificationPreferences(
      NotificationPreferences prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k(StorageService.keyNotificationPreferences),
        jsonEncode(prefs.toJson()));
  }

  @override
  Future<NotificationPreferences> loadNotificationPreferences() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k(StorageService.keyNotificationPreferences));
    if (raw == null) return NotificationPreferences.defaults();
    try {
      return NotificationPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint(
          'LocalStorageService: Error loading notification preferences: $e');
      return NotificationPreferences.defaults();
    }
  }

  // ── Device-level AI flags (not user-scoped) ──────────────────────────────────

  @override
  Future<void> saveUseCloudAi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageService.kUseCloudAi, value);
  }

  @override
  Future<bool> loadUseCloudAi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageService.kUseCloudAi) ?? true;
  }

  @override
  Future<void> saveAiPromptSkippedAt(int? msSinceEpoch) async {
    final prefs = await SharedPreferences.getInstance();
    if (msSinceEpoch == null) {
      await prefs.remove(StorageService.kAiPromptSkippedAt);
    } else {
      await prefs.setInt(StorageService.kAiPromptSkippedAt, msSinceEpoch);
    }
  }

  @override
  Future<int?> loadAiPromptSkippedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(StorageService.kAiPromptSkippedAt);
  }

  // ── Export / Import ──────────────────────────────────────────────────────────

  /// Exports only the current user's data. Keys are stripped of the
  /// `u/$userId/` prefix so the export format is stable across user IDs.
  @override
  Future<String> exportAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final allData = <String, dynamic>{};
    if (_userId != null) {
      final prefix = 'u/$_userId/';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix)) {
          allData[key.substring(prefix.length)] = prefs.get(key);
        }
      }
    } else {
      for (final key in prefs.getKeys()) {
        allData[key] = prefs.get(key);
      }
    }
    return jsonEncode(allData);
  }

  /// Imports data into the current user's namespace, replacing only that
  /// user's keys (does not touch other users' data or device-level keys).
  @override
  Future<void> importAllData(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      if (_userId != null) {
        final prefix = 'u/$_userId/';
        for (final key
            in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
          await prefs.remove(key);
        }
      }
      for (final key in data.keys) {
        final storageKey = _k(key);
        final value = data[key];
        if (value is bool) {
          await prefs.setBool(storageKey, value);
        } else if (value is int) {
          await prefs.setInt(storageKey, value);
        } else if (value is double) {
          await prefs.setDouble(storageKey, value);
        } else if (value is String) {
          await prefs.setString(storageKey, value);
        } else if (value is List) {
          await prefs.setStringList(storageKey, List<String>.from(value));
        }
      }
      debugPrint('LocalStorageService: Import successful.');
    } catch (e) {
      debugPrint('LocalStorageService: Import failed: $e');
      throw Exception('Invalid data format');
    }
  }
}
