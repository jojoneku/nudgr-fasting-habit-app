import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_lock/pin_verifier.dart';

enum AppLockRemoteFailure {
  /// No connection, or the request timed out. The cached copy still unlocks.
  offline,

  /// Migration 058 is not applied. The app lock is not offered at all.
  unavailable,

  /// Anything else (expired session, server error).
  other,
}

class AppLockRemoteException implements Exception {
  final AppLockRemoteFailure kind;
  final Object? cause;

  const AppLockRemoteException(this.kind, [this.cause]);

  @override
  String toString() => 'AppLockRemoteException($kind, $cause)';
}

/// The account's PIN verifier in the cloud (`app_lock` table).
///
/// Not a SyncDomain: writes are write-through and online-only, so a PIN can
/// never be clobbered by an offline last-write-wins push. A null verifier
/// means the lock is off for the account.
abstract class AppLockRemote {
  /// Throws [AppLockRemoteException].
  Future<PinVerifier?> fetch(String userId);

  /// Writes [verifier] (null turns the lock off). Throws
  /// [AppLockRemoteException]; on a throw nothing changed.
  Future<void> put(String userId, PinVerifier? verifier);

  /// A doorbell that rings when another device changes the row. The payload
  /// is ignored: the caller re-fetches. Best-effort — it may never ring.
  Stream<void> watch(String userId);
}

class SupabaseAppLockRemote implements AppLockRemote {
  SupabaseAppLockRemote({
    SupabaseClient Function()? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? (() => Supabase.instance.client);

  static const String table = 'app_lock';

  // Lazy: the app roots build the lock presenter before Supabase initializes.
  final SupabaseClient Function() _client;
  final Duration timeout;

  @override
  Future<PinVerifier?> fetch(String userId) => _guard(() async {
        final row = await _client()
            .from(table)
            .select('verifier')
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(timeout);
        return PinVerifier.tryFromJson(row?['verifier']);
      });

  @override
  Future<void> put(String userId, PinVerifier? verifier) => _guard(() async {
        await _client()
            .from(table)
            .upsert({
              'user_id': userId,
              'verifier': verifier?.toJson(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select('user_id')
            .timeout(timeout);
      });

  @override
  Stream<void> watch(String userId) {
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        try {
          channel = _client()
              .channel('app_lock:$userId')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: table,
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: userId,
                ),
                callback: (_) {
                  if (!controller.isClosed) controller.add(null);
                },
              )
              .subscribe();
        } catch (e) {
          // Best-effort, like RealtimeSyncService: foreground / tab-show
          // re-fetches still keep devices in step.
          debugPrint('SupabaseAppLockRemote: watch failed: $e');
        }
      },
      onCancel: () async {
        final c = channel;
        channel = null;
        if (c != null) await _client().removeChannel(c);
      },
    );
    return controller.stream;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AppLockRemoteException {
      rethrow;
    } catch (e) {
      throw AppLockRemoteException(classify(e), e);
    }
  }

  /// Maps a Supabase/HTTP error to the three cases the presenter acts on.
  @visibleForTesting
  static AppLockRemoteFailure classify(Object e) {
    if (e is PostgrestException) {
      // 42P01: relation does not exist. PGRST205: not in the schema cache.
      if (e.code == '42P01' || e.code == 'PGRST205') {
        return AppLockRemoteFailure.unavailable;
      }
      return AppLockRemoteFailure.other;
    }
    if (e is TimeoutException) return AppLockRemoteFailure.offline;
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup') ||
        text.contains('XMLHttpRequest error') ||
        text.contains('Failed to fetch')) {
      return AppLockRemoteFailure.offline;
    }
    return AppLockRemoteFailure.other;
  }
}
