import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_goals.dart';
import '../models/activity_log.dart';
import '../models/daily_nutrition_log.dart';
import '../models/fasting_log.dart';
import '../models/food_template.dart';
import '../models/grocery/remembered_price.dart';
import '../models/grocery/saved_trip.dart';
import '../models/habit_routine.dart';
import '../models/notification_preferences.dart';
import '../models/nutrition_goals.dart';
import '../models/quest.dart';
import '../models/quest_achievement.dart';
import '../models/tdee_profile.dart';
import '../models/user_stats.dart';
import '../models/weight_entry.dart';
import '../models/body_measurement_entry.dart';
import '../models/food_feedback.dart';
import '../models/finance/finance_dict_entry.dart';
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
  DateTime? _lastPulledAt;
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  VoidCallback? _onStateChange;
  Timer? _debounceTimer;

  // Diagnostics for the last pullAll: domains that threw and individual records
  // that were skipped because they couldn't be parsed. Surfaced so a failure
  // is debuggable in release builds (where debugPrint is stripped) instead of
  // collapsing into an opaque "Sync failed".
  List<String> _lastPullErrors = const [];
  final List<String> _lastSkippedRecords = [];

  /// Domain-level pull failures from the most recent [pullAll] (empty on a
  /// clean pull). Each entry is `'<domain>: <error>'`.
  List<String> get lastPullErrors => _lastPullErrors;

  /// Individual records skipped during the most recent [pullAll] because they
  /// could not be parsed. Each entry is `'<table>/<recordId>: <error>'`.
  List<String> get lastSkippedRecords => List.unmodifiable(_lastSkippedRecords);

  void _recordSkipped(String id, Object e) {
    _lastSkippedRecords.add('$id: $e');
    debugPrint('SyncService: skipping unparseable record $id: $e');
  }

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

  /// Schedules a push after a 3-second debounce so rapid saves batch together.
  void schedulePush() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), pushPending);
  }

  Future<void> init() async {
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOffline && _isOnline) pushPending();
    });
  }

  // Per-entry failure bookkeeping for skip-and-continue with exponential
  // backoff (Plan 053 Phase 2). Previously pushPending `break`ed on the first
  // error, so one poison/conflicting entry blocked every entry behind it
  // forever. Now a failure is isolated: the entry stays queued and is retried
  // after a growing delay, while the rest of the queue still drains.
  final Map<String, int> _failureCounts = {};
  final Map<String, DateTime> _retryAfter = {};

  String _entryId(SyncQueueEntry e) => '${e.domain.name}/${e.key}';

  @visibleForTesting
  int failureCountFor(SyncDomain domain, String key) =>
      _failureCounts['${domain.name}/$key'] ?? 0;

  Future<void> pushPending() async {
    if (_isSyncing || _queue.pendingCount == 0) {
      debugPrint(
          'SyncService: pushPending skipped — isSyncing=$_isSyncing, pending=${_queue.pendingCount}');
      return;
    }
    debugPrint(
        'SyncService: pushPending starting — ${_queue.pendingCount} entries');
    _isSyncing = true;
    _onStateChange?.call();
    try {
      final entries = List<SyncQueueEntry>.from(_queue.entries);
      final processed = <SyncQueueEntry>[];
      final now = DateTime.now();

      // Finance UPSERTS are batched into bulk requests (one HTTP call per
      // ~200 rows, each table read once) instead of one request + a full-list
      // reload per record. Boot was otherwise firing hundreds of serial
      // upserts (O(n²) local reads), taking minutes. Deletes/tombstones and
      // whole-object singletons keep the per-entry path with its failure
      // isolation + backoff.
      final financeUpserts = <SyncQueueEntry>[];
      final others = <SyncQueueEntry>[];
      for (final entry in entries) {
        if (entry.domain == SyncDomain.financeRecord &&
            entry.op == SyncOp.upsert) {
          financeUpserts.add(entry);
        } else {
          others.add(entry);
        }
      }

      final readyFinance =
          financeUpserts.where((e) => !_inBackoff(_entryId(e), now)).toList();
      if (readyFinance.isNotEmpty) {
        processed.addAll(await _pushFinanceUpsertBatch(readyFinance, now));
      }

      for (final entry in others) {
        final id = _entryId(entry);
        if (_inBackoff(id, now)) {
          // Quarantined after repeated failures — skip this round, stay queued.
          debugPrint('SyncService: skipping $id (in backoff)');
          continue;
        }
        try {
          debugPrint('SyncService: pushing $id');
          await _pushEntry(entry);
          processed.add(entry);
          _failureCounts.remove(id);
          _retryAfter.remove(id);
        } catch (e) {
          // Isolate the failure: record it, back off, and CONTINUE so later
          // entries still get a turn (no `break`).
          _recordFailure(id, now, e);
        }
      }
      _queue.removeEntries(processed);
      if (processed.isNotEmpty) _lastSyncedAt = DateTime.now();
      debugPrint(
          'SyncService: pushPending done — ${processed.length} pushed, ${_queue.pendingCount} remaining');
    } finally {
      _isSyncing = false;
      _onStateChange?.call();
    }
  }

  bool _inBackoff(String id, DateTime now) {
    final retryAt = _retryAfter[id];
    return retryAt != null && now.isBefore(retryAt);
  }

  void _recordFailure(String id, DateTime now, Object e) {
    final count = (_failureCounts[id] ?? 0) + 1;
    _failureCounts[id] = count;
    final backoffSec = (1 << count.clamp(1, 9)).clamp(2, 300);
    _retryAfter[id] = now.add(Duration(seconds: backoffSec));
    debugPrint(
        'SyncService: push failed for $id (attempt $count), backing off ${backoffSec}s: $e');
  }

  /// Maximum rows per bulk finance upsert. Keeps each request bounded while
  /// collapsing hundreds of per-record pushes into a handful of calls.
  static const int _financeBatchSize = 200;

  /// Bulk-pushes finance upsert [ready] entries. Each finance table is loaded
  /// once; entries whose local record has vanished (and that have no delete op)
  /// are dropped so they can't wedge the queue forever — this mirrors the old
  /// per-record path, which no-opped on missing data then removed the entry.
  /// A failed chunk backs off just that chunk's entries and leaves them queued.
  Future<List<SyncQueueEntry>> _pushFinanceUpsertBatch(
      List<SyncQueueEntry> ready, DateTime now) async {
    final pairs = await buildFinanceUpsertRows(ready);
    final present = pairs.map((p) => p.key).toSet();
    final processed = <SyncQueueEntry>[
      for (final e in ready)
        if (!present.contains(e)) e,
    ];

    for (var i = 0; i < pairs.length; i += _financeBatchSize) {
      final end = (i + _financeBatchSize).clamp(0, pairs.length);
      final chunk = pairs.sublist(i, end);
      try {
        await _supabase
            .from('finance_records')
            .upsert([for (final p in chunk) p.value]);
        for (final p in chunk) {
          final id = _entryId(p.key);
          processed.add(p.key);
          _failureCounts.remove(id);
          _retryAfter.remove(id);
        }
      } catch (e) {
        for (final p in chunk) {
          _recordFailure(_entryId(p.key), now, e);
        }
        debugPrint(
            'SyncService: finance batch upsert failed (${chunk.length} rows): $e');
      }
    }
    return processed;
  }

  /// Builds bulk-upsert (entry → row) pairs for finance upsert entries, reading
  /// each finance table at most once. Pairs are only produced for records that
  /// still exist locally; missing ones are omitted (the caller drops them).
  @visibleForTesting
  Future<List<MapEntry<SyncQueueEntry, Map<String, dynamic>>>>
      buildFinanceUpsertRows(List<SyncQueueEntry> entries) async {
    final byTable = <String, List<SyncQueueEntry>>{};
    for (final e in entries) {
      final parts = e.key.split('/');
      if (parts.length != 2) continue;
      byTable.putIfAbsent(parts[0], () => []).add(e);
    }
    final stamp = DateTime.now().toUtc().toIso8601String();
    final rows = <MapEntry<SyncQueueEntry, Map<String, dynamic>>>[];
    for (final tableName in byTable.keys) {
      final lookup = await _loadFinanceTable(tableName);
      if (lookup == null) continue;
      for (final e in byTable[tableName]!) {
        final recordId = e.key.split('/')[1];
        final data = lookup[recordId];
        if (data == null) continue;
        rows.add(MapEntry(e, {
          'user_id': _userId,
          'table_name': tableName,
          'record_id': recordId,
          'data': data,
          'updated_at': stamp,
        }));
      }
    }
    return rows;
  }

  /// Loads an entire finance table once as `recordId -> data`, so a batch push
  /// doesn't reload the full list per record (was O(n²)).
  Future<Map<String, Map<String, dynamic>>?> _loadFinanceTable(
      String tableName) async {
    switch (tableName) {
      case 'finance_accounts':
        return {
          for (final e in await _storage.loadAccounts()) e.id: e.toJson()
        };
      case 'finance_transactions':
        return {
          for (final e in await _storage.loadTransactions()) e.id: e.toJson()
        };
      case 'finance_categories':
        return {
          for (final e in await _storage.loadFinanceCategories())
            e.id: e.toJson()
        };
      case 'finance_budgets':
        return {for (final e in await _storage.loadBudgets()) e.id: e.toJson()};
      case 'finance_budgeted_expenses':
        return {
          for (final e in await _storage.loadBudgetedExpenses())
            e.id: e.toJson()
        };
      case 'finance_bills':
        return {for (final e in await _storage.loadBills()) e.id: e.toJson()};
      case 'finance_receivables':
        return {
          for (final e in await _storage.loadReceivables()) e.id: e.toJson()
        };
      case 'finance_installments':
        return {
          for (final e in await _storage.loadInstallments()) e.id: e.toJson()
        };
      case 'finance_monthly_summaries':
        return {
          for (final e in await _storage.loadMonthlySummaries())
            e.month: e.toJson()
        };
      default:
        return null;
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
      case SyncDomain.fastingState:
        await _pushFastingState();
      case SyncDomain.userQuests:
        await _pushUserQuests();
      case SyncDomain.nutritionLog:
        await _pushNutritionLog(entry.key);
      case SyncDomain.activityLog:
        await _pushActivityLog(entry.key);
      case SyncDomain.financeRecord:
        await _pushFinanceRecord(entry.key);
    }
  }

  /// Marker stored in a finance_records row's `data` to denote a deletion.
  /// (Plan 053 Phase 3.2 — tombstones, no schema change.)
  static const String _tombstoneKey = '__deleted';

  @visibleForTesting
  static bool isTombstone(Map<String, dynamic> data) =>
      data[_tombstoneKey] == true;

  Future<void> _pushDelete(SyncQueueEntry entry) async {
    if (entry.domain != SyncDomain.financeRecord) return;
    final parts = entry.key.split('/');
    if (parts.length != 2) return;
    // Write a TOMBSTONE rather than hard-deleting the row. A hard delete just
    // made the row vanish, which pull couldn't distinguish from "never synced"
    // — so a record deleted on one device resurrected on others. Keeping a
    // `{__deleted: true}` row with a fresh timestamp lets every other device
    // learn of the deletion on pull and drop its local copy via last-write-wins.
    await _supabase.from('finance_records').upsert({
      'user_id': _userId,
      'table_name': parts[0],
      'record_id': parts[1],
      'data': {_tombstoneKey: true},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // ── Empty-overwrite guards (Plan 053 Phase 1) ──────────────────────────────
  // A whole-object "singleton" push must never clobber a populated cloud row
  // with empty/default local data, and a pull must never wipe populated local
  // data with an empty/stale remote. This is the exact failure mode that
  // emptied `user_quests` to `[]` and reverted quests/fasting/weight/body.
  //
  // Tradeoff: for singletons we bias toward "never lose" over "propagate a
  // full clear". Wiping ALL quests / ALL weight on one device and expecting
  // that emptiness to replicate is vanishingly rare and far less damaging than
  // silent total loss; such a clear can still be redone explicitly. Per-record
  // deletes (finance) propagate normally via SyncOp.delete.

  static bool _listEmpty(dynamic v) => v == null || (v is List && v.isEmpty);

  @visibleForTesting
  static bool questsDataEmpty(Map<String, dynamic> d) =>
      _listEmpty(d['quests']) && _listEmpty(d['achievements']);

  @visibleForTesting
  static bool fastingDataEmpty(Map<String, dynamic> d) =>
      _listEmpty(d['history']) && d['isFasting'] != true;

  /// A nutrition snapshot whose chat feed is empty/absent. Such a snapshot
  /// must not overwrite a populated local feed on pull — that's the bug where
  /// the calorie totals survive (from `log`) but the list goes blank. Note we
  /// only gate on `messages`: the `log` half can be legitimately empty and is
  /// the source of truth for the totals.
  @visibleForTesting
  static bool nutritionFeedEmpty(Map<String, dynamic> d) =>
      _listEmpty(d['messages']);

  @visibleForTesting
  static bool profileDataEmpty(Map<String, dynamic> d) {
    final stats = d['userStats'] as Map<String, dynamic>?;
    final freshStats = stats == null ||
        (((stats['level'] as num?) ?? 1) <= 1 &&
            ((stats['currentXp'] as num?) ?? 0) == 0);
    return _listEmpty(d['weightLog']) &&
        _listEmpty(d['bodyMeasurements']) &&
        freshStats;
  }

  @visibleForTesting
  static bool collectionsDataEmpty(Map<String, dynamic> d) =>
      _listEmpty(d['routines']) &&
      _listEmpty(d['foodLibrary']) &&
      _listEmpty(d['personalDict']) &&
      _listEmpty(d['foodFeedback']) &&
      _listEmpty(d['financeDictionary']) &&
      _listEmpty(d['groceryPriceMemory']) &&
      _listEmpty(d['groceryTripHistory']);

  /// True when a push would clobber a populated cloud row: the local payload is
  /// empty AND a non-empty remote row already exists → the push must be skipped.
  Future<bool> _wouldClobberRemote(
    String table,
    bool localEmpty,
    bool Function(Map<String, dynamic>) remoteEmpty,
  ) async {
    if (!localEmpty) return false;
    final row = await _supabase
        .from(table)
        .select('data')
        .eq('user_id', _userId)
        .maybeSingle();
    final data = row?['data'] as Map<String, dynamic>?;
    if (data == null) return false;
    return !remoteEmpty(data);
  }

  Future<bool> _localQuestsEmpty() async =>
      (await _storage.loadQuests()).isEmpty &&
      (await _storage.loadAchievements()).isEmpty;

  Future<bool> _localFastingEmpty() async {
    final st = await _storage.loadState();
    final hist = st['history'] as List<FastingLog>;
    return hist.isEmpty && st['isFasting'] != true;
  }

  Future<bool> _localProfileEmpty() async {
    final stats = await _storage.loadUserStats();
    return (await _storage.loadWeightLog()).isEmpty &&
        (await _storage.loadBodyMeasurements()).isEmpty &&
        stats.level <= 1 &&
        stats.currentXp == 0;
  }

  Future<bool> _localCollectionsEmpty() async =>
      (await _storage.loadRoutines()).isEmpty &&
      (await _storage.loadFoodLibrary()).isEmpty &&
      (await _storage.loadPersonalDict()).isEmpty &&
      (await _storage.loadFoodFeedback()).isEmpty &&
      (await _storage.loadFinanceDictionary()).isEmpty &&
      (await _storage.loadGroceryPriceMemory()).isEmpty &&
      (await _storage.loadGroceryTripHistory()).isEmpty;

  Future<void> _pushUserProfile() async {
    debugPrint('SyncService: _pushUserProfile — pushing profile data');
    final data = {
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
      'preferredStepsSource': await _storage.loadPreferredStepsSource(),
      'weightLog':
          (await _storage.loadWeightLog()).map((e) => e.toJson()).toList(),
      'bodyMeasurements': (await _storage.loadBodyMeasurements())
          .map((e) => e.toJson())
          .toList(),
      'measurementUnit': (await _storage.loadMeasurementUnit()).name,
      'lastRecompXpDate':
          (await _storage.loadLastRecompXpDate())?.toIso8601String(),
      'calorieGoalCreditedDates':
          (await _storage.loadCalorieGoalCreditedDates()).toList(),
      'proteinGoalCreditedDates':
          (await _storage.loadProteinGoalCreditedDates()).toList(),
      'streakMilestonePaid': await _storage.loadStreakMilestonePaid(),
      'notificationPreferences':
          (await _storage.loadNotificationPreferences()).toJson(),
    };
    if (await _wouldClobberRemote(
        'user_profile', profileDataEmpty(data), profileDataEmpty)) {
      debugPrint(
          'SyncService: _pushUserProfile — local empty but cloud populated; skipping to avoid clobber');
      return;
    }
    await _supabase.from('user_profile').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    debugPrint('SyncService: userProfile upserted ✓');
  }

  Future<void> _pushFastingState() async {
    final state = await _storage.loadState();
    final history = state['history'] as List<FastingLog>;
    debugPrint(
        'SyncService: _pushFastingState — history=${history.length} entries, isFasting=${state['isFasting']}');
    final data = {
      'isFasting': state['isFasting'],
      'startTime': (state['startTime'] as DateTime?)?.toIso8601String(),
      'eatingStartTime':
          (state['eatingStartTime'] as DateTime?)?.toIso8601String(),
      'elapsedSeconds': state['elapsedSeconds'],
      'fastingGoalHours': state['fastingGoalHours'],
      'history': history.map((e) => e.toJson()).toList(),
      'lastPenaltyCheckDate':
          (state['lastPenaltyCheckDate'] as DateTime?)?.toIso8601String(),
    };
    if (await _wouldClobberRemote(
        'fasting_state', fastingDataEmpty(data), fastingDataEmpty)) {
      debugPrint(
          'SyncService: _pushFastingState — local empty but cloud populated; skipping to avoid clobber');
      return;
    }
    await _supabase.from('fasting_state').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    debugPrint('SyncService: fastingState upserted ✓');
  }

  Future<void> _pushUserQuests() async {
    final quests = await _storage.loadQuests();
    final achievements = await _storage.loadAchievements();
    debugPrint(
        'SyncService: _pushUserQuests — quests=${quests.length}, achievements=${achievements.length}');
    final data = {
      'quests': quests.map((e) => e.toJson()).toList(),
      'achievements': achievements.map((e) => e.toJson()).toList(),
      'questPenaltyCheckDate':
          (await _storage.loadQuestPenaltyCheckDate())?.toIso8601String(),
    };
    if (await _wouldClobberRemote(
        'user_quests', questsDataEmpty(data), questsDataEmpty)) {
      debugPrint(
          'SyncService: _pushUserQuests — local empty but cloud populated; skipping to avoid clobber');
      return;
    }
    await _supabase.from('user_quests').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    debugPrint('SyncService: userQuests upserted ✓');
  }

  Future<void> _pushUserCollections() async {
    debugPrint(
        'SyncService: _pushUserCollections — pushing routines, food library, personal dict');
    final data = {
      'routines':
          (await _storage.loadRoutines()).map((e) => e.toJson()).toList(),
      'foodLibrary':
          (await _storage.loadFoodLibrary()).map((e) => e.toJson()).toList(),
      'personalDict':
          (await _storage.loadPersonalDict()).map((e) => e.toJson()).toList(),
      'foodFeedback':
          (await _storage.loadFoodFeedback()).map((e) => e.toJson()).toList(),
      'financeDictionary': (await _storage.loadFinanceDictionary())
          .map((e) => e.toJson())
          .toList(),
      'groceryPriceMemory': (await _storage.loadGroceryPriceMemory())
          .map((e) => e.toJson())
          .toList(),
      'groceryTripHistory': (await _storage.loadGroceryTripHistory())
          .map((e) => e.toJson())
          .toList(),
    };
    if (await _wouldClobberRemote(
        'user_collections', collectionsDataEmpty(data), collectionsDataEmpty)) {
      debugPrint(
          'SyncService: _pushUserCollections — local empty but cloud populated; skipping to avoid clobber');
      return;
    }
    await _supabase.from('user_collections').upsert({
      'user_id': _userId,
      'data': data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    debugPrint('SyncService: userCollections upserted ✓');
  }

  Future<void> _pushNutritionLog(String dateKey) async {
    final log = await _storage.loadNutritionLogForDate(dateKey);
    final messages = await _storage.loadChatMessagesRaw(dateKey);

    // Don't let a session whose local feed is empty (the classic case: right
    // after a re-login, before the day's feed has reloaded into storage)
    // overwrite a populated cloud feed and blank the list while the calorie
    // totals survive. Mirrors the singleton push guards (_wouldClobberRemote)
    // but keyed per date, since nutrition rows are per-day. A genuinely empty
    // cloud feed is fine to overwrite — only a populated one is protected.
    if (messages.isEmpty) {
      final row = await _supabase
          .from('nutrition_logs')
          .select('data')
          .eq('user_id', _userId)
          .eq('date', dateKey)
          .maybeSingle();
      final remote = row?['data'] as Map<String, dynamic>?;
      if (remote != null && !nutritionFeedEmpty(remote)) {
        debugPrint('SyncService: _pushNutritionLog($dateKey) — local feed '
            'empty but cloud populated; skipping to avoid clobber');
        return;
      }
    }

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
      log = history.firstWhere((l) => l.date == dateKey,
          orElse: () => ActivityLog.empty(dateKey));
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

  Future<Map<String, dynamic>?> _loadFinanceRecord(
      String tableName, String recordId) async {
    switch (tableName) {
      case 'finance_accounts':
        return (await _storage.loadAccounts())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_transactions':
        return (await _storage.loadTransactions())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_categories':
        return (await _storage.loadFinanceCategories())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_budgets':
        return (await _storage.loadBudgets())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_budgeted_expenses':
        return (await _storage.loadBudgetedExpenses())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_bills':
        return (await _storage.loadBills())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_receivables':
        return (await _storage.loadReceivables())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_installments':
        return (await _storage.loadInstallments())
            .where((e) => e.id == recordId)
            .firstOrNull
            ?.toJson();
      case 'finance_monthly_summaries':
        return (await _storage.loadMonthlySummaries())
            .where((e) => e.month == recordId)
            .firstOrNull
            ?.toJson();
      default:
        return null;
    }
  }

  // ── Pull ─────────────────────────────────────────────────────────────────────

  Future<void> pullAll() async {
    debugPrint('SyncService: pullAll starting for user $_userId');
    _isSyncing = true;
    _onStateChange?.call();
    _lastSkippedRecords.clear();
    final errors = <String>[];
    var attempted = 0;

    // Each domain is pulled independently. A failure in one domain (a corrupt
    // singleton row, a poison record, a transient read) is logged and recorded
    // but does NOT abort the others — previously the first throw rethrew out of
    // pullAll and tore down sync entirely, surfacing as a blanket "Sync failed"
    // on every client that saw the bad data. We only rethrow when EVERY domain
    // failed, which signals a genuine connectivity/auth outage rather than one
    // unparseable row.
    Future<void> pull(String label, Future<void> Function() fn) async {
      attempted++;
      try {
        debugPrint('SyncService: pulling $label...');
        await fn();
      } catch (e) {
        errors.add('$label: $e');
        debugPrint('SyncService: pull failed for $label: $e');
      }
    }

    try {
      await pull('userProfile', _pullUserProfile);
      await pull('fastingState', _pullFastingState);
      await pull('userQuests', _pullUserQuests);
      await pull('userCollections', _pullUserCollections);
      await pull('nutritionLogs', _pullNutritionLogs);
      await pull('activityLogs', _pullActivityLogs);
      await pull('financeRecords', _pullFinanceRecords);

      _lastPullErrors = List.unmodifiable(errors);
      if (errors.length == attempted) {
        // Nothing pulled — treat as a real failure so the UI can prompt a retry.
        throw Exception(
            'Sync pull failed for all domains. First error — ${errors.first}');
      }
      if (errors.isNotEmpty || _lastSkippedRecords.isNotEmpty) {
        debugPrint(
            'SyncService: pullAll completed with ${errors.length} domain failure(s) '
            'and ${_lastSkippedRecords.length} skipped record(s): '
            '${[...errors, ..._lastSkippedRecords]}');
      }
      _lastSyncedAt = DateTime.now();
      _lastPulledAt = _lastSyncedAt;
      debugPrint('SyncService: pullAll complete ✓');
      _storage.onRemoteDataApplied?.call();
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
    if (row == null) {
      debugPrint('SyncService: userProfile — no remote row found');
      return;
    }
    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime = _queue.getTimestamp(SyncDomain.userProfile, 'default');
    if (!remoteTime.isAfter(localTime)) {
      debugPrint('SyncService: userProfile — local is newer, skipping');
      return;
    }
    debugPrint(
        'SyncService: userProfile — applying remote data (remote=$remoteTime)');
    final data = row['data'] as Map<String, dynamic>;
    if (profileDataEmpty(data) && !await _localProfileEmpty()) {
      debugPrint(
          'SyncService: userProfile — remote empty but local populated; skipping to avoid wipe');
      return;
    }
    await _storage.applyRemote(() async {
      if (data['userStats'] != null) {
        await _storage.saveUserStats(
            UserStats.fromJson(data['userStats'] as Map<String, dynamic>));
      }
      if (data['nutritionGoals'] != null) {
        await _storage.saveNutritionGoals(NutritionGoals.fromJson(
            data['nutritionGoals'] as Map<String, dynamic>));
      }
      if (data['tdeeProfile'] != null) {
        await _storage.saveTdeeProfile(
            TdeeProfile.fromJson(data['tdeeProfile'] as Map<String, dynamic>));
      }
      if (data['activityGoals'] != null) {
        await _storage.saveActivityGoals(ActivityGoals.fromJson(
            data['activityGoals'] as Map<String, dynamic>));
      }
      if (data['nutritionStreak'] != null)
        await _storage.saveNutritionStreak(data['nutritionStreak'] as int);
      if (data['nutritionGoalMetDate'] != null)
        await _storage
            .saveNutritionGoalMetDate(data['nutritionGoalMetDate'] as String);
      if (data['logStreak'] != null)
        await _storage.saveLogStreak(data['logStreak'] as int);
      if (data['logStreakDate'] != null)
        await _storage.saveLogStreakDate(data['logStreakDate'] as String);
      if (data['activityStreak'] != null)
        await _storage.saveActivityStreak(data['activityStreak'] as int);
      if (data['activityGoalMetDate'] != null)
        await _storage
            .saveActivityGoalMetDate(data['activityGoalMetDate'] as String);
      if (data['preferredStepsSource'] != null)
        await _storage
            .savePreferredStepsSource(data['preferredStepsSource'] as String?);
      if (data['weightLog'] != null) {
        await _storage.saveWeightLog([
          for (final e in data['weightLog'] as List)
            WeightEntry.fromJson(e as Map<String, dynamic>),
        ]);
      }
      if (data['bodyMeasurements'] != null) {
        await _storage.saveBodyMeasurements([
          for (final e in data['bodyMeasurements'] as List)
            BodyMeasurementEntry.fromJson(e as Map<String, dynamic>),
        ]);
      }
      if (data['measurementUnit'] != null) {
        await _storage.saveMeasurementUnit(
            MeasurementUnit.values.byName(data['measurementUnit'] as String));
      }
      if (data['lastRecompXpDate'] != null) {
        await _storage.saveLastRecompXpDate(
            DateTime.parse(data['lastRecompXpDate'] as String));
      }
      if (data['calorieGoalCreditedDates'] != null) {
        await _storage.saveCalorieGoalCreditedDates({
          for (final d in data['calorieGoalCreditedDates'] as List) d as String,
        });
      }
      if (data['proteinGoalCreditedDates'] != null) {
        await _storage.saveProteinGoalCreditedDates({
          for (final d in data['proteinGoalCreditedDates'] as List) d as String,
        });
      }
      if (data['streakMilestonePaid'] != null) {
        await _storage
            .saveStreakMilestonePaid(data['streakMilestonePaid'] as int);
      }
      if (data['notificationPreferences'] != null) {
        await _storage.saveNotificationPreferences(
            NotificationPreferences.fromJson(
                data['notificationPreferences'] as Map<String, dynamic>));
      }
    });
    _queue.setTimestamp(SyncDomain.userProfile, 'default', time: remoteTime);
  }

  Future<void> _pullFastingState() async {
    final row = await _supabase
        .from('fasting_state')
        .select('data, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) {
      debugPrint('SyncService: fastingState — no remote row found');
      return;
    }
    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime = _queue.getTimestamp(SyncDomain.fastingState, 'default');
    if (!remoteTime.isAfter(localTime)) {
      debugPrint('SyncService: fastingState — local is newer, skipping');
      return;
    }
    debugPrint(
        'SyncService: fastingState — applying remote data (remote=$remoteTime)');
    final data = row['data'] as Map<String, dynamic>;
    if (fastingDataEmpty(data) && !await _localFastingEmpty()) {
      debugPrint(
          'SyncService: fastingState — remote empty but local populated; skipping to avoid wipe');
      return;
    }
    await _storage.applyRemote(() async {
      final history = (data['history'] as List? ?? [])
          .map((e) => FastingLog.fromJson(e as Map<String, dynamic>))
          .toList();
      await _storage.saveState(
        isFasting: data['isFasting'] as bool? ?? false,
        startTime: data['startTime'] != null
            ? DateTime.parse(data['startTime'] as String)
            : null,
        eatingStartTime: data['eatingStartTime'] != null
            ? DateTime.parse(data['eatingStartTime'] as String)
            : null,
        elapsedSeconds: data['elapsedSeconds'] as int? ?? 0,
        fastingGoalHours: data['fastingGoalHours'] as int? ?? 16,
        history: history,
        lastPenaltyCheckDate: data['lastPenaltyCheckDate'] != null
            ? DateTime.parse(data['lastPenaltyCheckDate'] as String)
            : null,
      );
    });
    _queue.setTimestamp(SyncDomain.fastingState, 'default', time: remoteTime);
  }

  Future<void> _pullUserQuests() async {
    final row = await _supabase
        .from('user_quests')
        .select('data, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) {
      debugPrint('SyncService: userQuests — no remote row found');
      return;
    }
    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime = _queue.getTimestamp(SyncDomain.userQuests, 'default');
    if (!remoteTime.isAfter(localTime)) {
      debugPrint('SyncService: userQuests — local is newer, skipping');
      return;
    }
    debugPrint(
        'SyncService: userQuests — applying remote data (remote=$remoteTime)');
    final data = row['data'] as Map<String, dynamic>;
    if (questsDataEmpty(data) && !await _localQuestsEmpty()) {
      debugPrint(
          'SyncService: userQuests — remote empty but local populated; skipping to avoid wipe');
      return;
    }
    await _storage.applyRemote(() async {
      if (data['quests'] != null) {
        await _storage.saveQuests((data['quests'] as List)
            .map((e) => Quest.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['achievements'] != null) {
        await _storage.saveAchievements((data['achievements'] as List)
            .map((e) => QuestAchievement.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['questPenaltyCheckDate'] != null) {
        await _storage.saveQuestPenaltyCheckDate(
            DateTime.parse(data['questPenaltyCheckDate'] as String));
      }
    });
    _queue.setTimestamp(SyncDomain.userQuests, 'default', time: remoteTime);
  }

  Future<void> _pullUserCollections() async {
    final row = await _supabase
        .from('user_collections')
        .select('data, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) {
      debugPrint('SyncService: userCollections — no remote row found');
      return;
    }
    final remoteTime = DateTime.parse(row['updated_at'] as String);
    final localTime =
        _queue.getTimestamp(SyncDomain.userCollections, 'default');
    if (!remoteTime.isAfter(localTime)) {
      debugPrint('SyncService: userCollections — local is newer, skipping');
      return;
    }
    debugPrint('SyncService: userCollections — applying remote data');
    final data = row['data'] as Map<String, dynamic>;
    if (collectionsDataEmpty(data) && !await _localCollectionsEmpty()) {
      debugPrint(
          'SyncService: userCollections — remote empty but local populated; skipping to avoid wipe');
      return;
    }
    await _storage.applyRemote(() async {
      if (data['routines'] != null) {
        await _storage.saveRoutines((data['routines'] as List)
            .map((e) => HabitRoutine.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['foodLibrary'] != null) {
        await _storage.saveFoodLibrary((data['foodLibrary'] as List)
            .map((e) => FoodTemplate.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['personalDict'] != null) {
        await _storage.savePersonalDict((data['personalDict'] as List)
            .map((e) => PersonalFoodEntry.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['foodFeedback'] != null) {
        await _storage.saveFoodFeedback((data['foodFeedback'] as List)
            .map((e) => FoodFeedback.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['financeDictionary'] != null) {
        await _storage.saveFinanceDictionary((data['financeDictionary'] as List)
            .map((e) => FinanceDictEntry.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      if (data['groceryPriceMemory'] != null) {
        await _storage.saveGroceryPriceMemory(
            (data['groceryPriceMemory'] as List)
                .map((e) => RememberedPrice.fromJson(e as Map<String, dynamic>))
                .toList());
      }
      if (data['groceryTripHistory'] != null) {
        await _storage.saveGroceryTripHistory(
            (data['groceryTripHistory'] as List)
                .map((e) => SavedTrip.fromJson(e as Map<String, dynamic>))
                .toList());
      }
    });
    _queue.setTimestamp(SyncDomain.userCollections, 'default',
        time: remoteTime);
  }

  Future<void> _pullNutritionLogs() async {
    final rows = await _supabase
        .from('nutrition_logs')
        .select('date, data, updated_at')
        .eq('user_id', _userId);
    for (final row in rows as List) {
      final dateKey = row['date'] as String? ?? '';
      try {
        final remoteTime = DateTime.parse(row['updated_at'] as String);
        final localTime = _queue.getTimestamp(SyncDomain.nutritionLog, dateKey);
        if (!remoteTime.isAfter(localTime)) continue;
        final data = row['data'] as Map<String, dynamic>;
        final remoteMessages =
            (data['messages'] as List?)?.cast<Map<String, dynamic>>();

        // The log and the chat feed are pushed as a pair, but a snapshot can
        // be captured while the feed is momentarily empty (e.g. food logged
        // via a non-chat path, or pushed before chat persisted). Applying such
        // a snapshot would wipe a populated local feed and leave only the
        // calorie/macro totals — "consumed kcal but nothing in the list".
        // Guard: never overwrite a non-empty local feed with an empty remote
        // one. Keep the local rows and re-queue a push so the cloud snapshot
        // is repaired with the rows it dropped.
        final localMessages = await _storage.loadChatMessagesRaw(dateKey);
        final wouldClobberFeed =
            nutritionFeedEmpty(data) && localMessages.isNotEmpty;

        await _storage.applyRemote(() async {
          if (data['log'] != null) {
            await _storage.saveNutritionLog(DailyNutritionLog.fromJson(
                data['log'] as Map<String, dynamic>));
          }
          if (remoteMessages != null && !wouldClobberFeed) {
            await _storage.saveChatMessages(dateKey, remoteMessages);
          }
        });

        if (wouldClobberFeed) {
          // Local feed is ahead of the cloud — push it back to heal the row.
          // markDirty stamps the queue at "now", so don't roll the timestamp
          // back to remoteTime here or the heal-push would look stale.
          _queue.markDirty(SyncDomain.nutritionLog, dateKey);
        } else {
          _queue.setTimestamp(SyncDomain.nutritionLog, dateKey,
              time: remoteTime);
        }
      } catch (e) {
        _recordSkipped('nutrition_logs/$dateKey', e);
      }
    }
  }

  Future<void> _pullActivityLogs() async {
    final rows = await _supabase
        .from('activity_logs')
        .select('date, data, updated_at')
        .eq('user_id', _userId);
    for (final row in rows as List) {
      final dateKey = row['date'] as String? ?? '';
      try {
        final remoteTime = DateTime.parse(row['updated_at'] as String);
        final localTime = _queue.getTimestamp(SyncDomain.activityLog, dateKey);
        if (!remoteTime.isAfter(localTime)) continue;
        await _storage.applyRemote(() async {
          await _storage.saveActivityLog(
              ActivityLog.fromJson(row['data'] as Map<String, dynamic>));
        });
        _queue.setTimestamp(SyncDomain.activityLog, dateKey, time: remoteTime);
      } catch (e) {
        _recordSkipped('activity_logs/$dateKey', e);
      }
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

    await _pullFinanceTable<FinancialAccount>(
        byTable['finance_accounts'] ?? [], 'finance_accounts',
        loadAll: _storage.loadAccounts,
        fromJson: FinancialAccount.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveAccounts);
    await _pullFinanceTable<TransactionRecord>(
        byTable['finance_transactions'] ?? [], 'finance_transactions',
        loadAll: _storage.loadTransactions,
        fromJson: TransactionRecord.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveTransactions);
    await _pullFinanceTable<FinanceCategory>(
        byTable['finance_categories'] ?? [], 'finance_categories',
        loadAll: _storage.loadFinanceCategories,
        fromJson: FinanceCategory.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveFinanceCategories);
    await _pullFinanceTable<Budget>(
        byTable['finance_budgets'] ?? [], 'finance_budgets',
        loadAll: _storage.loadBudgets,
        fromJson: Budget.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveBudgets);
    await _pullFinanceTable<BudgetedExpense>(
        byTable['finance_budgeted_expenses'] ?? [], 'finance_budgeted_expenses',
        loadAll: _storage.loadBudgetedExpenses,
        fromJson: BudgetedExpense.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveBudgetedExpenses);
    await _pullFinanceTable<Bill>(
        byTable['finance_bills'] ?? [], 'finance_bills',
        loadAll: _storage.loadBills,
        fromJson: Bill.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveBills);
    await _pullFinanceTable<Receivable>(
        byTable['finance_receivables'] ?? [], 'finance_receivables',
        loadAll: _storage.loadReceivables,
        fromJson: Receivable.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveReceivables);
    await _pullFinanceTable<Installment>(
        byTable['finance_installments'] ?? [], 'finance_installments',
        loadAll: _storage.loadInstallments,
        fromJson: Installment.fromJson,
        getId: (e) => e.id,
        saveAll: _storage.saveInstallments);
    await _pullFinanceTable<MonthlySummary>(
        byTable['finance_monthly_summaries'] ?? [], 'finance_monthly_summaries',
        loadAll: _storage.loadMonthlySummaries,
        fromJson: MonthlySummary.fromJson,
        getId: (e) => e.month,
        saveAll: _storage.saveMonthlySummaries);
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
      final recordId = row['record_id'] as String? ?? '';
      try {
        final remoteTime = DateTime.parse(row['updated_at'] as String);
        final localTime = _queue.getTimestamp(
            SyncDomain.financeRecord, '$tableName/$recordId');
        if (!remoteTime.isAfter(localTime)) continue;
        final data = row['data'] as Map<String, dynamic>;
        if (isTombstone(data)) {
          // Deletion propagated from another device — remove the local record.
          if (localMap.remove(recordId) != null) changed = true;
        } else {
          localMap[recordId] = fromJson(data);
          changed = true;
        }
        _queue.setTimestamp(SyncDomain.financeRecord, '$tableName/$recordId',
            time: remoteTime);
      } catch (e) {
        // Skip a poison record (unparseable enum / null field / bad date)
        // rather than aborting the whole table — one corrupt row used to throw
        // out of pullAll and surface as a blanket "Sync failed". The timestamp
        // is deliberately NOT advanced, so a later app build that can parse the
        // row still picks it up on the next pull.
        _recordSkipped('$tableName/$recordId', e);
      }
    }
    if (changed) {
      await _storage.applyRemote(() async => saveAll(localMap.values.toList()));
    }
  }

  Future<void> forceSync() async {
    await pushPending();
    await pullAll();
  }

  /// Pulls from remote only if last pull was more than [staleness] ago.
  Future<void> pullIfStale(
      {Duration staleness = const Duration(minutes: 5)}) async {
    if (_lastPulledAt != null &&
        DateTime.now().difference(_lastPulledAt!) < staleness) {
      return;
    }
    await pullAll();
  }

  // Scoped under the `u/$userId/` prefix so an explicit reset (clearUserData)
  // wipes it via the same prefix sweep — previously a bare key, it survived a
  // wipe and suppressed the safety re-push forever. (Plan 053 Phase 1)
  static String _initialPushKey(String userId) =>
      'u/$userId/sync_initial_push_done_v2';

  Future<bool> _isInitialPushDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_initialPushKey(_userId)) ?? false;
  }

  Future<void> _markInitialPushDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_initialPushKey(_userId), true);
  }

  /// Pushes ALL local data to Supabase regardless of the sync queue.
  /// Runs only once per user per device (guarded by a SharedPreferences flag).
  Future<void> pushAll() async {
    if (await _isInitialPushDone()) {
      debugPrint('SyncService: pushAll skipped — already done for this user');
      return;
    }
    debugPrint('SyncService: pushAll starting — uploading all local data...');
    _isSyncing = true;
    _onStateChange?.call();
    try {
      debugPrint('SyncService: pushAll — uploading userProfile...');
      await _pushUserProfile();
      debugPrint('SyncService: pushAll — uploading fastingState...');
      await _pushFastingState();
      debugPrint('SyncService: pushAll — uploading userQuests...');
      await _pushUserQuests();
      debugPrint('SyncService: pushAll — uploading userCollections...');
      await _pushUserCollections();
      await _markInitialPushDone();
      _lastSyncedAt = DateTime.now();
      debugPrint('SyncService: pushAll complete ✓');
    } catch (e) {
      debugPrint('SyncService: pushAll error: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      _onStateChange?.call();
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySub?.cancel();
  }
}
