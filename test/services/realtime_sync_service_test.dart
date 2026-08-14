import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/services/realtime_sync_service.dart';

/// Fake Supabase client — `channel()` throws, which exercises the
/// degrade-gracefully path (no publication / unreachable socket).
class _FakeSupabaseClient extends Fake implements SupabaseClient {}

/// Drives the debounce/coalescing logic directly, without a socket. The
/// event-plumbing itself needs a live Realtime server; what is testable here —
/// and what carries the risk — is that bursts collapse to one cycle, that an
/// event during a cycle is not dropped, and that a dead socket is harmless.
void main() {
  late List<String> cycles;
  late RealtimeSyncService service;

  /// Reaches the private handler the channel callback would invoke.
  void fireEvent() => service.debugOnEvent('finance_records');

  setUp(() {
    cycles = [];
    service = RealtimeSyncService(
      supabase: _FakeSupabaseClient(),
      userId: 'test-user-id',
      onRemoteChange: () async => cycles.add('cycle'),
      debounce: const Duration(milliseconds: 100),
    );
  });

  tearDown(() => service.dispose());

  test('the synced table list matches what SyncService mirrors', () {
    expect(RealtimeSyncService.syncedTables, hasLength(8));
    expect(
        RealtimeSyncService.syncedTables,
        containsAll([
          'user_profile',
          'user_collections',
          'nutrition_logs',
          'activity_logs',
          'finance_records',
          'fasting_state',
          'user_quests',
          'advisor_state',
        ]));
  });

  test('an event triggers one cycle after the debounce', () {
    fakeAsync((async) {
      fireEvent();
      expect(cycles, isEmpty, reason: 'not until the debounce elapses');

      async.elapse(const Duration(milliseconds: 150));
      expect(cycles, hasLength(1));
    });
  });

  test('a burst of events collapses into a single cycle', () {
    fakeAsync((async) {
      // One user action can write hundreds of rows, each its own event.
      for (var i = 0; i < 50; i++) {
        fireEvent();
        async.elapse(const Duration(milliseconds: 5));
      }
      async.elapse(const Duration(milliseconds: 150));

      expect(cycles, hasLength(1));
    });
  });

  test('separated events each get their own cycle', () {
    fakeAsync((async) {
      fireEvent();
      async.elapse(const Duration(milliseconds: 150));
      fireEvent();
      async.elapse(const Duration(milliseconds: 150));

      expect(cycles, hasLength(2));
    });
  });

  test('an event arriving during a cycle re-arms instead of being dropped', () {
    // The cycle takes 500ms, so a second event lands squarely inside it.
    final slow = RealtimeSyncService(
      supabase: _FakeSupabaseClient(),
      userId: 'test-user-id',
      onRemoteChange: () async {
        cycles.add('cycle');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      debounce: const Duration(milliseconds: 100),
    );

    fakeAsync((async) {
      slow.debugOnEvent('finance_records');
      async.elapse(const Duration(milliseconds: 150));
      expect(cycles, hasLength(1), reason: 'first cycle is in flight');

      // Another device writes while that cycle is still running.
      slow.debugOnEvent('finance_records');
      async.elapse(const Duration(milliseconds: 150));
      expect(cycles, hasLength(1), reason: 'still blocked on the first');

      async.elapse(const Duration(milliseconds: 500)); // first cycle finishes
      async.elapse(const Duration(milliseconds: 150)); // re-armed debounce
      expect(cycles, hasLength(2), reason: 'the missed event re-armed');
    });

    slow.dispose();
  });

  test('a failing cycle does not kill the subscription', () {
    var calls = 0;
    final failing = RealtimeSyncService(
      supabase: _FakeSupabaseClient(),
      userId: 'test-user-id',
      onRemoteChange: () async {
        calls++;
        throw StateError('offline');
      },
      debounce: const Duration(milliseconds: 100),
    );

    fakeAsync((async) {
      failing.debugOnEvent('finance_records');
      async.elapse(const Duration(milliseconds: 150));
      failing.debugOnEvent('finance_records');
      async.elapse(const Duration(milliseconds: 150));

      expect(calls, 2, reason: 'a thrown cycle must not wedge the service');
    });

    failing.dispose();
  });

  test('events after dispose are ignored', () {
    fakeAsync((async) {
      service.dispose();
      fireEvent();
      async.elapse(const Duration(milliseconds: 150));

      expect(cycles, isEmpty);
    });
  });

  test('a pending debounce is cancelled by dispose', () {
    fakeAsync((async) {
      fireEvent();
      service.dispose();
      async.elapse(const Duration(milliseconds: 150));

      expect(cycles, isEmpty);
    });
  });

  test('connect survives an unreachable socket and reports the error', () {
    // The fake throws on channel(); sign-in must not break because realtime
    // is unavailable.
    expect(service.connect, returnsNormally);
    expect(service.isConnected, false);
    expect(service.lastError, isNotNull);
  });
}
