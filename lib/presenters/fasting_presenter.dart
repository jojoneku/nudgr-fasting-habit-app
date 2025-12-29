import 'dart:async';
import 'package:flutter/material.dart';
import '../models/fasting_log.dart';
import '../models/habit.dart';
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
  List<Habit> reminders = [];
  Timer? _ticker;

  FastingPresenter() {
    _init();
  }

  Future<void> _init() async {
    await _notificationService.init();
    await loadState();
  }

  Future<void> loadState() async {
    final state = await _storageService.loadState();
    isFasting = state['isFasting'];
    startTime = state['startTime'];
    eatingStartTime = state['eatingStartTime'];
    elapsedSeconds = state['elapsedSeconds'];
    fastingGoalHours = state['fastingGoalHours'];
    history = state['history'];
    reminders = state['reminders'];
    
    if (isFasting && startTime != null) {
      _startTicker();
    } else if (eatingStartTime != null) {
      _startTicker(); // Also tick for eating window
    }
    notifyListeners();
  }

  Future<void> saveState() async {
    await _storageService.saveState(
      isFasting: isFasting,
      startTime: startTime,
      eatingStartTime: eatingStartTime,
      elapsedSeconds: elapsedSeconds,
      fastingGoalHours: fastingGoalHours,
      history: history,
      reminders: reminders,
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
    if (isFasting) return;

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
    
    await _notificationService.cancelAll(); // Cancel eating alarms
    await _notificationService.scheduleFastingAlarm(startTime!, fastingGoalHours);
    
    _startTicker();
    saveState();
    notifyListeners();
  }

  Future<void> stopFast() async {
    if (!isFasting || startTime == null) return;

    final endTime = DateTime.now();
    final durationHours = endTime.difference(startTime!).inSeconds / 3600.0;
    
    // Create log
    final log = FastingLog(
      fastStart: startTime!,
      fastEnd: endTime,
      fastDuration: durationHours,
      success: durationHours >= fastingGoalHours,
      eatingStart: endTime, // Eating starts now
    );
    
    history.insert(0, log);
    
    isFasting = false;
    startTime = null;
    eatingStartTime = endTime;
    elapsedSeconds = 0;
    
    await _notificationService.cancelAll(); // Cancel fasting alarms
    await _notificationService.scheduleEatingAlarm(eatingStartTime!, fastingGoalHours);

    _startTicker();
    saveState();
    notifyListeners();
  }
  
  Future<void> updateFastingGoal(int hours) async {
      fastingGoalHours = hours;
      saveState();
      notifyListeners();
  }

  // Habit Methods
  Future<void> addHabit(String title, int hour, int minute, List<bool> days) async {
    int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final habit = Habit(
      id: id,
      title: title,
      hour: hour,
      minute: minute,
      days: days,
      isEnabled: true,
    );
    reminders.add(habit);
    await _notificationService.scheduleHabitNotifications(habit);
    saveState();
    notifyListeners();
  }

  Future<void> toggleHabit(int index, bool isEnabled) async {
    reminders[index].isEnabled = isEnabled;
    if (isEnabled) {
      await _notificationService.scheduleHabitNotifications(reminders[index]);
    } else {
      await _notificationService.cancelHabitNotifications(reminders[index]);
    }
    saveState();
    notifyListeners();
  }

  Future<void> deleteHabit(int index) async {
    await _notificationService.cancelHabitNotifications(reminders[index]);
    reminders.removeAt(index);
    saveState();
    notifyListeners();
  }
  
  Future<void> clearHistory() async {
      history.clear();
      reminders.clear();
      await _notificationService.cancelAll();
      saveState();
      notifyListeners();
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

    saveState();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
