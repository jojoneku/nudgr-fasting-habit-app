import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fasting_log.dart';
import '../models/quest.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

class FastingPresenter extends ChangeNotifier {
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();

  bool isFasting = false;
  DateTime? startTime;
  DateTime? eatingStartTime;
  int elapsedSeconds = 0;
  int fastingGoalHours = 16;
  List<FastingLog> history = [];
  List<Quest> quests = [];
  Timer? _ticker;

  FastingPresenter() {
    _init();
  }

  Future<void> _init() async {
    debugPrint('FastingPresenter: Initializing...');
    // Load state first to ensure UI is correct immediately
    await loadState();
    
    await _notificationService.init();
    await _notificationService.requestPermissions();
    debugPrint('FastingPresenter: Initialization complete');
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
    
    debugPrint('FastingPresenter: State loaded - isFasting: $isFasting, startTime: $startTime, eatingStartTime: $eatingStartTime');
    
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
        final eatingEndTime = eatingStartTime!.add(Duration(hours: eatingWindowHours));
        await _notificationService.showEatingTimerNotification(eatingEndTime);
      } catch (e) {
        // Error showing resume notification
      }
    }
    notifyListeners();
  }

  Future<void> saveState() async {
    debugPrint('FastingPresenter: Saving state - isFasting: $isFasting, startTime: $startTime, eatingStartTime: $eatingStartTime');
    await _storageService.saveState(
      isFasting: isFasting,
      startTime: startTime,
      eatingStartTime: eatingStartTime,
      elapsedSeconds: elapsedSeconds,
      fastingGoalHours: fastingGoalHours,
      history: history,
      quests: quests,
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
      final eatingDuration = eatingEnd.difference(eatingStartTime!).inSeconds / 3600.0;
      
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

      await _notificationService.cancelEatingNotifications(); // Cancel eating alarms
      await _notificationService.scheduleFastingAlarm(startTime!, fastingGoalHours);
    } catch (e) {
      // Error scheduling notifications
    }
  }

  Future<void> stopFast() async {
    debugPrint('FastingPresenter: Stopping fast...');
    if (!isFasting || startTime == null) {
      debugPrint('FastingPresenter: Not fasting or startTime is null, ignoring stopFast call');
      return;
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

    try {
      int eatingWindowHours = 24 - fastingGoalHours;
      final eatingEndTime = eatingStartTime!.add(Duration(hours: eatingWindowHours));
      // Show persistent notification first for immediate feedback
      await _notificationService.showEatingTimerNotification(eatingEndTime);

      await _notificationService.cancelFastingNotifications(); // Cancel fasting alarms
      await _notificationService.scheduleEatingAlarm(eatingStartTime!, fastingGoalHours);
    } catch (e) {
      // Error scheduling notifications
    }
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
  Future<void> addQuest(String title, int hour, int minute, List<bool> days) async {
    debugPrint('FastingPresenter: Adding quest - $title');
    int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final quest = Quest(
      id: id,
      title: title,
      hour: hour,
      minute: minute,
      days: days,
      isEnabled: true,
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

  Future<void> updateQuest(int index, String title, int hour, int minute, List<bool> days) async {
    debugPrint('FastingPresenter: Updating quest index $index - $title');
    final quest = quests[index];
    
    quest.title = title;
    quest.hour = hour;
    quest.minute = minute;
    quest.days = days;
    notifyListeners(); // Notify immediately
    
    await _notificationService.cancelQuestNotifications(quest);
    if (quest.isEnabled) {
      await _notificationService.scheduleQuestNotifications(quest);
    }
    
    saveState();
  }

  Future<void> completeQuest(int index) async {
    debugPrint('FastingPresenter: Completing quest index $index');
    if (quests[index].isCompletedToday) {
      quests[index].lastCompleted = null; // Toggle off (undo)
    } else {
      quests[index].lastCompleted = DateTime.now();
    }
    notifyListeners(); // Notify immediately
    saveState();
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
    await _notificationService.showSimpleNotification();
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
    notifyListeners();
    await saveState();
  }

  Future<void> updateEatingStartTime(DateTime newStartTime) async {
    debugPrint('FastingPresenter: Updating eating start time to $newStartTime');
    eatingStartTime = newStartTime;
    final now = DateTime.now();
    elapsedSeconds = now.difference(eatingStartTime!).inSeconds;
    notifyListeners();
    await saveState();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
