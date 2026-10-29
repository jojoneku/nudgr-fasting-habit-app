// Every create path stamps `createdAt` through the owning presenter, and no
// edit, undo or rewrite changes it (Plan 065 phase 3). Both presenters take an
// injected clock, so each stamp is checked against an exact time.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

FinancialAccount _bank(String id) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.bank,
      balance: 50000,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );

/// Closes the 25th, due the 10th: on Oct 3 the Sep 25 statement is due Oct 10.
FinancialAccount _card(String id, double balance) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 20000,
      statementDay: 25,
      paymentDueDay: 10,
    );

FinanceCategory _expenseCat(String id) => FinanceCategory(
      id: id,
      name: 'Misc',
      type: CategoryType.expense,
      icon: 'x',
      colorHex: '#FFFFFF',
    );

TransactionRecord _txn(
  String id, {
  String accountId = 'bpi',
  double amount = 250,
  DateTime? date,
  DateTime? createdAt,
}) {
  final on = date ?? DateTime(2026, 10, 2, 12);
  return TransactionRecord(
    id: id,
    date: on,
    accountId: accountId,
    categoryId: 'c1',
    amount: amount,
    type: TransactionType.outflow,
    description: id,
    month: toMonthKey(on),
    createdAt: createdAt,
  );
}

Bill _bill(
  String id, {
  String month = '2026-10',
  bool isRecurring = false,
  DateTime? createdAt,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: BillType.utility,
      amount: 100,
      dueDay: 4,
      month: month,
      categoryId: 'c1',
      isRecurring: isRecurring,
      createdAt: createdAt,
    );

Receivable _receivable(
  String id, {
  String month = '2026-10',
  bool isRecurring = false,
  DateTime? createdAt,
}) =>
    Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: 1000,
      expectedDate: DateTime.parse('$month-15'),
      month: month,
      categoryId: 'c1',
      isRecurring: isRecurring,
      createdAt: createdAt,
    );

