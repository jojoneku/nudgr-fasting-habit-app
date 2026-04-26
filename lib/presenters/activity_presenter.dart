import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/activity_goals.dart';
import '../models/activity_log.dart';
import '../models/tdee_profile.dart';
import '../services/health_service.dart';
import '../services/storage_service.dart';
import 'stats_presenter.dart';

class ActivityPresenter extends ChangeNotifier {
  final StatsPresenter _statsPresenter;
  final HealthService _healthService;
  final StorageService _storage;

  ActivityLog _todayLog = ActivityLog.empty(_todayKey());
  ActivityGoals _goals = ActivityGoals.initial();
  List<ActivityLog> _history = [];
  TdeeProfile? _tdeeProfile;
  bool _isHealthConnectAvailable = false;
  bool _hasHealthPermission = false;
  bool _isLoading = false;
  bool _isBackfilling = false;
  bool _isConnecting = false;
  bool _healthPermissionDenied = false;
  String? _goalMetDate;
  String? _preferredStepsSourceId;
  List<({String sourceId, String sourceName})> _stepSources = [];

  ActivityPresenter({
    required StatsPresenter statsPresenter,
    required HealthService healthService,
    required StorageService storage,
  })  : _statsPresenter = statsPresenter,
        _healthService = healthService,
        _storage = storage {
    loadState();
  }

  // ─── State getters ────────────────────────────────────────────────────────

  ActivityLog get todayLog => _todayLog;
  ActivityGoals get goals => _goals;
  List<ActivityLog> get history => _history;
  bool get isHealthConnectAvailable => _isHealthConnectAvailable;
  bool get hasHealthPermission => _hasHealthPermission;
  bool get isLoading => _isLoading;
  bool get isBackfilling => _isBackfilling;
  bool get isConnecting => _isConnecting;
  bool get healthPermissionDenied => _healthPermissionDenied;
  String? get preferredStepsSourceId => _preferredStepsSourceId;
  List<({String sourceId, String sourceName})> get stepSources => _stepSources;
  int? get tdee => _tdeeProfile?.tdee;

  // ─── Computed getters (safe for build()) ─────────────────────────────────

  int get todaySteps => _todayLog.steps;

  double get stepProgress =>
      _goals.dailyStepGoal > 0 ? todaySteps / _goals.dailyStepGoal : 0;

  bool get isGoalMet => todaySteps >= _goals.dailyStepGoal;

  double get distanceProgress {
    final goal = _goals.dailyDistanceGoalMeters;
    if (goal <= 0.0 || _todayLog.distanceMeters == null) return 0.0;
    return (_todayLog.distanceMeters! / goal).clamp(0.0, 1.0).toDouble();
  }

  bool get isDistanceGoalMet {
    final goal = _goals.dailyDistanceGoalMeters;
    return goal > 0 &&
        _todayLog.distanceMeters != null &&
        _todayLog.distanceMeters! >= goal;
  }

  String get summaryLabel {
    final f = NumberFormat('#,###');
    return '${f.format(todaySteps)} / ${f.format(_goals.dailyStepGoal)} steps';
  }

