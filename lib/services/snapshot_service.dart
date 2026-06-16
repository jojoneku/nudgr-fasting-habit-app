import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_storage_service.dart';

/// Immutable cloud snapshots (Plan 053 Phase 3.5) — the durable "never deleted"
/// backup. Periodically writes a full-state snapshot of the user's local data
/// to an append-only `backups` table that the normal sync code never overwrites
/// or deletes. Even if live sync ever clobbers a singleton row, an earlier
/// snapshot remains intact and restorable.
///
/// Works on BOTH mobile and web (pure Supabase). Requires the
/// `docs/supabase_migration_053_snapshots.sql` migration; until it's applied,
/// every method is a safe, logged no-op (the table simply doesn't exist).
class SnapshotService {
  final SupabaseClient _supabase;
  final LocalStorageService _storage;
  final String _userId;
  final DateTime Function() _now;

  /// Retain at most this many snapshots per user; older ones are pruned.
  static const int maxSnapshots = 30;

  /// Minimum gap between automatic snapshots.
  static const Duration interval = Duration(hours: 24);

  SnapshotService({
    required SupabaseClient supabase,
    required LocalStorageService storage,
    required String userId,
    DateTime Function()? now,
  })  : _supabase = supabase,
        _storage = storage,
        _userId = userId,
        _now = now ?? DateTime.now;

  // A bare (non-`u/$id/`) throttle key: it's only a cadence marker, must not be
  // wiped by clearUserData, and must not leak into the data snapshot itself.
  String get _lastKey => 'snapshot_last_at_$_userId';

  /// Which `taken_at` values to delete to keep only the newest [keep], given a
  /// newest-first list. Pure + testable (the prune decision, not the I/O).
  @visibleForTesting
  static List<String> snapshotsToDelete(List<String> takenAtDesc, int keep) {
    if (takenAtDesc.length <= keep) return const [];
    return takenAtDesc.sublist(keep);
  }

  /// Writes a snapshot if at least [interval] has passed since the last one.
  /// Fire-and-forget safe: never throws.
  Future<void> writeSnapshotIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_lastKey);
      final now = _now();
      if (lastMs != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (now.difference(last) < interval) return; // not due yet
      }
      final data = await _storage.exportUserData();
      if (data.isEmpty) return; // nothing worth snapshotting
      await _supabase.from('backups').insert({
        'user_id': _userId,
        'taken_at': now.toUtc().toIso8601String(),
        'data': data,
      });
      await prefs.setInt(_lastKey, now.millisecondsSinceEpoch);
      await _pruneOld();
      debugPrint('SnapshotService: wrote snapshot (${data.length} keys)');
    } catch (e) {
      // Table missing (migration not yet applied) / offline / etc. — never let
      // a backup failure disrupt the app.
      debugPrint('SnapshotService: writeSnapshotIfDue failed: $e');
    }
  }

  Future<void> _pruneOld() async {
    final rows = await _supabase
        .from('backups')
        .select('taken_at')
        .eq('user_id', _userId)
        .order('taken_at', ascending: false);
    final takenAt = [for (final r in rows as List) r['taken_at'] as String];
    final toDelete = snapshotsToDelete(takenAt, maxSnapshots);
    if (toDelete.isEmpty) return;
    // Delete everything older than the oldest one we're keeping.
    final keepOldest = takenAt[maxSnapshots - 1];
    await _supabase
        .from('backups')
        .delete()
        .eq('user_id', _userId)
        .lt('taken_at', keepOldest);
  }

  /// Snapshot timestamps for this user, newest first. Empty on any error.
  Future<List<DateTime>> listSnapshots() async {
    try {
      final rows = await _supabase
          .from('backups')
          .select('taken_at')
          .eq('user_id', _userId)
          .order('taken_at', ascending: false);
      return [
        for (final r in rows as List) DateTime.parse(r['taken_at'] as String),
      ];
    } catch (e) {
      debugPrint('SnapshotService: listSnapshots failed: $e');
      return [];
    }
  }

  /// Restores the snapshot taken at [takenAt] into local storage (raw write —
  /// no dirty mark / no LWW bump, so a newer cloud row still wins on next pull).
  /// Returns true on success.
  Future<bool> restoreSnapshot(DateTime takenAt) async {
    try {
      final row = await _supabase
          .from('backups')
          .select('data')
          .eq('user_id', _userId)
          .eq('taken_at', takenAt.toUtc().toIso8601String())
          .maybeSingle();
      final data = row?['data'];
      if (data is! Map<String, dynamic>) return false;
      await _storage.importUserData(data);
      debugPrint('SnapshotService: restored snapshot from $takenAt');
      return true;
    } catch (e) {
      debugPrint('SnapshotService: restoreSnapshot failed: $e');
      return false;
    }
  }
}
