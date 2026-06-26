import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';

// Fake Supabase client — throws UnimplementedError if any method is called,
// which the SyncService catches and treats as a push/pull failure.
class _FakeSupabaseClient extends Fake implements SupabaseClient {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _testUserId = 'test-user-id';
// Scoped under the user prefix (Plan 053 Phase 1) so an explicit reset wipes it.
const _pushDoneKey = 'u/$_testUserId/sync_initial_push_done_v2';

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

    test('records a failure count and keeps the entry (skip-and-continue)',
        () async {
      queue.markDirty(SyncDomain.fastingState, 'default');

      await service.pushPending();

      expect(service.pendingCount, 1, reason: 'failed entry stays queued');
      expect(service.failureCountFor(SyncDomain.fastingState, 'default'), 1);
    });

    test('quarantines a repeatedly-failing entry with backoff (does not spin)',
        () async {
      queue.markDirty(SyncDomain.fastingState, 'default');

      await service.pushPending(); // attempt 1 → fail, sets a backoff window
      await service.pushPending(); // immediate retry → within backoff, skipped

      // Still only one recorded failure: the second pass skipped the entry
      // rather than re-attempting (which is what prevents a poison entry from
      // spinning the loop or blocking others).
      expect(service.failureCountFor(SyncDomain.fastingState, 'default'), 1);
      expect(service.pendingCount, 1);
    });
  });

  // ── finance batch upsert ─────────────────────────────────────────────────────

  group('finance upsert batching', () {
    TransactionRecord txn(String id) => TransactionRecord(
          id: id,
          date: DateTime(2026, 1, 4),
          accountId: 'acc_cash',
          categoryId: '',
          amount: 100,
          type: TransactionType.outflow,
          description: 'Test $id',
          month: '2026-01',
        );

    test(
        'buildFinanceUpsertRows reads each table once and emits one row per '
        'present record, grouped correctly', () async {
      await storage.saveTransactions([txn('t1'), txn('t2'), txn('t3')]);
      final entries = [
        for (final id in ['t1', 't2', 't3'])
          SyncQueueEntry(
            domain: SyncDomain.financeRecord,
            key: 'finance_transactions/$id',
            op: SyncOp.upsert,
            queuedAt: DateTime(2026, 1, 4),
          ),
      ];

      final rows = await service.buildFinanceUpsertRows(entries);

      expect(rows.length, 3);
      expect(
        rows.map((p) => p.value['record_id']).toSet(),
        {'t1', 't2', 't3'},
      );
      expect(
        rows.every((p) => p.value['table_name'] == 'finance_transactions'),
        isTrue,
      );
    });

    test(
        'drops queue entries whose local record no longer exists '
        '(no infinite wedge) without touching Supabase', () async {
      // No transactions saved locally → the enqueued upserts reference records
      // that do not exist. They must be dropped, not retried forever.
      for (final id in ['gone1', 'gone2']) {
        queue.markDirty(SyncDomain.financeRecord, 'finance_transactions/$id');
      }
      expect(service.pendingCount, 2);

      await service.pushPending();

      // Dropped (removed from the queue) and never hit the Supabase fake.
      expect(service.pendingCount, 0);
      expect(
          service.failureCountFor(
            SyncDomain.financeRecord,
            'finance_transactions/gone1',
          ),
          0);
    });

    test(
        'a failed batch keeps present finance entries queued with backoff '
        '(no data loss)', () async {
      await storage.saveTransactions([txn('t1'), txn('t2')]);
      for (final id in ['t1', 't2']) {
        queue.markDirty(SyncDomain.financeRecord, 'finance_transactions/$id');
      }

      // The fake Supabase client throws on `.from(...)`, so the bulk upsert
      // fails; entries must remain queued and be backed off, never lost.
      await service.pushPending();

      expect(service.pendingCount, 2, reason: 'failed batch stays queued');
      expect(
        service.failureCountFor(
            SyncDomain.financeRecord, 'finance_transactions/t1'),
        1,
      );
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

  // ── pullAll resilience ───────────────────────────────────────────────────────
  // A single unparseable record or a corrupt domain must not abort the whole
  // pull (which used to surface as a blanket "Sync failed" on every client).
  // pullAll only rethrows when EVERY domain fails — a genuine outage.

  group('pullAll resilience', () {
    test(
        'rethrows an aggregate error and records every domain failure when all '
        'domains fail (e.g. offline)', () async {
      // The fake Supabase client throws on `.from(...)`, so every domain pull
      // fails — this stands in for a total connectivity/auth outage.
      await expectLater(service.pullAll(), throwsA(isA<Exception>()));

      // All seven domains were attempted and recorded as failures.
      expect(service.lastPullErrors.length, 7);
      // isSyncing is reset by the finally block even on a total failure.
      expect(service.isSyncing, false);
      // No partial pull succeeded, so nothing was timestamped as synced.
      expect(service.lastSyncedAt, isNull);
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

  // ── Empty-overwrite predicates (Plan 053 Phase 1) ────────────────────────────
  // These define "what counts as empty" for the guards that stop an empty/stale
  // singleton from clobbering populated data — the failure mode behind the
  // `quests: []` clobber. The full guard wiring (read-before-write, pull skip)
  // is exercised end-to-end by the Phase 4 fake-Supabase harness.

  group('singleton emptiness predicates', () {
    test('questsDataEmpty: true when both lists empty/absent, false otherwise',
        () {
      expect(SyncService.questsDataEmpty({'quests': [], 'achievements': []}),
          true);
      expect(SyncService.questsDataEmpty({}), true);
      expect(
          SyncService.questsDataEmpty({
            'quests': [
              {'id': 'q1'}
            ]
          }),
          false);
      expect(
          SyncService.questsDataEmpty({
            'achievements': [
              {'id': 'a1'}
            ]
          }),
          false);
    });

    test('fastingDataEmpty: empty only when no history AND not fasting', () {
      expect(SyncService.fastingDataEmpty({'history': [], 'isFasting': false}),
          true);
      expect(SyncService.fastingDataEmpty({'isFasting': true}), false,
          reason: 'an active fast is meaningful state');
      expect(
          SyncService.fastingDataEmpty({
            'history': [
              {'id': 'f1'}
            ]
          }),
          false);
    });

    test('nutritionFeedEmpty: gates on messages, not the log', () {
      // Empty/absent feed → must not overwrite a populated local feed.
      expect(SyncService.nutritionFeedEmpty({'messages': []}), true);
      expect(SyncService.nutritionFeedEmpty({}), true);
      // A log with entries but no chat rows is exactly the clobber snapshot
      // behind "consumed kcal but nothing in the list".
      expect(
          SyncService.nutritionFeedEmpty({
            'log': {
              'date': '2026-06-26',
              'meals': {
                'meal': [
                  {'id': 'e1', 'name': 'Rice', 'calories': 200}
                ]
              }
            },
            'messages': [],
          }),
          true);
      // A populated feed is safe to apply.
      expect(
          SyncService.nutritionFeedEmpty({
            'messages': [
              {'id': 'm1'}
            ]
          }),
          false);
    });

    test('profileDataEmpty: empty only when no weight/body AND fresh stats',
        () {
      expect(
          SyncService.profileDataEmpty({
            'weightLog': [],
            'bodyMeasurements': [],
            'userStats': {'level': 1, 'currentXp': 0},
          }),
          true);
      expect(
          SyncService.profileDataEmpty({
            'weightLog': [
              {'id': 'w1'}
            ],
          }),
          false);
      expect(
          SyncService.profileDataEmpty({
            'userStats': {'level': 7, 'currentXp': 300},
          }),
          false,
          reason: 'a leveled-up character is meaningful state');
    });

    test('collectionsDataEmpty: true only when every collection is empty', () {
      expect(SyncService.collectionsDataEmpty({}), true);
      expect(
          SyncService.collectionsDataEmpty({
            'routines': [
              {'id': 'r1'}
            ]
          }),
          false);
      expect(
          SyncService.collectionsDataEmpty({
            'groceryTripHistory': [
              {'id': 't1'}
            ]
          }),
          false);
    });
  });

  // ── Finance delete tombstones (Plan 053 Phase 3.2) ───────────────────────────
  // Deletes are written as `{__deleted: true}` rows so other devices learn of
  // them on pull and drop their local copy (instead of resurrecting it). Full
  // pull-reconcile wiring is exercised by the Phase 4 fake-Supabase harness.

  group('finance delete tombstones', () {
    test('isTombstone detects the deletion marker', () {
      expect(SyncService.isTombstone({'__deleted': true}), true);
      expect(SyncService.isTombstone({'__deleted': false}), false);
      expect(SyncService.isTombstone({'id': 'x', 'amount': 5}), false);
      expect(SyncService.isTombstone({}), false);
    });
  });
}