  /// Last 7 days (oldest→newest), including today, for the weekly chart.
  List<ActivityLog> get weeklyLogs {
    final all = [_todayLog, ..._history];
    final byDate = {for (final l in all) l.date: l};
    return List.generate(7, (i) {
      final date = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(Duration(days: 6 - i)));
      return byDate[date] ?? ActivityLog.empty(date);
    });
  }

  int get weeklyMaxSteps {
    final max = weeklyLogs.fold(0, (m, l) => l.steps > m ? l.steps : m);
    return max > 0 ? max : _goals.dailyStepGoal;
  }

  /// All history keyed by date string for O(1) calendar lookup.
  Map<String, ActivityLog> get historyByDate {
    final map = {for (final l in _history) l.date: l};
    map[_todayKey()] = _todayLog;
    return map;
  }

  /// Calories burned for a given log — active if available, otherwise total.
  double? caloriesBurned(ActivityLog log) =>
      log.activeCalories ?? log.totalCalories;

  /// Subtitle for the calories metric card — includes TDEE reminder when set.
  String get todayCaloriesLabel {
    final t = _tdeeProfile?.tdee;
    final base = _todayLog.activeCalories != null
        ? 'kcal active'
        : _todayLog.totalCalories != null
            ? 'kcal total'
            : 'no data';
    if (t != null) return '$base · TDEE ${NumberFormat('#,###').format(t)}';
    return base;
  }

  /// Subtitle shown on the Hub card.
  String get hubSubtitle {
    if (todaySteps == 0 && !_hasHealthPermission)
      return 'Tap to connect Health';
    if (isGoalMet) {
      return '${NumberFormat('#,###').format(todaySteps)} steps ✓';
    }
    return summaryLabel;
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> loadState() async {
    _isLoading = true;
    notifyListeners();

    try {
      _todayLog = await _storage.loadTodayActivityLog();
      _goals = await _storage.loadActivityGoals();
      _history = await _storage.loadActivityHistory();
      _goalMetDate = await _storage.loadActivityGoalMetDate();
      _preferredStepsSourceId = await _storage.loadPreferredStepsSource();
      _tdeeProfile = await _storage.loadTdeeProfile();
      _isHealthConnectAvailable = await _healthService.isAvailable();
      if (_isHealthConnectAvailable) {
        _hasHealthPermission = await _healthService.hasPermissions();
      }
    } catch (e) {
      debugPrint('ActivityPresenter: loadState error: $e');
    }

    _isLoading = false;
    notifyListeners();

    // Backfill historical data if permission already granted (e.g. returning user).
    // Safe to call every launch — skips days already in storage.
    if (_hasHealthPermission) {
      backfillHistory();
    }
  }

  Future<void> syncFromHealthConnect() async {
    if (!_isHealthConnectAvailable || !_hasHealthPermission) return;

    _isLoading = true;
    notifyListeners();

    try {
      final steps = await _healthService.readTodaySteps(
          sourceId: _preferredStepsSourceId);
      final activeCalories = await _healthService.readTodayActiveCalories();
      final totalCalories = await _healthService.readTodayTotalCalories();
      // Prefer workout distance (GPS from Strava etc.) over DISTANCE_DELTA,
      // since device sensors don't write distance to Health Connect.
      final workoutDistance = await _healthService.readTodayWorkoutDistance();
      final distance = workoutDistance ?? await _healthService.readTodayDistance();

      _todayLog = _todayLog.copyWith(
        steps: steps,
        activeCalories: activeCalories,
        totalCalories: totalCalories,
        distanceMeters: distance,
        isManualEntry: false,
        goalMet: steps >= _goals.dailyStepGoal,
      );
      await _storage.saveActivityLog(_todayLog);
      _checkGoalMet();
    } catch (e) {
      debugPrint('ActivityPresenter: syncFromHealthConnect error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setManualSteps(int steps) async {
    _todayLog = _todayLog.copyWith(
      steps: steps,
      isManualEntry: true,
      goalMet: steps >= _goals.dailyStepGoal,
    );
    await _storage.saveActivityLog(_todayLog);
    _checkGoalMet();
    notifyListeners();
  }

  Future<void> updateGoals(ActivityGoals goals) async {
    _goals = goals;
    await _storage.saveActivityGoals(goals);
    notifyListeners();
  }

  Future<void> requestHealthPermission() async {
    if (!_isHealthConnectAvailable || _isConnecting) return;
    _isConnecting = true;
    _healthPermissionDenied = false;
    notifyListeners();
    _hasHealthPermission = await _healthService.requestPermissions();
    _isConnecting = false;
    if (!_hasHealthPermission) _healthPermissionDenied = true;
    notifyListeners();
    if (_hasHealthPermission) {
      await syncFromHealthConnect();
      await backfillHistory();
    }
  }

  Future<void> openHealthConnectSettings() async {
    await _healthService.openHealthConnectSettings();
  }

  /// Called when the app resumes from background (e.g. returning from Health Connect settings).
  Future<void> recheckPermissions() async {
    if (!_isHealthConnectAvailable) return;
    final had = _hasHealthPermission;
    _hasHealthPermission = await _healthService.hasPermissions();
    _healthPermissionDenied = false;
    notifyListeners();
    if (_hasHealthPermission && !had) {
      await syncFromHealthConnect();
      await backfillHistory();
    }
  }

  Future<void> loadStepSources() async {
    if (!_isHealthConnectAvailable || !_hasHealthPermission) return;
    _stepSources = await _healthService.readStepSources();
    notifyListeners();
  }

  Future<void> setPreferredStepsSource(String? sourceId) async {
    _preferredStepsSourceId = sourceId;
    await _storage.savePreferredStepsSource(sourceId);
    notifyListeners();
    await clearAndRebackfill();
  }

  /// Clears stored history and re-fetches a full year from Health Connect.
  Future<void> clearAndRebackfill() async {
    if (!_isHealthConnectAvailable || !_hasHealthPermission) return;
    await _storage.clearActivityHistory();
    _history = [];
    notifyListeners();
    await backfillHistory(days: 365);
  }

  /// Fetches up to [days] past calendar days from Health Connect and stores any
  /// that are not already saved locally. Skips today (handled by syncFromHealthConnect).
  /// Uses a single batch request per data type to avoid Health Connect API quota exhaustion.
  Future<void> backfillHistory({int days = 90}) async {
    if (!_isHealthConnectAvailable || !_hasHealthPermission) return;
    if (_isBackfilling) return;

    _isBackfilling = true;
    notifyListeners();

    try {
      final existingKeys = await _storage.loadActivityLogKeys();
      final today = DateTime.now();
      final rangeStart = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: days));
      final rangeEnd =
          DateTime(today.year, today.month, today.day); // exclusive of today

      // 4 API calls total for the entire range (one per data type)
      final rangeData = await _healthService.readRangeDataByDay(
        rangeStart,
        rangeEnd,
        stepsSourceId: _preferredStepsSourceId,
      );

      final newLogs = <ActivityLog>[];
      for (final entry in rangeData.entries) {
        final dateKey = entry.key;
        if (existingKeys.contains(dateKey)) continue;

        final data = entry.value;
        if (data.steps == 0 &&
            data.activeCalories == null &&
            data.totalCalories == null &&
            data.distance == null) continue;

        newLogs.add(ActivityLog(
          date: dateKey,
          steps: data.steps,
          activeCalories: data.activeCalories,
          totalCalories: data.totalCalories,
          distanceMeters: data.distance,
          goalMet: data.steps >= _goals.dailyStepGoal,
        ));
      }

      if (newLogs.isNotEmpty) {
        await _storage.saveActivityLogs(newLogs);
        _history = await _storage.loadActivityHistory();
        debugPrint('ActivityPresenter: backfilled ${newLogs.length} days');
      }
    } catch (e) {
      debugPrint('ActivityPresenter: backfillHistory error: $e');
    }

    _isBackfilling = false;
    notifyListeners();
  }

  // ─── RPG hook ─────────────────────────────────────────────────────────────

  void _checkGoalMet() {
    if (!isGoalMet) return;
    final today = _todayKey();
    if (_goalMetDate == today) return; // already awarded today

    _goalMetDate = today;
    _storage.saveActivityGoalMetDate(today);
    _onGoalMet();
  }

  void _onGoalMet() {
    // +25 XP on first goal met each day
    _statsPresenter.addXp(25);

    // +1 AGI every 5 consecutive days goal met — update streak first
    _updateStreakAndAwardAgi();
  }

  Future<void> _updateStreakAndAwardAgi() async {
    final streak = await _storage.loadActivityStreak() + 1;
    await _storage.saveActivityStreak(streak);
    if (streak % 5 == 0) {
      await _statsPresenter.awardStat('agi');
    }
    debugPrint('ActivityPresenter: streak=$streak, goalMet=true');
  }
}

String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());
