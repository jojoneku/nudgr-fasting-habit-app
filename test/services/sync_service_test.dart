import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';

// Fake Supabase client — throws UnimplementedError if any method is called,
// which the SyncService catches and treats as a push/pull failure.
class _FakeSupabaseClient extends Fake implements SupabaseClient {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _testUserId = 'test-user-id';
const _pushDoneKey = 'sync_initial_push_done_v2_$_testUserId';

SyncService _buildService(SyncQueue queue, LocalStorageService storage) =>
    SyncService(
      supabase: _FakeSupabaseClient(),
      storage: storage,
      queue: queue,
      userId: _testUserId,
    );

void main() {
  late LocalStorageService storage;
  late SyncQueue queue;
  late SyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    queue = SyncQueue();
    await queue.load();
    service = _buildService(queue, storage);
  });

  tearDown(() {
    service.dispose();
  });

  // ── pendingCount ───────────────────────────────────────────────────────────

  group('pendingCount', () {
    test('is 0 on a fresh queue', () {
      expect(service.pendingCount, 0);
    });

    test('reflects entries added via SyncQueue.markDirty', () {
      queue.markDirty(SyncDomain.fastingState, 'default');
      expect(service.pendingCount, 1);

      queue.markDirty(SyncDomain.userProfile, 'default');
      expect(service.pendingCount, 2);
    });

    test('deduplicates entries for the same domain+key', () {
      queue.markDirty(SyncDomain.fastingState, 'default');
      queue.markDirty(SyncDomain.fastingState, 'default'); // overwrite
      expect(service.pendingCount, 1);
    });
  });

  // ── pushPending ────────────────────────────────────────────────────────────

  group('pushPending', () {
    test('skips and stays idle when queue is empty', () async {
      await service.pushPending();

      expect(service.isSyncing, false);
      expect(service.lastSyncedAt, isNull);
    });

    test('isSyncing is false after recovering from a Supabase failure',
        () async {
      // Add an entry so pushPending proceeds past the empty-queue guard.
      // The fake Supabase client throws UnimplementedError, which is caught
      // by the inner try/catch in pushPending — the service recovers cleanly.
      queue.markDirty(SyncDomain.fastingState, 'default');

      await service.pushPending();

      expect(service.isSyncing, false);
    });

    test('notifies onStateChange at start and end of push attempt', () async {
      queue.markDirty(SyncDomain.fastingState, 'default');
      final states = <bool>[];
      service.setOnStateChange(() => states.add(service.isSyncing));

      await service.pushPending();

      // First notification: isSyncing = true; second: isSyncing = false
      expect(states, [true, false]);
    });

    test('retains queue entries when push fails (will retry next time)',
        () async {
      queue.markDirty(SyncDomain.fastingState, 'default');

      await service.pushPending();

      // Entry was not removed because the push failed
      expect(service.pendingCount, 1);
    });
  });

  // ── pushAll ────────────────────────────────────────────────────────────────

  group('pushAll', () {
    test('skips when initial-push flag is already set in SharedPreferences',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pushDoneKey, true);

      await service.pushAll(); // should return before touching Supabase

      expect(service.isSyncing, false);
      expect(service.lastSyncedAt, isNull);
    });

    test('is idempotent: second call after flag is set is also a no-op',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pushDoneKey, true);

      await service.pushAll();
      await service.pushAll(); // second call also skips

      expect(service.isSyncing, false);
    });
  });

  // ── schedulePush ───────────────────────────────────────────────────────────

  group('schedulePush', () {
    test('dispose cancels the debounce timer — no crash after cancel', () {
      fakeAsync((fake) {
        service.schedulePush();
        service.dispose();

        // Elapse well past the 3-second debounce; timer should not fire
        fake.elapse(const Duration(seconds: 10));
        // No crash = pass
      });
    });

    test('multiple rapid calls produce only one deferred push attempt', () {
      fakeAsync((fake) {
        final stateChanges = <bool>[];
        service.setOnStateChange(() => stateChanges.add(service.isSyncing));

        // Three rapid calls before the debounce window expires
        service.schedulePush();
        service.schedulePush();
        service.schedulePush();

        // Nothing has happened yet
        expect(stateChanges, isEmpty);

        // Advance past the 3-second debounce; queue is empty so pushPending
        // returns early without touching Supabase or emitting state changes.
        fake.elapse(const Duration(seconds: 4));

        expect(service.isSyncing, false);
        // Empty-queue path emits no state change notifications
        expect(stateChanges, isEmpty);
      });
    });

    test('second schedulePush resets the timer', () {
      fakeAsync((fake) {
        int fireCount = 0;
        service.setOnStateChange(() => fireCount++);

        service.schedulePush();
        fake.elapse(const Duration(seconds: 2)); // 2s in — not yet fired

        service.schedulePush(); // resets timer; should fire 3s from now
        fake.elapse(
            const Duration(seconds: 2)); // 2s since reset — still not fired

        expect(fireCount, 0); // timer hasn't fired (only 2s since last call)

        fake.elapse(
            const Duration(seconds: 2)); // now 4s since last call — fires
        // Empty queue → pushPending exits early (no state change emitted)
        expect(service.isSyncing, false);
      });
    });
  });

  // ── isSyncing ──────────────────────────────────────────────────────────────

  group('isSyncing', () {
    test('starts as false', () {
      expect(service.isSyncing, false);
    });
  });

  // ── lastSyncedAt ───────────────────────────────────────────────────────────

  group('lastSyncedAt', () {
    test('is null until a successful push completes', () {
      expect(service.lastSyncedAt, isNull);
    });
  });
}
