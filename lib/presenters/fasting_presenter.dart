import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fasting_log.dart';
import '../models/fasting_phase.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/local_storage_service.dart';
import 'stats_presenter.dart';

class FastingPresenter extends ChangeNotifier {
  final NotificationService _notificationService;
  final StorageService _storageService;
  final StatsPresenter? statsPresenter;

  bool isFasting = false;
  DateTime? startTime;
  DateTime? eatingStartTime;
  int elapsedSeconds = 0;
  int fastingGoalHours = 16;
  List<FastingLog> history = [];
  Timer? _ticker;

  FastingPresenter({
    this.statsPresenter,
    StorageService? storage,
    NotificationService? notifications,
  })  : _storageService = storage ?? LocalStorageService(),
        _notificationService = notifications ?? NotificationService() {
    _init();
  }

  Future<void> _init() async {
    debugPrint('FastingPresenter: Initializing...');
    await loadState();

    await _notificationService.init();
    await _notificationService.requestPermissions();
    await _rescheduleActiveAlarms();

    debugPrint('FastingPresenter: Initialization complete');
  }

  Future<void> _rescheduleActiveAlarms() async {
    debugPrint('FastingPresenter: Rescheduling active alarms...');
    if (isFasting && startTime != null) {
      try {
        final endTime = startTime!.add(Duration(hours: fastingGoalHours));
        await _notificationService.showFastingTimerNotification(endTime);
        await _notificationService.cancelEatingNotifications();
        await _notificationService.scheduleFastingAlarm(
            startTime!, fastingGoalHours);
      } catch (e) {
        debugPrint('Error rescheduling fasting alarm: $e');
      }
    } else if (eatingStartTime != null) {
      try {
        final int eatingWindowHours =
            fastingGoalHours >= 36 ? 0 : 24 - fastingGoalHours;
        if (eatingWindowHours > 0) {
          final eatingEndTime =
              eatingStartTime!.add(Duration(hours: eatingWindowHours));
          if (DateTime.now().isAfter(eatingEndTime)) {
            // Window already expired — don't re-arm a stale alarm.
            debugPrint(
                'FastingPresenter: Skipping eating alarm reschedule; window already expired.');
            eatingStartTime = null;
            await _notificationService.cancelEatingNotifications();
            await saveState();
          } else {
            await _notificationService
                .showEatingTimerNotification(eatingEndTime);
            await _notificationService.cancelFastingNotifications();
            await _notificationService.scheduleEatingAlarm(
                eatingStartTime!, fastingGoalHours);
          }
        }
      } catch (e) {
        debugPrint('Error rescheduling eating alarm: $e');
      }
    }
  }

