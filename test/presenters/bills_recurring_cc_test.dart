import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

Bill _bill({
  required String id,
  required String month,
  bool isRecurring = false,
  BillType billType = BillType.utility,
  bool isPaid = false,
  String? transactionId,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: billType,
      amount: 100,
      dueDay: 4,
      month: month,
      categoryId: '',
      isRecurring: isRecurring,
      isPaid: isPaid,
      transactionId: transactionId,
    );

/// A 'YYYY-MM' key [delta] months from now (delta may be negative).
String _monthKey(int delta) {
  final now = DateTime.now();
  return toMonthKey(DateTime(now.year, now.month + delta));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;

  void stubStorage(List<Bill> bills) {
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => bills);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  BillsReceivablesPresenter build() {
    final ledger = LedgerPresenter(storage, stats);
    return BillsReceivablesPresenter(storage, ledger, stats);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
  });

  group('future recurring credit-card cleanup', () {
    test('removes future-month recurring CC statements, keeps others',
        () async {
      final future = _monthKey(2);
      stubStorage([
        _bill(
            id: 'cc-future',
            month: future,
            isRecurring: true,
            billType: BillType.creditCard),
        _bill(
            id: 'rent-future',
            month: future,
            isRecurring: true,
            billType: BillType.utility),
        _bill(
            id: 'cc-current',
            month: _monthKey(0),
            isRecurring: true,
            billType: BillType.creditCard),
      ]);

      final presenter = build();
      await presenter.load();
      await presenter.setMonth(future);

      final ids = presenter.bills.map((b) => b.id).toSet();
      expect(ids.contains('cc-future'), isFalse,
          reason: 'future recurring CC copy should be cleaned up');
      expect(ids.contains('rent-future'), isTrue,
          reason: 'non-CC recurring bill must be untouched');

      // Current-month CC bill is never touched by the future-only cleanup.
      await presenter.setMonth(_monthKey(0));
      expect(presenter.bills.map((b) => b.id), contains('cc-current'));
    });

    test('keeps a future CC bill that has a linked transaction', () async {
      final future = _monthKey(2);
      stubStorage([
        _bill(
            id: 'cc-paid',
            month: future,
            isRecurring: true,
            billType: BillType.creditCard,
            transactionId: 'txn-1'),
      ]);

      final presenter = build();
      await presenter.load();
      await presenter.setMonth(future);

      expect(presenter.bills.map((b) => b.id), contains('cc-paid'),
          reason: 'a transacted bill must never be auto-deleted');
    });
  });

  group('recurring auto-copy excludes credit cards', () {
    test('copies recurring non-CC bills forward but not CC ones', () async {
      final current = _monthKey(0);
      final next = _monthKey(1);
      stubStorage([
        _bill(
            id: 'cc',
            month: current,
            isRecurring: true,
            billType: BillType.creditCard),
        _bill(
            id: 'rent',
            month: current,
            isRecurring: true,
            billType: BillType.utility),
      ]);

      final presenter = build();
      await presenter.load();
      await presenter.setMonth(next);

      final names = presenter.bills.map((b) => b.name).toSet();
      expect(names.contains('Bill rent'), isTrue,
          reason: 'recurring utility bill should copy forward');
      expect(names.any((n) => n == 'Bill cc'), isFalse,
          reason: 'recurring credit-card bill must not copy forward');
    });
  });
}
