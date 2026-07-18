import 'package:flutter/material.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/update_presenter.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import 'app_theme.dart';
import 'home_screen.dart';

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

    // Check for updates after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePresenter.checkForUpdates();
    });
  }

  @override
  void dispose() {
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
        title: 'Nudgr',
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
