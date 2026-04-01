import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/activity_goals.dart';
import '../models/activity_log.dart';
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
  bool _isHealthConnectAvailable = false;
  bool _hasHealthPermission = false;
  bool _isLoading = false;
  String? _goalMetDate;

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

  // ─── Computed getters (safe for build()) ─────────────────────────────────

  int get todaySteps => _todayLog.steps;

  double get stepProgress =>
      _goals.dailyStepGoal > 0 ? todaySteps / _goals.dailyStepGoal : 0;

  bool get isGoalMet => todaySteps >= _goals.dailyStepGoal;

  String get summaryLabel {
    final f = NumberFormat('#,###');
    return '${f.format(todaySteps)} / ${f.format(_goals.dailyStepGoal)} steps';
  }

  /// Subtitle shown on the Hub card.
  String get hubSubtitle {
    if (todaySteps == 0 && !_hasHealthPermission) return 'Tap to connect Health';
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
      _isHealthConnectAvailable = await _healthService.isAvailable();
      if (_isHealthConnectAvailable) {
        _hasHealthPermission = await _healthService.hasPermissions();
      }
    } catch (e) {
      debugPrint('ActivityPresenter: loadState error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> syncFromHealthConnect() async {
    if (!_isHealthConnectAvailable || !_hasHealthPermission) return;

    _isLoading = true;
    notifyListeners();

    try {
      final steps = await _healthService.readTodaySteps();
      final calories = await _healthService.readTodayActiveCalories();
      final distance = await _healthService.readTodayDistance();

      _todayLog = _todayLog.copyWith(
        steps: steps,
        activeCalories: calories,
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
    if (!_isHealthConnectAvailable) return;
    _hasHealthPermission = await _healthService.requestPermissions();
    notifyListeners();
    if (_hasHealthPermission) {
      await syncFromHealthConnect();
    }
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
