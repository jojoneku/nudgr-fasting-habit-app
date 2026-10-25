import 'package:flutter/material.dart';
import '../models/alarm_notification.dart';
import '../models/app_lock/app_lock_policy.dart';
import '../presenters/app_lock_presenter.dart';
import '../services/app_lock/app_lock_remote.dart';
import '../services/app_lock/local_auth_biometric_authenticator.dart';
import '../services/app_lock/pin_verifier_cache.dart';
import '../utils/app_scroll_behavior.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/update_presenter.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import 'app_lock/app_lock_gate.dart';
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

  /// Gates the whole app, so the root owns it (not the Treasury graph).
  late final AppLockPresenter _appLock;
  late final AppLockBackGuard _appLockBackGuard;
  late final AppLifecycleListener _appLockLifecycle;
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
    // The only importer of local_auth: keeps it out of the web bundle.
    _appLock = AppLockPresenter(
      storage: _storage,
      cache: SecurePinVerifierCache(),
      remote: SupabaseAppLockRemote(),
      policy: AppLockPolicy.mobile,
      biometrics: LocalAuthBiometricAuthenticator(),
    );
    _appLock.init();
    // Before MaterialApp is built, so Back is asked here before the Navigator.
    _appLockBackGuard = AppLockBackGuard(_appLock)..attach();
    _appLockLifecycle = AppLifecycleListener(
      onHide: _appLock.onBackgrounded,
      onShow: _appLock.onForegrounded,
    );
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
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showAlarm(alarm, retry: false));
      }
      return;
    }
    _alarmRouteOpen = true;
    // A live alarm is never covered by the app lock; the lock (if due) shows
    // again once the alarm route closes.
    _appLock.suspend('alarm');
    navigator
        .push(MaterialPageRoute<void>(
      builder: (_) => QuestAlarmScreen(alarm: alarm),
      fullscreenDialog: true,
    ))
        .whenComplete(() {
      _alarmRouteOpen = false;
      _appLock.resume('alarm');
    });
  }

  @override
  void dispose() {
    NotificationService.onAlarmNotification = null;
    _settingsPresenter.dispose();
    _updatePresenter.dispose();
    _appLockLifecycle.dispose();
    _appLockBackGuard.detach();
    _appLock.dispose();
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
        // Above the Navigator: every route, dialog, and sheet sits under it.
        builder: (context, child) =>
            AppLockGate(presenter: _appLock, child: child!),
        home: HomeScreen(
          settingsPresenter: _settingsPresenter,
          updatePresenter: _updatePresenter,
          appLockPresenter: _appLock,
        ),
      ),
    );
  }
}
