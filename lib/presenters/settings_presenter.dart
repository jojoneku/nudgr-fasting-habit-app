import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../utils/hub_hero_slots.dart';

class SettingsPresenter extends ChangeNotifier {
  final StorageService _storage;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool _useCloudAi = false;
  bool get useCloudAi => _useCloudAi;

  /// Hub hero-ring slot configuration. `null` means "not configured" — the Hub
  /// auto-resolves the default (Fast/Food/Move, or macro-split slot 1 for
  /// non-fasters). See [resolveHeroSlots].
  List<HubHeroSlot>? _heroSlots;
  List<HubHeroSlot>? get heroSlots => _heroSlots;

  SettingsPresenter(this._storage);

  Future<void> init() async {
    final saved = await _storage.loadThemeMode();
    _themeMode = _parse(saved);
    _useCloudAi = await _storage.loadUseCloudAi();
    _heroSlots = _parseHeroSlots(await _storage.loadHeroSlots());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _storage.saveThemeMode(_serialize(mode));
  }

  Future<void> setUseCloudAi(bool value) async {
    if (_useCloudAi == value) return;
    _useCloudAi = value;
    notifyListeners();
    await _storage.saveUseCloudAi(value);
  }

  /// Sets (or clears, with `null`) the hero-slot configuration. Clearing
  /// restores the auto-resolved default on the next Hub build.
  Future<void> setHeroSlots(List<HubHeroSlot>? slots) async {
    _heroSlots = slots;
    notifyListeners();
    await _storage
        .saveHeroSlots(slots?.map((s) => s.name).toList() ?? const []);
  }

  static List<HubHeroSlot>? _parseHeroSlots(List<String> names) {
    if (names.length != 3) return null;
    final parsed = names.map(heroSlotFromName).toList();
    if (parsed.any((s) => s == null)) return null;
    return parsed.cast<HubHeroSlot>();
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
