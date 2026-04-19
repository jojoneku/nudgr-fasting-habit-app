import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:intl/intl.dart';
import '../models/quest.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Handle background notification tap
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Channel IDs and Names
  static const String channelIdFastingTimer = 'fasting_timer_channel_v6';
  static const String channelNameFastingTimer = 'Active Fasting Timer';

  static const String channelIdEatingTimer = 'eating_timer_channel_v6';
  static const String channelNameEatingTimer = 'Active Eating Timer';

  static const String channelIdMilestones = 'milestones_channel_v6';
  static const String channelNameMilestones = 'Fasting & Eating Alerts';

  static const String channelIdQuests = 'quests_channel_v6';
  static const String channelNameQuests = 'Daily Quests';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      debugPrint('NotificationService: Device timezone: $timeZoneName');
      try {
        // FlutterTimezone returns the IANA timezone name directly (e.g., "Asia/Manila")
        // Extract just the timezone identifier if it's wrapped in additional info
        String tzName = timeZoneName.toString();
        // Handle case where FlutterTimezone returns a complex object string
        if (tzName.contains('(') && tzName.contains(',')) {
          // Extract "Asia/Manila" from "TimezoneInfo(Asia/Manila, ...)"
          final match = RegExp(r'TimezoneInfo\(([^,]+)').firstMatch(tzName);
          if (match != null) {
            tzName = match.group(1)!.trim();
          }
        }
        debugPrint('NotificationService: Using timezone: $tzName');
        tz.setLocalLocation(tz.getLocation(tzName));
      } catch (e) {
        debugPrint(
            'NotificationService: Error setting location $timeZoneName: $e. Fallback to UTC.');
        try {
          tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (e2) {
          debugPrint(
              'NotificationService: CRITICAL: Could not set fallback UTC: $e2');
        }
      }
    } catch (e) {
      debugPrint('NotificationService: Error initializing timezones: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification clicked: ${details.payload}');
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Explicitly create channels
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      debugPrint('NotificationService: Cleanup & Setup channels...');

      // cleanup old channels to fix duplication in Settings
      final List<String> oldChannels = [
        'fasting_channel',
        'fasting_channel_v2',
        'fasting_timer_channel_v4',
        'eating_timer_channel_v4',
        'quests_channel',
        'quests_channel_v2',
        'test_channel'
      ];

      for (final channelId in oldChannels) {
        try {
          await androidImplementation.deleteNotificationChannel(channelId);
        } catch (e) {/* ignore */}
      }

      // 1. Active Fasting Timer
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdFastingTimer,
          channelNameFastingTimer,
          description: 'Shows the time remaining for your current fast',
          importance: Importance.max,
          playSound:
              false, // Timer usually silent or low noise, but importance max suggests heads-up.
          enableVibration: false,
        ),
      );

      // 2. Active Eating Timer
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdEatingTimer,
          channelNameEatingTimer,
          description: 'Shows the time remaining for your eating window',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
        ),
      );

      // 3. Milestones & Alerts (Fasting Done, etc)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdMilestones,
          channelNameMilestones,
          description:
              'Notifications for fasting milestones and eating window alerts',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // 4. Quests
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdQuests,
          channelNameQuests,
          description: 'Recurring reminders for habits and quests',
          importance: Importance.max,
          playSound: true,
          sound: null,
          enableVibration: true,
        ),
      );

      debugPrint('NotificationService: Channels created.');
    }

    _isInitialized = true;
    debugPrint('NotificationService: Initialized');
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final bool? granted =
        await androidImplementation?.requestNotificationsPermission();
    debugPrint(
        'NotificationService: Notifications permission granted: $granted');

    // Also request exact alarm permission for reliable scheduling on Android 12+
    // This is required for exact alarms (timers, habits) to fire at precise times.
    await androidImplementation?.requestExactAlarmsPermission();
  }

  /// Helper to convert a target DateTime (Local) to a TZDateTime (Relative to now)
  /// This ensures that even if TimeZone database is out of sync with device,
  /// the delay is correct.
  tz.TZDateTime _getRelativeScheduledTime(DateTime targetDateTime) {
    final now = DateTime.now();
    final duration = targetDateTime.difference(now);
    // If it's in the past, schedule it for "now" (or let the scheduler handle it).
    // But zonedSchedule requires future date usually.
    // We'll handle "in the past" in the calling method if needed.

    final tzNow = tz.TZDateTime.now(tz.local);
    return tzNow.add(duration);
  }

  Future<void> scheduleFastingAlarm(DateTime startTime, int goalHours) async {
    debugPrint(
        'NotificationService: Scheduling fasting alarm. Start: $startTime, Goal: $goalHours hours');

    // Calculate target time using local DateTime to avoid timezone confusion
    final goalTime = startTime.add(Duration(hours: goalHours));
    final scheduledDate = _getRelativeScheduledTime(goalTime);

    await _scheduleOneShotNotification(
      0,
      "You did it! 🏆",
      "Fasting goal reached. Time to eat!",
      scheduledDate,
      fullScreen: true,
      channelId: channelIdMilestones,
      channelName: channelNameMilestones,
    );

    final Map<int, Map<String, String>> fastingEffects = {
      12: {
        'title': 'Fat Burning Starts',
        'body': 'Your body is now burning fat for energy.'
      },
      16: {
        'title': 'Deeper Ketosis',
        'body': 'You are entering deeper ketosis.'
      },
      18: {
        'title': 'Autophagy Increases',
        'body': 'Cellular repair (autophagy) is increasing.'
      },
      24: {
        'title': 'Significant Autophagy',
        'body': 'Significant autophagy and cell renewal.'
      },
    };
    for (int h = 2; h < goalHours; h += 2) {
      final milestoneTime = startTime.add(Duration(hours: h));
      final notifTime = _getRelativeScheduledTime(milestoneTime);

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
        channelId: channelIdMilestones,
        channelName: channelNameMilestones,
      );
    }
  }

  Future<void> scheduleEatingAlarm(
      DateTime eatingStartTime, int goalHours) async {
    debugPrint(
        'NotificationService: Scheduling eating alarm. Start: $eatingStartTime, Goal: $goalHours hours');
    int eatingWindow = 24 - goalHours;
    if (eatingWindow <= 0) {
      return;
    }

    final windowEndTime = eatingStartTime.add(Duration(hours: eatingWindow));
    final scheduledDate = _getRelativeScheduledTime(windowEndTime);

    await _scheduleOneShotNotification(
      1,
      "Eating Window Over ⏳",
      "Time to start fasting!",
      scheduledDate,
      fullScreen: true,
      channelId: channelIdMilestones,
      channelName: channelNameMilestones,
    );

    for (int h = eatingWindow - 1; h > 0; h--) {
      final warnTime = eatingStartTime.add(Duration(hours: eatingWindow - h));
      final notifTime = _getRelativeScheduledTime(warnTime);

      await _scheduleOneShotNotification(
        200 + h,
        "$h hour${h == 1 ? '' : 's'} left to eat",
        "You have $h hour${h == 1 ? '' : 's'} left in your eating window.",
        notifTime,
        groupKey: 'eating_group',
        channelId: channelIdMilestones,
        channelName: channelNameMilestones,
      );
    }
  }

  Future<void> showSimpleNotification(
      {String title = 'Test Notification',
      String body = 'This is a test notification'}) async {
    // Use Milestones channel for generic tests now, as test_channel is deleted
    await _scheduleOneShotNotification(888, title, body,
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 1)),
        channelId: channelIdMilestones, channelName: channelNameMilestones);
  }

  Future<void> testAllChannels() async {
    debugPrint('NotificationService: Testing ALL channels');

    // 1. Simulating "Fasting Phase Complete" (Milestone)
    await _scheduleOneShotNotification(
      801,
      "You did it! 🏆",
      "Fasting goal reached. Time to eat! (Simulation)",
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 2)),
      fullScreen: true,
      channelId: channelIdMilestones,
      channelName: channelNameMilestones,
    );

    // 2. Simulating "Eating Phase Complete" (Milestone)
    await _scheduleOneShotNotification(
      802,
      "Eating Window Over ⏳",
      "Time to start fasting! (Simulation)",
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 4)),
      fullScreen: true,
      channelId: channelIdMilestones,
      channelName: channelNameMilestones,
    );

    // 3. Quest simulation
    await _scheduleOneShotNotification(
      803,
      'Test: Daily Quest',
      'This is a test Quest reminder. (Sound + Vib)',
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 6)),
      channelId: channelIdQuests,
      channelName: channelNameQuests,
      fullScreen: true,
    );

    // 4. Fasting Timer Channel (Direct Check)
    const AndroidNotificationDetails fastingChannelDetails =
        AndroidNotificationDetails(
      channelIdFastingTimer,
      channelNameFastingTimer,
      channelDescription: 'Shows the time remaining for your current fast',
      importance: Importance.max,
      priority: Priority.high,
    );
    await flutterLocalNotificationsPlugin.show(
      804,
      'Test: Active Fasting Timer',
      'Silent ongoing notification (Simulation)',
      const NotificationDetails(android: fastingChannelDetails),
    );

    // 5. Eating Timer Channel (Direct Check)
    const AndroidNotificationDetails eatingChannelDetails =
        AndroidNotificationDetails(
      channelIdEatingTimer,
      channelNameEatingTimer,
      channelDescription: 'Shows the time remaining for your eating window',
      importance: Importance.max,
      priority: Priority.high,
    );
    await flutterLocalNotificationsPlugin.show(
      805,
      'Test: Active Eating Timer',
      'Silent ongoing notification (Simulation)',
      const NotificationDetails(android: eatingChannelDetails),
    );
  }

  Future<void> showFastingTimerNotification(DateTime endTime) async {
    debugPrint(
        'NotificationService: Showing fasting timer notification. Ends at $endTime');
    // Ensure eating timer is cancelled
    try {
      await flutterLocalNotificationsPlugin.cancel(998);
    } catch (e) {
      debugPrint('Error cancelling eating timer: $e');
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdFastingTimer,
      channelNameFastingTimer,
      channelDescription: 'Shows the time remaining for your current fast',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
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
    debugPrint(
        'NotificationService: Showing eating timer notification. Ends at $endTime');
    // Ensure fasting timer is cancelled
    try {
      await flutterLocalNotificationsPlugin.cancel(999);
    } catch (e) {
      debugPrint('Error cancelling fasting timer: $e');
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdEatingTimer,
      channelNameEatingTimer,
      channelDescription: 'Shows the time remaining for your eating window',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
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
    debugPrint(
        'NotificationService: Scheduling quest notifications for ${quest.title}');

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdQuests,
      channelNameQuests,
      channelDescription: 'Recurring reminders for habits and quests',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500, 250, 500]),
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );
    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    switch (quest.recurrenceType) {
      case RecurrenceType.daily:
        await _scheduleDailyQuest(quest, details);
      case RecurrenceType.weekly:
        await _scheduleWeeklyQuest(quest, details);
      case RecurrenceType.biweekly:
        await _scheduleBiweeklyQuest(quest, details);
      case RecurrenceType.monthly:
        await _scheduleMonthlyQuest(quest, details);
    }
  }

  /// Daily: schedule one recurring notification per enabled day-of-week.
  Future<void> _scheduleDailyQuest(
      Quest quest, NotificationDetails details) async {
    final int baseId = quest.id;
    final now = tz.TZDateTime.now(tz.local);

    for (int i = 0; i < 7; i++) {
      if (!quest.days[i]) continue;
      int dayOfWeekISO = i + 1;
      tz.TZDateTime scheduledDate =
          _nextInstanceOfDay(dayOfWeekISO, quest.hour, quest.minute);
      int notificationId = baseId + i;

      if (scheduledDate.isBefore(now.add(const Duration(seconds: 10)))) {
        await _scheduleOneShotNotification(
          notificationId + 10000,
          quest.title,
          "It's time for your quest!",
          now.add(const Duration(seconds: 1)),
          channelId: channelIdQuests,
          channelName: channelNameQuests,
        );
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId,
          quest.title,
          "It's time for your quest!",
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (e) {
        debugPrint(
            'NotificationService: Error scheduling quest "${quest.title}": $e');
      }

      await _scheduleQuestReminder(quest, scheduledDate, baseId + 100 + i,
          details, DateTimeComponents.dayOfWeekAndTime);
    }
  }

  /// Weekly: one recurring notification on the chosen weekday.
  Future<void> _scheduleWeeklyQuest(
      Quest quest, NotificationDetails details) async {
    final int dayOfWeekISO = quest.weeklyWeekday + 1;
    tz.TZDateTime scheduledDate =
        _nextInstanceOfDay(dayOfWeekISO, quest.hour, quest.minute);
    final now = tz.TZDateTime.now(tz.local);

    if (scheduledDate.isBefore(now.add(const Duration(seconds: 10)))) {
      await _scheduleOneShotNotification(
        quest.id + 10000,
        quest.title,
        "It's time for your quest!",
        now.add(const Duration(seconds: 1)),
        channelId: channelIdQuests,
        channelName: channelNameQuests,
      );
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        quest.id,
        quest.title,
        "It's time for your quest!",
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (e) {
      debugPrint(
          'NotificationService: Error scheduling weekly quest "${quest.title}": $e');
    }

    await _scheduleQuestReminder(quest, scheduledDate, quest.id + 100, details,
        DateTimeComponents.dayOfWeekAndTime);
  }

  /// Biweekly: schedule the next 6 occurrences as one-shot notifications.
  Future<void> _scheduleBiweeklyQuest(
      Quest quest, NotificationDetails details) async {
    final int dayOfWeekISO = quest.weeklyWeekday + 1;
    tz.TZDateTime next =
        _nextInstanceOfDay(dayOfWeekISO, quest.hour, quest.minute);

    // If this week is not an "on" week, skip to next occurrence (+7 days).
    if (quest.recurrenceAnchorDate != null) {
      final anchor = DateTime.parse(quest.recurrenceAnchorDate!);
      final anchorMonday = anchor.subtract(Duration(days: anchor.weekday - 1));
      final now = DateTime.now();
      final thisMonday = now.subtract(Duration(days: now.weekday - 1));
      final weeksDiff = thisMonday.difference(anchorMonday).inDays ~/ 7;
      if (weeksDiff.abs() % 2 != 0) {
        next = next.add(const Duration(days: 7));
      }
    }

    for (int occurrence = 0; occurrence < 6; occurrence++) {
      final int notifId = quest.id + 200 + occurrence;
      await _scheduleOneShotNotification(
        notifId,
        quest.title,
        "It's time for your bi-weekly quest!",
        next,
        channelId: channelIdQuests,
        channelName: channelNameQuests,
      );
      if (quest.reminderMinutes != null && quest.reminderMinutes! > 0) {
        final reminderDate =
            next.subtract(Duration(minutes: quest.reminderMinutes!));
        await _scheduleOneShotNotification(
          notifId + 100,
          "Upcoming Quest: ${quest.title}",
          "${quest.reminderMinutes} minutes until your quest!",
          reminderDate,
          channelId: channelIdQuests,
          channelName: channelNameQuests,
        );
      }
      next = next.add(const Duration(days: 14));
    }
  }

  /// Monthly: one recurring notification per selected day-of-month.
  Future<void> _scheduleMonthlyQuest(
      Quest quest, NotificationDetails details) async {
    for (int idx = 0; idx < quest.monthlyDays.length; idx++) {
      final int dayOfMonth = quest.monthlyDays[idx];
      final int notifId = quest.id + 300 + idx;
      tz.TZDateTime scheduledDate =
          _nextInstanceOfMonthDay(dayOfMonth, quest.hour, quest.minute);

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          notifId,
          quest.title,
          "It's time for your quest!",
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        );
      } catch (e) {
        debugPrint(
            'NotificationService: Error scheduling monthly quest "${quest.title}": $e');
      }

      await _scheduleQuestReminder(quest, scheduledDate, notifId + 10, details,
          DateTimeComponents.dayOfMonthAndTime);
    }
  }

  /// Schedules a reminder notification before a quest, reusing the match component.
  Future<void> _scheduleQuestReminder(
    Quest quest,
    tz.TZDateTime questDate,
    int reminderId,
    NotificationDetails details,
    DateTimeComponents matchComponent,
  ) async {
    if (quest.reminderMinutes == null || quest.reminderMinutes! <= 0) return;
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime reminderDate =
        questDate.subtract(Duration(minutes: quest.reminderMinutes!));

    if (reminderDate.isBefore(now)) {
      reminderDate = reminderDate.add(const Duration(days: 7));
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        reminderId,
        "Upcoming Quest: ${quest.title}",
        "${quest.reminderMinutes} minutes until your quest!",
        reminderDate,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponent,
      );
    } catch (e) {
      debugPrint(
          'NotificationService: Error scheduling reminder for "${quest.title}": $e');
    }
  }

  Future<void> cancelQuestNotifications(Quest quest) async {
    debugPrint(
        'NotificationService: Cancelling quest notifications for ${quest.title}');
    final int baseId = quest.id;
    // Daily: IDs baseId+0..6 and reminders baseId+100..106
    for (int i = 0; i < 7; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + i);
      await flutterLocalNotificationsPlugin.cancel(baseId + 100 + i);
    }
    // Weekly: baseId, reminder baseId+100
    await flutterLocalNotificationsPlugin.cancel(baseId);
    await flutterLocalNotificationsPlugin.cancel(baseId + 100);
    // Biweekly: baseId+200..205 and baseId+300..305 (reminders)
    for (int i = 0; i < 6; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + 200 + i);
      await flutterLocalNotificationsPlugin.cancel(baseId + 300 + i);
    }
    // Monthly: baseId+300..301 and reminders baseId+310..311
    for (int i = 0; i < 2; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + 300 + i);
      await flutterLocalNotificationsPlugin.cancel(baseId + 310 + i);
    }
    // Immediate one-shots
    await flutterLocalNotificationsPlugin.cancel(baseId + 10000);
  }

  /// Schedules a "streak at risk" notification at 9 PM today.
  /// Only effective if quest is still incomplete and streakCount > 3.
  Future<void> scheduleStreakAtRiskNotification(
      int questId, String questTitle, int streakCount) async {
    const int notificationId = 997;
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
    if (scheduled.isBefore(now)) return; // Already past 9 PM — skip
    await _scheduleOneShotNotification(
      notificationId,
      '⚔️ Streak at risk: $questTitle',
      "Don't lose your $streakCount-day streak. You still have time.",
      scheduled,
      channelId: channelIdQuests,
      channelName: channelNameQuests,
    );
    debugPrint(
        'NotificationService: Streak-at-risk notification scheduled for $questTitle at 9 PM');
  }

  Future<void> cancelStreakAtRiskNotification() async {
    await flutterLocalNotificationsPlugin.cancel(997);
  }

  Future<void> cancelFastingNotifications() async {
    debugPrint('NotificationService: Cancelling fasting notifications');
    await flutterLocalNotificationsPlugin.cancel(0); // Goal reached
    await flutterLocalNotificationsPlugin.cancel(999); // Timer
    // Cancel milestones (100-124)
    for (int i = 100; i <= 124; i++) {
      await flutterLocalNotificationsPlugin.cancel(i);
    }
  }

  Future<void> cancelEatingNotifications() async {
    debugPrint('NotificationService: Cancelling eating notifications');
    await flutterLocalNotificationsPlugin.cancel(1); // Window over
    await flutterLocalNotificationsPlugin.cancel(998); // Timer
    // Cancel milestones (200-224)
    for (int i = 200; i <= 224; i++) {
      await flutterLocalNotificationsPlugin.cancel(i);
    }
  }

  Future<void> cancelAll() async {
    debugPrint('NotificationService: Cancelling all notifications');
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> cancel(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  tz.TZDateTime _nextInstanceOfDay(int dayOfWeek, int hour, int minute) {
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    // Allow scheduling for the current time if it's within the last minute (to fix "Test Now" scenarios)
    if (scheduledDate.isBefore(now.subtract(const Duration(minutes: 1)))) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }
    return scheduledDate;
  }

  /// Returns the next [tz.TZDateTime] matching a specific day-of-month.
  tz.TZDateTime _nextInstanceOfMonthDay(int dayOfMonth, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime candidate =
        tz.TZDateTime(tz.local, now.year, now.month, dayOfMonth, hour, minute);
    if (candidate.isBefore(now.subtract(const Duration(minutes: 1)))) {
      // Roll to next month
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      candidate = tz.TZDateTime(
          tz.local, nextYear, nextMonth, dayOfMonth, hour, minute);
    }
    return candidate;
  }

  Future<void> _scheduleOneShotNotification(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledDate, {
    String? groupKey,
    bool fullScreen = false,
    required String channelId,
    required String channelName,
  }) async {
    final now = tz.TZDateTime.now(tz.local);

    // Check if scheduled date is significantly in the past (e.g. > 5 mins ago)
    // If so, skip it to avoid spamming old notifications.
    if (scheduledDate.isBefore(now.subtract(const Duration(minutes: 5)))) {
      debugPrint(
          'NotificationService: Skipping notification $id ($title) as it is too far in the past ($scheduledDate)');
      return;
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Fasting & Eating Alerts',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: fullScreen,
      groupKey: groupKey,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: fullScreen ? AndroidNotificationCategory.alarm : null,
    );
    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    // If scheduled date is in the past (but within 5 mins) or very close to now (within 5 seconds), show immediately
    if (scheduledDate.isBefore(now.add(const Duration(seconds: 5)))) {
      debugPrint(
          'NotificationService: Showing immediate notification $id ($title) as time is effectively now');
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        details,
      );
      return;
    }

    debugPrint(
        'NotificationService: Scheduling notification $id ($title) for $scheduledDate');
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('NotificationService: Error scheduling notification $id: $e');
    }
  }
}
