import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:intl/intl.dart';
import '../models/quest.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      tz.initializeTimeZones();
    } catch (e) {
      print('Error initializing timezones: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {},
    );
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
    // Also request exact alarm permission for reliable scheduling on Android 12+
    await androidImplementation?.requestExactAlarmsPermission();
  }

  Future<void> scheduleFastingAlarm(DateTime startTime, int goalHours) async {
    final scheduledDate = tz.TZDateTime.from(
      startTime.add(Duration(hours: goalHours)),
      tz.local,
    );
    await _scheduleOneShotNotification(0, "You did it! 🏆", "Fasting goal reached. Time to eat!", scheduledDate, fullScreen: true);
    
    final Map<int, Map<String, String>> fastingEffects = {
      12: {'title': 'Fat Burning Starts', 'body': 'Your body is now burning fat for energy.'},
      16: {'title': 'Deeper Ketosis', 'body': 'You are entering deeper ketosis.'},
      18: {'title': 'Autophagy Increases', 'body': 'Cellular repair (autophagy) is increasing.'},
      24: {'title': 'Significant Autophagy', 'body': 'Significant autophagy and cell renewal.'},
    };
    for (int h = 2; h < goalHours; h += 2) {
      final notifTime = tz.TZDateTime.from(startTime.add(Duration(hours: h)), tz.local);
      String title;
      String body;
      if (fastingEffects.containsKey(h)) {
        title = fastingEffects[h]!['title']!;
        body = fastingEffects[h]!['body']!;
      } else {
        title = "$h hours fasted";
        body = "You've fasted for $h hours.";
      }
      await _scheduleOneShotNotification(
        100 + h,
        title,
        body,
        notifTime,
        groupKey: 'fasting_group',
      );
    }
  }

  Future<void> scheduleEatingAlarm(DateTime eatingStartTime, int goalHours) async {
    int eatingWindow = 24 - goalHours;
    if (eatingWindow <= 0) {
      return;
    }
    final scheduledDate = tz.TZDateTime.from(
      eatingStartTime.add(Duration(hours: eatingWindow)),
      tz.local,
    );
    await _scheduleOneShotNotification(1, "Eating Window Over ⏳", "Time to start fasting!", scheduledDate, fullScreen: true);

    for (int h = eatingWindow - 1; h > 0; h--) {
      final notifTime = tz.TZDateTime.from(eatingStartTime.add(Duration(hours: eatingWindow - h)), tz.local);
      await _scheduleOneShotNotification(
        200 + h,
        "$h hour${h == 1 ? '' : 's'} left to eat",
        "You have $h hour${h == 1 ? '' : 's'} left in your eating window.",
        notifTime,
        groupKey: 'eating_group',
      );
    }
  }

  Future<void> showFastingTimerNotification(DateTime endTime) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_timer_channel',
      'Active Fasting Timer',
      channelDescription: 'Shows the time remaining for your current fast',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: endTime.millisecondsSinceEpoch,
      usesChronometer: true,
      chronometerCountDown: true,
    );
    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    final formattedTime = DateFormat.jm().format(endTime);

    await flutterLocalNotificationsPlugin.show(
      999,
      'Fasting Goal',
      'Ends at $formattedTime',
      details,
    );
  }

  Future<void> showEatingTimerNotification(DateTime endTime) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'eating_timer_channel',
      'Active Eating Timer',
      channelDescription: 'Shows the time remaining for your eating window',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: endTime.millisecondsSinceEpoch,
      usesChronometer: true,
      chronometerCountDown: true,
    );
    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    final formattedTime = DateFormat.jm().format(endTime);

    await flutterLocalNotificationsPlugin.show(
      998,
      'Eating Window',
      'Ends at $formattedTime',
      details,
    );
  }

  Future<void> cancelFastingTimerNotification() async {
    await flutterLocalNotificationsPlugin.cancel(999);
  }

  Future<void> cancelEatingTimerNotification() async {
    await flutterLocalNotificationsPlugin.cancel(998);
  }

  Future<void> scheduleQuestNotifications(Quest quest) async {
    int baseId = quest.id;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'quests_channel',
      'Daily Quests',
      channelDescription: 'Recurring reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500, 250, 500]),
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);

    for (int i = 0; i < 7; i++) {
      if (quest.days[i]) {
        int dayOfWeekISO = i + 1;
        tz.TZDateTime scheduledDate = _nextInstanceOfDay(dayOfWeekISO, quest.hour, quest.minute);
        int notificationId = baseId + i;

        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId,
          quest.title,
          "It's time for your quest!",
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  Future<void> cancelQuestNotifications(Quest quest) async {
    int baseId = quest.id;
    for (int i = 0; i < 7; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + i);
    }
  }
  
  Future<void> cancelAll() async {
      await flutterLocalNotificationsPlugin.cancelAll();
  }
  
  Future<void> cancel(int id) async {
      await flutterLocalNotificationsPlugin.cancel(id);
  }

  tz.TZDateTime _nextInstanceOfDay(int dayOfWeek, int hour, int minute) {
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }
    return scheduledDate;
  }

  Future<void> _scheduleOneShotNotification(int id, String title, String body, tz.TZDateTime scheduledDate, {String? groupKey, bool fullScreen = false}) async {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_channel',
      'Fasting Timer',
      channelDescription: 'Notifications for fasting milestones',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: fullScreen,
      groupKey: groupKey,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: fullScreen ? AndroidNotificationCategory.alarm : null,
    );
    NotificationDetails details = NotificationDetails(android: androidDetails);
    
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
