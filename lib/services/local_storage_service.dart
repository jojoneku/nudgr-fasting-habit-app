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
import '../models/personal_food_entry.dart';
import '../models/sync_queue_entry.dart';
import 'storage_service.dart';
import 'sync_queue.dart';

class LocalStorageService extends StorageService {
  SyncQueue? _syncQueue;
  bool _applyingRemote = false;

  /// Called once SyncService is ready (after auth).
  void setSyncQueue(SyncQueue queue) => _syncQueue = queue;

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

  void _markDirty(SyncDomain domain, String key,
      {SyncOp op = SyncOp.upsert}) {
    if (!_applyingRemote) {
      _syncQueue?.markDirty(domain, key, op: op);
      onDirty?.call();
    }
  }

  // ── User Stats ───────────────────────────────────────────────────────────────

  @override
  Future<void> saveUserStats(UserStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyUserStats, jsonEncode(stats.toJson()));
    debugPrint('LocalStorageService: UserStats saved. Level=${stats.level}');
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<UserStats> loadUserStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyUserStats);
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
    await prefs.setBool(StorageService.keyIsFasting, isFasting);
    if (startTime != null) {
      await prefs.setString(StorageService.keyStartTime, startTime.toIso8601String());
    } else {
      await prefs.remove(StorageService.keyStartTime);
    }
    if (eatingStartTime != null) {
      await prefs.setString(StorageService.keyEatingStartTime, eatingStartTime.toIso8601String());
    } else {
      await prefs.remove(StorageService.keyEatingStartTime);
    }
    if (lastPenaltyCheckDate != null) {
      await prefs.setString(StorageService.keyLastPenaltyCheckDate, lastPenaltyCheckDate.toIso8601String());
    }
    await prefs.setInt(StorageService.keyElapsedSeconds, elapsedSeconds);
    await prefs.setInt(StorageService.keyFastingGoalHours, fastingGoalHours);
    await prefs.setString(StorageService.keyHistory, jsonEncode(history.map((e) => e.toJson()).toList()));
    debugPrint('LocalStorageService: State saved. isFasting=$isFasting');
    _markDirty(SyncDomain.fastingState, 'default');
  }

  @override
  Future<Map<String, dynamic>> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final isFasting = prefs.getBool(StorageService.keyIsFasting) ?? false;
    final startTimeStr = prefs.getString(StorageService.keyStartTime);
    final eatingStartTimeStr = prefs.getString(StorageService.keyEatingStartTime);
    final lastPenaltyStr = prefs.getString(StorageService.keyLastPenaltyCheckDate);
    final elapsedSeconds = prefs.getInt(StorageService.keyElapsedSeconds) ?? 0;
    final fastingGoalHours = prefs.getInt(StorageService.keyFastingGoalHours) ?? 16;

    List<FastingLog> history = [];
    final historyRaw = prefs.getString(StorageService.keyHistory);
    if (historyRaw != null) {
      try {
        history = (jsonDecode(historyRaw) as List)
            .map((e) => FastingLog.fromJson(e))
            .toList();
      } catch (_) {}
    }

    return {
      'isFasting': isFasting,
      'startTime': startTimeStr != null ? DateTime.parse(startTimeStr) : null,
      'eatingStartTime': eatingStartTimeStr != null ? DateTime.parse(eatingStartTimeStr) : null,
      'elapsedSeconds': elapsedSeconds,
      'fastingGoalHours': fastingGoalHours,
      'history': history,
      'lastPenaltyCheckDate': lastPenaltyStr != null ? DateTime.parse(lastPenaltyStr) : null,
    };
  }

  // ── Quests ───────────────────────────────────────────────────────────────────

  @override
  Future<void> saveQuests(List<Quest> quests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyQuests, jsonEncode(quests.map((e) => e.toJson()).toList()));
    debugPrint('LocalStorageService: Quests saved (${quests.length} items)');
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<List<Quest>> loadQuests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(StorageService.keyQuests);
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
    await prefs.setString(StorageService.keyQuestRoutines, jsonEncode(routines.map((r) => r.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<HabitRoutine>> loadRoutines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyQuestRoutines);
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
    await prefs.setString(StorageService.keyQuestAchievements, jsonEncode(achievements.map((a) => a.toJson()).toList()));
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<List<QuestAchievement>> loadAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyQuestAchievements);
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
    await prefs.setString(StorageService.keyQuestPenaltyCheckDate, date.toIso8601String());
    _markDirty(SyncDomain.userQuests, 'default');
  }

  @override
  Future<DateTime?> loadQuestPenaltyCheckDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyQuestPenaltyCheckDate);
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
    final raw = prefs.getString(StorageService.keyNutritionLogs);
    final Map<String, dynamic> all = raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(StorageService.keyNutritionLogs, jsonEncode(all));
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

  DailyNutritionLog _loadNutritionLogForKey(SharedPreferences prefs, String key) {
    final raw = prefs.getString(StorageService.keyNutritionLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
        if (all.containsKey(key)) {
          return DailyNutritionLog.fromJson(all[key] as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint('LocalStorageService: Error loading nutrition log [$key]: $e');
      }
    }
    return DailyNutritionLog.empty(key);
  }

  @override
  Future<List<DailyNutritionLog>> loadNutritionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyNutritionLogs);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final logs = all.entries
          .where((e) => e.key != todayKey)
          .map((e) => DailyNutritionLog.fromJson(e.value as Map<String, dynamic>))
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
    await prefs.setString(StorageService.keyNutritionGoals, jsonEncode(goals.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<NutritionGoals> loadNutritionGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyNutritionGoals);
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
    await prefs.setInt(StorageService.keyNutritionStreak, streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadNutritionStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(StorageService.keyNutritionStreak) ?? 0;
  }

  @override
  Future<void> saveNutritionGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyNutritionGoalMetDate, date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadNutritionGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageService.keyNutritionGoalMetDate);
  }

  @override
  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyTdeeProfile, jsonEncode(profile.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<TdeeProfile?> loadTdeeProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyTdeeProfile);
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
    await prefs.setString(StorageService.keyFoodLibrary, jsonEncode(templates.map((t) => t.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<FoodTemplate>> loadFoodLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyFoodLibrary);
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
    await prefs.setInt(StorageService.keyLogStreak, streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadLogStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(StorageService.keyLogStreak) ?? 0;
  }

  @override
  Future<void> saveLogStreakDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyLogStreakDate, date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadLogStreakDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageService.keyLogStreakDate);
  }

  // ── Activity ─────────────────────────────────────────────────────────────────

  @override
  Future<void> saveActivityLog(ActivityLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyActivityLogs);
    final Map<String, dynamic> all = raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    all[log.date] = log.toJson();
    await prefs.setString(StorageService.keyActivityLogs, jsonEncode(all));
    _markDirty(SyncDomain.activityLog, log.date);
  }

  @override
  Future<ActivityLog> loadTodayActivityLog() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final raw = prefs.getString(StorageService.keyActivityLogs);
    if (raw != null) {
      try {
        final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
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
    final raw = prefs.getString(StorageService.keyActivityLogs);
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
    final raw = prefs.getString(StorageService.keyActivityLogs);
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
    final raw = prefs.getString(StorageService.keyActivityLogs);
    if (raw == null) return;
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final todayEntry = all[todayKey];
      await prefs.setString(
        StorageService.keyActivityLogs,
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
    final raw = prefs.getString(StorageService.keyActivityLogs);
    final Map<String, dynamic> all = raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    for (final log in logs) {
      all[log.date] = log.toJson();
    }
    await prefs.setString(StorageService.keyActivityLogs, jsonEncode(all));
    if (!_applyingRemote) {
      for (final log in logs) {
        _syncQueue?.markDirty(SyncDomain.activityLog, log.date);
      }
    }
  }

  @override
  Future<void> saveActivityGoals(ActivityGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyActivityGoals, jsonEncode(goals.toJson()));
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<ActivityGoals> loadActivityGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyActivityGoals);
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
    return prefs.getString(StorageService.keyPreferredStepsSource);
  }

  @override
  Future<void> savePreferredStepsSource(String? sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sourceId == null) {
      await prefs.remove(StorageService.keyPreferredStepsSource);
    } else {
      await prefs.setString(StorageService.keyPreferredStepsSource, sourceId);
    }
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<void> saveActivityGoalMetDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyActivityGoalMetDate, date);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<String?> loadActivityGoalMetDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageService.keyActivityGoalMetDate);
  }

  @override
  Future<void> saveActivityStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageService.keyActivityStreak, streak);
    _markDirty(SyncDomain.userProfile, 'default');
  }

  @override
  Future<int> loadActivityStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(StorageService.keyActivityStreak) ?? 0;
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────

  @override
  Future<void> saveChatMessages(String date, List<dynamic> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyChatMessages);
    final Map<String, dynamic> all = raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
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
    await prefs.setString(StorageService.keyChatMessages, jsonEncode(all));
    _markDirty(SyncDomain.nutritionLog, date);
  }

  @override
  Future<List<Map<String, dynamic>>> loadChatMessagesRaw(String date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyChatMessages);
    if (raw == null) return [];
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final list = all[date] as List?;
      if (list == null) return [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading chat messages for $date: $e');
      return [];
    }
  }

  // ── Finance ──────────────────────────────────────────────────────────────────

  @override
  Future<void> saveAccounts(List<FinancialAccount> accounts) async {
    if (!_applyingRemote) {
      final existing = await loadAccounts();
      final removed = existing.map((e) => e.id).toSet()
          .difference(accounts.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_accounts/$id', op: SyncOp.delete);
      }
      for (final a in accounts) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_accounts/${a.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyFinancialAccounts, jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<FinancialAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyFinancialAccounts);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FinancialAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading accounts: $e');
      return [];
    }
  }

  @override
  Future<void> saveTransactions(List<TransactionRecord> transactions) async {
    if (!_applyingRemote) {
      final existing = await loadTransactions();
      final removed = existing.map((e) => e.id).toSet()
          .difference(transactions.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_transactions/$id', op: SyncOp.delete);
      }
      for (final t in transactions) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_transactions/${t.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyTransactions, jsonEncode(transactions.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<TransactionRecord>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyTransactions);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TransactionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LocalStorageService: Error loading transactions: $e');
      return [];
    }
  }

  @override
  Future<void> saveFinanceCategories(List<FinanceCategory> categories) async {
    if (!_applyingRemote) {
      final existing = await loadFinanceCategories();
      final removed = existing.map((e) => e.id).toSet()
          .difference(categories.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_categories/$id', op: SyncOp.delete);
      }
      for (final c in categories) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_categories/${c.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyFinanceCategories, jsonEncode(categories.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<FinanceCategory>> loadFinanceCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyFinanceCategories);
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
      final removed = existing.map((e) => e.id).toSet()
          .difference(budgets.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_budgets/$id', op: SyncOp.delete);
      }
      for (final b in budgets) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_budgets/${b.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyBudgets, jsonEncode(budgets.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Budget>> loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyBudgets);
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
      final removed = existing.map((e) => e.id).toSet()
          .difference(expenses.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_budgeted_expenses/$id', op: SyncOp.delete);
      }
      for (final e in expenses) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_budgeted_expenses/${e.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyBudgetedExpenses, jsonEncode(expenses.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<BudgetedExpense>> loadBudgetedExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyBudgetedExpenses);
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
      final removed = existing.map((e) => e.id).toSet()
          .difference(bills.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_bills/$id', op: SyncOp.delete);
      }
      for (final b in bills) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_bills/${b.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyBills, jsonEncode(bills.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Bill>> loadBills() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyBills);
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
      final removed = existing.map((e) => e.id).toSet()
          .difference(receivables.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_receivables/$id', op: SyncOp.delete);
      }
      for (final r in receivables) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_receivables/${r.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyReceivables, jsonEncode(receivables.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Receivable>> loadReceivables() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyReceivables);
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
      final removed = existing.map((e) => e.id).toSet()
          .difference(installments.map((e) => e.id).toSet());
      for (final id in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_installments/$id', op: SyncOp.delete);
      }
      for (final i in installments) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_installments/${i.id}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyInstallments, jsonEncode(installments.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<Installment>> loadInstallments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyInstallments);
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
      final removed = existing.map((e) => e.month).toSet()
          .difference(summaries.map((e) => e.month).toSet());
      for (final month in removed) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_monthly_summaries/$month', op: SyncOp.delete);
      }
      for (final s in summaries) {
        _syncQueue?.markDirty(SyncDomain.financeRecord, 'finance_monthly_summaries/${s.month}');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageService.keyMonthlySummaries, jsonEncode(summaries.map((e) => e.toJson()).toList()));
  }

  @override
  Future<List<MonthlySummary>> loadMonthlySummaries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyMonthlySummaries);
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
    await prefs.setString(StorageService.keyPersonalFoodDict, jsonEncode(entries.map((e) => e.toJson()).toList()));
    _markDirty(SyncDomain.userCollections, 'default');
  }

  @override
  Future<List<PersonalFoodEntry>> loadPersonalDict() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageService.keyPersonalFoodDict);
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

  // ── Export / Import ──────────────────────────────────────────────────────────

  @override
  Future<String> exportAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final allData = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      allData[key] = prefs.get(key);
    }
    return jsonEncode(allData);
  }

  @override
  Future<void> importAllData(String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final Map<String, dynamic> data = jsonDecode(jsonString);
      await prefs.clear();
      for (final key in data.keys) {
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
      debugPrint('LocalStorageService: Import successful.');
    } catch (e) {
      debugPrint('LocalStorageService: Import failed: $e');
      throw Exception('Invalid data format');
    }
  }
}
