import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:intl/intl.dart';
import '../models/quest.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Runs in a background isolate when a quest notification action button is
  // tapped while the app is terminated. Kept lightweight: it only records the
  // tap (or reschedules a snooze). The real completion — XP, streak, stat and
  // achievement checks — is applied through the presenters on next foreground
  // via WidgetBridgeService.drainPendingActions, so nothing RPG runs here.
  if (_handleInstallApkPayload(notificationResponse.payload)) return;
  _handleQuestNotificationAction(notificationResponse);
}

/// Routes an OTA "update ready" notification tap to the package installer.
/// Returns true when [payload] was an install payload (handled or not), so
/// callers skip the quest routing.
bool _handleInstallApkPayload(String? payload) {
  if (payload == null ||
      !payload.startsWith(NotificationService.installApkPayloadPrefix)) {
    return false;
  }
  final path =
      payload.substring(NotificationService.installApkPayloadPrefix.length);
  OpenFilex.open(path).then((result) {
    debugPrint(
        'NotificationService: install tap → ${result.type} ${result.message}');
  }).catchError((e) {
    debugPrint('NotificationService: install tap failed: $e');
  });
  return true;
}

/// Handles a quest notification action button tap ([NotificationService.
/// questActionDone] / [questActionSnooze] / [questActionSkip]). Safe to run in
/// either the background isolate or the foreground (main) isolate.
Future<void> _handleQuestNotificationAction(
    NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId == null) return; // body tap, not an action button

  Map<String, dynamic> data = const {};
  final payload = response.payload;
  if (payload != null && payload.isNotEmpty) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {/* non-JSON payload — ignore */}
  }
  final questId = data['id'];
  if (questId is! int) return;

  switch (actionId) {
    case NotificationService.questActionDone:
      await _enqueueQuestCompletion(questId);
      // Foreground: apply immediately. Background: this is null → applied on
      // next resume via drainPendingActions.
      NotificationService.onQuestActionDrain?.call();
      break;
    case NotificationService.questActionSkip:
      // cancelNotification:true on the action already dismissed it; skipping is
      // a no-op on state — the quest simply stays not-done for today.
      break;
    case NotificationService.questActionSnooze:
      await _snoozeQuestNotification(
          questId, data['title'] as String? ?? 'Quest');
      break;
  }
}

/// Enqueues a `completequest` token onto the shared pending-actions queue — the
/// same one home-screen widget taps use — so the next foreground drain finishes
/// it through the real [QuestPresenter]. Deduped by quest id so a double
/// delivery (or double tap) can't toggle a same-day completion back off.
Future<void> _enqueueQuestCompletion(int questId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final queue =
        prefs.getStringList(StorageService.kWidgetPendingActions) ?? [];
    final already = queue
        .any((t) => t.startsWith('completequest|') && t.endsWith('|$questId'));
    if (!already) {
      final now = DateTime.now().millisecondsSinceEpoch;
      queue.add('completequest|$now|$questId');
      await prefs.setStringList(StorageService.kWidgetPendingActions, queue);
    }
  } catch (e) {
    debugPrint('NotificationService: enqueue quest completion failed: $e');
  }
}

/// Reschedules a quest reminder [NotificationService.questSnoozeMinutes] minutes
/// from now, carrying the same action buttons and payload.
Future<void> _snoozeQuestNotification(int questId, String title) async {
  try {
    final service = NotificationService();
    await service.init(); // self-heal in this isolate (no-op if initialised)
    await service.showQuestSnooze(questId, title);
  } catch (e) {
    debugPrint('NotificationService: snooze failed: $e');
  }
}

/// Outcome of the settings-screen "Test Notification" action, so the UI can
/// tell the user what actually happened instead of always claiming success.
enum NotificationTestResult {
  /// Test notifications were dispatched — they should appear in the shade.
  sent,

  /// The in-app master switch is off; nothing was sent.
  disabledInApp,

  /// Android has notifications blocked/denied for this app; nothing was sent.
  blockedBySystem,
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

  static const String channelIdAchievements = 'achievements_channel_v1';
  static const String channelNameAchievements = 'Character Achievements';

