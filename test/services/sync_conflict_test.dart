import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';
import 'fake_postgrest.dart';

/// End-to-end conflict resolution against a responding PostgREST fake.
///
/// These are the cases the throw-everything fake could never reach: they were
/// carried as `[inspect]` in docs/sync_conflict_resolution_spec.md because
/// nothing in the suite could answer a query. The headline one is the reported
/// bug — a device pushing a stale queued edit over a newer cloud record, then
/// propagating it everywhere.
const _userId = 'test-user-id';

void main() {
  late FakePostgrest backend;
  late SupabaseClient supabase;
  late LocalStorageService storage;
  late SyncQueue queue;
  late SyncService service;

  TransactionRecord txn(String id, {double amount = 100}) => TransactionRecord(
        id: id,
        date: DateTime(2026, 1, 4),
        accountId: 'acc_cash',
        categoryId: '',
        amount: amount,
        type: TransactionType.outflow,
        description: 'Test $id',
        month: '2026-01',
      );

  /// A cloud stamp later than any edit this test queues. Local watermarks come
  /// from `DateTime.now()`, so "another device wrote after me" is only
  /// expressible relative to now — a fixed date silently becomes the *older*
  /// side and the test then proves the opposite of what it claims.
  DateTime afterLocalEdit() =>
      DateTime.now().toUtc().add(const Duration(hours: 1));

  /// A cloud stamp earlier than any edit this test queues.
  DateTime beforeLocalEdit() =>
      DateTime.now().toUtc().subtract(const Duration(hours: 1));

  /// Writes a finance row into the cloud as if another device had pushed it.
  void seedCloudTxn(String id, {required DateTime at, double amount = 999}) {
    backend.seed('finance_records', {
      'user_id': _userId,
      'table_name': 'finance_transactions',
      'record_id': id,
      'data': txn(id, amount: amount).toJson(),
      'updated_at': at.toUtc().toIso8601String(),
    });
  }

  String key(String id) => 'finance_transactions/$id';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakePostgrest();
    supabase =
        SupabaseClient('http://localhost', 'test-key', httpClient: backend);
    storage = LocalStorageService();
    await storage.setUserId(_userId);
    queue = SyncQueue();
    await queue.load(userId: _userId);
    storage.setSyncQueue(queue);
    service = SyncService(
      supabase: supabase,
      storage: storage,
      queue: queue,
      userId: _userId,
    );
  });

  tearDown(() async {
    service.dispose();
    await supabase.dispose();
  });

  // ── the reported bug ───────────────────────────────────────────────────────

  group('a stale local edit never overwrites a newer cloud record', () {
    test('the push is abandoned and the cloud value survives', () async {
      // Web edits t1 at 10:00 and the push doesn't go out (tab backgrounded).
      await storage.saveTransactions([txn('t1', amount: 100)]);
      expect(queue.pendingCount, 1, reason: 'the edit is queued');

      // Mobile edits the same record at 11:00 and its push lands.
      seedCloudTxn('t1', at: afterLocalEdit(), amount: 555);

      // Web finally pushes. It must NOT clobber mobile's newer write.
      await service.pushPending();

      final cloud = backend.rowWhere('finance_records', {'record_id': 't1'})!;
      expect((cloud['data'] as Map)['amount'], 555,
          reason: "mobile's newer value must survive");
      expect(backend.postCountFor('finance_records'), 0,
          reason: 'no write should have been attempted at all');
      expect(service.lastConflictsLost, contains('financeRecord/${key('t1')}'));
    });

    test('the losing entry is dequeued rather than retried forever', () async {
      await storage.saveTransactions([txn('t1')]);
      seedCloudTxn('t1', at: afterLocalEdit());

      await service.pushPending();

      expect(queue.pendingCount, 0);
      expect(service.failureCountFor(SyncDomain.financeRecord, key('t1')), 0,
          reason: 'losing a conflict is a resolution, not a failure');
    });

    test('the next pull adopts the cloud copy, so local stops being stale',
        () async {
      await storage.saveTransactions([txn('t1', amount: 100)]);
      seedCloudTxn('t1', at: afterLocalEdit(), amount: 555);

      await service.pushPending();
      await service.pullAll();

      final local = await storage.loadTransactions();
      expect(local.single.amount, 555,
          reason: 'the device must not sit on the copy it just gave up');
    });
  });

  // ── the push still works when it should ───────────────────────────────────

  group('a push proceeds when the cloud is not newer', () {
    test('writes when the cloud row is older', () async {
      seedCloudTxn('t1', at: beforeLocalEdit(), amount: 555);
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      final cloud = backend.rowWhere('finance_records', {'record_id': 't1'})!;
      expect((cloud['data'] as Map)['amount'], 100);
      expect(queue.pendingCount, 0);
      expect(service.lastConflictsLost, isEmpty);
    });

    test('writes when there is no cloud row yet', () async {
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      expect(
          backend.rowWhere('finance_records', {'record_id': 't1'}), isNotNull);
      expect(queue.pendingCount, 0);
    });

    test('a failed write keeps the entry queued and backs it off', () async {
      await storage.saveTransactions([txn('t1')]);
      backend.failNextPostTo = 'finance_records';

      await service.pushPending();

      expect(queue.pendingCount, 1, reason: 'never lose the edit');
      expect(service.failureCountFor(SyncDomain.financeRecord, key('t1')), 1);
    });
  });

  // ── deletes ───────────────────────────────────────────────────────────────

  group('tombstone deletes obey the same rule', () {
    test('a delete queued before a newer remote edit is abandoned', () async {
      await storage.saveTransactions([txn('t1')]);
      await service.pushPending();
      backend.requests.clear();

      // Locally deleted...
      await storage.saveTransactions([]);
      expect(queue.entries.single.op, SyncOp.delete);
      // ...but another device edited it afterwards.
      seedCloudTxn('t1', at: afterLocalEdit(), amount: 777);

      await service.pushPending();

      final cloud = backend.rowWhere('finance_records', {'record_id': 't1'})!;
      expect(SyncService.isTombstone(cloud['data'] as Map<String, dynamic>),
          isFalse,
          reason: 'deleting wins only when it is the later action');
      expect((cloud['data'] as Map)['amount'], 777);
    });

    test('a delete newer than the cloud row writes its tombstone', () async {
      seedCloudTxn('t1', at: beforeLocalEdit());
      await storage.saveTransactions([txn('t1')]);
      await storage.saveTransactions([]);

      await service.pushPending();

      final cloud = backend.rowWhere('finance_records', {'record_id': 't1'})!;
      expect(SyncService.isTombstone(cloud['data'] as Map<String, dynamic>),
          isTrue);
    });

    test('a pulled tombstone removes the local record', () async {
      await storage.saveTransactions([txn('t1'), txn('t2')]);
      queue.clear();
      backend.seed('finance_records', {
        'user_id': _userId,
        'table_name': 'finance_transactions',
        'record_id': 't1',
        'data': {'__deleted': true},
        'updated_at': afterLocalEdit().toIso8601String(),
      });

      await service.pullAll();

      final local = await storage.loadTransactions();
      expect(local.map((t) => t.id), ['t2']);
    });
  });

  // ── pull bookkeeping ──────────────────────────────────────────────────────

  group('pull', () {
    test('adopting a remote copy discards the superseded pending entry',
        () async {
      await storage.saveTransactions([txn('t1', amount: 100)]);
      seedCloudTxn('t1', at: afterLocalEdit(), amount: 555);

      await service.pullAll();

      expect(queue.pendingCount, 0,
          reason: 'the local edit lost when the pull applied over it');
      final local = await storage.loadTransactions();
      expect(local.single.amount, 555);
    });

    test('a local edit newer than the cloud row is left alone', () async {
      seedCloudTxn('t1', at: beforeLocalEdit(), amount: 555);
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pullAll();

      final local = await storage.loadTransactions();
      expect(local.single.amount, 100, reason: 'local edit is newer');
      expect(queue.pendingCount, 1, reason: 'still needs pushing');
    });

    test('pages past the response-row ceiling', () async {
      // collectPages walks offset/limit windows; a paging bug silently returns
      // a partial treasury, which is how 1,120 records once came back as 1,000.
      for (var i = 0; i < SyncService.pullPageSize * 2 + 7; i++) {
        seedCloudTxn('t${i.toString().padLeft(4, '0')}', at: afterLocalEdit());
      }

      await service.pullAll();

      final local = await storage.loadTransactions();
      expect(local, hasLength(SyncService.pullPageSize * 2 + 7));
    });
  });

  // ── echo suppression ──────────────────────────────────────────────────────

  group('echo suppression', () {
    test('a pull right after a push adopts nothing and fires no reload',
        () async {
      var reloads = 0;
      storage.onRemoteDataApplied = () => reloads++;
      await storage.saveTransactions([txn('t1')]);
      await service.pushPending();

      // This is what a realtime echo of our own write triggers.
      await service.pullAll();

      expect(reloads, 0,
          reason: 'the device must not re-apply and reload on its own write');
    });

    test('a pull that does adopt something fires the reload', () async {
      var reloads = 0;
      storage.onRemoteDataApplied = () => reloads++;
      seedCloudTxn('t1', at: afterLocalEdit());

      await service.pullAll();

      expect(reloads, 1);
    });
  });

  // ── emptiness guards still hold ───────────────────────────────────────────

  group('emptiness guards are not weakened by the recency guard', () {
    test('an empty local quest list does not wipe a populated cloud row',
        () async {
      backend.seed('user_quests', {
        'user_id': _userId,
        'data': {
          'quests': [
            {'id': 'q1'}
          ],
          'achievements': [],
        },
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      queue.markDirty(SyncDomain.userQuests, 'default'); // local is empty

      await service.pushPending();

      final cloud = backend.rowWhere('user_quests', {'user_id': _userId})!;
      expect(((cloud['data'] as Map)['quests'] as List), hasLength(1),
          reason: 'empty local must never clobber a populated cloud row');
      expect(backend.postCountFor('user_quests'), 0);
    });
  });
}
