import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/alarm_notification.dart';
import '../services/lock_screen_service.dart';
import '../services/notification_service.dart';

/// How an alarm screen was closed, so the view knows whether to pop a route or
/// hand the device back to the lock screen.
enum AlarmDismissal {
  /// The activity was launched over the keyguard — closing it must return the
  /// user to the lock screen, never to the app behind it.
  returnToLockScreen,

  /// The app was already open and unlocked; just pop the alarm route.
  popRoute,
}

/// Drives the alarm screen: the ticking clock, the three actions, and handing
/// the keyguard back when the alarm is done with it.
class QuestAlarmPresenter extends ChangeNotifier {
  QuestAlarmPresenter({
    required AlarmNotification alarm,
    NotificationService? notifications,
    LockScreenService? lockScreen,
  })  : _alarm = alarm,
        _notifications = notifications ?? NotificationService(),
        _lockScreen = lockScreen ?? LockScreenService();

  /// An alarm left untouched is auto-dismissed, so a forgotten phone does not
  /// sit with its screen on over the lock screen indefinitely.
  static const Duration autoDismissAfter = Duration(minutes: 2);

  final AlarmNotification _alarm;
  final NotificationService _notifications;
  final LockScreenService _lockScreen;

  Timer? _clock;
  Timer? _autoDismiss;
  bool _overLockScreen = false;
  bool _isClosing = false;
  String _timeLabel = '';

  String get title => _alarm.title;
  String get body => _alarm.body;
  String get timeLabel => _timeLabel;

  /// Quest alarms can be completed or snoozed; a fasting/eating milestone has
  /// nothing to tick off, so it only offers dismiss.
  bool get isQuest => _alarm.questId != null;

  int get snoozeMinutes => NotificationService.questSnoozeMinutes;

  /// Emits once when the screen should close, telling the view how.
  final ValueNotifier<AlarmDismissal?> closeRequest =
      ValueNotifier<AlarmDismissal?>(null);

  Future<void> init() async {
    _tick();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    _autoDismiss = Timer(autoDismissAfter, dismiss);
    // Backstop for the native onCreate check — see LockScreenService.acquire.
    await _lockScreen.acquire();
    _overLockScreen = await _lockScreen.isShowingOverLockScreen();
  }

  void _tick() {
    final label = DateFormat.jm().format(DateTime.now());
    if (label == _timeLabel) return;
    _timeLabel = label;
    notifyListeners();
  }

  Future<void> markDone() async {
    // Claimed up front, not inside _close: these buttons get double-tapped on a
    // locked phone, and the side effect runs before the close does.
    if (!_claimClose()) return;
    final questId = _alarm.questId;
    if (questId != null) {
      await _notifications.completeQuestFromAlarm(questId);
    }
    await _close();
  }

  Future<void> snooze() async {
    if (!_claimClose()) return;
    final questId = _alarm.questId;
    if (questId != null) {
      await _notifications.showQuestSnooze(questId, title, alarmStyle: true);
    }
    await _close();
  }

  Future<void> dismiss() async {
    if (!_claimClose()) return;
    await _close();
  }

  /// Returns true for the first caller only; every later one is a repeat tap
  /// (or the auto-dismiss timer racing a tap) and must do nothing.
  bool _claimClose() {
    if (_isClosing) return false;
    _isClosing = true;
    return true;
  }

  Future<void> _close() async {
    _clock?.cancel();
    _autoDismiss?.cancel();
    // Drop the flags first: if this activity is over the keyguard, leaving them
    // set would let whatever is behind the alarm screen (the Hub, and the
    // finance figures on it) stay visible on a locked phone.
    await _lockScreen.release();
    closeRequest.value = _overLockScreen
        ? AlarmDismissal.returnToLockScreen
        : AlarmDismissal.popRoute;
  }

  @override
  void dispose() {
    _clock?.cancel();
    _autoDismiss?.cancel();
    closeRequest.dispose();
    super.dispose();
  }
}
