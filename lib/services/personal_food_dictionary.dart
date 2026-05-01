import 'package:flutter/foundation.dart';

import '../models/personal_food_entry.dart';
import 'storage_service.dart';

/// In-memory dictionary of user-confirmed food entries, backed by StorageService.
///
/// Lookup runs BEFORE the USDA food DB so that foods the user has corrected
/// at least once always resolve immediately to their verified values.
/// Bounded at 500 entries; oldest (by lastUsedAt) are evicted when full.
class PersonalFoodDictionary {
  static const _maxEntries = 500;

  final StorageService _storage;
  final Map<String, PersonalFoodEntry> _map = {};
  bool _initialized = false;

  PersonalFoodDictionary(this._storage);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final list = await _storage.loadPersonalDict();
      // Re-key each entry through the current normalizeKey so old keys saved
      // under a previous normalization (e.g. with punctuation) become reachable.
      // If two entries collide on the new key, keep the more recently used one.
      bool keysChanged = false;
      for (final e in list) {
        final newKey = normalizeKey(e.name);
        if (newKey != e.key) keysChanged = true;
        final existing = _map[newKey];
        if (existing == null || e.lastUsedAt.isAfter(existing.lastUsedAt)) {
          _map[newKey] = PersonalFoodEntry(
            key: newKey,
            name: e.name,
            kcalPer100g: e.kcalPer100g,
            proteinPer100g: e.proteinPer100g,
            carbsPer100g: e.carbsPer100g,
            fatPer100g: e.fatPer100g,
            hits: e.hits,
            lastUsedAt: e.lastUsedAt,
          );
        }
      }
      if (keysChanged || _map.length != list.length) {
        await _persist();
      }
    } catch (e) {
      debugPrint('PersonalFoodDictionary: init failed: $e');
    }
    _initialized = true;
  }

  static String normalizeKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\sñ']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  PersonalFoodEntry? lookup(String name) => _map[normalizeKey(name)];

  Future<void> upsert({
    required String name,
    required double kcalPer100g,
    double? proteinPer100g,
    double? carbsPer100g,
    double? fatPer100g,
  }) async {
    if (kcalPer100g <= 0) return;
    final key = normalizeKey(name);
    final existing = _map[key];
    _map[key] = PersonalFoodEntry(
      key: key,
      name: name,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      hits: (existing?.hits ?? 0) + 1,
      lastUsedAt: DateTime.now(),
    );
    _evictIfNeeded();
    await _persist();
  }

  Future<void> remove(String name) async {
    _map.remove(normalizeKey(name));
    await _persist();
  }

  List<PersonalFoodEntry> all() => _map.values.toList()
    ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));

  void _evictIfNeeded() {
    if (_map.length <= _maxEntries) return;
    final oldest = _map.values.toList()
      ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
    for (final e in oldest.take(_map.length - _maxEntries)) {
      _map.remove(e.key);
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.savePersonalDict(_map.values.toList());
    } catch (e) {
      debugPrint('PersonalFoodDictionary: persist failed: $e');
    }
  }
}
