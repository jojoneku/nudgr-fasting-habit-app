import 'package:flutter/foundation.dart';

import '../models/finance/finance_dict_entry.dart';
import 'storage_service.dart';

/// In-memory map of lowercased tokens → categoryId, backed by StorageService.
///
/// Populated only by **user-confirmed** classifier resolutions — never by
/// raw AI guesses. The preprocessor consults this dict before falling
/// through to the AI; once a token is learned, the same input parses
/// without an AI call.
///
/// Cascade-cleared when a category is deleted: see [removeForCategory].
class FinancePersonalDictionary {
  static const _maxEntries = 500;

  final StorageService _storage;
  final Map<String, FinanceDictEntry> _map = {};
  bool _initialized = false;

  FinancePersonalDictionary(this._storage);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final list = await _storage.loadFinanceDictionary();
      for (final e in list) {
        final key = normalizeToken(e.token);
        if (key.isEmpty) continue;
        final existing = _map[key];
        if (existing == null || e.lastUsedAt.isAfter(existing.lastUsedAt)) {
          _map[key] = FinanceDictEntry(
            token: key,
            categoryId: e.categoryId,
            hits: e.hits,
            lastUsedAt: e.lastUsedAt,
          );
        }
      }
    } catch (e) {
      debugPrint('FinancePersonalDictionary: init failed: $e');
    }
    _initialized = true;
  }

  /// Lowercases and strips non-alphanumeric chars. Empty for whitespace.
  static String normalizeToken(String token) =>
      token.toLowerCase().replaceAll(RegExp(r"[^a-z0-9ñ']"), '').trim();

  /// Returns the categoryId mapped to [token], or null if not learned.
  String? lookup(String token) {
    final key = normalizeToken(token);
    if (key.isEmpty) return null;
    return _map[key]?.categoryId;
  }

  /// Snapshot of the current dict as `token → categoryId` — used to build AI
  /// prompts. Order is undefined.
  Map<String, String> snapshot() =>
      {for (final e in _map.values) e.token: e.categoryId};

  /// Records a confirmed [token] → [categoryId] mapping. If the token is
  /// already learned with a different category, the new mapping overwrites
  /// (most recent confirmation wins).
  Future<void> learn(String token, String categoryId) async {
    final key = normalizeToken(token);
    if (key.isEmpty) return;
    final existing = _map[key];
    _map[key] = FinanceDictEntry(
      token: key,
      categoryId: categoryId,
      hits:
          (existing?.categoryId == categoryId ? (existing?.hits ?? 0) : 0) + 1,
      lastUsedAt: DateTime.now(),
    );
    _evictIfNeeded();
    await _persist();
  }

  /// Removes a single token mapping.
  Future<void> remove(String token) async {
    final key = normalizeToken(token);
    if (_map.remove(key) != null) await _persist();
  }

  /// Cascades a category deletion — drops every token that pointed at it.
  /// Returns the count of removed entries (handy for tests/telemetry).
  Future<int> removeForCategory(String categoryId) async {
    final before = _map.length;
    _map.removeWhere((_, e) => e.categoryId == categoryId);
    final removed = before - _map.length;
    if (removed > 0) await _persist();
    return removed;
  }

  List<FinanceDictEntry> all() => _map.values.toList()
    ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));

  void _evictIfNeeded() {
    if (_map.length <= _maxEntries) return;
    final oldest = _map.values.toList()
      ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
    for (final e in oldest.take(_map.length - _maxEntries)) {
      _map.remove(e.token);
    }
  }

  Future<void> _persist() async {
    try {
      await _storage.saveFinanceDictionary(_map.values.toList());
    } catch (e) {
      debugPrint('FinancePersonalDictionary: persist failed: $e');
    }
  }
}
