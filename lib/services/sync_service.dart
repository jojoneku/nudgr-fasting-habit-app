import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import 'local_storage_service.dart';
import 'sync_queue.dart';

class SyncService {
  final SupabaseClient _supabase;
  final LocalStorageService _storage;
  final SyncQueue _queue;
  final String _userId;

  bool _isSyncing = false;
  DateTime? _lastSyncedAt;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  VoidCallback? _onStateChange;

  SyncService({
    required SupabaseClient supabase,
    required LocalStorageService storage,
    required SyncQueue queue,
    required String userId,
  })  : _supabase = supabase,
        _storage = storage,
        _queue = queue,
        _userId = userId;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get pendingCount => _queue.pendingCount;

  void setOnStateChange(VoidCallback cb) => _onStateChange = cb;

  Future<void> init() async {
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOffline && _isOnline) pushPending();
    });
  }

  Future<void> pushPending() async {
    if (_isSyncing || !_isOnline || _queue.pendingCount == 0) return;
    _isSyncing = true;
    _onStateChange?.call();
    try {
      final entries = List<SyncQueueEntry>.from(_queue.entries);
      final processed = <SyncQueueEntry>[];
      for (final entry in entries) {
        try {
          await _pushEntry(entry);
          processed.add(entry);
        } catch (e) {
          debugPrint('SyncService: push failed for ${entry.domain.name}/${entry.key}: $e');
          break;
        }
      }
      _queue.removeEntries(processed);
      if (processed.isNotEmpty) _lastSyncedAt = DateTime.now();
    } finally {
      _isSyncing = false;
      _onStateChange?.call();
    }
  }

  Future<void> _pushEntry(SyncQueueEntry entry) async {
    if (entry.op == SyncOp.delete) {
      await _pushDelete(entry);
      return;
    }
    switch (entry.domain) {
      case SyncDomain.userProfile:
        await _pushUserProfile();
      case SyncDomain.userCollections:
        await _pushUserCollections();
      case SyncDomain.nutritionLog:
        await _pushNutritionLog(entry.key);
      case SyncDomain.activityLog:
        await _pushActivityLog(entry.key);
      case SyncDomain.financeRecord:
        await _pushFinanceRecord(entry.key);
    }
  }

  Future<void> _pushDelete(SyncQueueEntry entry) async {
    if (entry.domain != SyncDomain.financeRecord) return;
    final parts = entry.key.split('/');
    if (parts.length != 2) return;
    await _supabase
        .from('finance_records')
        .delete()
        .eq('user_id', _userId)
        .eq('table_name', parts[0])
        .eq('record_id', parts[1]);
  }

  Future<void> _pushUserProfile() async {
    final state = await _storage.loadState();
    final history = state['history'] as List<FastingLog>;
    final data = {
      'fastingState': {
        'isFasting': state['isFasting'],
        'startTime': (state['startTime'] as DateTime?)?.toIso8601String(),
        'eatingStartTime': (state['eatingStartTime'] as DateTime?)?.toIso8601String(),
        'elapsedSeconds': state['elapsedSeconds'],
        'fastingGoalHours': state['fastingGoalHours'],
        'history': history.map((e) => e.toJson()).toList(),
        'lastPenaltyCheckDate': (state['lastPenaltyCheckDate'] as DateTime?)?.toIso8601String(),
      },
      'userStats': (await _storage.loadUserStats()).toJson(),
      'nutritionGoals': (await _storage.loadNutritionGoals()).toJson(),
      'tdeeProfile': (await _storage.loadTdeeProfile())?.toJson(),
      'activityGoals': (await _storage.loadActivityGoals()).toJson(),
      'nutritionStreak': await _storage.loadNutritionStreak(),
      'nutritionGoalMetDate': await _storage.loadNutritionGoalMetDate(),
      'logStreak': await _storage.loadLogStreak(),
      'logStreakDate': await _storage.loadLogStreakDate(),
      'activityStreak': await _storage.loadActivityStreak(),
      'activityGoalMetDate': await _storage.loadActivityGoalMetDate(),
      'questPenaltyCheckDate': (await _storage.loadQuestPenaltyCheckDate())?.toIso8601String(),
      'preferredStepsSource': await _storage.loadPreferredStepsSource(),
    };
    await _supabase.from('user_profile').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pushUserCollections() async {
    final data = {
      'quests': (await _storage.loadQuests()).map((e) => e.toJson()).toList(),
      'achievements': (await _storage.loadAchievements()).map((e) => e.toJson()).toList(),
      'routines': (await _storage.loadRoutines()).map((e) => e.toJson()).toList(),
      'foodLibrary': (await _storage.loadFoodLibrary()).map((e) => e.toJson()).toList(),
      'personalDict': (await _storage.loadPersonalDict()).map((e) => e.toJson()).toList(),
    };
    await _supabase.from('user_collections').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pushNutritionLog(String dateKey) async {
    final log = await _storage.loadNutritionLogForDate(dateKey);
    final messages = await _storage.loadChatMessagesRaw(dateKey);
    await _supabase.from('nutrition_logs').upsert({
      'user_id': _userId,
      'date': dateKey,
      'data': {'log': log.toJson(), 'messages': messages},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pushActivityLog(String dateKey) async {
    final todayLog = await _storage.loadTodayActivityLog();
    ActivityLog log;
    if (todayLog.date == dateKey) {
      log = todayLog;
    } else {
      final history = await _storage.loadActivityHistory();
      log = history.firstWhere((l) => l.date == dateKey, orElse: () => ActivityLog.empty(dateKey));
    }
    await _supabase.from('activity_logs').upsert({
      'user_id': _userId,
      'date': dateKey,
      'data': log.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _pushFinanceRecord(String key) async {
    final parts = key.split('/');
    if (parts.length != 2) return;
    final tableName = parts[0];
    final recordId = parts[1];
    final data = await _loadFinanceRecord(tableName, recordId);
    if (data == null) return;
    await _supabase.from('finance_records').upsert({
      'user_id': _userId,
      'table_name': tableName,
      'record_id': recordId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> _loadFinanceRecord(String tableName, String recordId) async {
    switch (tableName) {
      case 'finance_accounts':
        return (await _storage.loadAccounts()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_transactions':
        return (await _storage.loadTransactions()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_categories':
        return (await _storage.loadFinanceCategories()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_budgets':
        return (await _storage.loadBudgets()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_budgeted_expenses':
        return (await _storage.loadBudgetedExpenses()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_bills':
        return (await _storage.loadBills()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_receivables':
        return (await _storage.loadReceivables()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_installments':
        return (await _storage.loadInstallments()).where((e) => e.id == recordId).firstOrNull?.toJson();
      case 'finance_monthly_summaries':
        return (await _storage.loadMonthlySummaries()).where((e) => e.month == recordId).firstOrNull?.toJson();
      default:
        return null;
    }
  }

  // ── Pull ─────────────────────────────────────────────────────────────────────

  Future<void> pullAll() async {
    if (!_isOnline) return;
    _isSyncing = true;
    _onStateChange?.call();
    try {
      await _pullUserProfile();
      await _pullUserCollections();
      await _pullNutritionLogs();
      await _pullActivityLogs();
      await _pullFinanceRecords();
      _lastSyncedAt = DateTime.now();
      _storage.onRemoteDataApplied?.call();
    } catch (e) {
      debugPrint('SyncService: pullAll error: $e');
    } finally {
      _isSyncing = false;
      _onStateChange?.call();
    }
  }

  Future<void> _pullUserProfile() async {
    final row = await _supabase
        .from('user_profile')
        .select('data, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return;

    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime = _queue.getTimestamp(SyncDomain.userProfile, 'default');
    if (!remoteTime.isAfter(localTime)) return;

    final data = row['data'] as Map<String, dynamic>;
    await _storage.applyRemote(() async {
      if (data['userStats'] != null) {
        await _storage.saveUserStats(UserStats.fromJson(data['userStats'] as Map<String, dynamic>));
      }
      if (data['nutritionGoals'] != null) {
        await _storage.saveNutritionGoals(NutritionGoals.fromJson(data['nutritionGoals'] as Map<String, dynamic>));
      }
      if (data['tdeeProfile'] != null) {
        await _storage.saveTdeeProfile(TdeeProfile.fromJson(data['tdeeProfile'] as Map<String, dynamic>));
      }
      if (data['activityGoals'] != null) {
        await _storage.saveActivityGoals(ActivityGoals.fromJson(data['activityGoals'] as Map<String, dynamic>));
      }
      if (data['nutritionStreak'] != null) await _storage.saveNutritionStreak(data['nutritionStreak'] as int);
      if (data['nutritionGoalMetDate'] != null) await _storage.saveNutritionGoalMetDate(data['nutritionGoalMetDate'] as String);
      if (data['logStreak'] != null) await _storage.saveLogStreak(data['logStreak'] as int);
      if (data['logStreakDate'] != null) await _storage.saveLogStreakDate(data['logStreakDate'] as String);
      if (data['activityStreak'] != null) await _storage.saveActivityStreak(data['activityStreak'] as int);
      if (data['activityGoalMetDate'] != null) await _storage.saveActivityGoalMetDate(data['activityGoalMetDate'] as String);
      if (data['preferredStepsSource'] != null) await _storage.savePreferredStepsSource(data['preferredStepsSource'] as String?);
      final fs = data['fastingState'] as Map<String, dynamic>?;
      if (fs != null) {
        final history = (fs['history'] as List? ?? [])
            .map((e) => FastingLog.fromJson(e as Map<String, dynamic>))
            .toList();
        await _storage.saveState(
          isFasting: fs['isFasting'] as bool? ?? false,
          startTime: fs['startTime'] != null ? DateTime.parse(fs['startTime'] as String) : null,
          eatingStartTime: fs['eatingStartTime'] != null ? DateTime.parse(fs['eatingStartTime'] as String) : null,
          elapsedSeconds: fs['elapsedSeconds'] as int? ?? 0,
          fastingGoalHours: fs['fastingGoalHours'] as int? ?? 16,
          history: history,
          lastPenaltyCheckDate: fs['lastPenaltyCheckDate'] != null ? DateTime.parse(fs['lastPenaltyCheckDate'] as String) : null,
        );
      }
    });
    _queue.setTimestamp(SyncDomain.userProfile, 'default', time: remoteTime);
  }

  Future<void> _pullUserCollections() async {
    final row = await _supabase
        .from('user_collections')
        .select('data, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return;

    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime = _queue.getTimestamp(SyncDomain.userCollections, 'default');
    if (!remoteTime.isAfter(localTime)) return;

    final data = row['data'] as Map<String, dynamic>;
    await _storage.applyRemote(() async {
      if (data['quests'] != null) {
        await _storage.saveQuests((data['quests'] as List)
            .map((e) => Quest.fromJson(e as Map<String, dynamic>)).toList());
      }
      if (data['achievements'] != null) {
        await _storage.saveAchievements((data['achievements'] as List)
            .map((e) => QuestAchievement.fromJson(e as Map<String, dynamic>)).toList());
      }
      if (data['routines'] != null) {
        await _storage.saveRoutines((data['routines'] as List)
            .map((e) => HabitRoutine.fromJson(e as Map<String, dynamic>)).toList());
      }
      if (data['foodLibrary'] != null) {
        await _storage.saveFoodLibrary((data['foodLibrary'] as List)
            .map((e) => FoodTemplate.fromJson(e as Map<String, dynamic>)).toList());
      }
      if (data['personalDict'] != null) {
        await _storage.savePersonalDict((data['personalDict'] as List)
            .map((e) => PersonalFoodEntry.fromJson(e as Map<String, dynamic>)).toList());
      }
    });
    _queue.setTimestamp(SyncDomain.userCollections, 'default', time: remoteTime);
  }

  Future<void> _pullNutritionLogs() async {
    final rows = await _supabase
        .from('nutrition_logs')
        .select('date, data, updated_at')
        .eq('user_id', _userId);
    for (final row in rows as List) {
      final dateKey = row['date'] as String;
      final remoteTime = DateTime.parse(row['updated_at'] as String);
      final localTime = _queue.getTimestamp(SyncDomain.nutritionLog, dateKey);
      if (!remoteTime.isAfter(localTime)) continue;
      final data = row['data'] as Map<String, dynamic>;
      await _storage.applyRemote(() async {
        if (data['log'] != null) {
          await _storage.saveNutritionLog(DailyNutritionLog.fromJson(data['log'] as Map<String, dynamic>));
        }
        if (data['messages'] != null) {
          await _storage.saveChatMessages(dateKey, (data['messages'] as List).cast<Map<String, dynamic>>());
        }
      });
      _queue.setTimestamp(SyncDomain.nutritionLog, dateKey, time: remoteTime);
    }
  }

  Future<void> _pullActivityLogs() async {
    final rows = await _supabase
        .from('activity_logs')
        .select('date, data, updated_at')
        .eq('user_id', _userId);
    for (final row in rows as List) {
      final dateKey = row['date'] as String;
      final remoteTime = DateTime.parse(row['updated_at'] as String);
      final localTime = _queue.getTimestamp(SyncDomain.activityLog, dateKey);
      if (!remoteTime.isAfter(localTime)) continue;
      await _storage.applyRemote(() async {
        await _storage.saveActivityLog(ActivityLog.fromJson(row['data'] as Map<String, dynamic>));
      });
      _queue.setTimestamp(SyncDomain.activityLog, dateKey, time: remoteTime);
    }
  }

  Future<void> _pullFinanceRecords() async {
    final rows = await _supabase
        .from('finance_records')
        .select('table_name, record_id, data, updated_at')
        .eq('user_id', _userId);

    final byTable = <String, List<Map<String, dynamic>>>{};
    for (final row in rows as List) {
      final t = row['table_name'] as String;
      byTable.putIfAbsent(t, () => []).add(row as Map<String, dynamic>);
    }

    await _pullFinanceTable<FinancialAccount>(byTable['finance_accounts'] ?? [], 'finance_accounts',
        loadAll: _storage.loadAccounts, fromJson: FinancialAccount.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveAccounts);
    await _pullFinanceTable<TransactionRecord>(byTable['finance_transactions'] ?? [], 'finance_transactions',
        loadAll: _storage.loadTransactions, fromJson: TransactionRecord.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveTransactions);
    await _pullFinanceTable<FinanceCategory>(byTable['finance_categories'] ?? [], 'finance_categories',
        loadAll: _storage.loadFinanceCategories, fromJson: FinanceCategory.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveFinanceCategories);
    await _pullFinanceTable<Budget>(byTable['finance_budgets'] ?? [], 'finance_budgets',
        loadAll: _storage.loadBudgets, fromJson: Budget.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveBudgets);
    await _pullFinanceTable<BudgetedExpense>(byTable['finance_budgeted_expenses'] ?? [], 'finance_budgeted_expenses',
        loadAll: _storage.loadBudgetedExpenses, fromJson: BudgetedExpense.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveBudgetedExpenses);
    await _pullFinanceTable<Bill>(byTable['finance_bills'] ?? [], 'finance_bills',
        loadAll: _storage.loadBills, fromJson: Bill.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveBills);
    await _pullFinanceTable<Receivable>(byTable['finance_receivables'] ?? [], 'finance_receivables',
        loadAll: _storage.loadReceivables, fromJson: Receivable.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveReceivables);
    await _pullFinanceTable<Installment>(byTable['finance_installments'] ?? [], 'finance_installments',
        loadAll: _storage.loadInstallments, fromJson: Installment.fromJson,
        getId: (e) => e.id, saveAll: _storage.saveInstallments);
    await _pullFinanceTable<MonthlySummary>(byTable['finance_monthly_summaries'] ?? [], 'finance_monthly_summaries',
        loadAll: _storage.loadMonthlySummaries, fromJson: MonthlySummary.fromJson,
        getId: (e) => e.month, saveAll: _storage.saveMonthlySummaries);
  }

  Future<void> _pullFinanceTable<T>(
    List<Map<String, dynamic>> rows,
    String tableName, {
    required Future<List<T>> Function() loadAll,
    required T Function(Map<String, dynamic>) fromJson,
    required String Function(T) getId,
    required Future<void> Function(List<T>) saveAll,
  }) async {
    if (rows.isEmpty) return;
    final localList = await loadAll();
    final localMap = {for (final item in localList) getId(item): item};
    bool changed = false;
    for (final row in rows) {
      final recordId = row['record_id'] as String;
      final remoteTime = DateTime.parse(row['updated_at'] as String);
      final localTime = _queue.getTimestamp(SyncDomain.financeRecord, '$tableName/$recordId');
      if (!remoteTime.isAfter(localTime)) continue;
      localMap[recordId] = fromJson(row['data'] as Map<String, dynamic>);
      _queue.setTimestamp(SyncDomain.financeRecord, '$tableName/$recordId', time: remoteTime);
      changed = true;
    }
    if (changed) {
      await _storage.applyRemote(() async => saveAll(localMap.values.toList()));
    }
  }

  Future<void> forceSync() async {
    await pushPending();
    await pullAll();
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
