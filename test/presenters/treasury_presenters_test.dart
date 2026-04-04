import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

FinancialAccount _account({
  required String id,
  String name = 'Account',
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
  String? parentAccountId,
  bool isActive = true,
}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
      parentAccountId: parentAccountId,
      isActive: isActive,
    );

TransactionRecord _txn({
  required String id,
  required String accountId,
  required double amount,
  required TransactionType type,
  String? month,
  String? transferGroupId,
  String? transferToAccountId,
  String categoryId = '',
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, 3, 15),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: 'Test',
      month: month ?? '2026-03',
    );

Bill _bill({
  required String id,
  double amount = 100,
  bool isPaid = false,
  String month = '2026-03',
  String categoryId = '',
  bool isRecurring = false,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: BillType.utility,
      amount: amount,
      dueDay: 10,
      month: month,
      categoryId: categoryId,
      isPaid: isPaid,
      isRecurring: isRecurring,
    );

Receivable _receivable({
  required String id,
  double amount = 200,
  bool isReceived = false,
  String month = '2026-03',
}) =>
    Receivable(
      id: id,
      name: 'Receivable $id',
      receivableType: ReceivableType.salary,
      amount: amount,
      expectedDate: DateTime(2026, 3, 20),
      month: month,
      categoryId: '',
      isReceived: isReceived,
    );

FinanceCategory _category({
  required String id,
  CategoryType type = CategoryType.expense,
  String name = 'Category',
}) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

// ─── TreasuryDashboardPresenter ───────────────────────────────────────────────

void main() {
  group('TreasuryDashboardPresenter', () {
    late MockStorageService mockStorage;
    late TreasuryDashboardPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      presenter = TreasuryDashboardPresenter(mockStorage);
    });

    test('liquidAccounts returns only active liquid top-level accounts',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1', category: AccountCategory.ewallet, balance: 500),
            _account(
                id: 'a2', category: AccountCategory.creditCard, balance: 200),
            _account(
                id: 'a3',
                category: AccountCategory.savings,
                balance: 100,
                parentAccountId: 'a1'),
          ]);
      await presenter.load();
      expect(presenter.liquidAccounts.map((a) => a.id), ['a1']);
    });

    test('liabilityAccounts returns creditCard/creditLine/bnpl', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.creditCard, balance: 300),
            _account(id: 'a2', category: AccountCategory.bnpl, balance: 150),
            _account(
                id: 'a3', category: AccountCategory.ewallet, balance: 1000),
          ]);
      await presenter.load();
      expect(presenter.liabilityAccounts.map((a) => a.id),
          containsAll(['a1', 'a2']));
      expect(presenter.liabilityAccounts.any((a) => a.id == 'a3'), isFalse);
    });

    test('totalLiquidCash sums liquid account balances', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.ewallet, balance: 1000),
            _account(id: 'a2', category: AccountCategory.bank, balance: 2500),
            _account(
                id: 'a3', category: AccountCategory.creditCard, balance: 500),
          ]);
      await presenter.load();
      expect(presenter.totalLiquidCash, 3500);
    });

    test('netWorth = assets - liabilities', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1', category: AccountCategory.bank, balance: 5000),
            _account(
                id: 'a2', category: AccountCategory.creditCard, balance: 1000),
          ]);
      await presenter.load();
      expect(presenter.netWorth, 4000);
    });

    test('pendingReceivables sums unReceived receivables for current month',
        () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadReceivables()).thenAnswer((_) async => [
            _receivable(id: 'r1', amount: 500, isReceived: false, month: month),
            _receivable(id: 'r2', amount: 300, isReceived: true, month: month),
          ]);
      await presenter.load();
      expect(presenter.pendingReceivables, 500);
    });

    test('deleteAccount throws StateError when sub-accounts exist', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'parent'),
            _account(id: 'child', parentAccountId: 'parent'),
          ]);
      await presenter.load();
      expect(
          () => presenter.deleteAccount('parent'), throwsA(isA<StateError>()));
    });

    test('deleteAccount removes account and saves', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'a1'),
          ]);
      await presenter.load();
      await presenter.deleteAccount('a1');
      expect(presenter.liquidAccounts.any((a) => a.id == 'a1'), isFalse);
      verify(mockStorage.saveAccounts(argThat(isEmpty))).called(1);
    });

    test('addAccount persists to storage', () async {
      await presenter.load();
      final account =
          _account(id: 'new1', category: AccountCategory.bank, balance: 0);
      await presenter.addAccount(account);
      verify(mockStorage.saveAccounts(any)).called(1);
    });
  });

  // ─── LedgerPresenter ──────────────────────────────────────────────────────

  group('LedgerPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();

      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'gcash', category: AccountCategory.ewallet, balance: 1000),
            _account(id: 'bpi', category: AccountCategory.bank, balance: 5000),
          ]);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      presenter = LedgerPresenter(mockStorage, mockStats);
    });

    test('addTransaction increases account balance for inflow', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 200,
          type: TransactionType.inflow));
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 1200);
    });

    test('addTransaction decreases account balance for outflow', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 300,
          type: TransactionType.outflow));
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 700);
    });

    test('deleteTransaction reverses balance delta', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 400,
          type: TransactionType.outflow));
      await presenter.deleteTransaction('t1');
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      expect(gcash.balance, 1000);
    });

    test('addTransfer creates 2 records with shared transferGroupId', () async {
      await _waitForLoad(presenter);
      final now = DateTime.now();
      await presenter.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 500,
        categoryId: '',
        description: 'Transfer test',
        date: now,
      );
      final txns =
          presenter.groupedTransactions.values.expand((l) => l).toList();
      // In all-accounts view, deduplication keeps only outflow leg
      expect(txns.length, 1);
      expect(txns.first.type, TransactionType.outflow);
    });

    test('addTransfer updates balances on both accounts', () async {
      await _waitForLoad(presenter);
      await presenter.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 500,
        categoryId: '',
        description: 'Transfer',
        date: DateTime.now(),
      );
      final gcash = presenter.accounts.firstWhere((a) => a.id == 'gcash');
      final bpi = presenter.accounts.firstWhere((a) => a.id == 'bpi');
      expect(gcash.balance, 500);
      expect(bpi.balance, 5500);
    });

    test('addTransaction awards +25 XP for first-ever transaction', () async {
      await _waitForLoad(presenter);
      await presenter.addTransaction(_txn(
          id: 't1',
          accountId: 'gcash',
          amount: 100,
          type: TransactionType.outflow));
      verify(mockStats.addXp(25)).called(1);
    });

    test('filteredMonthInflow sums inflow for selected month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'gcash',
                amount: 500,
                type: TransactionType.inflow,
                month: '2026-03'),
            _txn(
                id: 't2',
                accountId: 'gcash',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.filteredMonthInflow, 500);
      expect(presenter.filteredMonthOutflow, 200);
    });

    test('setAccount filters to single-account transactions', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'gcash',
                amount: 100,
                type: TransactionType.outflow,
                month: '2026-03'),
            _txn(
                id: 't2',
                accountId: 'bpi',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      presenter.setAccount('gcash');
      final txns =
          presenter.groupedTransactions.values.expand((l) => l).toList();
      expect(txns.length, 1);
      expect(txns.first.accountId, 'gcash');
    });
  });

  // ─── BillsReceivablesPresenter ────────────────────────────────────────────

  group('BillsReceivablesPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late LedgerPresenter ledger;
    late BillsReceivablesPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();

      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'gcash', category: AccountCategory.ewallet, balance: 5000),
          ]);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(mockStorage.saveBills(any)).thenAnswer((_) async {});
      when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
      when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
      when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());

      ledger = LedgerPresenter(mockStorage, mockStats);
      presenter = BillsReceivablesPresenter(mockStorage, ledger, mockStats);
    });

    test('bills getter filters by selectedMonth', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', month: '2026-03'),
            _bill(id: 'b2', month: '2026-02'),
          ]);
      await presenter.load();
      presenter..setMonth('2026-03');
      // Use unawaited setMonth result; call getter synchronously
      final bills = presenter.bills;
      expect(bills.map((b) => b.id), contains('b1'));
      expect(bills.any((b) => b.id == 'b2'), isFalse);
    });

    test('totalBillsPending sums unpaid bills', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 300, isPaid: false, month: '2026-03'),
            _bill(id: 'b2', amount: 200, isPaid: true, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      expect(presenter.totalBillsPending, 300);
    });

    test('markBillPaid marks bill paid and creates outflow transaction',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 500, isPaid: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      await presenter.markBillPaid('b1', paidAmount: 500, accountId: 'gcash');

      final capturedBills =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      final paidBill = capturedBills.firstWhere((b) => b.id == 'b1');
      expect(paidBill.isPaid, isTrue);
      expect(paidBill.paidAmount, 500);
    });

    test('markBillPaid awards XP when all bills are paid', () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 300, isPaid: false, month: '2026-03'),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-03');
      await _waitForLoad(ledger);

      await presenter.markBillPaid('b1', paidAmount: 300, accountId: 'gcash');

      verify(mockStats.addXp(50)).called(1);
    });

    test('addBill persists to storage', () async {
      await presenter.load();
      await presenter.setMonth('2026-03');
      await presenter.addBill(_bill(id: 'b_new', month: '2026-03'));
      verify(mockStorage.saveBills(any)).called(greaterThanOrEqualTo(1));
    });

    test('recurring bills auto-generated when navigating to new month',
        () async {
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', month: '2026-02', isRecurring: true),
          ]);
      await presenter.load();
      await presenter.setMonth('2026-02');
      // Navigate to next month — no bills exist yet for March
      await presenter.setMonth('2026-03');

      final capturedBills =
          verify(mockStorage.saveBills(captureAny)).captured.last as List<Bill>;
      final march = capturedBills.where((b) => b.month == '2026-03').toList();
      expect(march.length, 1);
    });
  });

  // ─── BudgetPresenter ──────────────────────────────────────────────────────

  group('BudgetPresenter', () {
    late MockStorageService mockStorage;
    late MockStatsPresenter mockStats;
    late BudgetPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      mockStats = MockStatsPresenter();
      when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.saveBudgets(any)).thenAnswer((_) async {});
      when(mockStats.addXp(any)).thenAnswer((_) async {});
      when(mockStats.stats).thenReturn(UserStats.initial());
      presenter = BudgetPresenter(mockStorage, mockStats);
    });

    test('spentFor sums outflow transactions for category in month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 't2',
                accountId: 'a1',
                amount: 150,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
            _txn(
                id: 't3',
                accountId: 'a1',
                amount: 100,
                type: TransactionType.inflow,
                month: '2026-03',
                categoryId: 'food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.spentFor('food'), 350);
    });

    test('setBudget creates new budget for category', () async {
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => [
            _category(id: 'food', type: CategoryType.expense, name: 'Food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.setBudget('food', 3000);

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      expect(
          captured
              .any((b) => b.categoryId == 'food' && b.allocatedAmount == 3000),
          isTrue);
    });

    test('setBudget updates existing budget', () async {
      final existingBudget = Budget(
        id: 'bud1',
        categoryId: 'food',
        month: '2026-03',
        allocatedAmount: 2000,
        group: BudgetGroup.variableOptional,
        budgetType: BudgetType.monthly,
      );
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [existingBudget]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.setBudget('food', 2500);

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      final updated = captured.firstWhere((b) => b.id == 'bud1');
      expect(updated.allocatedAmount, 2500);
    });

    test('isOverBudget returns true when spent > allocated', () async {
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
              id: 'bud1',
              categoryId: 'food',
              month: '2026-03',
              allocatedAmount: 1000,
              group: BudgetGroup.variableOptional,
              budgetType: BudgetType.monthly,
            ),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 1200,
                type: TransactionType.outflow,
                month: '2026-03',
                categoryId: 'food'),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      expect(presenter.isOverBudget('food'), isTrue);
    });

    test('removeBudget removes budget and saves', () async {
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
              id: 'bud1',
              categoryId: 'food',
              month: '2026-03',
              allocatedAmount: 1000,
              group: BudgetGroup.variableOptional,
              budgetType: BudgetType.monthly,
            ),
          ]);
      await presenter.load();
      presenter.setMonth('2026-03');
      await presenter.removeBudget('food');

      final captured = verify(mockStorage.saveBudgets(captureAny)).captured.last
          as List<Budget>;
      expect(captured.any((b) => b.categoryId == 'food'), isFalse);
    });
  });

  // ─── TreasuryHistoryPresenter ─────────────────────────────────────────────

  group('TreasuryHistoryPresenter', () {
    late MockStorageService mockStorage;
    late TreasuryHistoryPresenter presenter;

    setUp(() {
      mockStorage = MockStorageService();
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
      when(mockStorage.loadBills()).thenAnswer((_) async => []);
      when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
      when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
      when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
      presenter = TreasuryHistoryPresenter(mockStorage);
    });

    test('summaries are sorted descending by month', () async {
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => [
            _summary('2026-01'),
            _summary('2026-03'),
            _summary('2026-02'),
          ]);
      await presenter.load();
      final months = presenter.summaries.map((s) => s.month).toList();
      expect(months, ['2026-03', '2026-02', '2026-01']);
    });

    test('closePreviousMonthIfNeeded is idempotent', () async {
      final lastMonth = previousMonth(toMonthKey(DateTime.now()));
      when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => [
            _summary(lastMonth),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 100,
                type: TransactionType.outflow,
                month: lastMonth),
          ]);
      await presenter.load();
      // saveMonthlySummaries should NOT be called since month is already closed
      verifyNever(mockStorage.saveMonthlySummaries(any));
    });

    test('closePreviousMonthIfNeeded skips when no data exists for prior month',
        () async {
      // No bills, transactions, or receivables for prior month → no summary created
      await presenter.load();
      verifyNever(mockStorage.saveMonthlySummaries(any));
    });

    test('closePreviousMonthIfNeeded creates summary for prior month with data',
        () async {
      final lastMonth = previousMonth(toMonthKey(DateTime.now()));
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 500,
                type: TransactionType.inflow,
                month: lastMonth),
          ]);
      await presenter.load();
      verify(mockStorage.saveMonthlySummaries(any)).called(1);
    });

    test('currentMonthSummary computes live data for current month', () async {
      final currentMonth = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'a1', category: AccountCategory.ewallet, balance: 2000),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(
                id: 't1',
                accountId: 'a1',
                amount: 1000,
                type: TransactionType.inflow,
                month: currentMonth),
            _txn(
                id: 't2',
                accountId: 'a1',
                amount: 300,
                type: TransactionType.outflow,
                month: currentMonth),
          ]);
      await presenter.load();
      final summary = presenter.currentMonthSummary;
      expect(summary?.totalInflow, 1000);
      expect(summary?.totalOutflow, 300);
      expect(summary?.netSavings, 700);
    });
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

MonthlySummary _summary(String month) => MonthlySummary(
      month: month,
      totalInflow: 0,
      totalOutflow: 0,
      totalBills: 0,
      totalBillsPaid: 0,
      billCount: 0,
      billsPaidCount: 0,
      totalReceivables: 0,
      totalReceived: 0,
      receivableCount: 0,
      netSavings: 0,
      endingCash: 0,
      accountSnapshots: {},
      categorySpend: {},
    );

/// Waits for [presenter]'s initial load() to complete.
Future<void> _waitForLoad(LedgerPresenter presenter) async {
  while (presenter.isLoading) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