  Future<void> loadState() async {
    debugPrint('FastingPresenter: Loading state...');
    final state = await _storageService.loadState();
    isFasting = state['isFasting'];
    startTime = state['startTime'];
    eatingStartTime = state['eatingStartTime'];
    elapsedSeconds = state['elapsedSeconds'];
    fastingGoalHours = state['fastingGoalHours'];
    history = state['history'];

    debugPrint(
        'FastingPresenter: State loaded - isFasting: $isFasting, startTime: $startTime, eatingStartTime: $eatingStartTime');

    if (isFasting && startTime != null) {
      elapsedSeconds = DateTime.now().difference(startTime!).inSeconds;
      _startTicker();
      try {
        final endTime = startTime!.add(Duration(hours: fastingGoalHours));
        await _notificationService.showFastingTimerNotification(endTime);
      } catch (_) {}
    } else if (eatingStartTime != null) {
      final int eatingWindowHours =
          fastingGoalHours >= 36 ? 0 : 24 - fastingGoalHours;
      final eatingEndTime =
          eatingStartTime!.add(Duration(hours: eatingWindowHours));

      if (eatingWindowHours == 0 || DateTime.now().isAfter(eatingEndTime)) {
        // Eating window has expired — clear stale state silently.
        debugPrint(
            'FastingPresenter: Eating window expired (ended $eatingEndTime), clearing stale state.');
        eatingStartTime = null;
        elapsedSeconds = 0;
        await _notificationService.cancelEatingNotifications();
        await saveState();
      } else {
        elapsedSeconds = DateTime.now().difference(eatingStartTime!).inSeconds;
        _startTicker();
        try {
          await _notificationService
              .showEatingTimerNotification(eatingEndTime);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> saveState() async {
    debugPrint(
        'FastingPresenter: Saving state - isFasting: $isFasting, startTime: $startTime, eatingStartTime: $eatingStartTime');
    await _storageService.saveState(
      isFasting: isFasting,
      startTime: startTime,
      eatingStartTime: eatingStartTime,
      elapsedSeconds: elapsedSeconds,
      fastingGoalHours: fastingGoalHours,
      history: history,
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimer();
    });
  }

  void _updateTimer() {
    if (isFasting && startTime != null) {
      elapsedSeconds = DateTime.now().difference(startTime!).inSeconds;
    } else if (eatingStartTime != null) {
      final int eatingWindowHours =
          fastingGoalHours >= 36 ? 0 : 24 - fastingGoalHours;
      final eatingEndTime =
          eatingStartTime!.add(Duration(hours: eatingWindowHours));
      if (eatingWindowHours == 0 || DateTime.now().isAfter(eatingEndTime)) {
        // Eating window just expired mid-session — clear state.
        eatingStartTime = null;
        elapsedSeconds = 0;
        _ticker?.cancel();
        _notificationService.cancelEatingNotifications();
        saveState();
      } else {
        elapsedSeconds = DateTime.now().difference(eatingStartTime!).inSeconds;
      }
    }
    notifyListeners();
  }

  // ── Computed getters ────────────────────────────────────────────────────────

  int get targetSeconds => fastingGoalHours * 3600;

  bool get isOvertime => isFasting && elapsedSeconds > targetSeconds;

  int get overtimeSeconds =>
      isOvertime ? (elapsedSeconds - targetSeconds).clamp(0, 999999) : 0;

  FastingPhase get currentPhase =>
      FastingPhase.fromElapsedSeconds(isFasting ? elapsedSeconds : 0);

  /// True when elapsed fast time >= 24 hours — triggers refeeding protocol UI.
  bool get requiresRefeedingProtocol =>
      isFasting && elapsedSeconds >= 86400; // 24h

  /// Consecutive days ending with a successful fast (most-recent-first history).
  int get currentStreak {
    if (history.isEmpty) return 0;
    int streak = 0;
    DateTime? prevDate;
    for (final log in history) {
      if (!log.success) break;
      final day = DateUtils.dateOnly(log.fastEnd);
      if (prevDate == null) {
        streak = 1;
        prevDate = day;
      } else {
        final diff = prevDate.difference(day).inDays;
        if (diff <= 1) {
          streak++;
          prevDate = day;
        } else {
          break;
        }
      }
    }
    return streak;
  }

  int get longestStreak {
    if (history.isEmpty) return 0;
    int best = 0;
    int current = 0;
    DateTime? prevDate;
    for (final log in history.reversed) {
      if (log.success) {
        final day = DateUtils.dateOnly(log.fastEnd);
        if (prevDate == null) {
          current = 1;
        } else {
          final diff = day.difference(prevDate).inDays;
          current = diff <= 1 ? current + 1 : 1;
        }
        prevDate = day;
        if (current > best) best = current;
      } else {
        current = 0;
        prevDate = null;
      }
    }
    return best;
  }

  double get totalHoursFasted =>
      history.fold(0.0, (sum, log) => sum + log.fastDuration);

  double get successRate {
    if (history.isEmpty) return 0.0;
    final successes = history.where((l) => l.success).length;
    return successes / history.length * 100;
  }

  /// Returns fasts that started on the given calendar day.
  List<FastingLog> fastsOnDay(DateTime day) {
    final d = DateUtils.dateOnly(day);
    return history
        .where((log) => DateUtils.dateOnly(log.fastStart) == d)
        .toList();
  }

  Future<void> startFast() async {
    debugPrint('FastingPresenter: Starting fast...');
    if (isFasting) {
      debugPrint('FastingPresenter: Already fasting, ignoring startFast call');
      return;
    }

    // If we were in eating window, log it
    if (eatingStartTime != null) {
      final eatingEnd = DateTime.now();
      final eatingDuration =
          eatingEnd.difference(eatingStartTime!).inSeconds / 3600.0;

      // Find the last log to update eating info
      // This logic assumes the last log corresponds to the fast that preceded this eating window
      // In the original code, it seemed to update the last entry.
      if (history.isNotEmpty) {
        // Logic from original main.dart:
        // _history.first['eatingEnd'] = now.toIso8601String();
        // _history.first['eatingDuration'] = duration;
        history.first.eatingEnd = eatingEnd;
        history.first.eatingDuration = eatingDuration;
      }
      eatingStartTime = null;
    }

    isFasting = true;
    startTime = DateTime.now();
    elapsedSeconds = 0;
    _startTicker();
    notifyListeners(); // Notify immediately for UI responsiveness

    // Save state immediately to prevent data loss if app is killed or notification fails
    await saveState();

    try {
      final endTime = startTime!.add(Duration(hours: fastingGoalHours));
      // Show persistent notification first for immediate feedback
      await _notificationService.showFastingTimerNotification(endTime);

      await _notificationService
          .cancelEatingNotifications(); // Cancel eating alarms
      await _notificationService.scheduleFastingAlarm(
          startTime!, fastingGoalHours);
    } catch (e) {
      // Error scheduling notifications
    }
  }

  Future<(int, int)> stopFast() async {
    debugPrint('FastingPresenter: Stopping fast...');
    if (!isFasting || startTime == null) {
      debugPrint(
          'FastingPresenter: Not fasting or startTime is null, ignoring stopFast call');
      return (0, 0);
    }

    final endTime = DateTime.now();
    final durationHours = endTime.difference(startTime!).inSeconds / 3600.0;

    // Create log
    final log = FastingLog(
      fastStart: startTime!,
      fastEnd: endTime,
      fastDuration: durationHours,
      success: durationHours >= fastingGoalHours,
      eatingStart: endTime, // Eating starts now
      goalDuration: fastingGoalHours,
    );

    history.insert(0, log);

    isFasting = false;
    startTime = null;
    eatingStartTime = endTime;
    elapsedSeconds = 0;
    _startTicker();
    notifyListeners(); // Notify immediately

    // Save state immediately
    await saveState();

    // Award XP & Health
    int xp = 0;
    int hpChange = 0;

    if (durationHours >= fastingGoalHours) {
      xp = (50 + (durationHours * 10)).round();
      // Overtime bonus: +5 XP per overtime hour
      if (isOvertime) {
        final overtimeHours = overtimeSeconds / 3600.0;
        xp += (overtimeHours * 5).round();
      }
      statsPresenter?.addXp(xp);
      statsPresenter?.incrementStreak();

      // Status Recovery: Partial Heal based on duration
      if (statsPresenter != null) {
        // Base 30 HP + 2 HP per hour fasted
        int healAmount = 30 + (durationHours * 2).round();

        // Cap at Max HP
        final currentHp = statsPresenter!.stats.currentHp;
        final maxHp = statsPresenter!.maxHp;

        if (currentHp + healAmount > maxHp) {
          healAmount = maxHp - currentHp;
        }

        hpChange = healAmount;
        if (hpChange > 0) {
          statsPresenter!.modifyHp(hpChange);
        }
      }
    } else {
      // Penalty? For now just no XP or small XP
      xp = (durationHours * 5).round();
      statsPresenter?.addXp(xp);
      statsPresenter?.resetStreak();

      // Penalty: Damage scales with how early you stopped
      // Base 10 damage + 2 damage per hour missed
      double missedHours = fastingGoalHours - durationHours;
      if (missedHours < 0) missedHours = 0;

      int damage = 10 + (missedHours * 2).round();
      hpChange = -damage;

      statsPresenter?.modifyHp(hpChange);
    }

    try {
      int eatingWindowHours =
          fastingGoalHours >= 36 ? 0 : 24 - fastingGoalHours;
      if (eatingWindowHours > 0) {
        final eatingEndTime =
            eatingStartTime!.add(Duration(hours: eatingWindowHours));
        await _notificationService.showEatingTimerNotification(eatingEndTime);
        await _notificationService.cancelFastingNotifications();
        await _notificationService.scheduleEatingAlarm(
            eatingStartTime!, fastingGoalHours);
      } else {
        await _notificationService.cancelFastingNotifications();
      }
    } catch (e) {
      debugPrint('Error scheduling notifications: $e');
    }

    return (xp, hpChange);
  }

  Future<void> updateFastingGoal(int hours) async {
    debugPrint('FastingPresenter: Updating fasting goal to $hours hours');
    fastingGoalHours = hours;
    await saveState();

    if (isFasting && startTime != null) {
      final endTime = startTime!.add(Duration(hours: fastingGoalHours));
      await _notificationService.showFastingTimerNotification(endTime);
    }
    notifyListeners();
  }

  Future<void> clearAllData() async {
    debugPrint('FastingPresenter: Clearing all data');
    history.clear();
    isFasting = false;
    startTime = null;
    eatingStartTime = null;
    elapsedSeconds = 0;
    _ticker?.cancel();

    notifyListeners();
    await _notificationService.cancelAll();
    await saveState();
  }

  Future<void> testNotification() async {
    await _notificationService.requestPermissions();
    // Fire all types of notifications to verify channels
    await _notificationService.testAllChannels();
  }

  Future<void> addTestData() async {
    final now = DateTime.now();

    // Test 1: Fast that spans midnight (yesterday 10 PM to today 2 PM = 16h)
    final test1FastStart = now.subtract(const Duration(days: 1, hours: 10));
    final test1FastEnd = now.subtract(const Duration(hours: 10));
    final test1EatingEnd = now.subtract(const Duration(hours: 2));
    history.add(FastingLog(
      fastStart: test1FastStart,
      fastEnd: test1FastEnd,
      fastDuration: 16.0,
      success: true,
      eatingStart: test1FastEnd,
      eatingEnd: test1EatingEnd,
      eatingDuration: 8.0,
    ));

    // Test 2: Incomplete fast (yesterday 8 AM to 6 PM = 10h of 16h goal)
    final test2FastStart = now.subtract(const Duration(days: 2, hours: 16));
    final test2FastEnd = now.subtract(const Duration(days: 2, hours: 6));
    final test2EatingEnd = now.subtract(const Duration(days: 1, hours: 22));
    history.add(FastingLog(
      fastStart: test2FastStart,
      fastEnd: test2FastEnd,
      fastDuration: 10.0,
      success: false,
      eatingStart: test2FastEnd,
      eatingEnd: test2EatingEnd,
      eatingDuration: 8.0,
    ));

    notifyListeners();
    saveState();
  }

  Future<void> updateLog(int index, FastingLog newLog) async {
    debugPrint('FastingPresenter: Updating log at index $index');
    if (index >= 0 && index < history.length) {
      history[index] = newLog;
      notifyListeners();
      await saveState();
    }
  }

  Future<void> deleteLog(int index) async {
    debugPrint('FastingPresenter: Deleting log at index $index');
    if (index >= 0 && index < history.length) {
      history.removeAt(index);
      notifyListeners();
      await saveState();
    }
  }

  Future<void> skipEatingWindow() async {
    debugPrint('FastingPresenter: Skipping eating window');
    eatingStartTime = null;
    elapsedSeconds = 0;
    notifyListeners();
    await saveState();
  }

  /// Cancels the current fast with no XP, no HP penalty, no history entry.
  Future<void> discardFast() async {
    debugPrint('FastingPresenter: Discarding fast (no penalty)');
    if (!isFasting) return;
    isFasting = false;
    startTime = null;
    elapsedSeconds = 0;
    _ticker?.cancel();
    notifyListeners();
    await _notificationService.cancelFastingNotifications();
    await saveState();
  }

  Future<void> updateStartTime(DateTime newStartTime) async {
    debugPrint('FastingPresenter: Updating start time to $newStartTime');
    startTime = newStartTime;
    final now = DateTime.now();
    elapsedSeconds = now.difference(startTime!).inSeconds;

    // Sync with previous history log (End of previous eating window)
    if (history.isNotEmpty) {
      final lastLog = history.first;
      if (lastLog.eatingStart.isBefore(newStartTime)) {
        debugPrint(
            'FastingPresenter: Syncing previous log eatingEnd to $newStartTime');
        lastLog.eatingEnd = newStartTime;
        lastLog.eatingDuration =
            newStartTime.difference(lastLog.eatingStart).inSeconds / 3600.0;
      }
    }

    // Reschedule notifications since end time changed
    try {
      final endTime = startTime!.add(Duration(hours: fastingGoalHours));
      await _notificationService.showFastingTimerNotification(endTime);
      await _notificationService
          .cancelFastingNotifications(); // Reset milestones
      await _notificationService.scheduleFastingAlarm(
          startTime!, fastingGoalHours);
    } catch (e) {
      debugPrint('Error rescheduling fasting notifications: $e');
    }

    notifyListeners();
    await saveState();
  }

  Future<void> updateEatingStartTime(DateTime newStartTime) async {
    debugPrint('FastingPresenter: Updating eating start time to $newStartTime');
    eatingStartTime = newStartTime;
    final now = DateTime.now();
    elapsedSeconds = now.difference(eatingStartTime!).inSeconds;

    // Sync with most recent history log (End of just-finished fast)
    if (history.isNotEmpty) {
      final lastLog = history.first;
      debugPrint(
          'FastingPresenter: Syncing recent log fastEnd to $newStartTime');

      // Update times
      lastLog.fastEnd = newStartTime;
      lastLog.eatingStart = newStartTime;

      // Recalculate stats
      final durationHours =
          newStartTime.difference(lastLog.fastStart).inSeconds / 3600.0;
      lastLog.fastDuration = durationHours;
      lastLog.success = durationHours >= lastLog.goalDuration;
    }

    // Reschedule eating notifications since window changed
    try {
      int eatingWindowHours = 24 - fastingGoalHours;
      final eatingEndTime =
          eatingStartTime!.add(Duration(hours: eatingWindowHours));
      await _notificationService.showEatingTimerNotification(eatingEndTime);

      await _notificationService.cancelEatingNotifications();
      await _notificationService.scheduleEatingAlarm(
          eatingStartTime!, fastingGoalHours);
    } catch (e) {
      debugPrint('Error rescheduling eating notifications: $e');
    }

    notifyListeners();
    await saveState();
  }

  Future<String> exportData() async {
    return await _storageService.exportAllData();
  }

  Future<void> importData(String jsonString) async {
    debugPrint('FastingPresenter: Importing data...');
    try {
      await _storageService.importAllData(jsonString);
      // Reload everything
      await loadState();
      await statsPresenter?.loadStats(); // Reload stats too

      // Reschedule alarms based on new data
      await _notificationService.cancelAll();
      await _rescheduleActiveAlarms();

      notifyListeners();
    } catch (e) {
      debugPrint('FastingPresenter: Import failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
