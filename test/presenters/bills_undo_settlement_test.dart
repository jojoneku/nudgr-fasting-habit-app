import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Undoing a settlement. Marking something paid / received / funded used to be
/// one-way: a mis-tap left the wrong state and a wrong account balance behind,
/// recoverable only by deleting the entry and re-creating it. These tests pin
/// the reverse — including that the ledger entry it created is taken back out,
/// both legs of a transfer unwind, and "keep the transaction" is honoured.

const _month = '2026-03';

FinancialAccount _account({
  required String id,
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
}) =>
    FinancialAccount(
      id: id,
      name: 'Account $id',
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

Bill _bill({
  required String id,
  double amount = 500,
  BillType billType = BillType.utility,
  String? accountId,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: billType,
      amount: amount,
      dueDay: 10,
      month: _month,
      categoryId: 'food',
      accountId: accountId,
    );

Receivable _receivable({
  required String id,
  double amount = 400,
  ReceivableType type = ReceivableType.salary,
}) =>
    Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: type,
      amount: amount,
      expectedDate: DateTime(2026, 3, 20),
      month: _month,
      categoryId: 'salary',
    );

BudgetedExpense _budgeted({required String id, double amount = 300}) =>
    BudgetedExpense(
      id: id,
      name: 'Set-aside $id',
      budgetedType: SetAsideType.savings,
      month: _month,
      allocatedAmount: amount,
      categoryId: 'food',
    );

Future<void> _waitForLoad(LedgerPresenter ledger) async {
  while (ledger.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;

  /// Builds a presenter pair AFTER the per-test storage stubs are in place —
  /// the ledger loads accounts in its constructor, so it has to be built last.
  Future<(LedgerPresenter, BillsReceivablesPresenter)> build() async {
    final ledger = LedgerPresenter(mockStorage, mockStats);
    final presenter = BillsReceivablesPresenter(mockStorage, ledger, mockStats);
    await presenter.load();
    await presenter.setMonth(_month);
    await _waitForLoad(ledger);
    return (ledger, presenter);
  }

  double balanceOf(LedgerPresenter ledger, String id) =>
      ledger.accounts.firstWhere((a) => a.id == id).balance;

  setUp(() {
    mockStorage = MockStorageService();
    mockStats = MockStatsPresenter();
    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(mockStorage.loadAccounts()).thenAnswer((_) async => [
          _account(id: 'gcash', balance: 5000),
          _account(
              id: 'savings', category: AccountCategory.savings, balance: 10000),
        ]);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.saveBills(any)).thenAnswer((_) async {});
    when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
    when(mockStorage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
    when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
    when(mockStorage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(mockStorage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.stats).thenReturn(UserStats.initial());
  });

  group('markBillUnpaid', () {
    test('reopens the bill and removes the outflow it created', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [_bill(id: 'b1')]);
      final (ledger, presenter) = await build();

      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');
      expect(balanceOf(ledger, 'gcash'), 4500);
      expect(presenter.billHasLedgerEntry(presenter.bills.first), isTrue);

      await presenter.markBillUnpaid('b1');

      final bill = presenter.bills.firstWhere((b) => b.id == 'b1');
      expect(bill.isPaid, isFalse);
      expect(bill.paidDate, isNull,
          reason: 'a reopened bill must not keep its old paid date');
      expect(bill.paidAmount, isNull);
      expect(bill.transactionId, isNull);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
    });

    test('keeps the transaction when asked to', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [_bill(id: 'b1')]);
      final (ledger, presenter) = await build();

      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');
      await presenter.markBillUnpaid('b1', removeTransaction: false);

      // The money really did move — only the bill's flag was wrong.
      expect(presenter.bills.firstWhere((b) => b.id == 'b1').isPaid, isFalse);
      expect(ledger.allTransactions.length, 1);
      expect(balanceOf(ledger, 'gcash'), 4500);
    });

    test('unwinds both legs of a credit-card statement transfer', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'gcash', balance: 5000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 3000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(
                id: 'stmt',
                amount: 1000,
                billType: BillType.creditCard,
                accountId: 'cc'),
          ]);
      final (ledger, presenter) = await build();

      await presenter.markBillPaid('stmt',
          paidAmount: 1000, accountId: 'gcash');
      expect(balanceOf(ledger, 'gcash'), 4000);
      expect(balanceOf(ledger, 'cc'), 2000);

      await presenter.markBillUnpaid('stmt');

      // A statement payment stores no id on the bill (it's a transfer), so the
      // undo has to find it via the billId stamped on the legs.
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
      expect(balanceOf(ledger, 'cc'), 3000);
      expect(presenter.bills.firstWhere((b) => b.id == 'stmt').isPaid, isFalse);
    });

    test('finds a legacy transfer that carries no billId back-link', () async {
      // Payments made before transfers were stamped with their bill: the only
      // handle is the settlement's own shape (destination, amount, day, name).
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'gcash', balance: 4000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 2000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            Bill(
              id: 'stmt',
              name: 'Bill stmt',
              billType: BillType.creditCard,
              amount: 1000,
              dueDay: 10,
              month: _month,
              categoryId: 'food',
              accountId: 'cc',
              isPaid: true,
              paidDate: DateTime(2026, 3, 15),
              paidAmount: 1000,
            ),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            TransactionRecord(
              id: 'leg-out',
              date: DateTime(2026, 3, 15),
              accountId: 'gcash',
              categoryId: FinanceCategory.transferCategoryId,
              amount: 1000,
              type: TransactionType.outflow,
              description: 'Bill stmt',
              month: _month,
              transferToAccountId: 'cc',
              transferGroupId: 'grp',
            ),
            TransactionRecord(
              id: 'leg-in',
              date: DateTime(2026, 3, 15),
              accountId: 'cc',
              categoryId: FinanceCategory.transferCategoryId,
              amount: 1000,
              type: TransactionType.inflow,
              description: 'Bill stmt',
              month: _month,
              transferToAccountId: 'gcash',
              transferGroupId: 'grp',
            ),
          ]);
      final (ledger, presenter) = await build();

      await presenter.markBillUnpaid('stmt');

      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
      expect(balanceOf(ledger, 'cc'), 3000);
    });

    test('is a no-op on a bill that is already unpaid', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [_bill(id: 'b1')]);
      final (ledger, presenter) = await build();

      await presenter.markBillUnpaid('b1');
      await presenter.markBillUnpaid('nope');

      expect(presenter.bills.firstWhere((b) => b.id == 'b1').isPaid, isFalse);
      expect(balanceOf(ledger, 'gcash'), 5000);
    });

    test('does not re-award the all-bills-paid XP on undo then re-pay',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [_bill(id: 'b1')]);
      final (_, presenter) = await build();

      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');
      await presenter.markBillUnpaid('b1');
      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');

      verify(mockStats.addXp(50)).called(1);
    });
  });

  group('markReceivableUnreceived', () {
    test('reopens the receivable and removes the inflow it created', () async {
      when(mockStorage.loadReceivables())
          .thenAnswer((_) async => [_receivable(id: 'r1')]);
      final (ledger, presenter) = await build();

      await presenter.markReceivableReceived('r1',
          receivedAmount: 400, accountId: 'gcash');
      expect(balanceOf(ledger, 'gcash'), 5400);

      await presenter.markReceivableUnreceived('r1');

      final rec = presenter.receivables.firstWhere((r) => r.id == 'r1');
      expect(rec.isReceived, isFalse);
      expect(rec.receivedDate, isNull);
      expect(rec.receivedAmount, isNull);
      expect(rec.transactionId, isNull);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
      // It's owed again, so it belongs back in the still-owed slice.
      expect(presenter.pendingReceivables.map((r) => r.id), ['r1']);
    });

    test('keeps the transaction when asked to', () async {
      when(mockStorage.loadReceivables())
          .thenAnswer((_) async => [_receivable(id: 'r1')]);
      final (ledger, presenter) = await build();

      await presenter.markReceivableReceived('r1',
          receivedAmount: 400, accountId: 'gcash');
      await presenter.markReceivableUnreceived('r1', removeTransaction: false);

      expect(presenter.receivables.first.isReceived, isFalse);
      expect(ledger.allTransactions.length, 1);
      expect(balanceOf(ledger, 'gcash'), 5400);
    });

    test('puts a reimbursement back into the ledger\'s outstanding set',
        () async {
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(id: 'r1', type: ReceivableType.reimbursement),
          ]);
      final (ledger, presenter) = await build();

      await presenter.markReceivableReceived('r1',
          receivedAmount: 400, accountId: 'gcash');
      // Settled — an expense linked to it is no longer owed to you.
      expect(
        ledger.isOutstandingReimbursable(_reimbursableOutflow('r1')),
        isFalse,
      );

      await presenter.markReceivableUnreceived('r1');

      expect(
        ledger.isOutstandingReimbursable(_reimbursableOutflow('r1')),
        isTrue,
        reason: 'un-receiving a payback means you are owed the money again',
      );
    });
  });

  group('markExpenseUnpaid', () {
    test('reopens a spent set-aside and removes the outflow', () async {
      when(mockStorage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_budgeted(id: 'e1')]);
      final (ledger, presenter) = await build();

      // No destination → a plain outflow ("spend it").
      await presenter.markExpensePaid('e1',
          paidAmount: 300, accountId: 'gcash', paidDate: DateTime(2026, 3, 15));
      expect(balanceOf(ledger, 'gcash'), 4700);

      await presenter.markExpenseUnpaid('e1');

      final expense =
          presenter.budgetedExpenses.firstWhere((e) => e.id == 'e1');
      expect(expense.isPaid, isFalse);
      expect(expense.spentAmount, 0);
      expect(expense.transactionId, isNull);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
    });

    test('unwinds both legs when the set-aside was moved into savings',
        () async {
      when(mockStorage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_budgeted(id: 'e1')]);
      final (ledger, presenter) = await build();

      await presenter.markExpensePaid('e1',
          paidAmount: 300,
          accountId: 'gcash',
          toAccountId: 'savings',
          paidDate: DateTime(2026, 3, 15));
      expect(balanceOf(ledger, 'gcash'), 4700);
      expect(balanceOf(ledger, 'savings'), 10300);

      await presenter.markExpenseUnpaid('e1');

      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'gcash'), 5000);
      expect(balanceOf(ledger, 'savings'), 10000);
      expect(presenter.budgetedExpenses.firstWhere((e) => e.id == 'e1').isPaid,
          isFalse);
    });
  });

  group('model settlement fields clear', () {
    test('Bill.copyWith can null the paid fields back out', () {
      final paid = _bill(id: 'b1').copyWith(
        isPaid: true,
        paidDate: DateTime(2026, 3, 15),
        paidAmount: 500,
        transactionId: 't1',
      );
      final reopened = paid.copyWith(
        isPaid: false,
        paidDate: null,
        paidAmount: null,
        transactionId: null,
      );

      expect(reopened.paidDate, isNull);
      expect(reopened.paidAmount, isNull);
      expect(reopened.transactionId, isNull);
      // Omitting them still leaves the values alone.
      expect(paid.copyWith(name: 'x').paidAmount, 500);
    });

    test('Receivable.copyWith can null the received fields back out', () {
      final received = _receivable(id: 'r1').copyWith(
        isReceived: true,
        receivedDate: DateTime(2026, 3, 15),
        receivedAmount: 400,
        transactionId: 't1',
      );
      final reopened = received.copyWith(
        isReceived: false,
        receivedDate: null,
        receivedAmount: null,
        transactionId: null,
      );

      expect(reopened.receivedDate, isNull);
      expect(reopened.receivedAmount, isNull);
      expect(reopened.transactionId, isNull);
      expect(received.copyWith(name: 'x').receivedAmount, 400);
    });

    test('BudgetedExpense.copyWith can null the transaction link back out', () {
      final funded =
          _budgeted(id: 'e1').copyWith(isPaid: true, transactionId: 't1');

      expect(funded.copyWith(transactionId: null).transactionId, isNull);
      expect(funded.copyWith(name: 'x').transactionId, 't1');
    });
  });
}

/// A reimbursable expense linked to [receivableId] — the ledger reads its
/// "owed to you" state from the receivable, so this stands in for one.
TransactionRecord _reimbursableOutflow(String receivableId) =>
    TransactionRecord(
      id: 'exp-$receivableId',
      date: DateTime(2026, 3, 10),
      accountId: 'gcash',
      categoryId: 'food',
      amount: 400,
      type: TransactionType.outflow,
      description: 'Lunch',
      month: _month,
      reimbursable: true,
      reimbursementReceivableId: receivableId,
    );
