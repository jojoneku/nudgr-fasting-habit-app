import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../mocks.mocks.dart';

// Regression tests for the Finance/Treasury audit remediation (Batch A).
// See docs/finance_audit_remediation_spec.md.

FinancialAccount _account({
  required String id,
  AccountCategory category = AccountCategory.ewallet,
  double balance = 0,
  double? creditLimit,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
      creditLimit: creditLimit,
    );

TransactionRecord _txn({
  required String id,
  required String accountId,
  required double amount,
  required TransactionType type,
  String categoryId = '',
  String? transferGroupId,
  String? month,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.now(),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: 'Test',
      month: month ?? toMonthKey(DateTime.now()),
      transferGroupId: transferGroupId,
    );

Bill _bill({
  required String id,
  double amount = 100,
  bool isPaid = false,
  String? month,
  int dueDay = 10,
  String categoryId = '',
  String? accountId,
  BillType billType = BillType.utility,
}) =>
    Bill(
      id: id,
      name: 'Bill $id',
      billType: billType,
      amount: amount,
      dueDay: dueDay,
      month: month ?? toMonthKey(DateTime.now()),
      categoryId: categoryId,
      isPaid: isPaid,
      accountId: accountId,
    );

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;

  void stubEmpty() {
    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(mockStorage.loadAccounts()).thenAnswer((_) async => []);
    when(mockStorage.loadTransactions()).thenAnswer((_) async => []);
    when(mockStorage.loadBills()).thenAnswer((_) async => []);
    when(mockStorage.loadReceivables()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgets()).thenAnswer((_) async => []);
    when(mockStorage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(mockStorage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(mockStorage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(mockStorage.loadWarnedBudgetKeys())
        .thenAnswer((_) async => <String>{});
    when(mockStorage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(mockStorage.saveAccounts(any)).thenAnswer((_) async {});
    when(mockStorage.saveTransactions(any)).thenAnswer((_) async {});
    when(mockStorage.saveBills(any)).thenAnswer((_) async {});
    when(mockStorage.saveReceivables(any)).thenAnswer((_) async {});
    when(mockStorage.saveBudgets(any)).thenAnswer((_) async {});
    when(mockStorage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(mockStorage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(mockStorage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(mockStats.addXp(any)).thenAnswer((_) async {});
    when(mockStats.stats).thenReturn(UserStats.initial());
  }

  setUp(() {
    mockStorage = MockStorageService();
    mockStats = MockStatsPresenter();
    stubEmpty();
  });

  // ── A7: overpaid liability must not inflate available credit ──────────────
  group('A7 — overpaid liability credit math', () {
    test('overpaid card floors payable at 0; available credit caps at limit',
        () {
      final card = _account(
        id: 'cc',
        category: AccountCategory.creditCard,
        balance: -2000, // overpaid: the bank owes you
        creditLimit: 50000,
      );
      expect(card.currentPayable, 0);
      expect(card.availableCredit, 50000); // NOT 52000
      expect(card.utilization, 0); // NOT negative
    });

    test('normal positive balance is unchanged', () {
      final card = _account(
        id: 'cc',
        category: AccountCategory.creditCard,
        balance: 12000,
        creditLimit: 50000,
      );
      expect(card.currentPayable, 12000);
      expect(card.availableCredit, 38000);
      expect(card.utilization, closeTo(0.24, 1e-9));
    });
  });

  // ── A3: isBillOverdue honours the bill's month ────────────────────────────
  group('A3 — isBillOverdue is month-aware', () {
    test('past-month unpaid bill is overdue; future-month bill is not',
        () async {
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      // isBillOverdue is pure — pass bills directly.
      expect(p.isBillOverdue(_bill(id: 'past', month: '2020-01')), isTrue);
      expect(p.isBillOverdue(_bill(id: 'future', month: '2099-12')), isFalse);
      expect(p.isBillOverdue(_bill(id: 'paid', month: '2020-01', isPaid: true)),
          isFalse);
    });
  });

  // ── A5: savings contributions net in−out (Budget ↔ Dashboard parity) ──────
  group('A5 — savings net contributions', () {
    test('transfer between two savings accounts nets to zero across budgets',
        () async {
      final accounts = [
        _account(id: 'sav1', category: AccountCategory.savings, balance: 0),
        _account(id: 'sav2', category: AccountCategory.goal, balance: 0),
      ];
      // A transfer sav1 → sav2 is two legs sharing a group id.
      final txns = [
        _txn(
            id: 'out',
            accountId: 'sav1',
            amount: 3000,
            type: TransactionType.outflow,
            transferGroupId: 'g1'),
        _txn(
            id: 'in',
            accountId: 'sav2',
            amount: 3000,
            type: TransactionType.inflow,
            transferGroupId: 'g1'),
      ];
      // Savings budgets targeting BOTH accounts (categoryId = account id).
      final budgets = [
        Budget(
            id: 'b1',
            categoryId: 'sav1',
            month: toMonthKey(DateTime.now()),
            allocatedAmount: 5000,
            group: BudgetGroupDef.idSavings,
            budgetType: BudgetType.monthly),
        Budget(
            id: 'b2',
            categoryId: 'sav2',
            month: toMonthKey(DateTime.now()),
            allocatedAmount: 5000,
            group: BudgetGroupDef.idSavings,
            budgetType: BudgetType.monthly),
      ];
      when(mockStorage.loadAccounts()).thenAnswer((_) async => accounts);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => txns);
      when(mockStorage.loadBudgets()).thenAnswer((_) async => budgets);

      final dash = TreasuryDashboardPresenter(mockStorage);
      await dash.load();
      // Dashboard total savings spent and net contributions must agree at 0.
      expect(dash.totalBudgetSpent, 0);
      expect(dash.monthSavingsContributions, 0);

      final budget = BudgetPresenter(mockStorage, mockStats);
      await budget.load();
      // sav1 net = −3000, sav2 net = +3000 → section spent nets to 0.
      expect(budget.contributedTo('sav1'), -3000);
      expect(budget.contributedTo('sav2'), 3000);
      expect(budget.sectionSpent(BudgetGroupDef.idSavings), 0);
    });
  });

  // ── A6: forecast doesn't double-subtract a budgeted unpaid bill ───────────
  group('A6 — forecast bill/budget overlap', () {
    test('unpaid bill in a budgeted category is deducted once, not twice',
        () async {
      final month = toMonthKey(DateTime.now());
      when(mockStorage.loadAccounts())
          .thenAnswer((_) async => [_account(id: 'acc', balance: 10000)]);
      when(mockStorage.loadBills()).thenAnswer((_) async =>
          [_bill(id: 'rent', amount: 5000, categoryId: 'rent', month: month)]);
      when(mockStorage.loadBudgets()).thenAnswer((_) async => [
            Budget(
                id: 'b1',
                categoryId: 'rent',
                month: month,
                allocatedAmount: 5000,
                group: BudgetGroupDef.idVariableOptional,
                budgetType: BudgetType.monthly),
          ]);
      final p = TreasuryDashboardPresenter(mockStorage);
      await p.load();

      // endingCash = 10000 − 5000 unpaid bill = 5000.
      expect(p.endingCash, 5000);
      // totalBudgetRemaining = 5000 (nothing spent yet).
      expect(p.totalBudgetRemaining, 5000);
      // Forecast credits back the 5000 overlap → 5000, NOT 0 (double-subtract).
      expect(p.forecastedNetBalance, 5000);
    });
  });

  // ── A1: a liability statement cannot be paid from itself ──────────────────
  group('A1 — liability self-payment guard', () {
    test('markBillPaid throws when funding account == the liability account',
        () async {
      when(mockStorage.loadAccounts()).thenAnswer((_) async => [
            _account(
                id: 'cc', category: AccountCategory.creditCard, balance: 2000),
          ]);
      when(mockStorage.loadBills()).thenAnswer((_) async => [
            _bill(id: 'b1', amount: 2000, accountId: 'cc', month: '2026-03'),
          ]);
      final ledger = LedgerPresenter(mockStorage, mockStats);
      final bills = BillsReceivablesPresenter(mockStorage, ledger, mockStats);
      await bills.load();

      expect(
        () => bills.markBillPaid('b1', paidAmount: 2000, accountId: 'cc'),
        throwsArgumentError,
      );
    });
  });

  // ── A9: averageDailyOutflow is 0 (not ₱1) for a zero-spend month ──────────
  group('A9 — averageDailyOutflow sentinel', () {
    test('empty month reports 0.0, not 1.0', () async {
      final ledger = LedgerPresenter(mockStorage, mockStats);
      await ledger.load();
      expect(ledger.averageDailyOutflow, 0.0);
    });
  });

  // ── Both transfer legs visible in the all-accounts view ───────────────────
  group('transfer legs in all-accounts list', () {
    test('all-accounts view shows BOTH transfer legs; totals exclude them',
        () async {
      final accounts = [
        _account(id: 'a', balance: 0),
        _account(id: 'b', balance: 0),
      ];
      // Transfer a → b (two legs sharing g1) plus a real expense.
      final txns = [
        _txn(
            id: 'out',
            accountId: 'a',
            amount: 1000,
            type: TransactionType.outflow,
            transferGroupId: 'g1'),
        _txn(
            id: 'in',
            accountId: 'b',
            amount: 1000,
            type: TransactionType.inflow,
            transferGroupId: 'g1'),
        _txn(
            id: 'spend',
            accountId: 'a',
            amount: 250,
            type: TransactionType.outflow),
      ];
      when(mockStorage.loadAccounts()).thenAnswer((_) async => accounts);
      when(mockStorage.loadTransactions()).thenAnswer((_) async => txns);

      final ledger = LedgerPresenter(mockStorage, mockStats);
      await ledger.load();
      // Default = all-accounts view (no account filter).

      final ids = ledger.groupedTransactions.values
          .expand((list) => list)
          .map((t) => t.id)
          .toSet();
      // BOTH transfer legs are present, not just the outflow leg.
      expect(ids, containsAll(<String>{'out', 'in', 'spend'}));

      // Totals still exclude transfer legs — only the ₱250 expense counts.
      expect(ledger.filteredMonthInflow, 0.0);
      expect(ledger.filteredMonthOutflow, 250.0);
    });
  });
}
