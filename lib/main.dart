import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

// --- Notification Setup ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Handle background notification tap if needed
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (details) {},
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  runApp(const FastingApp());
}

class FastingApp extends StatelessWidget {
  const FastingApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: brightness,
    );

    final scaffoldShade = brightness == Brightness.light
        ? Color.alphaBlend(Colors.white.withOpacity(0.45), scheme.surface)
        : Color.alphaBlend(Colors.white.withOpacity(0.04), scheme.surface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldShade,
      canvasColor: scaffoldShade,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldShade,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(0.15),
        labelTextStyle: MaterialStateProperty.all(
          TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nudgr',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Future<void> _sendTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Channel for test notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      9999,
      'Nudgr Test Notification',
      'This is a test notification. Notifications are working!',
      details,
    );
  }

  Future<void> _sendFullScreenAlarmNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'alarm_channel',
      'Alarms',
      channelDescription: 'Channel for alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      10001,
      'Alarm!',
      'This is a disruptive alarm notification!',
      details,
    );
  }
  // --- Fasting State ---
  bool _isFasting = false;
  DateTime? _startTime;
  DateTime? _eatingStartTime;
  int _elapsedSeconds = 0;
  int _fastingGoalHours = 16;
  List<Map<String, dynamic>> _history = [];
  Timer? _ticker;

  // --- Habits/Reminders State ---
  // Updated Structure:
  // {
  //   'id': int,
  //   'title': String,
  //   'hour': int,
  //   'minute': int,
  //   'isEnabled': bool,
  //   'days': List<bool> (Length 7, [Mon, Tue, Wed...])
  // }
  List<Map<String, dynamic>> _reminders = [];

  // --- UI State ---
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateTimer();
    }
  }

  Future<void> _requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
  }

  // --- Persistence ---

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Load Fasting Data
      _isFasting = prefs.getBool('isFasting') ?? false;
      String? startStr = prefs.getString('startTime');
      _startTime = startStr != null ? DateTime.parse(startStr) : null;

      String? eatStr = prefs.getString('eatingStartTime');
      _eatingStartTime = eatStr != null ? DateTime.parse(eatStr) : null;

      _fastingGoalHours = prefs.getInt('goal') ?? 16;

      String? histStr = prefs.getString('history');
      if (histStr != null) {
        List<dynamic> decoded = jsonDecode(histStr);
        _history = decoded.map((item) {
          Map<String, dynamic> map = Map<String, dynamic>.from(item);

          // Migrate old format to new format
          if (map.containsKey('start') && !map.containsKey('fastStart')) {
            // Old format detected, convert it
            map['fastStart'] = map['start'];
            map['fastEnd'] = map['end'];
            map['fastDuration'] = map['duration'];
            map['eatingStart'] = map['end']; // Eating starts when old fast ended
            map['eatingEnd'] = null;
            map['eatingDuration'] = null;

            // Remove old keys
            map.remove('start');
            map.remove('end');
            map.remove('duration');
          }

          return map;
        }).toList();
      }

      // Load Reminders Data
      String? remStr = prefs.getString('reminders');
      if (remStr != null) {
        List<dynamic> decoded = jsonDecode(remStr);
        _reminders = decoded.map((item) {
          Map<String, dynamic> map = Map<String, dynamic>.from(item);
          // Backward compatibility: If 'days' is missing, assume Daily (all true)
          if (!map.containsKey('days')) {
            map['days'] = List.generate(7, (index) => true);
          } else {
            map['days'] = List<bool>.from(map['days']);
          }
          return map;
        }).toList();
      }
    });

    if (_isFasting || _eatingStartTime != null) {
      _startTicker();
    }

    // Save migrated data
    _saveState();
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    // Save Fasting
    await prefs.setBool('isFasting', _isFasting);
    if (_startTime != null) {
      await prefs.setString('startTime', _startTime!.toIso8601String());
    } else {
      await prefs.remove('startTime');
    }
    if (_eatingStartTime != null) {
      await prefs.setString('eatingStartTime', _eatingStartTime!.toIso8601String());
    } else {
      await prefs.remove('eatingStartTime');
    }
    await prefs.setInt('goal', _fastingGoalHours);
    await prefs.setString('history', jsonEncode(_history));

    // Save Reminders
    await prefs.setString('reminders', jsonEncode(_reminders));
  }

  // --- Fasting Logic ---

  void _startTicker() {
    _ticker?.cancel();
    _updateTimer();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimer());
  }

  void _updateTimer() {
    final now = DateTime.now();
    int newElapsed = 0;

    if (_isFasting && _startTime != null) {
      newElapsed = now.difference(_startTime!).inSeconds;
    } else if (_eatingStartTime != null) {
      newElapsed = now.difference(_eatingStartTime!).inSeconds;
    }

    // Update state variable
    _elapsedSeconds = newElapsed;

    // Only rebuild the UI if we are on the Timer tab (index 0)
    if (_selectedIndex == 0 && mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleFast() async {
    if (_isFasting) {
      // End Fast - Start Eating Window
      DateTime endTime = DateTime.now();
      double durationHours = _elapsedSeconds / 3600;

      Map<String, dynamic> log = {
        'fastStart': _startTime!.toIso8601String(),
        'fastEnd': endTime.toIso8601String(),
        'fastDuration': durationHours,
        'goal': _fastingGoalHours,
        'success': durationHours >= _fastingGoalHours,
        'eatingStart': endTime.toIso8601String(), // Eating starts when fast ends
        'eatingEnd': null, // Will be filled when next fast starts
        'eatingDuration': null,
      };

      setState(() {
        _history.insert(0, log);
        _isFasting = false;
        _startTime = null;
        _eatingStartTime = DateTime.now();
        _elapsedSeconds = 0;
      });

      await flutterLocalNotificationsPlugin.cancel(0);
      await _scheduleEatingAlarm();

    } else {
      // Start Fast - End Eating Window
      DateTime fastStartTime = DateTime.now();

      // Update the previous record's eating window if it exists
      if (_eatingStartTime != null && _history.isNotEmpty) {
        double eatingDurationHours = fastStartTime.difference(_eatingStartTime!).inSeconds / 3600;
        setState(() {
          _history[0]['eatingEnd'] = fastStartTime.toIso8601String();
          _history[0]['eatingDuration'] = eatingDurationHours;
        });
      }

      setState(() {
        _isFasting = true;
        _startTime = fastStartTime;
        _eatingStartTime = null;
        _elapsedSeconds = 0;
      });
      _startTicker();
      await flutterLocalNotificationsPlugin.cancel(1);
      await _scheduleFastingAlarm();
    }
    _saveState();
  }

  Future<void> _skipEatingWindow() async {
    setState(() {
      _eatingStartTime = null;
      _elapsedSeconds = 0;
    });
    await flutterLocalNotificationsPlugin.cancel(1);
    _saveState();
  }

  // --- Reminder Logic ---

  Future<void> _addReminder() async {
    // All-in-one dialog for title, time, and days
    String? title;
    TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);
    List<bool> days = List.filled(7, true);
    const dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    bool submitted = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        TextEditingController controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("New Habit"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Title"),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: "e.g., Jogging, Meds"),
                      autofocus: true,
                    ),
                    const SizedBox(height: 20),
                    const Text("Time"),
                    InkWell(
                      onTap: () async {
                        TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (picked != null) {
                          setState(() {
                            time = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.neutral),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(time.format(context), style: const TextStyle(fontSize: 16)),
                            const Icon(Icons.access_time, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("Repeat on"),
                    Column(
                      children: List.generate(7, (index) {
                        return CheckboxListTile(
                          title: Text(dayLabels[index]),
                          value: days[index],
                          onChanged: (val) {
                            setState(() => days[index] = val ?? false);
                          },
                          dense: true,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    title = controller.text.trim();
                    if (title == null || title!.isEmpty) {
                      // Optionally show error
                      return;
                    }
                    submitted = true;
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (!submitted || title == null || title!.isEmpty) return;

    int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Map<String, dynamic> newReminder = {
      'id': id,
      'title': title,
      'hour': time.hour,
      'minute': time.minute,
      'isEnabled': true,
      'days': days,
    };

    setState(() {
      _reminders.add(newReminder);
    });
    _saveState();
    _scheduleHabitNotifications(newReminder);
  }

  Future<void> _deleteReminder(int index) async {
    Map<String, dynamic> item = _reminders[index];
    await _cancelHabitNotifications(item);
    setState(() {
      _reminders.removeAt(index);
    });
    _saveState();
  }

  Future<void> _toggleReminder(int index, bool value) async {
    setState(() {
      _reminders[index]['isEnabled'] = value;
    });
    _saveState();

    if (value) {
      _scheduleHabitNotifications(_reminders[index]);
    } else {
      await _cancelHabitNotifications(_reminders[index]);
    }
  }

  // --- Advanced Notification Scheduling ---

  Future<void> _scheduleFastingAlarm() async {
    final scheduledDate = tz.TZDateTime.from(
      _startTime!.add(Duration(hours: _fastingGoalHours)),
      tz.local,
    );
    await _scheduleOneShotNotification(0, "Fasting Goal Reached! 🏆", "Time to eat!", scheduledDate, fullScreen: true);
    // Schedule notifications for every 2 hours fasted
    // Fasting effect milestones
    final Map<int, Map<String, String>> fastingEffects = {
      12: {'title': 'Fat Burning Starts', 'body': 'Your body is now burning fat for energy.'},
      16: {'title': 'Deeper Ketosis', 'body': 'You are entering deeper ketosis.'},
      18: {'title': 'Autophagy Increases', 'body': 'Cellular repair (autophagy) is increasing.'},
      24: {'title': 'Significant Autophagy', 'body': 'Significant autophagy and cell renewal.'},
    };
    for (int h = 2; h < _fastingGoalHours; h += 2) {
      final notifTime = tz.TZDateTime.from(_startTime!.add(Duration(hours: h)), tz.local);
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
        100 + h, // unique ID for each interval
        title,
        body,
        notifTime,
        groupKey: 'fasting_group',
      );
    }
  }

  Future<void> _scheduleEatingAlarm() async {
    int eatingWindow = 24 - _fastingGoalHours;
    if (eatingWindow <= 0 || _eatingStartTime == null) {
      return;
    }
    final scheduledDate = tz.TZDateTime.from(
      _eatingStartTime!.add(Duration(hours: eatingWindow)),
      tz.local,
    );
    await _scheduleOneShotNotification(1, "Eating Window Over 🍽️", "Time to start fasting!", scheduledDate, fullScreen: true);

    // Schedule notifications for every hour remaining in eating window
    for (int h = eatingWindow - 1; h > 0; h--) {
      final notifTime = tz.TZDateTime.from(_eatingStartTime!.add(Duration(hours: eatingWindow - h)), tz.local);
      await _scheduleOneShotNotification(
        200 + h, // unique ID for each interval
        "$h hour${h == 1 ? '' : 's'} left to eat",
        "You have $h hour${h == 1 ? '' : 's'} left in your eating window.",
        notifTime,
        groupKey: 'eating_group',
      );
    }
  }

  Future<void> _scheduleHabitNotifications(Map<String, dynamic> item) async {
    // item['days'] is List<bool> [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
    // We schedule a separate notification for each active day
    List<bool> days = List<bool>.from(item['days']);
    int baseId = item['id']; // e.g. 170000000

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'habits_channel',
      'Daily Habits',
      channelDescription: 'Recurring reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500, 250, 500]),
      sound: RawResourceAndroidNotificationSound('notification'), // Use 'notification' from res/raw/notification.mp3 if present, else default
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);

    for (int i = 0; i < 7; i++) {
      if (days[i]) {
        // i=0 is Monday, i=6 is Sunday.
        // timezone package uses 1=Mon, 7=Sun. So we use i+1.
        int dayOfWeekISO = i + 1;

        // Calculate next instance of this day
        tz.TZDateTime scheduledDate = _nextInstanceOfDay(dayOfWeekISO, item['hour'], item['minute']);

        // Unique ID for this specific day: Base ID + Day Index (0-6)
        // We assume baseId is large enough or spaced enough (seconds timestamp)
        int notificationId = baseId + i;

        await flutterLocalNotificationsPlugin.zonedSchedule(
          notificationId,
          item['title'],
          "It's time for your habit!",
          scheduledDate,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Repeats weekly on this day
        );
      }
    }
  }

  Future<void> _cancelHabitNotifications(Map<String, dynamic> item) async {
    int baseId = item['id'];
    // Cancel all 7 potential slots
    for (int i = 0; i < 7; i++) {
      await flutterLocalNotificationsPlugin.cancel(baseId + i);
    }
  }

  tz.TZDateTime _nextInstanceOfDay(int dayOfWeek, int hour, int minute) {
    tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // Move to correct day
    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    // If today is the day but time passed, add 7 days
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }
    return scheduledDate;
  }

  Future<void> _scheduleOneShotNotification(int id, String title, String body, tz.TZDateTime scheduledDate, {String? groupKey, bool fullScreen = false}) async {
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'fasting_channel',
      'Fasting Timer',
      channelDescription: 'Notifications for fasting goals',
      importance: Importance.max,
      priority: Priority.high,
      groupKey: groupKey,
      fullScreenIntent: fullScreen,
      playSound: true,
      enableVibration: true,
    );
    NotificationDetails details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id, title, body, scheduledDate, details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // --- UI Components ---

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildTimerView(),
      _buildHistoryView(),
      _buildHabitsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Settings'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.science, color: AppColors.primary),
                        title: const Text('Add Test Data'),
                        subtitle: const Text('Add sample fasting records'),
                        onTap: () {
                          Navigator.pop(context);
                          _addTestData();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.notifications_active, color: AppColors.primary),
                        title: const Text('Send Test Notification'),
                        subtitle: const Text('Check if notifications work'),
                        onTap: () async {
                          Navigator.pop(context);
                          await _sendTestNotification();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.alarm, color: AppColors.primary),
                        title: const Text('Send Full-Screen Alarm Notification'),
                        subtitle: const Text('Test disruptive alarm notification'),
                        onTap: () async {
                          Navigator.pop(context);
                          await _sendFullScreenAlarmNotification();
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: AppColors.neutral),
                        title: const Text('Clear All Data'),
                        subtitle: const Text('Delete all fasting history and habits'),
                        onTap: () async {
                          Navigator.pop(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirm Reset'),
                              content: const Text('This will delete ALL your data including fasting history and habits. This cannot be undone!'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.neutral),
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            setState(() {
                              _history.clear();
                              _reminders.clear();
                              _isFasting = false;
                              _startTime = null;
                              _eatingStartTime = null;
                              _elapsedSeconds = 0;
                              _fastingGoalHours = 16;
                              _ticker?.cancel();
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('All data cleared successfully')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 2
          ? FloatingActionButton(
        onPressed: _addReminder,
        child: const Icon(Icons.add),
      )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer),
              label: 'Fasting'
          ),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'
          ),
          NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle),
              label: 'Habits'
          ),
        ],
      ),
    );
  }

  void _addTestData() {
    final now = DateTime.now();

    setState(() {
      // Test 1: Fast that spans midnight (yesterday 10 PM to today 2 PM = 16h)
      final test1FastStart = now.subtract(const Duration(days: 1, hours: 10));
      final test1FastEnd = now.subtract(const Duration(hours: 10));
      final test1EatingEnd = now.subtract(const Duration(hours: 2));
      _history.add({
        'fastStart': test1FastStart.toIso8601String(),
        'fastEnd': test1FastEnd.toIso8601String(),
        'fastDuration': 16.0,
        'goal': 16,
        'success': true,
        'eatingStart': test1FastEnd.toIso8601String(),
        'eatingEnd': test1EatingEnd.toIso8601String(),
        'eatingDuration': 8.0,
      });

      // Test 2: Incomplete fast (yesterday 8 AM to 6 PM = 10h of 16h goal)
      final test2FastStart = now.subtract(const Duration(days: 2, hours: 16));
      final test2FastEnd = now.subtract(const Duration(days: 2, hours: 6));
      final test2EatingEnd = now.subtract(const Duration(days: 1, hours: 22));
      _history.add({
        'fastStart': test2FastStart.toIso8601String(),
        'fastEnd': test2FastEnd.toIso8601String(),
        'fastDuration': 10.0,
        'goal': 16,
        'success': false,
        'eatingStart': test2FastEnd.toIso8601String(),
        'eatingEnd': test2EatingEnd.toIso8601String(),
        'eatingDuration': 8.0,
      });

      // Test 3: OMAD (24h fast) - 3 days ago
      final test3FastStart = now.subtract(const Duration(days: 3, hours: 20));
      final test3FastEnd = now.subtract(const Duration(days: 2, hours: 20));
      final test3EatingEnd = now.subtract(const Duration(days: 2, hours: 19));
      _history.add({
        'fastStart': test3FastStart.toIso8601String(),
        'fastEnd': test3FastEnd.toIso8601String(),
        'fastDuration': 24.0,
        'goal': 24,
        'success': true,
        'eatingStart': test3FastEnd.toIso8601String(),
        'eatingEnd': test3EatingEnd.toIso8601String(),
        'eatingDuration': 1.0,
      });

      // Test 4: 18:6 fast - 4 days ago
      final test4FastStart = now.subtract(const Duration(days: 4, hours: 14));
      final test4FastEnd = now.subtract(const Duration(days: 3, hours: 20));
      final test4EatingEnd = now.subtract(const Duration(days: 3, hours: 14));
      _history.add({
        'fastStart': test4FastStart.toIso8601String(),
        'fastEnd': test4FastEnd.toIso8601String(),
        'fastDuration': 18.0,
        'goal': 18,
        'success': true,
        'eatingStart': test4FastEnd.toIso8601String(),
        'eatingEnd': test4EatingEnd.toIso8601String(),
        'eatingDuration': 6.0,
      });

      // Test 5: Extended fast (20:4) - 5 days ago
      final test5FastStart = now.subtract(const Duration(days: 5, hours: 18));
      final test5FastEnd = now.subtract(const Duration(days: 4, hours: 22));
      final test5EatingEnd = now.subtract(const Duration(days: 4, hours: 18));
      _history.add({
        'fastStart': test5FastStart.toIso8601String(),
        'fastEnd': test5FastEnd.toIso8601String(),
        'fastDuration': 20.0,
        'goal': 20,
        'success': true,
        'eatingStart': test5FastEnd.toIso8601String(),
        'eatingEnd': test5EatingEnd.toIso8601String(),
        'eatingDuration': 4.0,
      });

      // Test 6: Ongoing eating window (no eatingEnd) - most recent
      final test6FastStart = now.subtract(const Duration(hours: 20));
      final test6FastEnd = now.subtract(const Duration(hours: 4));
      _history.insert(0, {
        'fastStart': test6FastStart.toIso8601String(),
        'fastEnd': test6FastEnd.toIso8601String(),
        'fastDuration': 16.0,
        'goal': 16,
        'success': true,
        'eatingStart': test6FastEnd.toIso8601String(),
        'eatingEnd': null,
        'eatingDuration': null,
      });
    });

    _saveState();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Added 6 test fasting records!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ... (Timer View Logic same as before)
  Widget _buildTimerView() {
    // Copied from previous logic to keep file complete
    double progress = 0.0;
    int targetSeconds = 1;
    String statusLabel = "Ready?";
    int eatingHours = 24 - _fastingGoalHours;
    if (eatingHours < 0) eatingHours = 0;
    final bool hasEatingWindow = eatingHours > 0;
    int eatingRemainingSeconds = 0;
    double eatingElapsedPercent = 0;

    if (_isFasting) {
      targetSeconds = _fastingGoalHours * 3600;
      progress = (_elapsedSeconds / targetSeconds);
      statusLabel = "Fasting Time";
    } else if (_eatingStartTime != null) {
      final int eatingTargetSeconds = hasEatingWindow ? eatingHours * 3600 : 1;
      targetSeconds = eatingTargetSeconds;
      if (hasEatingWindow) {
        eatingRemainingSeconds = eatingTargetSeconds - _elapsedSeconds;
        if (eatingRemainingSeconds < 0) eatingRemainingSeconds = 0;
        progress = eatingTargetSeconds > 0 ? (eatingRemainingSeconds / eatingTargetSeconds) : 0;
        eatingElapsedPercent = eatingTargetSeconds > 0 ? (_elapsedSeconds / eatingTargetSeconds) : 0;
        if (eatingElapsedPercent < 0) eatingElapsedPercent = 0;
        if (eatingElapsedPercent > 1) eatingElapsedPercent = 1;
      } else {
        eatingRemainingSeconds = 0;
        progress = 0;
        eatingElapsedPercent = 0;
      }
      statusLabel = hasEatingWindow ? "Eating Window Left" : "Eating Window Disabled";
    }
    if (progress > 1.0) progress = 1.0;

    final theme = Theme.of(context);
    final Color fastingAccent = theme.colorScheme.primary;
    final Color eatingAccent = Colors.orange.shade300;
    final bool showEatingProgress = _eatingStartTime != null && hasEatingWindow;
    final bool showProgressLabel = _isFasting || showEatingProgress;
    final String timerDisplay = _isFasting
        ? _formatTime(_elapsedSeconds)
        : (_eatingStartTime != null
        ? (hasEatingWindow ? _formatTime(eatingRemainingSeconds) : '00:00:00')
        : "$_fastingGoalHours:00:00");
    double displayProgress = (_isFasting || _eatingStartTime != null)
        ? progress
        : 0.0;
    displayProgress = math.max(0.0, math.min(1.0, displayProgress));

    final bool reverseProgress = !_isFasting && _eatingStartTime != null;

    final timerCore = Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: _PartialRingPainter(
              progress: displayProgress,
              trackColor: theme.colorScheme.surfaceContainerHighest,
              progressColor: _isFasting
                  ? fastingAccent
                  : (_eatingStartTime != null ? eatingAccent : Colors.grey),
              strokeWidth: 20,
              reverse: reverseProgress,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(statusLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              timerDisplay,
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            if (showProgressLabel)
              Text(
                _isFasting
                    ? "${(progress * 100).toInt()}%"
                    : "${(eatingElapsedPercent * 100).toInt()}% elapsed",
                style: theme.textTheme.titleLarge?.copyWith(
                  color: _isFasting ? fastingAccent : eatingAccent,
                ),
              ),
          ],
        )
      ],
    );

    Widget? leftPanel;
    Widget? rightPanel;

    if (_isFasting && _startTime != null) {
      final start = _startTime!;
      leftPanel = _buildTimerInfoPanel(
        title: 'Started',
        value: _format12Hour(start),
        accentColor: fastingAccent,
        onEdit: _editCurrentFastingTime,
      );
      rightPanel = _buildTimerInfoPanel(
        title: 'Goal End',
        value: _format12Hour(start.add(Duration(hours: _fastingGoalHours))),
        accentColor: fastingAccent,
      );
    } else if (_eatingStartTime != null) {
      final eatingStart = _eatingStartTime!;
      leftPanel = _buildTimerInfoPanel(
        title: 'Window Start',
        value: _format12Hour(eatingStart),
        accentColor: eatingAccent,
        onEdit: _editCurrentEatingTime,
      );
      rightPanel = _buildTimerInfoPanel(
        title: 'Window End',
        value: _format12Hour(eatingStart.add(Duration(hours: 24 - _fastingGoalHours))),
        accentColor: eatingAccent,
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_isFasting)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: ToggleButtons(
                isSelected: [16, 18, 20, 24].map((e) => e == _fastingGoalHours).toList(),
                onPressed: (int index) {
                  setState(() {
                    _fastingGoalHours = [16, 18, 20, 24][index];
                  });
                  _saveState();
                },
                borderRadius: BorderRadius.circular(10),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("16:8")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("18:6")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("20:4")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("OMAD")),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: timerCore,
                    ),
                    if (leftPanel != null || rightPanel != null) ...[
                      const SizedBox(height: 16), // reduced from 32
                      IntrinsicHeight(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (leftPanel != null)
                              Expanded(child: leftPanel!),
                            if (rightPanel != null)
                              Expanded(child: rightPanel!),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20), // reduced from 40
                    SizedBox(
                      width: double.infinity,
                      height: 56, // slightly reduced from 60
                      child: FilledButton(
                        onPressed: _toggleFast,
                        style: FilledButton.styleFrom(
                          backgroundColor: _isFasting
                              ? fastingAccent
                              : (_eatingStartTime != null
                              ? eatingAccent
                              : theme.colorScheme.primary),
                        ),
                        child: Text(
                          _isFasting ? "END FAST" : "START FAST",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (_eatingStartTime != null && !_isFasting && hasEatingWindow) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _skipEatingWindow,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey,
                          ),
                          child: const Text("Skip / Pause Today"),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerInfoPanel({
    required String title,
    required String value,
    Color? accentColor,
    VoidCallback? onEdit,
  }) {
    final color = accentColor ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.neutral,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: color,
                  ),
                ),
              ),
              if (onEdit != null)
                Positioned(
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Edit $title',
                    splashRadius: 18,
                    onPressed: onEdit,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHabitsView() {
    if (_reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notification_add_outlined, size: 64, color: AppColors.neutral),
            const SizedBox(height: 16),
            const Text("No habits yet."),
            TextButton(onPressed: _addReminder, child: const Text("Add your first habit"))
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _reminders.length,
      itemBuilder: (context, index) {
        final item = _reminders[index];
        final timeStr = "${item['hour'].toString().padLeft(2,'0')}:${item['minute'].toString().padLeft(2,'0')}";

        // Generate Days Text string
        String daysText = "Daily";
        List<bool> days = List<bool>.from(item['days']);
        if (days.every((d) => !d)) {
          daysText = "Never";
        } else if (!days.every((d) => d)) {
          const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
          daysText = "";
          for(int i=0; i<7; i++) {
            if (days[i]) daysText += "${labels[i]} ";
          }
        }

        return Dismissible(
          key: Key(item['id'].toString()),
          background: Container(color: AppColors.primary, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (direction) => _deleteReminder(index),
          child: ListTile(
            leading: Icon(
              item['isEnabled'] ? Icons.alarm_on : Icons.alarm_off,
              color: item['isEnabled'] ? AppColors.primary : AppColors.neutral,
            ),
            title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("$timeStr • $daysText"),
            trailing: Switch(
                value: item['isEnabled'],
                onChanged: (val) => _toggleReminder(index, val)
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryView() {
    if (_history.isEmpty) {
      return const Center(child: Text("No fasts recorded yet."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final log = _history[index];
        final fastStart = DateTime.parse(log['fastStart']);
        final fastEnd = DateTime.parse(log['fastEnd']);
        final fastDuration = log['fastDuration'] as double;
        final isSuccess = log['success'] as bool;

        // Eating window data (might be null for the most recent/ongoing cycle)
        final eatingStart = DateTime.parse(log['eatingStart']);
        final eatingEnd = log['eatingEnd'] != null ? DateTime.parse(log['eatingEnd']) : null;
        final eatingDuration = log['eatingDuration'] as double?;
        final hasEatingData = eatingEnd != null && eatingDuration != null;
        final note = log['note'] as String?;

        // Check if fast spans multiple days
        final fastStartDate = DateTime(fastStart.year, fastStart.month, fastStart.day);
        final fastEndDate = DateTime(fastEnd.year, fastEnd.month, fastEnd.day);
        final fastSpansMultipleDays = !isSameDay(fastStartDate, fastEndDate);

        // Calculate date header
        String dateHeader;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final tomorrow = today.add(const Duration(days: 1));

        // Helper to get day name
        String getDayName(DateTime date) {
          const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
          return days[date.weekday - 1];
        }

        // Calculate difference in days
        final daysDifference = fastStartDate.difference(today).inDays;

        if (isSameDay(fastStartDate, today)) {
          dateHeader = 'Today';
        } else if (isSameDay(fastStartDate, yesterday)) {
          dateHeader = 'Yesterday';
        } else if (isSameDay(fastStartDate, tomorrow)) {
          dateHeader = 'Tomorrow';
        } else if (daysDifference >= -6 && daysDifference <= 6) {
          // Within a week, show day name
          dateHeader = getDayName(fastStartDate);
        } else if (isSameDay(fastStartDate, fastEndDate)) {
          dateHeader = '${fastStart.month}/${fastStart.day}';
        } else {
          dateHeader = '${fastStart.month}/${fastStart.day} - ${fastEnd.month}/${fastEnd.day}';
        }

        return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              elevation: 2,
              child: InkWell(
                onLongPress: () => _showHistoryContextMenu(context, index),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateHeader,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.more_horiz, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showHistoryContextMenu(context, index),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Summary Line
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${fastDuration.round()}:${eatingDuration?.round() ?? (24 - fastDuration).round()} Fast',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                             decoration: BoxDecoration(
                               color: (isSuccess ? Colors.green : Colors.orange).withOpacity(0.1),
                               borderRadius: BorderRadius.circular(20),
                               border: Border.all(
                                 color: isSuccess ? Colors.green : Colors.orange,
                                 width: 2,
                               ),
                             ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSuccess ? Icons.check_circle : Icons.cancel,
                                  color: isSuccess ? Colors.green : Colors.orange,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isSuccess ? 'Achieved' : 'Incomplete',
                                  style: TextStyle(
                                    color: isSuccess ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Timeline Flow
                      Row(
                        children: [
                          // Fast Start
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _format12Hour(fastStart),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                                Text(
                                  '${fastStart.month}/${fastStart.day}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.neutral,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                             child: Icon(
                               Icons.arrow_forward,
                               color: AppColors.neutral,
                               size: 16,
                             ),
                          ),
                          // Switch Point (Fast End = Eating Start)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Switch',
                                  style: TextStyle(
                                    color: AppColors.neutral,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _format12Hour(fastEnd),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.green,
                                  ),
                                ),
                                if (fastSpansMultipleDays)
                                  Text(
                                    '${fastEnd.month}/${fastEnd.day}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.neutral,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(
                              Icons.arrow_forward,
                              color: AppColors.neutral,
                              size: 16,
                            ),
                          ),
                          // Eating End
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Finish',
                                  style: TextStyle(
                                    color: AppColors.neutral,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (hasEatingData) ...[
                                  Text(
                                    _format12Hour(eatingEnd),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  if (!isSameDay(eatingStart, eatingEnd))
                                    Text(
                                      '${eatingEnd.month}/${eatingEnd.day}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.neutral,
                                      ),
                                    ),
                                ] else ...[
                                  Text(
                                    'Ongoing',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.neutral,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Combined Timeline Bar (Fasting + Eating)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: double.infinity,
                              height: 40,
                              child: Row(
                                children: [
                                  // Fasting portion
                                  Expanded(
                                    flex: (fastDuration * 100).toInt(),
                                    child: Container(
                                      color: AppColors.primary,
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.nightlight_round,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${fastDuration.toStringAsFixed(1)}h',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Eating portion
                                  if (hasEatingData)
                                    Expanded(
                                      flex: (eatingDuration * 100).toInt(),
                                      child: Container(
                                        color: Colors.green,
                                        alignment: Alignment.center,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.restaurant,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${eatingDuration.toStringAsFixed(1)}h',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  else
                                    Expanded(
                                      flex: ((24 - fastDuration) * 100).toInt(),
                                      child: Container(
                                        color: AppColors.neutral,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Note display
                      if (note != null && note.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          '"$note"',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.neutral,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
        );

      },
    );
  }

  void _showHistoryContextMenu(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.pop(context);
                        _editHistoryTimes(index);
                      },
                    ),
                    const Text('Edit Times', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.note_add),
                      onPressed: () {
                        Navigator.pop(context);
                        _editHistoryNote(index);
                      },
                    ),
                    const Text('Add Note', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteHistoryEntry(index);
                      },
                    ),
                    const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editHistoryTimes(int index) async {
    final log = _history[index];
    final fastStart = DateTime.parse(log['fastStart']);
    final fastEnd = DateTime.parse(log['fastEnd']);
    final eatingEnd = log['eatingEnd'] != null ? DateTime.parse(log['eatingEnd']) : null;

    DateTime newFastStart = fastStart;
    DateTime newFastEnd = fastEnd;
    DateTime? newEatingEnd = eatingEnd;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Times'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Fast Start
                      const Text('Fast Start', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.dateAndTime,
                          initialDateTime: newFastStart,
                          maximumDate: DateTime.now(),
                          onDateTimeChanged: (DateTime value) {
                            setState(() {
                              newFastStart = value;
                            });
                          },
                        ),
                      ),
                      const Divider(height: 32),
                      // Fast End
                      const Text('Fast End', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.dateAndTime,
                          initialDateTime: newFastEnd,
                          maximumDate: DateTime.now(),
                          onDateTimeChanged: (DateTime value) {
                            setState(() {
                              newFastEnd = value;
                            });
                          },
                        ),
                      ),
                      if (eatingEnd != null) ...[
                        const Divider(height: 32),
                        // Eating End
                        const Text('Eating End', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.dateAndTime,
                            initialDateTime: newEatingEnd ?? DateTime.now(),
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (DateTime value) {
                              setState(() {
                                newEatingEnd = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final newFastDuration = newFastEnd.difference(newFastStart).inSeconds / 3600;
                    final newEatingDuration = newEatingEnd != null
                        ? newEatingEnd!.difference(newFastEnd).inSeconds / 3600
                        : null;

                    setState(() {
                      _history[index]['fastStart'] = newFastStart.toIso8601String();
                      _history[index]['fastEnd'] = newFastEnd.toIso8601String();
                      _history[index]['fastDuration'] = newFastDuration;
                      _history[index]['eatingStart'] = newFastEnd.toIso8601String();
                      _history[index]['eatingEnd'] = newEatingEnd?.toIso8601String();
                      _history[index]['eatingDuration'] = newEatingDuration;
                      _history[index]['success'] = newFastDuration >= _history[index]['goal'];
                    });
                    _saveState();
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editHistoryNote(int index) async {
    final currentNote = _history[index]['note'] as String? ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentNote);
        return AlertDialog(
          title: const Text('Add Note'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter your note...',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result.isEmpty) {
          _history[index].remove('note');
        } else {
          _history[index]['note'] = result;
        }
      });
      _saveState();
    }
  }

  Future<void> _deleteHistoryEntry(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this fasting record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _history.removeAt(index);
      });
      _saveState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry deleted')),
        );
      }
    }
  }

  Future<void> _editCurrentFastingTime() async {
    if (_startTime == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        DateTime tempStartTime = _startTime!;
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        final now = DateTime.now();
        final earliestAllowed = now.subtract(const Duration(days: 1));
        if (tempStartTime.isBefore(earliestAllowed)) {
          tempStartTime = earliestAllowed;
        } else if (tempStartTime.isAfter(now)) {
          tempStartTime = now;
        }

        String relativeLabel(DateTime date) {
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));
          final dateOnly = DateTime(date.year, date.month, date.day);
          if (dateOnly == today) return 'Today';
          if (dateOnly == yesterday) return 'Yesterday';
          return DateFormat('EEEE, MMM d').format(date);
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Edit Fasting Start Time',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 220,
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.dateAndTime,
                        initialDateTime: tempStartTime,
                        minimumDate: earliestAllowed,
                        maximumDate: now,
                        onDateTimeChanged: (DateTime newDateTime) {
                          setModalState(() {
                            tempStartTime = newDateTime;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    '${relativeLabel(tempStartTime)} • ${_format12Hour(tempStartTime)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _startTime = tempStartTime;
                              final nowInstant = DateTime.now();
                              _elapsedSeconds = nowInstant.difference(_startTime!).inSeconds;
                            });
                            _saveState();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Start time updated')),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editCurrentEatingTime() async {
    if (_eatingStartTime == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        DateTime tempStartTime = _eatingStartTime!;
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Edit Eating Window Start Time',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 220,
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.dateAndTime,
                        initialDateTime: tempStartTime,
                        minimumDate: _startTime,
                        maximumDate: DateTime.now(),
                        onDateTimeChanged: (DateTime newDateTime) {
                          setModalState(() {
                            tempStartTime = newDateTime;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'New start time: ${_format12Hour(tempStartTime)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            setState(() {
                              _eatingStartTime = tempStartTime;
                              final now = DateTime.now();
                              _elapsedSeconds = now.difference(_eatingStartTime!).inSeconds;
                            });
                            _saveState();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Start time updated')),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _format12Hour(DateTime dateTime) {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }
}

class _PartialRingPainter extends CustomPainter {
  _PartialRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.reverse,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final bool reverse;

  static const double _gapFraction = 0.2; // 20% gap at bottom

  @override
  void paint(Canvas canvas, Size size) {
    final offset = strokeWidth / 2;
    final rect = Offset(offset, offset) &
    Size(size.width - strokeWidth, size.height - strokeWidth);

    final paintBase = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    const gapAngle = 2 * math.pi * _gapFraction;
    final startAngle = math.pi / 2 + gapAngle / 2;
    final sweepAngle = 2 * math.pi - gapAngle;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paintBase);

    final paintProgress = paintBase..color = progressColor;
    final double clampedProgress = math.max(0.0, math.min(1.0, progress));
    final sweep = sweepAngle * clampedProgress;
    if (reverse) {
      canvas.drawArc(
        rect,
        startAngle + sweepAngle,
        -sweep,
        false,
        paintProgress,
      );
    } else {
      canvas.drawArc(
        rect,
        startAngle,
        sweep,
        false,
        paintProgress,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PartialRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.reverse != reverse;
  }
}