BudgetedExpense _expense(
  String id, {
  String month = '2026-10',
  bool isRecurring = false,
  DateTime? createdAt,
}) =>
    BudgetedExpense(
      id: id,
      name: 'Set-aside $id',
      budgetedType: SetAsideType.savings,
      month: month,
      allocatedAmount: 500,
      categoryId: 'c1',
      isRecurring: isRecurring,
      createdAt: createdAt,
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
  late MockNotificationService notifications;

  late List<TransactionRecord> storedTxns;
  late List<Bill> storedBills;
  late List<Receivable> storedReceivables;
  late List<BudgetedExpense> storedExpenses;
  late List<Installment> storedPlans;

  // The presenters' "now". Tests move it forward to tell a create apart from
  // a later edit.
  final oct3 = DateTime(2026, 10, 3, 10);
  late DateTime now;
  DateTime clock() => now;

  void stubStorage({
    List<FinancialAccount>? accounts,
    List<TransactionRecord> transactions = const [],
    List<Bill> bills = const [],
    List<Receivable> receivables = const [],
    List<BudgetedExpense> expenses = const [],
  }) {
    storedTxns = [...transactions];
    storedBills = [...bills];
    storedReceivables = [...receivables];
    storedExpenses = [...expenses];
    storedPlans = [];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts())
        .thenAnswer((_) async => accounts ?? [_bank('bpi'), _bank('gcash')]);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [_expenseCat('c1')]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => storedTxns);
    when(storage.saveTransactions(any)).thenAnswer((inv) async {
      storedTxns =
          List<TransactionRecord>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => storedBills);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      storedBills = List<Bill>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => storedReceivables);
    when(storage.saveReceivables(any)).thenAnswer((inv) async {
      storedReceivables =
          List<Receivable>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadBudgetedExpenses())
        .thenAnswer((_) async => storedExpenses);
    when(storage.saveBudgetedExpenses(any)).thenAnswer((inv) async {
      storedExpenses =
          List<BudgetedExpense>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadInstallments()).thenAnswer((_) async => storedPlans);
    when(storage.saveInstallments(any)).thenAnswer((inv) async {
      storedPlans =
          List<Installment>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  Future<LedgerPresenter> buildLedger() async {
    final ledger = LedgerPresenter(storage, stats, clock: clock);
    await _waitForLoad(ledger);
    return ledger;
  }

  Future<({LedgerPresenter ledger, BillsReceivablesPresenter bills})>
      buildGraph() async {
    final ledger = await buildLedger();
    final bills = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications, clock: clock);
    await bills.load();
    return (ledger: ledger, bills: bills);
  }

  TransactionRecord txnIn(LedgerPresenter ledger, String id) =>
      ledger.allTransactions.firstWhere((t) => t.id == id);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    now = oct3;
  });

  group('LedgerPresenter stamps createdAt on create', () {
    test('addTransaction stamps the clock time', () async {
      stubStorage();
      final ledger = await buildLedger();

      await ledger.addTransaction(_txn('t1'));

      expect(txnIn(ledger, 't1').createdAt, oct3);
      // And it reaches storage, which the sync pushes from.
      expect(storedTxns.single.createdAt, oct3);
    });

    test('a record that already carries a stamp keeps it', () async {
      stubStorage();
      final ledger = await buildLedger();
      final earlier = DateTime(2026, 9, 1);

      await ledger.addTransaction(_txn('t1', createdAt: earlier));

      expect(txnIn(ledger, 't1').createdAt, earlier);
    });

    test('addTransfer stamps both legs', () async {
      stubStorage();
      final ledger = await buildLedger();

      await ledger.addTransfer(
        fromAccountId: 'bpi',
        toAccountId: 'gcash',
        amount: 500,
        description: 'Top up',
        date: DateTime(2026, 10, 3),
      );

      final legs =
          ledger.allTransactions.where((t) => t.transferGroupId != null);
      expect(legs, hasLength(2));
      expect(legs.map((t) => t.createdAt), everyElement(oct3));
    });

    test('postSystemTransactions stamps each record', () async {
      stubStorage();
      final ledger = await buildLedger();

      await ledger.postSystemTransactions([_txn('s1'), _txn('s2')]);

      expect(txnIn(ledger, 's1').createdAt, oct3);
      expect(txnIn(ledger, 's2').createdAt, oct3);
    });

    test('addInstallmentPurchase stamps the purchase record', () async {
      stubStorage(accounts: [_card('bpi-cc', 0)]);
      final ledger = await buildLedger();

      await ledger.addInstallmentPurchase(Installment(
        id: 'plan1',
        name: 'Phone',
        accountId: 'bpi-cc',
        totalAmount: 12000,
        monthlyAmount: 2000,
        totalMonths: 6,
        startMonth: '2026-11',
        purchaseDate: DateTime(2026, 10, 2),
      ));

      final purchase =
          ledger.allTransactions.firstWhere((t) => t.installmentId == 'plan1');
      expect(purchase.createdAt, oct3);
    });

    test('a reimbursable expense stamps the record and its receivable',
        () async {
      stubStorage();
      final g = await buildGraph();

      await g.ledger.addReimbursableExpense(
        _txn('t1').copyWith(
          reimbursable: true,
          reimbursementReceivableId: 'r1',
        ),
        expectedReimbursementDate: null,
      );

      expect(txnIn(g.ledger, 't1').createdAt, oct3);
      final receivable = g.bills.allReceivables.firstWhere((r) => r.id == 'r1');
      expect(receivable.createdAt, oct3);
    });
  });

  group('LedgerPresenter keeps createdAt on edit and undo', () {
    test('an edit built fresh by a form keeps the stored stamp', () async {
      stubStorage();
      final ledger = await buildLedger();
      await ledger.addTransaction(_txn('t1'));

      now = DateTime(2026, 10, 20);
      // The edit forms build a new record with no createdAt.
      await ledger.updateTransaction(_txn('t1', amount: 300));

      final edited = txnIn(ledger, 't1');
      expect(edited.amount, 300);
      expect(edited.createdAt, oct3);
    });

    test('an edit cannot overwrite the stamp with its own value', () async {
      stubStorage();
      final ledger = await buildLedger();
      await ledger.addTransaction(_txn('t1'));

      await ledger.updateTransaction(
          _txn('t1', amount: 300, createdAt: DateTime(2030)));

      expect(txnIn(ledger, 't1').createdAt, oct3);
    });

    test('an edit of an old record leaves it unstamped', () async {
      stubStorage(transactions: [_txn('old')]);
      final ledger = await buildLedger();

      await ledger.updateTransaction(_txn('old', amount: 999));

      expect(txnIn(ledger, 'old').createdAt, isNull);
    });

    test('editing a transfer replaces its legs but keeps the stamp', () async {
      stubStorage();
      final ledger = await buildLedger();
      await ledger.addTransfer(
        fromAccountId: 'bpi',
        toAccountId: 'gcash',
        amount: 500,
        description: 'Top up',
        date: DateTime(2026, 10, 3),
      );
      final existing =
          ledger.allTransactions.firstWhere((t) => t.transferGroupId != null);

      // What the edit forms do: drop the pair, then add the edited pair.
      now = DateTime(2026, 10, 20);
      await ledger.deleteTransactionOrGroup(existing.id);
      await ledger.addTransfer(
        fromAccountId: 'bpi',
        toAccountId: 'gcash',
        amount: 800,
        description: 'Top up',
        date: DateTime(2026, 10, 3),
        replacing: existing,
      );

      final legs = ledger.allTransactions;
      expect(legs, hasLength(2));
      expect(legs.map((t) => t.amount), everyElement(800));
      expect(legs.map((t) => t.createdAt), everyElement(oct3));
    });

    test('a transfer edited into an expense keeps the stamp, null included',
        () async {
      stubStorage();
      final ledger = await buildLedger();
      await ledger.addTransfer(
        fromAccountId: 'bpi',
        toAccountId: 'gcash',
        amount: 500,
        description: 'Top up',
        date: DateTime(2026, 10, 3),
      );
      final existing = ledger.allTransactions.first;

      now = DateTime(2026, 10, 20);
      await ledger.deleteTransactionOrGroup(existing.id);
      await ledger.addTransaction(_txn(existing.id), replacing: existing);
      expect(txnIn(ledger, existing.id).createdAt, oct3);

      // A record from before this release stays "before this release".
      final old = _txn('old');
      await ledger.addTransaction(_txn('old2'), replacing: old);
      expect(txnIn(ledger, 'old2').createdAt, isNull);
    });

    test('undoing a delete restores the original stamp', () async {
      stubStorage();
      final ledger = await buildLedger();
      await ledger.addTransaction(_txn('t1'));
      final deleted = txnIn(ledger, 't1');
      await ledger.deleteTransaction('t1');

      now = DateTime(2026, 10, 20);
      await ledger.restoreTransaction(deleted);

      expect(txnIn(ledger, 't1').createdAt, oct3);
    });
  });

  group('BillsReceivablesPresenter stamps createdAt on create', () {
    test('addBill, addReceivable and addBudgetedExpense stamp the clock time',
        () async {
      stubStorage();
      final g = await buildGraph();

      await g.bills.addBill(_bill('b1'));
      await g.bills.addReceivable(_receivable('r1'));
      await g.bills.addBudgetedExpense(_expense('e1'));

      expect(g.bills.allBills.single.createdAt, oct3);
      expect(g.bills.allReceivables.single.createdAt, oct3);
      expect(g.bills.allBudgetedExpenses.single.createdAt, oct3);
      expect(storedBills.single.createdAt, oct3);
      expect(storedReceivables.single.createdAt, oct3);
      expect(storedExpenses.single.createdAt, oct3);
    });

    test('a statement bill generated from a card cycle is stamped', () async {
      stubStorage(
        accounts: [_card('bpi-cc', 3000)],
        transactions: [
          _txn('charge',
              accountId: 'bpi-cc', amount: 3000, date: DateTime(2026, 9, 15)),
        ],
      );
      final g = await buildGraph();

      final statement = g.bills.allBills
          .singleWhere((b) => b.accountId == 'bpi-cc' && b.isAutoStatement);
      expect(statement.createdAt, oct3);
    });

    test('recurring rows copied into a new month get their own stamp',
        () async {
      final sourceStamp = DateTime(2026, 9, 2);
      stubStorage(
        bills: [
          _bill('b9',
              month: '2026-09', isRecurring: true, createdAt: sourceStamp)
        ],
        receivables: [
          _receivable('r9',
              month: '2026-09', isRecurring: true, createdAt: sourceStamp)
        ],
        expenses: [
          _expense('e9',
              month: '2026-09', isRecurring: true, createdAt: sourceStamp)
        ],
      );
      final g = await buildGraph();

      await g.bills.setMonth('2026-10');

      final bill = g.bills.allBills.singleWhere((b) => b.month == '2026-10');
      final rec =
          g.bills.allReceivables.singleWhere((r) => r.month == '2026-10');
      final exp =
          g.bills.allBudgetedExpenses.singleWhere((e) => e.month == '2026-10');
      expect(bill.createdAt, oct3);
      expect(rec.createdAt, oct3);
      expect(exp.createdAt, oct3);
      // The sources are untouched.
      expect(g.bills.allBills.singleWhere((b) => b.id == 'b9').createdAt,
          sourceStamp);
    });

    test(
        'apply-to-future seeds a later month with a new stamp and a rewrite '
        'keeps the later row\'s own', () async {
      final novStamp = DateTime(2026, 9, 5);
      stubStorage(bills: [
        // November already holds bills, so a new recurring bill is seeded there.
        _bill('other', month: '2026-11', createdAt: novStamp),
      ]);
      final g = await buildGraph();

      await g.bills
          .addBill(_bill('b1', isRecurring: true), applyToFuture: true);
      final seeded = g.bills.allBills
          .singleWhere((b) => b.month == '2026-11' && b.id != 'other');
      expect(seeded.createdAt, oct3);

      now = DateTime(2026, 10, 20);
      final current = g.bills.allBills.singleWhere((b) => b.id == 'b1');
      await g.bills.updateBill(
        _bill('b1', isRecurring: true).copyWith(
          amount: 250,
          seriesId: current.seriesId,
        ),
        applyToFuture: true,
      );

      final rewritten = g.bills.allBills.singleWhere((b) => b.id == seeded.id);
      expect(rewritten.amount, 250);
      expect(rewritten.createdAt, oct3);
      expect(g.bills.allBills.singleWhere((b) => b.id == 'b1').createdAt, oct3);
    });
  });

  group('BillsReceivablesPresenter keeps createdAt on edit', () {
    test('form-built edits of a bill, receivable and set-aside keep the stamp',
        () async {
      stubStorage();
      final g = await buildGraph();
      await g.bills.addBill(_bill('b1'));
      await g.bills.addReceivable(_receivable('r1'));
      await g.bills.addBudgetedExpense(_expense('e1'));

      now = DateTime(2026, 10, 20);
      await g.bills.updateBill(_bill('b1').copyWith(amount: 999));
      await g.bills.updateReceivable(_receivable('r1').copyWith(amount: 999));
      await g.bills
          .updateBudgetedExpense(_expense('e1').copyWith(allocatedAmount: 999));

      expect(g.bills.allBills.single.amount, 999);
      expect(g.bills.allBills.single.createdAt, oct3);
      expect(g.bills.allReceivables.single.createdAt, oct3);
      expect(g.bills.allBudgetedExpenses.single.createdAt, oct3);
    });

    test('an edit of an old row leaves it unstamped', () async {
      stubStorage(bills: [_bill('old')]);
      final g = await buildGraph();

      await g.bills.updateBill(_bill('old').copyWith(amount: 5));

      expect(g.bills.allBills.single.createdAt, isNull);
    });
  });
}