  static const String channelIdFinance = 'finance_channel_v1';
  static const String channelNameFinance = 'Finance Alerts';

  static const String channelIdDailyBrief = 'daily_brief';
  static const String channelNameDailyBrief = 'System Analysis';

  static const String channelIdUpdate = 'update_channel';
  static const String channelNameUpdate = 'App Updates';

  /// Payload prefix on the "update ready" notification; the rest of the
  /// payload is the absolute path of the downloaded APK.
  static const String installApkPayloadPrefix = 'install_apk:';

  // ── Notification ID constants ───────────────────────────────────────────────
  static const int notifIdLevelUp = 500;
  static const int notifIdRankPromotion = 501;
  static const int notifIdWeightReminder = 510;
  static const int notifIdCalorieGoal = 511;
  static const int notifIdDailyBrief = 512;
  static const int notifIdUpdateReady = 513;
  static const int notifIdBillsReminder = 600;
  // Per-credit-account due reminders occupy 620–719 (id derived from accountId).
  static const int notifIdCreditDueBase = 620;

  // ── Quest notification action buttons ───────────────────────────────────────
  /// Action button ids on quest notifications. Handled in a background isolate
  /// (showsUserInterface:false) so tapping them never opens the app.
  static const String questActionDone = 'quest_action_done';
  static const String questActionSnooze = 'quest_action_snooze';
  static const String questActionSkip = 'quest_action_skip';

  /// How long "Snooze" defers a quest reminder.
  static const int questSnoozeMinutes = 15;

  /// Notification-id offset for a snoozed quest, kept clear of the ranges used
  /// by the recurring/reminder/one-shot schedules (baseId+0..306, +10000).
  static const int _questSnoozeIdOffset = 20000;

  /// Set by the app so a foreground action tap drains the pending-actions queue
  /// immediately instead of waiting for the next resume. Null in a background
  /// isolate (fresh memory), where the drain happens on next foreground.
  static void Function()? onQuestActionDrain;

  // Budget warnings: stable int in 560–599. Must stay disjoint from the
  // credit-due range above — both derive ids from a hash, and the previous
  // 601–640 range overlapped 620–719, letting a budget warning and a credit
  // reminder collide on one id and silently replace/cancel each other.
  // (Safe to move: budget warnings are immediate show() notifications, not
  // persisted alarms, so no stale scheduled ids are left behind.)
  static int _budgetWarningId(String budgetId) =>
      budgetId.hashCode.abs() % 40 + 560;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// In-app master switch (mirrors NotificationPreferences.masterEnabled).
  /// Loaded by FastingPresenter at startup and flipped from the notification
  /// settings sheet. Every schedule/show method no-ops while this is false;
  /// cancel methods stay live so turning the switch off can clear alarms.
  bool _masterEnabled = true;
  bool get masterEnabled => _masterEnabled;

  /// Opens Android's per-app notification settings (for when notifications
  /// are blocked at the OS level and the in-app prompt can no longer appear).
  static const MethodChannel _systemSettingsChannel =
      MethodChannel('com.nudgr.app/system_settings');

  // Per-reminder signature of the last successful (re)schedule. Recurring
  // reminders get re-scheduled on every app resume / cloud-sync reload; when
  // the inputs haven't changed that's pure alarm-manager churn. We skip the
  // redundant cancel+reschedule when the signature matches. In-memory only, so
  // a cold start (fresh process) always reschedules once.
  final Map<String, String> _scheduleSignatures = {};

  /// True if [key] should be (re)scheduled — i.e. its [signature] changed since
  /// the last successful schedule this session. Records the new signature.
  bool _scheduleChanged(String key, String signature) {
    if (_scheduleSignatures[key] == signature) return false;
    _scheduleSignatures[key] = signature;
    return true;
  }

  /// Forget a reminder's signature so the next schedule call runs (e.g. after
  /// cancelling it, or when the master toggle flips and alarms were cleared).
  void _invalidateSchedule(String key) => _scheduleSignatures.remove(key);

