import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';
import 'fake_postgrest.dart';

/// `createdAt` (Plan 065 phase 3) rides inside the finance row's JSON `data`,
/// so the cloud needs no new column. These check that the push carries it, a
/// pull gives it back unchanged, and a row from a build without the field
/// still loads.
const _userId = 'test-user-id';

void main() {
  late FakePostgrest backend;
  late SupabaseClient supabase;
  late LocalStorageService storage;
  late SyncQueue queue;
  late SyncService service;

  final created = DateTime(2026, 10, 3, 9, 15);

  TransactionRecord txn(String id, {DateTime? createdAt}) => TransactionRecord(
        id: id,
        date: DateTime(2026, 10, 3),
        accountId: 'acc_cash',
        categoryId: '',
        amount: 100,
        type: TransactionType.outflow,
        description: 'Test $id',
        month: '2026-10',
        createdAt: createdAt,
      );

  Bill bill(String id, {DateTime? createdAt}) => Bill(
        id: id,
        name: 'Bill $id',
        billType: BillType.utility,
        amount: 100,
        dueDay: 4,
        month: '2026-10',
        categoryId: '',
        createdAt: createdAt,
      );

  /// A cloud stamp later than any local edit, so the pull adopts the row.
  DateTime afterLocalEdit() =>
      DateTime.now().toUtc().add(const Duration(hours: 1));

  void seedCloud(String table, String id, Map<String, dynamic> data) {
    backend.seed('finance_records', {
      'user_id': _userId,
      'table_name': table,
      'record_id': id,
      'data': data,
      'updated_at': afterLocalEdit().toIso8601String(),
    });
  }

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

  test('a push carries createdAt in the row data', () async {
    await storage.saveTransactions([txn('t1', createdAt: created)]);
    await storage.saveBills([bill('b1', createdAt: created)]);

    await service.pushPending();

    final t = backend.rowWhere('finance_records', {'record_id': 't1'})!;
    final b = backend.rowWhere('finance_records', {'record_id': 'b1'})!;
    expect((t['data'] as Map)['createdAt'], created.toIso8601String());
    expect((b['data'] as Map)['createdAt'], created.toIso8601String());
  });

  test('a pull gives createdAt back unchanged', () async {
    seedCloud(
        'finance_transactions', 't1', txn('t1', createdAt: created).toJson());
    seedCloud('finance_bills', 'b1', bill('b1', createdAt: created).toJson());

    await service.pullAll();

    expect((await storage.loadTransactions()).single.createdAt, created);
    expect((await storage.loadBills()).single.createdAt, created);
  });

  test('a pulled row from a build without the field loads with null', () async {
    seedCloud(
        'finance_transactions', 't1', txn('t1').toJson()..remove('createdAt'));
    seedCloud('finance_bills', 'b1', bill('b1').toJson()..remove('createdAt'));

    await service.pullAll();

    final local = await storage.loadTransactions();
    expect(local.single.id, 't1');
    expect(local.single.createdAt, isNull);
    expect((await storage.loadBills()).single.createdAt, isNull);
    expect(service.lastSkippedRecords, isEmpty);
  });
}
