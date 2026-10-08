import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';
import 'fake_postgrest.dart';

/// Plan 062 A: an outdated build must not overwrite finance data a newer build
/// wrote. A browser tab left open across an update read six installment
/// purchases without `isInstallment` and wrote them back stripped; edit-time
/// ordering could not stop it, because the stale tab's edit was fresh.
/// Migration 057 records the data version on each row and skips any update
/// from a lower one; the client sends its version and treats a skipped row as
/// a lost conflict.
const _userId = 'test-user-id';

void main() {
  late FakePostgrest backend;
  late SupabaseClient supabase;
  late LocalStorageService storage;
  late SyncQueue queue;
  late SyncService service;

  TransactionRecord txn(String id,
          {double amount = 100, bool isInstallment = false}) =>
      TransactionRecord(
        id: id,
        date: DateTime(2026, 9, 4),
        accountId: 'acc_shopeepay',
        categoryId: '',
        amount: amount,
        type: TransactionType.outflow,
        description: 'Test $id',
        month: '2026-09',
        installmentId: isInstallment ? 'plan_$id' : null,
        isInstallment: isInstallment,
      );

  Future<void> build() async {
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
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakePostgrest();
    supabase =
        SupabaseClient('http://localhost', 'test-key', httpClient: backend);
    await build();
  });

  tearDown(() async {
    service.dispose();
    await supabase.dispose();
  });

  Map<String, dynamic> cloudRow(String id) =>
      backend.rowWhere('finance_records', {'record_id': id})!;

  /// A row another device wrote: data version [version], edited [ago] before
  /// now — older than anything this test edits, so edit-time ordering alone
  /// would let this device overwrite it.
  void seedRow(String id, Map<String, dynamic> data,
      {int? version, Duration ago = const Duration(hours: 1)}) {
    final at = backend.serverNow.subtract(ago).toIso8601String();
    backend.seed('finance_records', {
      'user_id': _userId,
      'table_name': 'finance_transactions',
      'record_id': id,
      'data': data,
      'updated_at': at,
      'client_edited_at': at,
      if (version != null) 'data_version': version,
    });
  }

  test('every finance write carries this build\'s data version', () async {
    await storage.saveTransactions([txn('t1')]);

    await service.pushPending();

    expect(cloudRow('t1')['data_version'], kFinanceDataVersion);
  });

  test('a row a newer build wrote is not overwritten, and the push lets go',
      () async {
    seedRow('t1', txn('t1', amount: 555).toJson(),
        version: kFinanceDataVersion + 1);
    await storage.saveTransactions([txn('t1', amount: 100)]);

    await service.pushPending();

    expect((cloudRow('t1')['data'] as Map)['amount'], 555);
    expect(cloudRow('t1')['data_version'], kFinanceDataVersion + 1);
    expect(service.pendingCount, 0,
        reason: 'a skipped write is a lost conflict, not a retry loop');
  });

  test('a delete cannot tombstone a row a newer build wrote', () async {
    await storage.saveTransactions([txn('t1'), txn('t2')]);
    await service.pushPending();
    seedRow('t1', txn('t1', amount: 555).toJson(),
        version: kFinanceDataVersion + 1);

    await storage.saveTransactions([txn('t2')]); // t1 deleted locally
    await service.pushPending();

    expect(cloudRow('t1')['data'], isNot(contains('__deleted')));
    expect(service.pendingCount, 0);
  });

  test('an outdated client cannot strip a field from a current row', () async {
    // What the old browser tab did: write a known row back without the field
    // and without any data version.
    await storage.saveTransactions([txn('buy1', isInstallment: true)]);
    await service.pushPending();
    expect(cloudRow('buy1')['data_version'], kFinanceDataVersion);

    final stripped = Map<String, dynamic>.from(cloudRow('buy1')['data'] as Map)
      ..remove('isInstallment');
    await supabase.from('finance_records').upsert({
      'user_id': _userId,
      'table_name': 'finance_transactions',
      'record_id': 'buy1',
      'data': stripped,
      'updated_at': backend.serverNow.toIso8601String(),
    });

    expect((cloudRow('buy1')['data'] as Map)['isInstallment'], isTrue);
  });

  test('rows written before the migration stay writable by anyone', () async {
    seedRow('t1', txn('t1', amount: 555).toJson()); // no data_version
    await storage.saveTransactions([txn('t1', amount: 100)]);

    await service.pushPending();

    expect((cloudRow('t1')['data'] as Map)['amount'], 100);
    expect(cloudRow('t1')['data_version'], kFinanceDataVersion);
  });

  group('without migration 057 applied', () {
    setUp(() async {
      backend.hasDataVersionColumn = false;
      backend.applyDataVersionGuard = false;
      await build();
    });

    test('sync still works — the column is probed, not assumed', () async {
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      expect((cloudRow('t1')['data'] as Map)['amount'], 100);
      expect(cloudRow('t1').containsKey('data_version'), isFalse);
      expect(service.pendingCount, 0);
    });
  });
}
