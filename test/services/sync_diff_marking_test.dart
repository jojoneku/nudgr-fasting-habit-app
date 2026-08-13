import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/sync_queue_entry.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';

/// Verifies the diff-based dirty marking that replaced "mark every record on
/// every save" (audit #1 + #2): only added / changed / removed finance records
/// are enqueued, unchanged records keep their sync timestamp, and the queue no
/// longer silently evicts a large backlog.
void main() {
  late LocalStorageService storage;
  late SyncQueue queue;

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

  Set<String> dirtyKeys() => queue.entries.map((e) => e.key).toSet();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    queue = SyncQueue();
    await queue.load();
    storage.setSyncQueue(queue);
  });

  test('a finance edit notifies onDirty so the auto-push is scheduled',
      () async {
    // onDirty drives SyncService.schedulePush (the 3s debounced upload). It was
    // never called for finance saves, so a ledger edit only reached the cloud
    // on the next resume/boot/manual sync — a focused web tab could hold an
    // entry indefinitely without uploading it.
    var notified = 0;
    storage.onDirty = () => notified++;

    await storage.saveTransactions([txn('t1')]);

    expect(notified, 1);
  });

  test('onDirty fires once per save, not once per record', () async {
    var notified = 0;
    storage.onDirty = () => notified++;

    await storage.saveTransactions([txn('t1'), txn('t2'), txn('t3')]);

    expect(notified, 1, reason: 'a bulk save must not fire a storm of pushes');
  });

  test('a save that changes nothing does not notify onDirty', () async {
    await storage.saveTransactions([txn('t1')]);
    var notified = 0;
    storage.onDirty = () => notified++;

    await storage.saveTransactions([txn('t1')]); // identical

    expect(notified, 0);
  });

  test('a remote apply does not notify onDirty', () async {
    var notified = 0;
    storage.onDirty = () => notified++;

    await storage.applyRemote(() async {
      await storage.saveTransactions([txn('t1')]);
    });

    expect(notified, 0, reason: 'pulled data must not schedule a push');
  });

  test('a delete also notifies onDirty', () async {
    await storage.saveTransactions([txn('t1')]);
    var notified = 0;
    storage.onDirty = () => notified++;

    await storage.saveTransactions([]); // t1 removed

    expect(notified, 1);
  });

  test('first save of new records marks each dirty once', () async {
    await storage.saveTransactions([txn('t1'), txn('t2'), txn('t3')]);
    expect(dirtyKeys(), {
      'finance_transactions/t1',
      'finance_transactions/t2',
      'finance_transactions/t3',
    });
    expect(queue.entries.every((e) => e.op == SyncOp.upsert), isTrue);
  });

  test('editing one record marks only that record dirty', () async {
    await storage.saveTransactions([txn('t1'), txn('t2'), txn('t3')]);
    queue.clear();

    await storage
        .saveTransactions([txn('t1', amount: 999), txn('t2'), txn('t3')]);

    expect(dirtyKeys(), {'finance_transactions/t1'});
  });

  test('re-saving an unchanged list marks nothing dirty', () async {
    final rows = [txn('t1'), txn('t2'), txn('t3')];
    await storage.saveTransactions(rows);
    queue.clear();

    await storage.saveTransactions(rows);

    expect(dirtyKeys(), isEmpty);
  });

  test('removing a record enqueues a delete for it only', () async {
    await storage.saveTransactions([txn('t1'), txn('t2')]);
    queue.clear();

    await storage.saveTransactions([txn('t1')]);

    expect(dirtyKeys(), {'finance_transactions/t2'});
    expect(
      queue.entries.firstWhere((e) => e.key == 'finance_transactions/t2').op,
      SyncOp.delete,
    );
  });

  test('an unrelated save does not bump an unchanged record\'s timestamp',
      () async {
    // This is the LWW-clobber fix: previously every save re-stamped every
    // record's timestamp to now, so a pull would then discard remote edits.
    await storage.saveTransactions([txn('t1'), txn('t2')]);
    final t2Stamp =
        queue.getTimestamp(SyncDomain.financeRecord, 'finance_transactions/t2');
    queue.clear();

    await storage.saveTransactions([txn('t1', amount: 5), txn('t2')]);

    expect(
      queue.getTimestamp(SyncDomain.financeRecord, 'finance_transactions/t2'),
      t2Stamp,
      reason: 'unchanged record keeps its original timestamp',
    );
  });

  test('a large dirty backlog is never evicted', () async {
    final rows = [for (var i = 0; i < 2000; i++) txn('t$i')];
    await storage.saveTransactions(rows);

    expect(queue.pendingCount, 2000);

    // Survives a persist + reload round trip.
    await Future<void>.delayed(Duration.zero); // let the microtask flush
    final reloaded = SyncQueue();
    await reloaded.load();
    expect(reloaded.pendingCount, 2000);
  });
}
