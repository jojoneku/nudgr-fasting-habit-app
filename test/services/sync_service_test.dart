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

      // All eight domains were attempted and recorded as failures.
      expect(service.lastPullErrors.length, 8);
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

  // ── conflict resolution (docs/sync_conflict_resolution_spec.md) ────────────
  // Last-write-wins used to be enforced only on pull: every push was an
  // unconditional upsert stamped "now", so a queued edit from hours ago won on
  // the server and was then pulled down over the newer copy on every other
  // device. These cover the rule that stops it and the queue bookkeeping that
  // keeps the loser from being stranded on data it gave up.

  group('cloudCopyWins', () {
    final earlier = DateTime.utc(2026, 8, 13, 10);
    final later = DateTime.utc(2026, 8, 13, 11);

    test('the cloud wins when its copy is newer than the local edit', () {
      expect(SyncService.cloudCopyWins(later, earlier), true);
    });

    test('the local edit wins when it is newer than the cloud copy', () {
      expect(SyncService.cloudCopyWins(earlier, later), false);
    });

    test('an equal stamp is not a conflict — a device may re-push its own row',
        () {
      expect(SyncService.cloudCopyWins(later, later), false);
    });

    test('no cloud row yet means no conflict', () {
      expect(SyncService.cloudCopyWins(null, earlier), false);
    });

    test('a seeding push (no edit time) is never gated', () {
      expect(SyncService.cloudCopyWins(later, null), false);
    });

    test('compares absolute instants across a local/UTC mix', () {
      // Cloud stamps parse as UTC; the local edit time is the device's wall
      // clock. Ordering must not depend on which zone each side carries.
      final localEdit = later.toLocal();
      expect(
          SyncService.cloudCopyWins(
              later.add(const Duration(minutes: 1)), localEdit),
          true);
      expect(
          SyncService.cloudCopyWins(
              later.subtract(const Duration(minutes: 1)), localEdit),
          false);
    });
  });

  group('queue bookkeeping for a lost conflict', () {
    test('discardEntry drops the superseded pending entry', () {
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_1');
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_2');

      queue.discardEntry(SyncDomain.financeRecord, 'finance_accounts/acc_1');

      expect(queue.pendingCount, 1);
      expect(queue.entries.single.key, 'finance_accounts/acc_2');
    });

    test('discardEntry is a no-op for a key that is not queued', () {
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_1');

      queue.discardEntry(SyncDomain.financeRecord, 'finance_accounts/nope');

      expect(queue.pendingCount, 1);
    });

    test(
        'invalidateTimestamp resets the watermark so the next pull adopts the '
        'cloud copy', () {
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_1');
      expect(
          queue
              .getTimestamp(SyncDomain.financeRecord, 'finance_accounts/acc_1')
              .millisecondsSinceEpoch,
          greaterThan(0),
          reason: 'markDirty stamps the local edit time');

      queue.invalidateTimestamp(
          SyncDomain.financeRecord, 'finance_accounts/acc_1');

      // Epoch 0 → any cloud stamp is `isAfter` it, so the pull cannot skip the
      // row as "local is newer" and strand this device on the copy it lost.
      expect(
          queue.getTimestamp(
              SyncDomain.financeRecord, 'finance_accounts/acc_1'),
          DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('invalidating one record leaves other watermarks alone', () {
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_1');
      queue.markDirty(SyncDomain.financeRecord, 'finance_accounts/acc_2');

      queue.invalidateTimestamp(
          SyncDomain.financeRecord, 'finance_accounts/acc_1');

      expect(
          queue
              .getTimestamp(SyncDomain.financeRecord, 'finance_accounts/acc_2')
              .millisecondsSinceEpoch,
          greaterThan(0));
    });
  });

  group('pushPending re-arms when it lands mid-cycle', () {
    test('a debounced push blocked by an in-flight sync is not dropped',
        () async {
      // pullAll holds _isSyncing for the whole cycle. A schedulePush firing in
      // that window used to be discarded outright, stranding the edit until the
      // next resume; it must re-arm instead.
      queue.markDirty(SyncDomain.fastingState, 'default');
      final pull = service.pullAll(); // sets _isSyncing

      fakeAsync((async) {
        service.pushPending(); // bails — a cycle is running
        async.elapse(const Duration(seconds: 4));
        // The re-armed debounce fired; the entry is still queued for it.
        expect(service.pendingCount, 1);
      });

      await pull.catchError((_) {});
    });

    test('an empty queue does not re-arm the debounce', () async {
      final pull = service.pullAll();
      await service.pushPending(); // nothing queued → no re-arm
      expect(service.pendingCount, 0);
      await pull.catchError((_) {});
    });
  });

  group('syncCycle', () {
    test('still pushes when the pull fails, instead of stranding the outbox',
        () async {
      // The fake client throws for every call, so the pull fails outright.
      queue.markDirty(SyncDomain.fastingState, 'default');

      await service.syncCycle();

      // The push was attempted despite the failed pull — proven by the failure
      // it recorded for the entry. Safe because each push checks the cloud
      // stamp itself before writing.
      expect(service.failureCountFor(SyncDomain.fastingState, 'default'), 1);
      expect(service.pendingCount, 1, reason: 'entry stays queued to retry');
    });

    test('a pull failure is swallowed rather than thrown to the caller',
        () async {
      await expectLater(service.syncCycle(), completes);
    });

    test('forceSync surfaces a pull failure — the user is watching', () async {
      await expectLater(service.forceSync(), throwsA(isA<Exception>()));
    });
  });

  // ── paged pulls (row-ceiling truncation) ───────────────────────────────────

  group('collectPages', () {
    /// A server that holds [total] rows and — like hosted Supabase — refuses to
    /// return more than [maxRows] in one response, silently.
    Future<List<Map<String, dynamic>>> Function(int, int) server({
      required int total,
      int maxRows = 1000,
    }) =>
        (from, to) async {
          if (from >= total) return const [];
          final requested = to - from + 1;
          final end = [from + requested, from + maxRows, total]
              .reduce((a, b) => a < b ? a : b);
          return [
            for (var i = from; i < end; i++) {'i': i},
          ];
        };

    test('returns every row when the total exceeds the response ceiling',
        () async {
      // The exact shape of the reported bug: 1,120 rows behind a 1,000-row
      // ceiling. A single select saw 1,000 and could not tell it was short.
      final rows = await SyncService.collectPages(server(total: 1120));

      expect(rows, hasLength(1120));
      expect(rows.first['i'], 0);
      expect(rows.last['i'], 1119);
      // No row fetched twice and none skipped.
      expect(rows.map((r) => r['i']).toSet(), hasLength(1120));
    });

    test('a total below one page costs a single extra empty probe', () async {
      var calls = 0;
      final rows = await SyncService.collectPages((from, to) async {
        calls++;
        return server(total: 19)(from, to);
      });

      expect(rows, hasLength(19));
      expect(calls, 2, reason: 'one full-ish page, then the terminating probe');
    });

    test('an exact multiple of the page size still terminates', () async {
      final rows = await SyncService.collectPages(
        server(total: 1000),
        pageSize: 500,
      );
      expect(rows, hasLength(1000));
    });

    test('an empty table yields nothing', () async {
      expect(await SyncService.collectPages(server(total: 0)), isEmpty);
    });

    test('stays correct when the server caps pages below what we asked for',
        () async {
      // Offsets advance by rows actually received, so a server handing back
      // 200 rows for a 500-row request does not truncate the walk.
      final rows = await SyncService.collectPages(
        server(total: 1120, maxRows: 200),
        pageSize: 500,
      );
      expect(rows, hasLength(1120));
      expect(rows.map((r) => r['i']).toSet(), hasLength(1120));
    });

    test('the runaway guard bounds a page source that never drains', () async {
      // A non-unique sort order re-serving the same page would otherwise spin
      // forever. Returns a partial result rather than hanging.
      final rows = await SyncService.collectPages(
        (from, to) async => [
          for (var i = 0; i < 10; i++) {'i': i},
        ],
        pageSize: 10,
        maxPages: 3,
      );
      expect(rows, hasLength(30));
    });

    test('the default page size sits below the hosted row ceiling', () {
      expect(SyncService.pullPageSize, lessThan(1000));
    });
  });
}