  Future<void> setMasterEnabled(bool enabled) async {
    _masterEnabled = enabled;
    // Force a reschedule on the next call regardless of cached signatures:
    // disabling cancels everything, and re-enabling must re-register alarms.
    _scheduleSignatures.clear();
    if (!enabled) {
      await cancelAll();
    }
  }

  /// Whether Android currently allows this app to post notifications at all
  /// (POST_NOTIFICATIONS granted and the app/channel not blocked).
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || !_isInitialized) return false;
    final android =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Whether the "Alarms & reminders" special access is granted (needed for
  /// alarm-clock-mode scheduling to fire at exact times).
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb || !_isInitialized) return false;
    final android =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  Future<void> openSystemNotificationSettings() async {
    if (kIsWeb) return;
    try {
      await _systemSettingsChannel.invokeMethod('openNotificationSettings');
    } on PlatformException catch (e) {
      debugPrint('NotificationService: openNotificationSettings failed: $e');
    }
  }

  Future<void> init() async {
    // Web has no local-notification platform channel (Plan 042). Returning
    // early leaves `_isInitialized` false, so every schedule/show/cancel method
    // below — all already guarded by `if (!_isInitialized) return;` — becomes a
    // safe no-op. This keeps Stats/Budget/Bills presenters constructible on web
    // with zero call-site changes.
    if (kIsWeb) return;
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      // flutter_timezone 5.x returns a TimezoneInfo object whose IANA name is in
      // `.identifier` (e.g. "Asia/Manila"). Read it directly — do NOT parse
      // `.toString()`, whose format is not the IANA name and made
      // tz.getLocation() throw, silently falling back to UTC. With tz.local set
      // to UTC, a quest at 08:30 was scheduled as 08:30 UTC, which fires at
      // 16:30 in UTC+8 zones — the "wrong time" notification bug.
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final String tzName = timezoneInfo.identifier;
      debugPrint('NotificationService: Device timezone: $tzName');
      try {
        tz.setLocalLocation(tz.getLocation(tzName));
        debugPrint('NotificationService: Using timezone: $tzName');
      } catch (e) {
        debugPrint(
            'NotificationService: Error setting location $tzName: $e. Fallback to UTC.');
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

    // NOTE: must stay in sync with res/raw/keep.xml. Release builds run the
    // resource shrinker (isShrinkResources), which cannot see Dart-string
    // resource references — an icon not listed in keep.xml gets stripped and
    // every notification fails with invalid_icon in release builds only.
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Notification clicked: ${response.payload}');
        if (_handleInstallApkPayload(response.payload)) return;
        // Route action-button taps that were delivered to the main isolate
        // (some Android versions/states) through the same handler.
        if (response.actionId != null) {
          _handleQuestNotificationAction(response);
        }
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

      // 5. Character Achievements (level-up, rank promotion)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdAchievements,
          channelNameAchievements,
          description: 'Notifications for level-up and rank promotion',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // 6. Finance Alerts (bill reminders, budget warnings)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdFinance,
          channelNameFinance,
          description: 'Bill reminders and budget-over-limit warnings',
          importance: Importance.max,
          playSound: true,
          enableVibration: false,
        ),
      );

      // 7. System Analysis (morning daily-brief reminder)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdDailyBrief,
          channelNameDailyBrief,
          description: 'Morning reminder that your System Analysis is ready',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // 8. App Updates (OTA download-complete → install)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelIdUpdate,
          channelNameUpdate,
          description: 'New version downloaded and ready to install',
          importance: Importance.high,
          playSound: true,
          enableVibration: false,
        ),
      );

      debugPrint('NotificationService: Channels created.');
    }

    _isInitialized = true;
    debugPrint('NotificationService: Initialized');

    // A tap that launched the app from a terminated state is not delivered to
    // onDidReceiveNotificationResponse — it arrives here. Route update-ready
    // taps to the installer so the notification works after the app was
    // swiped away too.
    try {
      final launchDetails = await flutterLocalNotificationsPlugin
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _handleInstallApkPayload(launchDetails!.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('NotificationService: launch-details check failed: $e');
    }
  }

  /// Requests the POST_NOTIFICATIONS + exact-alarm permissions. Returns
  /// whether the app can actually post notifications afterwards, so callers
  /// can surface a "blocked by system" state instead of failing silently
  /// (Android stops showing the prompt after it has been denied).
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    await init(); // self-heal: no-op when already initialized
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

    if (granted != null) return granted;
    // Older Androids (<13) have no runtime permission — fall back to the
    // effective enabled state.
    return await androidImplementation?.areNotificationsEnabled() ?? false;
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
    await init(); // self-heal: no-op when already initialized
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
    if (!_isInitialized || !_masterEnabled) return;
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
    if (!_isInitialized || !_masterEnabled) return;
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
    if (!_isInitialized || !_masterEnabled) return;
    // Skip if this quest's schedule-relevant config is unchanged since the last
    // schedule this session — avoids re-registering the same alarms on every
    // app resume / sync reload. Cleared on cold start and on edit/cancel.
    final sig = [
      quest.recurrenceType.name,
      quest.hour,
      quest.minute,
      quest.days.map((d) => d ? '1' : '0').join(),
      quest.weeklyWeekday,
      quest.monthlyDays.join(','),
      quest.recurrenceAnchorDate,
      quest.reminderMinutes,
      quest.title,
    ].join('|');
    if (!_scheduleChanged('quest/${quest.id}', sig)) return;
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
      actions: _questActions(),
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

  /// Action buttons shown on quest notifications.
  ///
  /// "Mark as Done" uses [showsUserInterface] = true: the tap is delivered to
  /// the FOREGROUND isolate (bringing the app forward), where `onQuestActionDrain`
  /// is wired so the completion applies immediately (and the UI reflects it).
  /// With `showsUserInterface: false` the tap runs in a background isolate where
  /// that hook is null, so completion was only queued and deferred to the next
  /// app resume — which made the button appear to do nothing.
  ///
  /// Snooze/Skip stay background-only ([showsUserInterface] = false): Snooze
  /// reschedules a notification and Skip is a no-op on state, so neither needs
  /// the app open. [cancelNotification] dismisses the notification on tap.
  List<AndroidNotificationAction> _questActions() => const [
        AndroidNotificationAction(
          questActionDone,
          'Mark as Done',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          questActionSnooze,
          'Snooze 15m',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          questActionSkip,
          'Skip today',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];

  /// JSON payload carrying the quest identity for the action handler.
  String _questPayload(Quest quest) =>
      jsonEncode({'id': quest.id, 'title': quest.title});

  /// Reschedules a single quest reminder [questSnoozeMinutes] minutes from now,
  /// carrying the same action buttons and payload. Called by the snooze action.
  Future<void> showQuestSnooze(int questId, String title) async {
    if (!_isInitialized || !_masterEnabled) return;
    final when = tz.TZDateTime.now(tz.local)
        .add(const Duration(minutes: questSnoozeMinutes));
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdQuests,
      channelNameQuests,
      channelDescription: 'Recurring reminders for habits and quests',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      actions: _questActions(),
    );
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        questId + _questSnoozeIdOffset,
        title,
        "It's time for your quest!",
        when,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode({'id': questId, 'title': title}),
      );
    } catch (e) {
      debugPrint('NotificationService: Error scheduling snooze: $e');
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
          actions: _questActions(),
          payload: _questPayload(quest),
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
          payload: _questPayload(quest),
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
        actions: _questActions(),
        payload: _questPayload(quest),
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
        payload: _questPayload(quest),
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
        actions: _questActions(),
        payload: _questPayload(quest),
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
          actions: _questActions(),
          payload: _questPayload(quest),
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
          payload: _questPayload(quest),
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
        payload: _questPayload(quest),
      );
    } catch (e) {
      debugPrint(
          'NotificationService: Error scheduling reminder for "${quest.title}": $e');
    }
  }

  Future<void> cancelQuestNotifications(Quest quest) async {
    debugPrint(
        'NotificationService: Cancelling quest notifications for ${quest.title}');
    _invalidateSchedule('quest/${quest.id}');
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
    // Snoozed reminder (from the notification "Snooze 15m" action)
    await flutterLocalNotificationsPlugin.cancel(baseId + _questSnoozeIdOffset);
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

  // ── RPG Achievement notifications ────────────────────────────────────────────

  Future<void> showLevelUpNotification(int level, String rank) async {
    if (!_isInitialized || !_masterEnabled) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdAchievements,
      channelNameAchievements,
      channelDescription: 'Notifications for level-up and rank promotion',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await flutterLocalNotificationsPlugin.show(
      notifIdLevelUp,
      '⚔️ LEVEL UP — Lv. $level [$rank]',
      'Your power grows, Shadow.',
      const NotificationDetails(android: androidDetails),
    );
    debugPrint(
        'NotificationService: Level-up notification shown. Level=$level Rank=$rank');
  }

  Future<void> showRankPromotionNotification(
      String fromRank, String toRank) async {
    if (!_isInitialized || !_masterEnabled) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdAchievements,
      channelNameAchievements,
      channelDescription: 'Notifications for level-up and rank promotion',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await flutterLocalNotificationsPlugin.show(
      notifIdRankPromotion,
      '★ RANK PROMOTION — $fromRank → $toRank',
      'You have ascended.',
      const NotificationDetails(android: androidDetails),
    );
    debugPrint(
        'NotificationService: Rank-promotion notification shown. $fromRank → $toRank');
  }

  Future<void> cancelAchievementNotifications() async {
    if (!_isInitialized) return;
    await flutterLocalNotificationsPlugin.cancel(notifIdLevelUp);
    await flutterLocalNotificationsPlugin.cancel(notifIdRankPromotion);
  }

  // ── Nutrition notifications ─────────────────────────────────────────────────

  /// Schedule a daily weight-log reminder at [time]. Fires daily via
  /// [DateTimeComponents.time] — persists across app restarts automatically.
  Future<void> scheduleWeightReminder(TimeOfDay time) async {
    if (!_isInitialized || !_masterEnabled) return;
    if (!_scheduleChanged('weightReminder', '${time.hour}:${time.minute}')) {
      return;
    }
    await flutterLocalNotificationsPlugin.cancel(notifIdWeightReminder);

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdMilestones,
      channelNameMilestones,
      channelDescription: 'Fasting & Eating Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifIdWeightReminder,
        'Log your weight',
        'Keep your progress tracked — tap to open.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint(
          'NotificationService: Weight reminder scheduled for ${time.hour}:${time.minute.toString().padLeft(2, '0')} daily');
    } catch (e) {
      debugPrint('NotificationService: Error scheduling weight reminder: $e');
    }
  }

  Future<void> cancelWeightReminder() async {
    if (!_isInitialized) return;
    _invalidateSchedule('weightReminder');
    await flutterLocalNotificationsPlugin.cancel(notifIdWeightReminder);
  }

  /// Schedule a daily "System Analysis ready" reminder at [time]. Fires daily
  /// via [DateTimeComponents.time] — persists across app restarts. The brief
  /// itself is generated lazily on the next app open/resume (see
  /// [InsightsPresenter.generateDailyBriefIfDue]); this only nudges the user to
  /// open the Hub. Mirrors [scheduleWeightReminder].
  Future<void> scheduleDailyBriefReminder(TimeOfDay time) async {
    if (!_isInitialized || !_masterEnabled) return;
    if (!_scheduleChanged('dailyBrief', '${time.hour}:${time.minute}')) {
      return;
    }
    await flutterLocalNotificationsPlugin.cancel(notifIdDailyBrief);

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdDailyBrief,
      channelNameDailyBrief,
      channelDescription: 'Morning reminder that your System Analysis is ready',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifIdDailyBrief,
        'System Analysis ready',
        'Your morning briefing awaits in the Hub.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint(
          'NotificationService: Daily brief reminder scheduled for ${time.hour}:${time.minute.toString().padLeft(2, '0')} daily');
    } catch (e) {
      debugPrint(
          'NotificationService: Error scheduling daily brief reminder: $e');
    }
  }

  Future<void> cancelDailyBriefReminder() async {
    if (!_isInitialized) return;
    _invalidateSchedule('dailyBrief');
    await flutterLocalNotificationsPlugin.cancel(notifIdDailyBrief);
  }

  // ── OTA update notifications ─────────────────────────────────────────────────

  /// Fired when an update APK finishes downloading (even if the app is
  /// backgrounded). Tapping it routes the APK path straight to the package
  /// installer via [installApkPayloadPrefix].
  Future<void> showUpdateReadyNotification(
      String version, String apkPath) async {
    if (!_isInitialized || !_masterEnabled) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdUpdate,
      channelNameUpdate,
      channelDescription: 'New version downloaded and ready to install',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
    );
    await flutterLocalNotificationsPlugin.show(
      notifIdUpdateReady,
      'System Patch Ready',
      'Nudgr v$version downloaded — tap to install.',
      const NotificationDetails(android: androidDetails),
      payload: '$installApkPayloadPrefix$apkPath',
    );
    debugPrint(
        'NotificationService: Update-ready notification shown for v$version');
  }

  Future<void> cancelUpdateReadyNotification() async {
    if (!_isInitialized) return;
    await flutterLocalNotificationsPlugin.cancel(notifIdUpdateReady);
  }

  Future<void> showCalorieGoalNotification(int calories, int goal) async {
    if (!_isInitialized || !_masterEnabled) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdMilestones,
      channelNameMilestones,
      channelDescription: 'Fasting & Eating Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    await flutterLocalNotificationsPlugin.show(
      notifIdCalorieGoal,
      'Daily goal reached 🎯',
      '$calories / $goal kcal logged today.',
      const NotificationDetails(android: androidDetails),
    );
    debugPrint(
        'NotificationService: Calorie-goal notification shown. $calories/$goal kcal');
  }

  // ── Finance notifications ────────────────────────────────────────────────────

  /// Schedule a monthly bills reminder on [dayOfMonth] at 9 AM via
  /// [DateTimeComponents.dayOfMonthAndTime].
  Future<void> scheduleBillsReminder(int dayOfMonth) async {
    if (!_isInitialized || !_masterEnabled) return;
    final day = dayOfMonth.clamp(1, 28);
    if (!_scheduleChanged('billsReminder', '$day')) return;
    await flutterLocalNotificationsPlugin.cancel(notifIdBillsReminder);

    final scheduled = _nextInstanceOfMonthDay(day, 9, 0);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdFinance,
      channelNameFinance,
      channelDescription: 'Bill reminders and budget-over-limit warnings',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifIdBillsReminder,
        'Bills due this month',
        'Check your unpaid bills in Treasury.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
      debugPrint(
          'NotificationService: Bills reminder scheduled for day $day of month at 9 AM');
    } catch (e) {
      debugPrint('NotificationService: Error scheduling bills reminder: $e');
    }
  }

  Future<void> cancelBillsReminder() async {
    if (!_isInitialized) return;
    _invalidateSchedule('billsReminder');
    await flutterLocalNotificationsPlugin.cancel(notifIdBillsReminder);
  }

  /// Stable notification id for a credit account's due reminder, derived from
  /// its id so re-scheduling replaces the prior one rather than stacking.
  int _creditDueId(String accountId) =>
      notifIdCreditDueBase + (accountId.hashCode.abs() % 100);

  // Per-bill reminder ids live in a dedicated high range (5000–5999) to avoid
  // colliding with the credit-due (620–719) and budget-warning (560–599) ranges.
  static const int notifIdBillReminderBase = 5000;
  int _billReminderId(String billId) =>
      notifIdBillReminderBase + (billId.hashCode.abs() % 1000);

  /// Schedules a one-shot reminder [daysBefore] days before a bill's [dueDate]
  /// (at 9:00 AM). No-ops if the fire time is already in the past. Paired with
  /// [cancelBillReminder]. Gated by the master switch like every other schedule.
  Future<void> scheduleBillReminder({
    required String billId,
    required String billName,
    required DateTime dueDate,
    required int daysBefore,
  }) async {
    if (!_isInitialized || !_masterEnabled) return;
    final id = _billReminderId(billId);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0)
        .subtract(Duration(days: daysBefore));
    if (!_scheduleChanged(
        'billReminder/$billId', '${target.toIso8601String()}|$billName')) {
      return;
    }
    await flutterLocalNotificationsPlugin.cancel(id);
    // Nothing to schedule if the reminder moment has already passed.
    if (!target.isAfter(DateTime.now())) return;
    final scheduled = _getRelativeScheduledTime(target);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdFinance,
      channelNameFinance,
      channelDescription: 'Bill reminders and budget-over-limit warnings',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    final lead = daysBefore == 1 ? '1 day' : '$daysBefore days';

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        'Bill due soon',
        '$billName is due in $lead. Settle it in Treasury.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('NotificationService: Error scheduling bill reminder: $e');
    }
  }

  Future<void> cancelBillReminder(String billId) async {
    if (!_isInitialized) return;
    _invalidateSchedule('billReminder/$billId');
    await flutterLocalNotificationsPlugin.cancel(_billReminderId(billId));
  }

  /// Schedule a monthly reminder on a credit account's payment [dueDay] at 9 AM.
  Future<void> scheduleCreditDueReminder({
    required String accountId,
    required String accountName,
    required int dueDay,
  }) async {
    if (!_isInitialized || !_masterEnabled) return;
    final day = dueDay.clamp(1, 28);
    if (!_scheduleChanged('creditDue/$accountId', '$day|$accountName')) return;
    final id = _creditDueId(accountId);
    await flutterLocalNotificationsPlugin.cancel(id);

    final scheduled = _nextInstanceOfMonthDay(day, 9, 0);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdFinance,
      channelNameFinance,
      channelDescription: 'Bill reminders and budget-over-limit warnings',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        'Credit payment due',
        '$accountName payment is due today. Settle it in Treasury.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    } catch (e) {
      debugPrint(
          'NotificationService: Error scheduling credit due reminder: $e');
    }
  }

  Future<void> cancelCreditDueReminder(String accountId) async {
    if (!_isInitialized) return;
    _invalidateSchedule('creditDue/$accountId');
    await flutterLocalNotificationsPlugin.cancel(_creditDueId(accountId));
  }

  Future<void> showBudgetWarning(
    String budgetId,
    String budgetName,
    double spent,
    double limit,
    int thresholdPercent,
  ) async {
    if (!_isInitialized || !_masterEnabled) return;
    final id = _budgetWarningId(budgetId);
    final spentLabel = spent.toStringAsFixed(0);
    final limitLabel = limit.toStringAsFixed(0);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelIdFinance,
      channelNameFinance,
      channelDescription: 'Bill reminders and budget-over-limit warnings',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: false,
    );
    await flutterLocalNotificationsPlugin.show(
      id,
      'Budget alert — $budgetName',
      '$thresholdPercent% of limit reached ($spentLabel / $limitLabel).',
      const NotificationDetails(android: androidDetails),
    );
    debugPrint(
        'NotificationService: Budget warning shown for "$budgetName" (id=$id)');
  }

  Future<void> cancelBudgetWarning(String budgetId) async {
    if (!_isInitialized) return;
    await flutterLocalNotificationsPlugin.cancel(_budgetWarningId(budgetId));
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
    List<AndroidNotificationAction>? actions,
    String? payload,
  }) async {
    // Central backstop: every scheduled notification funnels through here.
    if (!_isInitialized || !_masterEnabled) return;
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
      actions: actions,
    );
    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    // If the target time is already now/past, SKIP — do not fire it here.
    // This method is re-run on every app open / sync (reschedule), so showing
    // a now/past one-shot immediately made quests re-notify on every reopen.
    // The real fire happens via the recurring zonedSchedule at the actual time;
    // a moment that has already passed should not be resurfaced on launch.
    if (scheduledDate.isBefore(now.add(const Duration(seconds: 5)))) {
      debugPrint(
          'NotificationService: Skipping one-shot $id ($title) — target is now/past ($scheduledDate); not firing on reschedule');
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
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService: Error scheduling notification $id: $e');
    }
  }
}
