import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/services/sync_clock.dart';
import 'package:intermittent_fasting/services/sync_queue.dart';
import 'package:intermittent_fasting/services/sync_service.dart';
import 'fake_postgrest.dart';

/// Phase 5: ordering edits from devices whose clocks disagree.
///
/// Last-write-wins has to order *edits*, and an edit time can only be measured
/// on the device that made it — so no server trigger normalises it by itself.
/// The device measures its own offset against the server's clock and writes
/// `client_edited_at` already corrected into that frame. Without this, a
/// browser running fast out-ranks a phone's genuinely newer edit and a
/// corrected balance reverts. See docs/sync_conflict_resolution_spec.md.
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

  group('SyncClock', () {
    test('converts between device and server frames', () {
      final clock = SyncClock(_userId)
        ..setOffsetForTest(const Duration(minutes: 5));
      final deviceTime = DateTime.utc(2026, 8, 14, 12);

      expect(clock.toServerFrame(deviceTime), DateTime.utc(2026, 8, 14, 12, 5));
      expect(clock.toDeviceFrame(DateTime.utc(2026, 8, 14, 12, 5)), deviceTime);
    });

    test('learns the offset from an observed server timestamp', () async {
      final clock = SyncClock(_userId);
      final deviceNow = DateTime.utc(2026, 8, 14, 12);

      await clock.observeServerTime(
          deviceNow.add(const Duration(minutes: 4)), deviceNow);

      expect(clock.offset, const Duration(minutes: 4));
    });

    test('ignores an implausible offset rather than reordering everything',
        () async {
      final clock = SyncClock(_userId);
      final deviceNow = DateTime.utc(2026, 8, 14, 12);

      await clock.observeServerTime(
          deviceNow.add(const Duration(days: 400)), deviceNow);

      expect(clock.offset, Duration.zero);
    });

    test('a sub-second difference is not worth rewriting prefs for', () async {
      final clock = SyncClock(_userId);
      final deviceNow = DateTime.utc(2026, 8, 14, 12);

      await clock.observeServerTime(
          deviceNow.add(const Duration(milliseconds: 200)), deviceNow);

      expect(clock.offset, Duration.zero);
    });
  });

  group('with migration 054 applied', () {
    test('a push records the edit time, not just the push time', () async {
      await storage.saveTransactions([txn('t1')]);
      final editedAt = queue.entries.single.queuedAt;

      await service.pushPending();

      final row = cloudRow('t1');
      expect(row['client_edited_at'], isNotNull);
      // updated_at is the server's stamp; client_edited_at is the edit.
      expect(
          DateTime.parse(row['client_edited_at'] as String).isAfter(editedAt),
          isFalse,
          reason: 'edit time must not drift forward into push time');
    });

    test('the device learns the server offset from its own push', () async {
      backend.serverClockSkew = const Duration(minutes: 7);
      await storage.saveTransactions([txn('t1')]);

      await service.pushPending();

      expect(service.clock.offset.inMinutes, closeTo(7, 1));
    });

    test(
        'a fast-running device does not out-rank a genuinely newer edit from '
        'a correct one', () async {
      // The reported failure mode. This device's clock runs 10 minutes fast, so
      // pre-Phase-5 its stale edit carried a future-dated stamp and beat the
      // other device's newer one.
      backend.serverClockSkew = const Duration(minutes: -10);
      await storage.saveTransactions([txn('t1', amount: 100)]);
      await service.pushPending(); // learns offset ≈ -10min
      expect(service.clock.offset.inMinutes, closeTo(-10, 1));

      // Another device (correct clock) edits 1 minute ago in SERVER frame —
      // which is *older* than this device's raw wall clock but newer than its
      // corrected edit time.
      backend.seed('finance_records', {
        'user_id': _userId,
        'table_name': 'finance_transactions',
        'record_id': 't1',
        'data': txn('t1', amount: 555).toJson(),
        'updated_at': backend.serverNow.toIso8601String(),
        'client_edited_at': backend.serverNow
            .subtract(const Duration(seconds: 30))
            .toIso8601String(),
      });

      // This device queues another edit now and pushes.
      await storage.saveTransactions([txn('t1', amount: 200)]);
      await service.pushPending();

      // Our edit really is the newest one, so it should win — and it does,
      // because both sides are compared in the same frame.
      expect((cloudRow('t1')['data'] as Map)['amount'], 200);

      // Now the same setup, but the other device's edit is genuinely newer.
      backend.seed('finance_records', {
        'user_id': _userId,
        'table_name': 'finance_transactions',
        'record_id': 't1',
        'data': txn('t1', amount: 777).toJson(),
        'updated_at': backend.serverNow.toIso8601String(),
        'client_edited_at':
            backend.serverNow.add(const Duration(minutes: 5)).toIso8601String(),
      });
      await storage.saveTransactions([txn('t1', amount: 300)]);
      await service.pushPending();

      expect((cloudRow('t1')['data'] as Map)['amount'], 777,
          reason: 'the other device edited later in the shared frame');
    });

    test('a legacy row without client_edited_at still orders by updated_at',
        () async {
      backend.seed('finance_records', {
        'user_id': _userId,
        'table_name': 'finance_transactions',
        'record_id': 't1',
        'data': txn('t1', amount: 555).toJson(),
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        // no client_edited_at — written before migration 054
      });
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      expect((cloudRow('t1')['data'] as Map)['amount'], 555,
          reason: 'falls back to updated_at rather than ignoring the row');
    });
  });

  group('without migration 054 applied', () {
    setUp(() async {
      backend.hasEditTimeColumn = false;
      backend.applyUpdatedAtTrigger = false;
      await build();
    });

    test('sync still works — the column is probed, not assumed', () async {
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      expect(
          backend.rowWhere('finance_records', {'record_id': 't1'}), isNotNull,
          reason: 'a missing column must not break every push');
      expect(queue.pendingCount, 0);
    });

    test('written rows carry no edit-time column', () async {
      await storage.saveTransactions([txn('t1')]);

      await service.pushPending();

      expect(cloudRow('t1').containsKey('client_edited_at'), isFalse);
    });

    test('conflicts still resolve, on updated_at as before', () async {
      backend.seed('finance_records', {
        'user_id': _userId,
        'table_name': 'finance_transactions',
        'record_id': 't1',
        'data': txn('t1', amount: 555).toJson(),
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      await storage.saveTransactions([txn('t1', amount: 100)]);

      await service.pushPending();

      expect((cloudRow('t1')['data'] as Map)['amount'], 555);
    });

    test('the probe runs once, not per record', () async {
      await storage
          .saveTransactions([txn('t1'), txn('t2'), txn('t3'), txn('t4')]);

      await service.pushPending();

      final probes = backend.requests
          .where((r) => r.method == 'GET' && r.table == 'finance_records')
          .length;
      expect(probes, lessThanOrEqualTo(2),
          reason: 'one capability probe plus the stamp lookup');
    });
  });
}
