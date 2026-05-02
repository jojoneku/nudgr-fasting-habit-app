import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class SettingsPresenter extends ChangeNotifier {
  final StorageService _storage;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  SettingsPresenter(this._storage);

  Future<void> init() async {
    final saved = await _storage.loadThemeMode();
    _themeMode = _parse(saved);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _storage.saveThemeMode(_serialize(mode));
  }

  static ThemeMode _parse(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _serialize(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      };
}
