import 'package:flutter/material.dart';
import '../models/alarm_notification.dart';
import '../utils/app_scroll_behavior.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/update_presenter.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'quests/quest_alarm_screen.dart';

class FastingApp extends StatefulWidget {
  const FastingApp({super.key});

  @override
  State<FastingApp> createState() => _FastingAppState();
}

class _FastingAppState extends State<FastingApp> {
  late final LocalStorageService _storage;
  late final SettingsPresenter _settingsPresenter;
  late final UpdatePresenter _updatePresenter;
  late final ThemeData _cachedDarkTheme;
  late final ThemeData _cachedLightTheme;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Guards against stacking alarm screens when two alarms land close together.
  bool _alarmRouteOpen = false;

  // Injected by CI via `--dart-define=APP_VERSION=${new_version}`. The fallback
  // only fires on local `flutter run` — production builds always set it.
  static const String _currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  @override
  void initState() {
    super.initState();
    _storage = LocalStorageService();
    _settingsPresenter = SettingsPresenter(_storage);
    _settingsPresenter.init();
    _cachedDarkTheme = buildDarkTheme();
    _cachedLightTheme = buildLightTheme();

    // Initialize update checker with manifest URL from dart-define
    const manifestUrl = String.fromEnvironment(
      'UPDATE_MANIFEST_URL',
      defaultValue:
          'https://github.com/jojoneku/nudgr-fasting-habit-app/releases/latest/download/manifest.json',
    );
    final updateService = UpdateService(manifestUrl: manifestUrl);
    _updatePresenter = UpdatePresenter(
      updateService: updateService,
      storage: _storage,
      currentVersion: _currentVersion,
      notifications: NotificationService(),
    );

    // A full-screen alarm must not land on the Hub — the app can be drawn over
    // the lock screen on that path, and the Hub shows finance figures. Route it
    // to the alarm screen instead: live alarms via the callback, and the one
    // that cold-started the app via the pending slot the service parked it in.
    NotificationService.onAlarmNotification = _showAlarm;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAlarm(NotificationService.takePendingAlarm());
      _updatePresenter.checkForUpdates();
    });
  }

  void _showAlarm(AlarmNotification? alarm, {bool retry = true}) {
    if (alarm == null || _alarmRouteOpen) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // An alarm can arrive between initState and the first frame, before the
      // navigator exists. Retry once after the frame that builds it rather
      // than dropping the alarm; bounded so a missing navigator can't spin.
      if (retry) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showAlarm(alarm, retry: false));
      }
      return;
    }
    _alarmRouteOpen = true;
    navigator
        .push(MaterialPageRoute<void>(
          builder: (_) => QuestAlarmScreen(alarm: alarm),
          fullscreenDialog: true,
        ))
        .whenComplete(() => _alarmRouteOpen = false);
  }

  @override
  void dispose() {
    NotificationService.onAlarmNotification = null;
    _settingsPresenter.dispose();
    _updatePresenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settingsPresenter,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        title: 'Nudgr',
        // Enable mouse/trackpad drag on scrollables (PageViews, etc.) so swipe
        // gestures work on web and desktop, not just touch.
        scrollBehavior: const AppScrollBehavior(),
        theme: _cachedLightTheme,
        darkTheme: _cachedDarkTheme,
        themeMode: _settingsPresenter.themeMode,
        home: HomeScreen(
          settingsPresenter: _settingsPresenter,
          updatePresenter: _updatePresenter,
        ),
      ),
    );
  }
}
