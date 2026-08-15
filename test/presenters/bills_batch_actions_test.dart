import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import '../mocks.mocks.dart';

/// Batch actions behind the Bills tab's multi-select: settle, reverse, and
/// delete a whole selection in one pass. These pin the parts a per-row loop
/// would get wrong — a refused payment must not abandon the rest of the batch,
/// and each set-aside must keep its own destination while the batch answers the
/// question only for the rows that never named one.

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

Receivable _receivable({required String id, double amount = 400}) => Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: amount,
      expectedDate: DateTime(2026, 3, 20),
      month: _month,
      categoryId: 'salary',
    );

BudgetedExpense _budgeted({
  required String id,
  double amount = 300,
  String? accountId,
  String? destinationAccountId,
}) =>
    BudgetedExpense(
      id: id,
      name: 'Set-aside $id',
      budgetedType: SetAsideType.savings,
      month: _month,
      allocatedAmount: amount,
      categoryId: 'food',
      accountId: accountId,
      destinationAccountId: destinationAccountId,
    );

Future<void> _waitForLoad(LedgerPresenter ledger) async {
  while (ledger.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;

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
          _account(id: 'bpi', balance: 20000),
          _account(id: 'maya', category: AccountCategory.savings, balance: 0),
          _account(id: 'goal', category: AccountCategory.goal, balance: 0),
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

  group('bills', () {
    test('pays every selected bill from one account, in one save', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 500),
            _bill(id: 'b2', amount: 300),
            _bill(id: 'b3', amount: 200),
          ]);
      final (ledger, presenter) = await build();

      final result =
          await presenter.markBillsPaid(['b1', 'b2'], accountId: 'bpi');

      expect(result.applied, 2);
      expect(result.skipped, 0);
      expect(presenter.bills.where((b) => b.isPaid).map((b) => b.id),
          unorderedEquals(['b1', 'b2']));
      // Each bill settles for its own amount, not a shared one.
      expect(balanceOf(ledger, 'bpi'), 19200);
      expect(ledger.allTransactions.length, 2);
      // The whole batch costs a single write, not one per row.
      verify(mockStorage.saveBills(any)).called(1);
    });

    test('leaves already-paid and unknown ids alone', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1'),
            _bill(id: 'b2'),
          ]);
      final (ledger, presenter) = await build();
      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'bpi');

      final result = await presenter
          .markBillsPaid(['b1', 'b2', 'ghost'], accountId: 'bpi');

      expect(result.applied, 1, reason: 'only b2 was still open');
      expect(ledger.allTransactions.length, 2);
    });

    test('flags them paid without a ledger entry when asked', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1'),
            _bill(id: 'b2'),
          ]);
      final (ledger, presenter) = await build();

      final result =
          await presenter.markBillsPaid(['b1', 'b2'], recordInLedger: false);

      expect(result.applied, 2);
      expect(presenter.bills.every((b) => b.isPaid), isTrue);
      expect(ledger.allTransactions, isEmpty,
          reason: 'the user already logged these by hand');
      expect(balanceOf(ledger, 'bpi'), 20000);
    });

    test('a refused payment is skipped, not fatal to the rest', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'bpi', balance: 20000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 3000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            // Paying this card's statement from the card itself is impossible.
            _bill(
                id: 'stmt',
                amount: 1000,
                billType: BillType.creditCard,
                accountId: 'cc'),
            _bill(id: 'b2', amount: 500),
          ]);
      final (ledger, presenter) = await build();

      final result =
          await presenter.markBillsPaid(['stmt', 'b2'], accountId: 'cc');

      expect(result.applied, 1);
      expect(result.skipped, 1);
      expect(presenter.bills.firstWhere((b) => b.id == 'b2').isPaid, isTrue);
      expect(presenter.bills.firstWhere((b) => b.id == 'stmt').isPaid, isFalse);
      expect(ledger.allTransactions.length, 1);
    });

    test('the payer list is what can pay every selected bill', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'bpi', balance: 20000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 3000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'stmt', billType: BillType.creditCard, accountId: 'cc'),
            _bill(id: 'b2'),
          ]);
      final (_, presenter) = await build();

      // The card drops out: it can't pay its own statement, so it can't pay
      // the batch either — which is what keeps the refusal above from ever
      // being reachable through the UI.
      expect(presenter.payerAccountsForAll(presenter.bills).map((a) => a.id),
          ['bpi']);
      expect(presenter.preferredBatchPayerAccountId(presenter.bills), 'bpi');
    });

    test('reopens a selection and takes its transactions back out', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 500),
            _bill(id: 'b2', amount: 300),
          ]);
      final (ledger, presenter) = await build();
      await presenter.markBillsPaid(['b1', 'b2'], accountId: 'bpi');

      final result = await presenter.markBillsUnpaid(['b1', 'b2']);

      expect(result.applied, 2);
      expect(presenter.bills.every((b) => !b.isPaid), isTrue);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'bpi'), 20000);
    });

    test('keeps the transactions when the money really did move', () async {
      when(mockStorage.loadBills())
          .thenAnswer((_) async => [_bill(id: 'b1'), _bill(id: 'b2')]);
      final (ledger, presenter) = await build();
      await presenter.markBillsPaid(['b1', 'b2'], accountId: 'bpi');

      await presenter.markBillsUnpaid(['b1', 'b2'], removeTransaction: false);

      expect(presenter.bills.every((b) => !b.isPaid), isTrue);
      expect(ledger.allTransactions.length, 2);
      expect(balanceOf(ledger, 'bpi'), 19000);
    });

    test('deletes a selection and reports how many existed', () async {
      when(mockStorage.loadBills()).thenAnswer(
          (_) async => [_bill(id: 'b1'), _bill(id: 'b2'), _bill(id: 'b3')]);
      final (_, presenter) = await build();

      expect(await presenter.deleteBills(['b1', 'b3', 'ghost']), 2);
      expect(presenter.bills.map((b) => b.id), ['b2']);
    });
  });

  group('receivables', () {
    test('deposits every selected receivable into one account', () async {
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(id: 'r1', amount: 400),
            _receivable(id: 'r2', amount: 600),
          ]);
      final (ledger, presenter) = await build();

      final result = await presenter
          .markReceivablesReceived(['r1', 'r2'], accountId: 'bpi');

      expect(result.applied, 2);
      expect(presenter.receivables.every((r) => r.isReceived), isTrue);
      expect(balanceOf(ledger, 'bpi'), 21000);
      verify(mockStorage.saveReceivables(any)).called(1);
    });

    test('reverses a selection back to still-owed', () async {
      when(mockStorage.loadReceivables()).thenAnswer(
          (_) async => [_receivable(id: 'r1'), _receivable(id: 'r2')]);
      final (ledger, presenter) = await build();
      await presenter.markReceivablesReceived(['r1', 'r2'], accountId: 'bpi');

      final result = await presenter.markReceivablesUnreceived(['r1', 'r2']);

      expect(result.applied, 2);
      expect(presenter.receivables.every((r) => !r.isReceived), isTrue);
      expect(ledger.allTransactions, isEmpty);
      expect(balanceOf(ledger, 'bpi'), 20000);
    });

    test('deletes a selection', () async {
      when(mockStorage.loadReceivables()).thenAnswer(
          (_) async => [_receivable(id: 'r1'), _receivable(id: 'r2')]);
      final (_, presenter) = await build();

      expect(await presenter.deleteReceivables(['r1']), 1);
      expect(presenter.receivables.map((r) => r.id), ['r2']);
    });
  });

  group('set-asides', () {
    test('each keeps its own destination; the batch answers for the rest',
        () async {
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            _budgeted(id: 'e1', amount: 5000, destinationAccountId: 'maya'),
            _budgeted(id: 'e2', amount: 1000),
          ]);
      final (ledger, presenter) = await build();

      final result = await presenter.markExpensesPaid(
        ['e1', 'e2'],
        accountId: 'bpi',
        toAccountId: 'goal',
      );

      expect(result.applied, 2);
      // ₱5,000 BPI → Maya, as the set-aside itself says; ₱1,000 to the
      // destination the batch was asked for.
      expect(balanceOf(ledger, 'maya'), 5000);
      expect(balanceOf(ledger, 'goal'), 1000);
      expect(balanceOf(ledger, 'bpi'), 14000);
    });

    test('saved destinations can be overridden for the whole batch', () async {
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            _budgeted(id: 'e1', amount: 5000, destinationAccountId: 'maya'),
            _budgeted(id: 'e2', amount: 1000),
          ]);
      final (ledger, presenter) = await build();

      await presenter.markExpensesPaid(
        ['e1', 'e2'],
        accountId: 'bpi',
        toAccountId: 'goal',
        preferSavedDestination: false,
      );

      expect(balanceOf(ledger, 'maya'), 0);
      expect(balanceOf(ledger, 'goal'), 6000);
    });

    test('no destination at all spends the money instead of moving it',
        () async {
      when(mockStorage.loadBudgetedExpenses())
          .thenAnswer((_) async => [_budgeted(id: 'e1', amount: 300)]);
      final (ledger, presenter) = await build();

      await presenter.markExpensesPaid(['e1'], accountId: 'bpi');

      expect(balanceOf(ledger, 'bpi'), 19700);
      expect(ledger.allTransactions.length, 1,
          reason: 'a plain outflow, not a transfer pair');
    });

    test('unfunds and deletes a selection', () async {
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            _budgeted(id: 'e1', amount: 300, destinationAccountId: 'maya'),
            _budgeted(id: 'e2', amount: 200, destinationAccountId: 'maya'),
          ]);
      final (ledger, presenter) = await build();
      await presenter.markExpensesPaid(['e1', 'e2'], accountId: 'bpi');
      expect(balanceOf(ledger, 'maya'), 500);

      final result = await presenter.markExpensesUnpaid(['e1', 'e2']);
      expect(result.applied, 2);
      expect(presenter.budgetedExpenses.every((e) => !e.isPaid), isTrue);
      expect(balanceOf(ledger, 'maya'), 0);
      expect(balanceOf(ledger, 'bpi'), 20000);

      expect(await presenter.deleteBudgetedExpenses(['e1', 'e2']), 2);
      expect(presenter.budgetedExpenses, isEmpty);
    });
  });

  group('destination preference', () {
    test('a saved destination is offered; anything else asks', () async {
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            _budgeted(id: 'saved', destinationAccountId: 'maya'),
            _budgeted(id: 'none'),
            _budgeted(id: 'stale', destinationAccountId: 'closed-account'),
          ]);
      final (_, presenter) = await build();
      BudgetedExpense byId(String id) =>
          presenter.budgetedExpenses.firstWhere((e) => e.id == id);

      expect(presenter.preferredSetAsideDestinationId(byId('saved')), 'maya');
      expect(presenter.preferredSetAsideDestinationId(byId('none')), isNull,
          reason: 'never guess a destination — ask at confirmation time');
      expect(presenter.preferredSetAsideDestinationId(byId('stale')), isNull,
          reason: 'an account that no longer exists is not a destination');
      // A transfer into the account the money is leaving is not a transfer.
      expect(
        presenter.preferredSetAsideDestinationId(byId('saved'),
            fromAccountId: 'maya'),
        isNull,
      );
    });

    test('destinations exclude liabilities and lead with savings/goals',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'bpi'),
            _account(id: 'cc', category: AccountCategory.creditCard),
            _account(id: 'goal', category: AccountCategory.goal),
            _account(id: 'maya', category: AccountCategory.savings),
          ]);
      final (_, presenter) = await build();

      expect(presenter.setAsideDestinationAccounts.map((a) => a.id),
          ['maya', 'goal', 'bpi']);
    });
  });
}
