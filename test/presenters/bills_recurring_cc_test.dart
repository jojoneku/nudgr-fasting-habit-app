import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
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

/// A credit-card statement bill for [accountId]. [auto] carries the
/// auto-statement marker; set false to model a user-created bill for the card.
Bill _statement({
  required String id,
  required String accountId,
  required String month,
  bool auto = true,
  bool isPaid = false,
  BillType billType = BillType.creditCard,
}) =>
    Bill(
      id: id,
      name: '$accountId statement',
      billType: billType,
      amount: 500,
      dueDay: 15,
      month: month,
      categoryId: 'c1',
      accountId: accountId,
      isPaid: isPaid,
      paymentNote: auto ? Bill.autoStatementNote : null,
    );

FinancialAccount _card(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 10000,
      statementDay: 1,
      paymentDueDay: 15,
    );

FinancialAccount _bank(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.bank,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );

FinanceCategory _expenseCat(String id) => FinanceCategory(
      id: id,
      name: 'Misc',
      type: CategoryType.expense,
      icon: 'x',
      colorHex: '#FFFFFF',
    );

Future<void> _waitForLoad(LedgerPresenter p) async {
  while (p.isLoading) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
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

  group('duplicate credit statement dedup', () {
    test(
        'drops the redundant unpaid auto-statement when another bill covers '
        'the same card+month', () async {
      final month = _monthKey(0);
      stubStorage([
        // A user-created bill for the card (the "upper" one that stays deleted).
        _statement(
            id: 'manual',
            accountId: 'sp',
            month: month,
            auto: false,
            billType: BillType.other),
        // The auto-statement duplicate that used to regenerate on delete.
        _statement(id: 'auto', accountId: 'sp', month: month),
      ]);
      // A category must exist so statement generation/dedup runs at all.
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);

      final presenter = build();
      await presenter.load();

      final ids = presenter.bills.map((b) => b.id).toSet();
      expect(ids, contains('manual'),
          reason: 'the user-created bill must be kept');
      expect(ids.contains('auto'), isFalse,
          reason: 'the redundant unpaid auto-statement should be removed');
    });

    test('never removes a paid auto-statement even if another bill covers it',
        () async {
      final month = _monthKey(0);
      stubStorage([
        _statement(
            id: 'manual',
            accountId: 'sp',
            month: month,
            auto: false,
            billType: BillType.other),
        _statement(id: 'auto', accountId: 'sp', month: month, isPaid: true),
      ]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);

      final presenter = build();
      await presenter.load();

      final ids = presenter.bills.map((b) => b.id).toSet();
      expect(ids, containsAll(<String>['manual', 'auto']),
          reason: 'a paid statement is authoritative and must survive');
    });
  });

  group('quickPayCard statement reconciliation', () {
    Future<BillsReceivablesPresenter> buildWithCard(List<Bill> bills) async {
      stubStorage(bills);
      when(storage.loadAccounts())
          .thenAnswer((_) async => [_card('sp', 500), _bank('gcash', 5000)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      final ledger = LedgerPresenter(storage, stats);
      await _waitForLoad(ledger);
      final presenter = BillsReceivablesPresenter(storage, ledger, stats);
      await presenter.load();
      return presenter;
    }

    test('marks the statement bill paid when the payment clears the card',
        () async {
      final month = _monthKey(0);
      final presenter = await buildWithCard(
          [_statement(id: 'auto', accountId: 'sp', month: month)]);

      await presenter.quickPayCard(
          accountId: 'sp', fromAccountId: 'gcash', amount: 500);

      final bill = presenter.bills.firstWhere((b) => b.id == 'auto');
      expect(bill.isPaid, isTrue,
          reason: 'clearing the card should reconcile its statement bill');
    });

    test('leaves the statement unpaid on a partial payment', () async {
      final month = _monthKey(0);
      final presenter = await buildWithCard(
          [_statement(id: 'auto', accountId: 'sp', month: month)]);

      await presenter.quickPayCard(
          accountId: 'sp', fromAccountId: 'gcash', amount: 200);

      final bill = presenter.bills.firstWhere((b) => b.id == 'auto');
      expect(bill.isPaid, isFalse,
          reason: 'a partial payment still leaves a balance owed');
    });
  });
}
