import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_queue_entry.dart';

/// Tracks pending local writes to push to Supabase.
/// Also stores per-domain timestamps for last-write-wins comparisons.
///
/// Backed by a map keyed by `domain::key`, so [markDirty] and [removeEntries]
/// are O(1) and the queue naturally deduplicates to the latest op per record.
/// There is deliberately NO size cap: with diff-based dirty marking upstream,
/// only genuinely-changed records are enqueued, and a large offline backlog is
/// exactly what must survive to reach the cloud — silently evicting it would
/// strand edits permanently.
///
/// Keys are scoped to [userId] when provided via [load] so multiple users on
/// the same device never share queue or timestamp state.
class SyncQueue {
  String? _userId;
  final Map<String, SyncQueueEntry> _entryByKey = {};
  final Map<String, DateTime> _timestamps = {};
  bool _loaded = false;
  bool _flushScheduled = false;

  String get _queueKey =>
      _userId != null ? 'u/$_userId/syncQueue' : 'syncQueue';
  String get _timestampsKey =>
      _userId != null ? 'u/$_userId/syncTimestamps' : 'syncTimestamps';

  String _entryKey(SyncDomain domain, String key) => '${domain.name}::$key';

  Future<void> load({String? userId}) async {
    if (_loaded && _userId == userId) return;
    _userId = userId;
    _loaded = true;
    _entryByKey.clear();
    _timestamps.clear();
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_queueKey);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List) {
          final m = item as Map<String, dynamic>;
          final entry = SyncQueueEntry(
            domain: SyncDomain.values.byName(m['domain'] as String),
            key: m['key'] as String,
            op: SyncOp.values.byName(m['op'] as String),
            queuedAt: DateTime.parse(m['queuedAt'] as String),
          );
          final k = _entryKey(entry.domain, entry.key);
          // Restoring an older persisted queue may hold duplicates for one
          // record; keep the most recently queued op.
          final existing = _entryByKey[k];
          if (existing == null || entry.queuedAt.isAfter(existing.queuedAt)) {
            _entryByKey[k] = entry;
          }
        }
      } catch (e) {
        debugPrint('SyncQueue: failed to restore pending queue: $e');
      }
    }

    final tsRaw = prefs.getString(_timestampsKey);
    if (tsRaw != null) {
      try {
        (jsonDecode(tsRaw) as Map<String, dynamic>).forEach((k, v) {
          _timestamps[k] = DateTime.parse(v as String);
        });
      } catch (e) {
        debugPrint('SyncQueue: failed to restore timestamps: $e');
      }
    }
  }

  int get pendingCount => _entryByKey.length;

  List<SyncQueueEntry> get entries => List.unmodifiable(_entryByKey.values);

  void markDirty(SyncDomain domain, String key, {SyncOp op = SyncOp.upsert}) {
    _entryByKey[_entryKey(domain, key)] = SyncQueueEntry(
      domain: domain,
      key: key,
      op: op,
      queuedAt: DateTime.now(),
    );
    setTimestamp(domain, key, time: DateTime.now());
    _scheduleFlush();
  }

  /// Drops a pending entry whose local edit has been superseded by a newer
  /// cloud copy (see `docs/sync_conflict_resolution_spec.md`).
  ///
  /// Unlike [removeEntries] this is unconditional: the caller has already
  /// established that the cloud wins, so a re-dirty that happened in the
  /// meantime is irrelevant — that newer edit re-enqueues itself anyway.
  void discardEntry(SyncDomain domain, String key) {
    if (_entryByKey.remove(_entryKey(domain, key)) != null) _scheduleFlush();
  }

  /// Resets a record's watermark to the epoch so the next pull unconditionally
  /// applies the cloud copy.
  ///
  /// Used when a push is abandoned on conflict: the local copy is known-stale,
  /// and leaving its watermark at the local edit time would make the pull skip
  /// the very row that just beat us ("local is newer"), stranding the device on
  /// data it already agreed to give up.
  void invalidateTimestamp(SyncDomain domain, String key) {
    _timestamps.remove('${domain.name}::$key');
    _scheduleFlush();
  }

  void removeEntries(List<SyncQueueEntry> processed) {
    for (final e in processed) {
      final k = _entryKey(e.domain, e.key);
      final current = _entryByKey[k];
      // Only drop the entry if it hasn't been re-dirtied since we snapshotted
      // it for push (a newer queuedAt means a fresh edit still needs to sync).
      if (current != null && current.queuedAt == e.queuedAt) {
        _entryByKey.remove(k);
      }
    }
    _scheduleFlush();
  }

  DateTime getTimestamp(SyncDomain domain, String key) {
    return _timestamps['${domain.name}::$key'] ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void setTimestamp(SyncDomain domain, String key, {required DateTime time}) {
    _timestamps['${domain.name}::$key'] = time;
    _scheduleFlush();
  }

  void clear() {
    _entryByKey.clear();
    _scheduleFlush();
  }

  /// Clears all in-memory state on sign-out. Persisted prefs keys under the
  /// user prefix are wiped by [LocalStorageService.clearUserData].
  void clearAll() {
    _entryByKey.clear();
    _timestamps.clear();
    _loaded = false;
    _userId = null;
  }

  /// Coalesces persistence. A single save can mark hundreds of records dirty in
  /// one synchronous burst; without this, each call would do two full jsonEncode
  /// + prefs writes, jamming the main isolate and making edits feel like they
  /// hang. Instead we flush once on the next microtask, after the burst settles.
  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      _persist();
      _persistTimestamps();
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _entryByKey.values
        .map((e) => {
              'domain': e.domain.name,
              'key': e.key,
              'op': e.op.name,
              'queuedAt': e.queuedAt.toIso8601String(),
            })
        .toList();
    await prefs.setString(_queueKey, jsonEncode(list));
  }

  Future<void> _persistTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _timestamps.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_timestampsKey, jsonEncode(map));
  }
}
