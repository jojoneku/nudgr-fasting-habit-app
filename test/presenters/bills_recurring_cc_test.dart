import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
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

/// A "shifted" card: the payment-due day is on/before the statement day, so
/// the payment for a cycle rolls into the following month. statementDay 1
/// keeps generation deterministic (the close day has always passed).
FinancialAccount _shiftedCard(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 10000,
      statementDay: 1,
      paymentDueDay: 1,
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
        'keeps both when a user-created bill covers the same card+month, '
        'rather than deleting the statement in the background', () async {
      final month = _monthKey(0);
      stubStorage([
        // A bill the user made. Bill.accountId means "preferred payment
        // account", so this is indistinguishable from the card's own statement
        // — it may just be a bill payable FROM the card.
        _statement(
            id: 'manual',
            accountId: 'sp',
            month: month,
            auto: false,
            billType: BillType.other),
        _statement(id: 'auto', accountId: 'sp', month: month),
      ]);
      // A category must exist so statement generation/dedup runs at all.
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);

      final presenter = build();
      await presenter.load();

      final ids = presenter.bills.map((b) => b.id).toSet();
      expect(ids, containsAll(<String>['manual', 'auto']),
          reason: 'this pass runs on app open, where a silently removed '
              'statement for money still owed cannot be noticed or undone');
    });

    test('still drops a stray second auto-statement for the same card+month',
        () async {
      // Two GENERATED statements is an internal duplicate: both are app-made,
      // so collapsing them loses nothing and needs no telling. This is the only
      // removal the pass still performs.
      final month = _monthKey(0);
      stubStorage([
        _statement(id: 'auto-a', accountId: 'sp', month: month, isPaid: true),
        _statement(id: 'auto-b', accountId: 'sp', month: month),
      ]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);

      final presenter = build();
      await presenter.load();

      final ids = presenter.bills.map((b) => b.id).toSet();
      expect(ids, contains('auto-a'),
          reason: 'the paid statement is authoritative');
      expect(ids.contains('auto-b'), isFalse,
          reason: 'the redundant generated copy should be collapsed');
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

  group('statement due-month filing', () {
    Future<BillsReceivablesPresenter> buildWithAccounts(
      List<FinancialAccount> accounts,
      List<Bill> bills,
    ) async {
      stubStorage(bills);
      when(storage.loadAccounts()).thenAnswer((_) async => accounts);
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

    test('due day after close → statement files under the cycle month',
        () async {
      final presenter = await buildWithAccounts([_card('cc', 500)], []);

      final stmt = presenter.allBillsForTest
          .firstWhere((b) => b.accountId == 'cc' && b.isAutoStatement);
      expect(stmt.month, _monthKey(0));
      expect(stmt.amount, 500);
    });

    test('due day on/before close → statement files under the NEXT month',
        () async {
      final presenter = await buildWithAccounts([_shiftedCard('cc', 500)], []);

      final stmt = presenter.allBillsForTest
          .firstWhere((b) => b.accountId == 'cc' && b.isAutoStatement);
      expect(stmt.month, _monthKey(1),
          reason: 'payment is due next month — filing it under the cycle '
              'month makes it instantly overdue');
      expect(stmt.amount, 500);
      // Nothing left behind in the cycle month.
      expect(
        presenter.allBillsForTest
            .where((b) => b.accountId == 'cc' && b.month == _monthKey(0)),
        isEmpty,
      );
    });

    test('migration relocates a mis-filed unpaid statement, no duplicate',
        () async {
      // Pre-fix state: the shifted card's statement was filed under the cycle
      // (current) month, where it read as overdue.
      final presenter = await buildWithAccounts(
        [_shiftedCard('cc', 500)],
        [_statement(id: 'legacy', accountId: 'cc', month: _monthKey(0))],
      );

      final statements = presenter.allBillsForTest
          .where((b) => b.accountId == 'cc' && b.isAutoStatement)
          .toList();
      expect(statements, hasLength(1),
          reason: 'the generator must not duplicate the relocated bill');
      expect(statements.single.id, 'legacy');
      expect(statements.single.month, _monthKey(1));
    });

    test('paid legacy statement at the cycle month suppresses ₱0 backfill',
        () async {
      // Two settled cycles recorded under the old scheme (cycle month).
      final presenter = await buildWithAccounts(
        [_shiftedCard('cc', 500)],
        [
          _statement(
              id: 'old-2', accountId: 'cc', month: _monthKey(-2), isPaid: true),
          _statement(
              id: 'old-1', accountId: 'cc', month: _monthKey(-1), isPaid: true),
        ],
      );

      // The -1 cycle is already covered by its legacy paid bill — no ₱0
      // placeholder may appear in the current month.
      expect(
        presenter.allBillsForTest.where((b) =>
            b.accountId == 'cc' && b.month == _monthKey(0) && b.amount == 0),
        isEmpty,
      );
      // The current cycle's live statement lands in next month as usual.
      final current = presenter.allBillsForTest.firstWhere((b) =>
          b.accountId == 'cc' && b.month == _monthKey(1) && b.isAutoStatement);
      expect(current.amount, 500);
    });

    // The backfill window used to start at nextMonth(oldest statement). Once
    // the oldest auto-statement sat in the current month — or a future one —
    // that start ran past today, the month list came out empty, and NO card got
    // a statement. Whichever card closed first won; the rest were never billed.
    test(
        'a statement already filed for this month still leaves the window '
        'open for another card', () async {
      final month = _monthKey(0);
      final presenter = await buildWithAccounts(
        [_card('bpi', 6393.46), _card('sp', 1011.31)],
        [_statement(id: 'bpi-auto', accountId: 'bpi', month: month)],
      );

      final spStatements = presenter.allBillsForTest
          .where((b) => b.accountId == 'sp' && b.isAutoStatement)
          .toList();
      expect(spStatements, hasLength(1),
          reason: "the first card's statement must not suppress the second's");
      expect(spStatements.single.month, month);
      expect(spStatements.single.amount, 1011.31);

      // And the card that already had one is left exactly as it was.
      expect(
        presenter.allBillsForTest
            .where((b) => b.accountId == 'bpi' && b.isAutoStatement),
        hasLength(1),
      );
    });

    test('a statement filed under a future due month leaves the window open',
        () async {
      // A shifted card files under next month, so the oldest — and only —
      // auto-statement can legitimately live in the future.
      final presenter = await buildWithAccounts(
        [_shiftedCard('bpi', 500), _card('sp', 1011.31)],
        [_statement(id: 'bpi-auto', accountId: 'bpi', month: _monthKey(1))],
      );

      final spStatements = presenter.allBillsForTest
          .where((b) => b.accountId == 'sp' && b.isAutoStatement)
          .toList();
      expect(spStatements, hasLength(1));
      expect(spStatements.single.month, _monthKey(0));
      expect(spStatements.single.amount, 1011.31);
    });
  });

  group('statement amount is the closing balance', () {
    /// A charge on card 'sp' dated [on].
    TransactionRecord charge(String id, double amount, DateTime on) =>
        TransactionRecord(
          id: id,
          date: on,
          accountId: 'sp',
          categoryId: 'c1',
          amount: amount,
          type: TransactionType.outflow,
          description: id,
          month: toMonthKey(on),
        );

    test('excludes charges made after the cycle closed', () async {
      // statementDay 1, so the close has always passed whatever day this runs.
      // 1011.31 was on the card at the close; 500 was charged afterwards and
      // belongs to the next cycle. The generator used to read today's live
      // balance, billing all 1511.31 into the closed cycle — and never
      // correcting it.
      final now = DateTime.now();
      final atClose = DateTime(now.year, now.month, 1);
      final afterClose = now.add(const Duration(days: 1));

      stubStorage([]);
      when(storage.loadAccounts())
          .thenAnswer((_) async => [_card('sp', 1511.31)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.loadTransactions()).thenAnswer((_) async => [
            charge('at-close', 1011.31, atClose),
            charge('after-close', 500, afterClose),
          ]);

      final ledger = LedgerPresenter(storage, stats);
      await _waitForLoad(ledger);
      final presenter = BillsReceivablesPresenter(storage, ledger, stats);
      await presenter.load();

      final stmt = presenter.allBillsForTest
          .firstWhere((b) => b.accountId == 'sp' && b.isAutoStatement);
      expect(stmt.amount, closeTo(1011.31, 0.001),
          reason: 'a charge made after the close date belongs to the next '
              'cycle, not the statement that already closed');
    });

    test('skips the statement when everything was charged after the close',
        () async {
      // Nothing had closed, so there is no statement to bill yet.
      final afterClose = DateTime.now().add(const Duration(days: 1));

      stubStorage([]);
      when(storage.loadAccounts()).thenAnswer((_) async => [_card('sp', 800)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.loadTransactions())
          .thenAnswer((_) async => [charge('after-close', 800, afterClose)]);

      final ledger = LedgerPresenter(storage, stats);
      await _waitForLoad(ledger);
      final presenter = BillsReceivablesPresenter(storage, ledger, stats);
      await presenter.load();

      expect(
        presenter.allBillsForTest
            .where((b) => b.accountId == 'sp' && b.isAutoStatement),
        isEmpty,
      );
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

    test('clearing a shifted card reconciles its next-month statement',
        () async {
      stubStorage([]);
      when(storage.loadAccounts()).thenAnswer(
          (_) async => [_shiftedCard('sp', 500), _bank('gcash', 5000)]);
      when(storage.loadFinanceCategories())
          .thenAnswer((_) async => [_expenseCat('c1')]);
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      final ledger = LedgerPresenter(storage, stats);
      await _waitForLoad(ledger);
      final presenter = BillsReceivablesPresenter(storage, ledger, stats);
      await presenter.load(); // auto-generates the statement under next month

      await presenter.quickPayCard(
          accountId: 'sp', fromAccountId: 'gcash', amount: 500);

      final stmt = presenter.allBillsForTest.firstWhere(
          (b) => b.accountId == 'sp' && b.isAutoStatement,
          orElse: () => fail('statement bill missing'));
      expect(stmt.month, _monthKey(1));
      expect(stmt.isPaid, isTrue,
          reason: 'clearing the card must settle the statement even though '
              'it is filed under next month');
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
