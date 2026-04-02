import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fasting_log.dart';
import '../models/quest.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
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
  List<Quest> quests = [];
  DateTime? lastPenaltyCheckDate;
  Timer? _ticker;

  FastingPresenter({
    this.statsPresenter,
    StorageService? storage,
    NotificationService? notifications,
  })  : _storageService = storage ?? StorageService(),
        _notificationService = notifications ?? NotificationService() {
    _init();
  }

  Future<void> _init() async {
    debugPrint('FastingPresenter: Initializing...');
    // Load state first to ensure UI is correct immediately
    await loadState();

    await _notificationService.init();
    await _notificationService.requestPermissions();

    // Reschedule all quests to ensure they are on the correct channel and active
    // This fixes the issue where channel cleanup wipes existing alarms
    await _rescheduleAllQuests();

    // Also reschedule active fasting/eating alarms
    await _rescheduleActiveAlarms();

    debugPrint('FastingPresenter: Initialization complete');
  }

  Future<void> _rescheduleActiveAlarms() async {
    debugPrint('FastingPresenter: Rescheduling active alarms...');
    if (isFasting && startTime != null) {
      try {
        // Show persistent notification
        final endTime = startTime!.add(Duration(hours: fastingGoalHours));
        await _notificationService.showFastingTimerNotification(endTime);

        // Schedule end alarm and milestones
        // We do not cancel old ones here because scheduleFastingAlarm uses fixed IDs (0, 100+)
        // and usually overwrites them. But for safety against "stuck" eating alarms:
        await _notificationService.cancelEatingNotifications();
        await _notificationService.scheduleFastingAlarm(
            startTime!, fastingGoalHours);
      } catch (e) {
        debugPrint('Error rescheduling fasting alarm: $e');
      }
    } else if (eatingStartTime != null) {
      try {
        // Show persistent notification
        int eatingWindowHours = 24 - fastingGoalHours;
        final eatingEndTime =
            eatingStartTime!.add(Duration(hours: eatingWindowHours));
        await _notificationService.showEatingTimerNotification(eatingEndTime);

        // Schedule end alarm and milestones
        await _notificationService.cancelFastingNotifications();
        await _notificationService.scheduleEatingAlarm(
            eatingStartTime!, fastingGoalHours);
      } catch (e) {
        debugPrint('Error rescheduling eating alarm: $e');
      }
    }
  }

  Future<void> _rescheduleAllQuests() async {
    debugPrint('FastingPresenter: Rescheduling all enabled quests...');
    for (final quest in quests) {
      if (quest.isEnabled) {
        await _notificationService.scheduleQuestNotifications(quest);
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
    quests = state['quests'];
    lastPenaltyCheckDate = state['lastPenaltyCheckDate'];

    debugPrint(
        'FastingPresenter: State loaded - isFasting: $isFasting, startTime: $startTime, eatingStartTime: $eatingStartTime');

    _checkMissedQuests();

    if (isFasting && startTime != null) {
      // Calculate elapsed time immediately to prevent UI jump to 0
      elapsedSeconds = DateTime.now().difference(startTime!).inSeconds;
      _startTicker();
      try {
        final endTime = startTime!.add(Duration(hours: fastingGoalHours));
        await _notificationService.showFastingTimerNotification(endTime);
      } catch (e) {
        // Error showing resume notification
      }
    } else if (eatingStartTime != null) {
      // Calculate elapsed time immediately to prevent UI jump to 0
      elapsedSeconds = DateTime.now().difference(eatingStartTime!).inSeconds;
      _startTicker(); // Also tick for eating window
      try {
        int eatingWindowHours = 24 - fastingGoalHours;
        final eatingEndTime =
            eatingStartTime!.add(Duration(hours: eatingWindowHours));
        await _notificationService.showEatingTimerNotification(eatingEndTime);
      } catch (e) {
        // Error showing resume notification
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
      quests: quests,
      lastPenaltyCheckDate: lastPenaltyCheckDate,
    );
  }

  void _checkMissedQuests() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lastPenaltyCheckDate == null) {
      // First run, just set the date
      lastPenaltyCheckDate = today;
      saveState();
      return;
    }

    if (lastPenaltyCheckDate!.isBefore(today)) {
      debugPrint(
          'FastingPresenter: Checking missed quests from $lastPenaltyCheckDate to $today');

      int totalDamage = 0;
      int missedCount = 0;

      // Iterate from last check date until yesterday
      DateTime checkDate = lastPenaltyCheckDate!;
      while (checkDate.isBefore(today)) {
        final dayIndex = checkDate.weekday - 1; // Mon=0, Sun=6

        for (final quest in quests) {
          if (quest.isEnabled && quest.days[dayIndex]) {
            // Check if completed on this specific date
            bool completedOnDate = false;
            if (quest.lastCompleted != null) {
              final completedDate = DateTime(
                quest.lastCompleted!.year,
                quest.lastCompleted!.month,
                quest.lastCompleted!.day,
              );
              if (completedDate.isAtSameMomentAs(checkDate)) {
                completedOnDate = true;
              }
            }

            if (!completedOnDate) {
              // Missed quest!
              totalDamage += 10;
              missedCount++;
            }
          }
        }

        checkDate = checkDate.add(const Duration(days: 1));
      }

      if (totalDamage > 0) {
        debugPrint(
            'FastingPresenter: Missed $missedCount quests. Applying $totalDamage damage.');
        statsPresenter?.modifyHp(-totalDamage);
        statsPresenter
            ?.resetStreak(); // Reset streak on missed quest? Maybe too harsh? Let's keep it.

        // Show notification or snackbar?
        // Since this happens on load, we might not have context for SnackBar.
        // We can use the notification service to show a local notification.
        _notificationService.showSimpleNotification(
          title: 'Penalty Applied',
          body: 'You missed $missedCount quests. Took $totalDamage damage.',
        );
      }

      lastPenaltyCheckDate = today;
      saveState();
    }
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
      elapsedSeconds = DateTime.now().difference(eatingStartTime!).inSeconds;
    }
    notifyListeners();
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
      int eatingWindowHours = 24 - fastingGoalHours;
      final eatingEndTime =
          eatingStartTime!.add(Duration(hours: eatingWindowHours));
      // Show persistent notification first for immediate feedback
      await _notificationService.showEatingTimerNotification(eatingEndTime);

      await _notificationService
          .cancelFastingNotifications(); // Cancel fasting alarms
      await _notificationService.scheduleEatingAlarm(
          eatingStartTime!, fastingGoalHours);
    } catch (e) {
      debugPrint('Error scheduling notifications: $e');
    }

    return (xp, hpChange);
  }

  Future<void> updateFastingGoal(int hours) async {
    debugPrint('FastingPresenter: Updating fasting goal to $hours hours');
    fastingGoalHours = hours;
    await saveState(); // Save immediately

    if (isFasting && startTime != null) {
      final endTime = startTime!.add(Duration(hours: fastingGoalHours));
      await _notificationService.showFastingTimerNotification(endTime);
    }
    notifyListeners();
  }

  // Quest Methods
  Future<void> addQuest(String title, int hour, int minute, List<bool> days,
      {bool isOneTime = false, int? reminderMinutes}) async {
    debugPrint('FastingPresenter: Adding quest - $title');
    int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final quest = Quest(
      id: id,
      title: title,
      hour: hour,
      minute: minute,
      days: days,
      isEnabled: true,
      isOneTime: isOneTime,
      reminderMinutes: reminderMinutes,
    );
    quests.add(quest);
    notifyListeners(); // Notify immediately

    await _notificationService.scheduleQuestNotifications(quest);
    saveState();
  }

  Future<void> toggleQuest(int index, bool isEnabled) async {
    debugPrint('FastingPresenter: Toggling quest index $index to $isEnabled');
    quests[index].isEnabled = isEnabled;
    notifyListeners(); // Notify immediately

    if (isEnabled) {
      await _notificationService.scheduleQuestNotifications(quests[index]);
    } else {
      await _notificationService.cancelQuestNotifications(quests[index]);
    }
    saveState();
  }

  Future<void> deleteQuest(int index) async {
    debugPrint('FastingPresenter: Deleting quest index $index');
    final quest = quests[index];
    quests.removeAt(index);
    notifyListeners(); // Notify immediately

    await _notificationService.cancelQuestNotifications(quest);
    saveState();
  }

  Future<void> updateQuest(
      int index, String title, int hour, int minute, List<bool> days,
      {bool isOneTime = false, int? reminderMinutes}) async {
    debugPrint('FastingPresenter: Updating quest index $index - $title');
    final quest = quests[index];

    quest.title = title;
    quest.hour = hour;
    quest.minute = minute;
    quest.days = days;
    quest.isOneTime = isOneTime;
    quest.reminderMinutes = reminderMinutes;
    notifyListeners(); // Notify immediately

    await _notificationService.cancelQuestNotifications(quest);
    if (quest.isEnabled) {
      await _notificationService.scheduleQuestNotifications(quest);
    }

    saveState();
  }

  Future<int> completeQuest(int index, {DateTime? date}) async {
    debugPrint('FastingPresenter: Completing quest index $index');
    int xpGained = 0;
    final quest = quests[index];
    final completionDate = date ?? DateTime.now();

    if (quest.isCompletedOn(completionDate)) {
      // Toggle off (undo) - Remove date
      final dateStr = completionDate.toIso8601String().split('T')[0];
      quest.completedDates.remove(dateStr);
      // Do not remove XP, do not reset lastXpAwarded to prevent farming
    } else {
      // Mark as completed
      quest.lastCompleted = completionDate; // Uses setter to add to list

      // Check if XP was already awarded today (or on the completion date?)
      // The requirement says "daily quests".
      // If I complete yesterday's quest today, should I gain XP? Yes.
      // But avoid double dipping for the SAME day.
      // lastXpAwarded tracks WHEN we gave XP.
      // If we give XP now, we update lastXpAwarded to now.

      bool alreadyAwardedToday = false;
      final now = DateTime.now();

      if (quest.lastXpAwarded != null) {
        if (quest.lastXpAwarded!.year == now.year &&
            quest.lastXpAwarded!.month == now.month &&
            quest.lastXpAwarded!.day == now.day) {
          alreadyAwardedToday = true;
        }
      }

      if (!alreadyAwardedToday) {
        xpGained = quest.xpReward;
        statsPresenter?.addXp(xpGained);
        quest.lastXpAwarded = now; // Awarded NOW
      }

      if (quest.isOneTime) {
        await deleteQuest(index);
        return xpGained;
      }
    }
    notifyListeners(); // Notify immediately
    saveState();
    return xpGained;
  }

  Future<void> clearAllData() async {
    debugPrint('FastingPresenter: Clearing all data');
    history.clear();
    quests.clear();
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
      await _rescheduleAllQuests();

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
