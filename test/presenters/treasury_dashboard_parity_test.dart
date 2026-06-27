import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// Plan 050 — web dashboard parity getters (totalAssets, monthNetCashFlow,
// savingsRate, currentObligations, projectedSpareThisMonth, canAfford).

FinancialAccount _account({
  required String id,
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

TransactionRecord _txn({
  required String id,
  required double amount,
  required TransactionType type,
  String accountId = 'acc1',
  String categoryId = 'cat',
  String? transferGroupId,
  bool reimbursable = false,
  String? reimbursementReceivableId,
  String? receivableId,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.now(),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: 'Test',
      month: toMonthKey(DateTime.now()),
      transferGroupId: transferGroupId,
      reimbursable: reimbursable,
      reimbursementReceivableId: reimbursementReceivableId,
      receivableId: receivableId,
    );

void main() {
  late MockStorageService mockStorage;

  setUp(() {
    mockStorage = MockStorageService();
    when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
  });

  group('parity getters', () {
    test(
        'totalAssets sums top-level non-liability accounts; netWorth nets debt',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1', balance: 10000),
            _account(id: 'acc2', category: AccountCategory.cash, balance: 2000),
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 4000),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.totalAssets, 12000);
      expect(p.totalLiabilities, 4000);
      // netWorth == totalAssets - held(0) - liabilities
      expect(p.netWorth, p.totalAssets - p.totalHeldForOthers - 4000);
      expect(p.netWorth, 8000);
      // Obligations are unpaid bills only — NOT liabilities (the card statement
      // is already a bill, so adding the liability balance too would
      // double-count) and NOT budgeted expenses (those are a separate
      // "Budget / Savings Due" figure). No bills here → 0.
      expect(p.currentObligations, 0);
    });

    test(
        'currentObligations = unpaid bills only; budgetedExpensesRemaining is '
        'separate (allocated − spent, excluding settled expenses)', () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            // A liability that must NOT be added on top of the bill below.
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 9000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            Bill(
              id: 'b1',
              name: 'Electricity',
              billType: BillType.utility,
              amount: 1800,
              dueDay: 16,
              month: month,
              categoryId: '',
            ),
            Bill(
              id: 'b2',
              name: 'Paid bill',
              billType: BillType.utility,
              amount: 500,
              dueDay: 1,
              month: month,
              categoryId: '',
              isPaid: true,
            ),
          ]);
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            // Remaining = 5000 − 2000 = 3000.
            BudgetedExpense(
              id: 'e1',
              name: 'Family Support',
              budgetedType: SetAsideType.other,
              month: month,
              allocatedAmount: 5000,
              spentAmount: 2000,
              categoryId: '',
            ),
            // Settled expense contributes nothing.
            BudgetedExpense(
              id: 'e2',
              name: 'Done',
              budgetedType: SetAsideType.other,
              month: month,
              allocatedAmount: 1000,
              spentAmount: 0,
              categoryId: '',
              isPaid: true,
            ),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.monthUnpaidBills, 1800); // paid bill excluded
      expect(p.budgetedExpensesRemaining, 3000); // 5000−2000; settled excluded
      // Obligations = unpaid bills ONLY: budgeted set-asides and the 9000
      // liability are intentionally NOT folded in.
      expect(p.currentObligations, 1800);
    });

    test('monthNetCashFlow computes from this month', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 't1', amount: 5000, type: TransactionType.inflow),
            _txn(id: 't2', amount: 2000, type: TransactionType.outflow),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.monthNetCashFlow, 3000);
    });

    test('savingsRate = money moved into savings / real income', () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1', balance: 0),
            _account(
                id: 'sav', category: AccountCategory.savings, balance: 8000),
          ]);
      // 40k salary into the spending account, then an 8k transfer into savings
      // (stored as an outflow leg on acc1 + an inflow leg on sav, sharing a
      // group id). Income denominator must exclude that transfer inflow leg.
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 'salary', amount: 40000, type: TransactionType.inflow),
            _txn(
                id: 'xfer_out',
                amount: 8000,
                type: TransactionType.outflow,
                accountId: 'acc1',
                transferGroupId: 'g1'),
            _txn(
                id: 'xfer_in',
                amount: 8000,
                type: TransactionType.inflow,
                accountId: 'sav',
                transferGroupId: 'g1'),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.monthTotalInflow, 40000); // transfer inflow leg excluded
      expect(p.monthTotalOutflow, 0); // transfer outflow leg excluded too
      expect(p.monthSavingsContributions, 8000); // landed in the savings acct
      expect(p.savingsRate, closeTo(0.2, 1e-9)); // 8000 / 40000
    });

    test('savingsRate goes negative when you net-withdraw from savings',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1'),
            _account(id: 'sav', category: AccountCategory.savings),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 'salary', amount: 10000, type: TransactionType.inflow),
            _txn(
                id: 'raid',
                amount: 2000,
                type: TransactionType.outflow,
                accountId: 'sav'),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.monthSavingsContributions, -2000);
      expect(p.savingsRate, closeTo(-0.2, 1e-9)); // -2000 / 10000
    });

    test('savingsRate is null when there is no income', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 't1', amount: 2000, type: TransactionType.outflow),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      expect(p.savingsRate, isNull);
      expect(p.monthNetCashFlow, -2000);
    });

    test(
        'forecastedNetBalance subtracts unfunded set-asides + remaining budget; '
        'budget "spent" comes from real ledger outflows (so it shrinks)',
        () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts())
          .thenAnswer((_) async => [_account(id: 'acc1', balance: 10000)]);
      // Category budget Food = 5000 allocated; 2000 actually spent via ledger.
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
              id: 'b1',
              categoryId: 'cat', // _txn defaults categoryId to 'cat'
              month: month,
              allocatedAmount: 5000,
              group: BudgetGroupDef.idVariableOptional,
              budgetType: BudgetType.monthly,
            ),
          ]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async =>
          [_txn(id: 't1', amount: 2000, type: TransactionType.outflow)]);
      // One unfunded set-aside still to fund: 1000.
      when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => [
            BudgetedExpense(
              id: 'e1',
              name: 'Gift',
              budgetedType: SetAsideType.other,
              month: month,
              allocatedAmount: 1000,
              categoryId: '',
            ),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      // Spent = real outflow (2000), NOT the set-aside spentAmount.
      expect(p.totalBudgetSpent, 2000);
      expect(
          p.totalBudgetRemaining, 3000); // 5000 − 2000 → shrinks as you spend
      expect(p.budgetedExpensesRemaining, 1000);
      // 10000 liquid − 0 bills − 1000 set-aside − 3000 remaining budget = 6000.
      expect(p.forecastedNetBalance, 6000);
    });
  });

  group('reimbursable expenses & loans', () {
    final month = toMonthKey(DateTime.now());

    Budget catBudget() => Budget(
          id: 'b1',
          categoryId: 'cat',
          month: month,
          allocatedAmount: 5000,
          group: BudgetGroupDef.idVariableOptional,
          budgetType: BudgetType.monthly,
        );

    test('reimbursable/loan outflow is excluded from expenses and budget',
        () async {
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [catBudget()]);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            _txn(id: 'normal', amount: 2000, type: TransactionType.outflow),
            _txn(
                id: 'reimb',
                amount: 1500,
                type: TransactionType.outflow,
                reimbursable: true),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      // Money you'll get back isn't spending — only the genuine 2000 counts.
      expect(p.monthTotalOutflow, 2000);
      expect(p.totalBudgetSpent, 2000);
      expect(p.totalBudgetRemaining, 3000);
    });

    test('a reimbursable/loan repayment is excluded from income', () async {
      when(mockStorage.loadTransactions()).thenAnswer((_) async => [
            // Salary — real income.
            _txn(id: 'salary', amount: 40000, type: TransactionType.inflow),
            // Lent 1500 (reimbursable) and got it back — the settling inflow
            // references the spawned receivable id.
            _txn(
                id: 'lent',
                amount: 1500,
                type: TransactionType.outflow,
                reimbursable: true,
                reimbursementReceivableId: 'r1'),
            _txn(
                id: 'payback',
                amount: 1500,
                type: TransactionType.inflow,
                receivableId: 'r1'),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      // The loan out isn't an expense; its repayment isn't income.
      expect(p.monthTotalOutflow, 0);
      expect(p.monthTotalInflow, 40000);
    });
  });

  group('canAfford', () {
    // With no bills/receivables/budgets, projectedSpareThisMonth == liquid cash.
    Future<TreasuryDashboardPresenter> presenterWithCash() async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(id: 'acc1', balance: 10000),
            _account(id: 'acc2', category: AccountCategory.cash, balance: 2000),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();
      return p;
    }

    test('yes when amount is well within spare', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(5000);
      expect(v.tier, AffordTier.yes); // 5000 <= 12000 * 0.8 (9600)
      expect(v.spareAfter, 7000);
      expect(v.accountShortfall, isNull);
    });

    test('tight when amount is above 80% of spare but still fits', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(11000);
      expect(v.tier, AffordTier.tight); // 9600 < 11000 <= 12000
      expect(v.spareAfter, 1000);
    });

    test('no when amount exceeds spare', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(13000);
      expect(v.tier, AffordTier.no);
      expect(v.spareAfter, -1000);
    });

    test('no with shortfall when the chosen account cannot cover it', () async {
      final p = await presenterWithCash(); // spare = 12000
      final v = p.canAfford(3000, accountId: 'acc2'); // acc2 has 2000
      expect(v.tier, AffordTier.no);
      expect(v.accountShortfall, 1000);
    });
  });
}
