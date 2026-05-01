import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_queue_entry.dart';

/// Tracks pending local writes to push to Supabase.
/// Also stores per-domain timestamps for last-write-wins comparisons.
/// Capped at 1000 entries; deduplicates by (domain, key) keeping latest op.
class SyncQueue {
  static const String _keyQueue = 'syncQueue';
  static const String _keyTimestamps = 'syncTimestamps';
  static const int _maxEntries = 1000;

  final List<SyncQueueEntry> _entries = [];
  final Map<String, DateTime> _timestamps = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_keyQueue);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final m = item as Map<String, dynamic>;
          _entries.add(SyncQueueEntry(
            domain: SyncDomain.values.byName(m['domain'] as String),
            key: m['key'] as String,
            op: SyncOp.values.byName(m['op'] as String),
            queuedAt: DateTime.parse(m['queuedAt'] as String),
          ));
        }
      } catch (_) {}
    }

    final tsRaw = prefs.getString(_keyTimestamps);
    if (tsRaw != null) {
      try {
        (jsonDecode(tsRaw) as Map<String, dynamic>).forEach((k, v) {
          _timestamps[k] = DateTime.parse(v as String);
        });
      } catch (_) {}
    }
  }

  int get pendingCount => _entries.length;

  List<SyncQueueEntry> get entries => List.unmodifiable(_entries);

  void markDirty(SyncDomain domain, String key, {SyncOp op = SyncOp.upsert}) {
    _entries.removeWhere((e) => e.domain == domain && e.key == key);
    _entries.add(SyncQueueEntry(
      domain: domain,
      key: key,
      op: op,
      queuedAt: DateTime.now(),
    ));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    setTimestamp(domain, key, time: DateTime.now());
    _persist();
  }

  void removeEntries(List<SyncQueueEntry> processed) {
    for (final e in processed) {
      _entries.removeWhere((q) =>
          q.domain == e.domain && q.key == e.key && q.queuedAt == e.queuedAt);
    }
    _persist();
  }

  DateTime getTimestamp(SyncDomain domain, String key) {
    return _timestamps['${domain.name}::$key'] ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void setTimestamp(SyncDomain domain, String key, {required DateTime time}) {
    _timestamps['${domain.name}::$key'] = time;
    _persistTimestamps();
  }

  void clear() {
    _entries.clear();
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _entries
        .map((e) => {
              'domain': e.domain.name,
              'key': e.key,
              'op': e.op.name,
              'queuedAt': e.queuedAt.toIso8601String(),
            })
        .toList();
    await prefs.setString(_keyQueue, jsonEncode(list));
  }

  Future<void> _persistTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _timestamps.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_keyTimestamps, jsonEncode(map));
  }
}
