import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens for Postgres change events on the signed-in user's rows and asks the
/// caller to run a sync cycle when another device writes something.
///
/// **The events are a doorbell, not a delivery.** The payload is discarded and
/// [onRemoteChange] runs the normal reconciliation path. Applying payloads
/// directly would mean a second write path with its own conflict rules,
/// ordering, and tombstone handling — the duplication that produced the sync
/// bugs documented in `docs/sync_conflict_resolution_spec.md`. One
/// reconciliation path, faster trigger.
///
/// Best-effort by design: if the `supabase_realtime` publication was never
/// applied, or the socket cannot open, no events arrive and the app falls back
/// to its boot / resume / manual triggers. Nothing about correctness depends on
/// this class working. See `docs/realtime_sync_spec.md`.
class RealtimeSyncService {
  /// The tables [SyncService] mirrors. Each gets its own binding on one channel.
  static const List<String> syncedTables = [
    'user_profile',
    'user_collections',
    'nutrition_logs',
    'activity_logs',
    'finance_records',
    'fasting_state',
    'user_quests',
    'advisor_state',
  ];

  final SupabaseClient _supabase;
  final String _userId;
  final Future<void> Function() _onRemoteChange;
  final Duration _debounce;

  RealtimeChannel? _channel;
  Timer? _debounceTimer;
  bool _isConnected = false;
  bool _hasSubscribed = false;
  bool _running = false;
  bool _missedWhileRunning = false;
  bool _disposed = false;
  String? _lastError;

  RealtimeSyncService({
    required SupabaseClient supabase,
    required String userId,
    required Future<void> Function() onRemoteChange,
    Duration debounce = const Duration(milliseconds: 1500),
  })  : _supabase = supabase,
        _userId = userId,
        _onRemoteChange = onRemoteChange,
        _debounce = debounce;

  bool get isConnected => _isConnected;

  /// Last channel error, for diagnostics. Null while healthy.
  String? get lastError => _lastError;

  /// Opens the channel. Call once per signed-in user.
  void connect() {
    if (_disposed || _channel != null) return;
    try {
      var channel = _supabase.channel('sync:$_userId');
      for (final table in syncedTables) {
        channel = channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          // Server-side filter. RLS already restricts rows to this user; the
          // filter avoids waking the client for rows it would discard anyway.
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _userId,
          ),
          callback: (_) => _onEvent(table),
        );
      }
      _channel = channel.subscribe(_onStatus);
      debugPrint('RealtimeSyncService: subscribing for $_userId');
    } catch (e) {
      // A malformed channel or an unavailable socket must never break sign-in.
      _lastError = e.toString();
      debugPrint('RealtimeSyncService: connect failed: $e');
    }
  }

  void _onStatus(RealtimeSubscribeStatus status, Object? error) {
    if (_disposed) return;
    _isConnected = status == RealtimeSubscribeStatus.subscribed;
    if (error != null) _lastError = error.toString();
    debugPrint('RealtimeSyncService: channel status $status'
        '${error != null ? ' ($error)' : ''}');

    if (status != RealtimeSubscribeStatus.subscribed) return;
    _lastError = null;
    if (_hasSubscribed) {
      // A RE-subscribe after a drop (sleep, network change, tab throttling).
      // Events that occurred during the gap are gone — Realtime does not replay
      // them — so catch up explicitly.
      debugPrint('RealtimeSyncService: re-subscribed, syncing to catch up');
      _schedule();
    }
    _hasSubscribed = true;
  }

  void _onEvent(String table) {
    if (_disposed) return;
    debugPrint('RealtimeSyncService: change on $table');
    _schedule();
  }

  /// Delivers a change event as if it arrived on the channel. The socket itself
  /// needs a live Realtime server; the debounce/coalescing logic around it is
  /// where the risk is, so it is driven directly in tests.
  @visibleForTesting
  void debugOnEvent(String table) => _onEvent(table);

  /// Coalesces a burst of events into one cycle. A single user action can write
  /// hundreds of rows, and each one arrives as its own event.
  void _schedule() {
    if (_disposed) return;
    if (_running) {
      // Don't drop the signal: the running cycle may already have read the
      // rows this event refers to, so re-arm once it finishes.
      _missedWhileRunning = true;
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _run);
  }

  Future<void> _run() async {
    if (_disposed || _running) return;
    _running = true;
    try {
      await _onRemoteChange();
    } catch (e) {
      // The cycle reports its own failures; never let one escape into the
      // realtime callback and kill the subscription.
      debugPrint('RealtimeSyncService: sync cycle failed: $e');
    } finally {
      _running = false;
      if (_missedWhileRunning && !_disposed) {
        _missedWhileRunning = false;
        _schedule();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _isConnected = false;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _supabase.removeChannel(channel);
      } catch (e) {
        debugPrint('RealtimeSyncService: removeChannel failed: $e');
      }
    }
  }
}
