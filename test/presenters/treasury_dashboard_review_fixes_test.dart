import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Review fixes on the mobile dashboard (PR #838): float residue, held money
/// above the balance, the empty state, the savings-rate tone, a ±0.00 net
/// flow and over-limit credit.
void main() {
  final month = toMonthKey(DateTime.now());

  FinancialAccount acct(
    String id,
    double balance, {
    AccountCategory category = AccountCategory.bank,
    String? linkedAccountId,
    double? creditLimit,
    bool isActive = true,
  }) =>
      FinancialAccount(
        id: id,
        name: id,
        category: category,
        balance: balance,
        colorHex: '#2E90FA',
        icon: 'wallet',
        linkedAccountId: linkedAccountId,
        creditLimit: creditLimit,
        isActive: isActive,
      );

  TransactionRecord txn(
    String id,
    double amount,
    TransactionType type, {
    String accountId = 'a1',
    String? transferGroupId,
  }) =>
      TransactionRecord(
        id: id,
        date: DateTime.now(),
        accountId: accountId,
        categoryId: '',
        amount: amount,
        type: type,
        description: 'Test',
        month: month,
        transferGroupId: transferGroupId,
      );

  Future<TreasuryDashboardPresenter> load({
    List<FinancialAccount> accounts = const [],
    List<TransactionRecord> transactions = const [],
    List<Bill> bills = const [],
    List<Budget> budgets = const [],
  }) async {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => accounts);
    when(s.loadTransactions()).thenAnswer((_) async => transactions);
    when(s.loadBills()).thenAnswer((_) async => bills);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => budgets);
    when(s.loadBudgetGroups()).thenAnswer((_) async => []);
    when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(s.loadFinanceCategories()).thenAnswer((_) async => []);
    when(s.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(s.saveAccounts(any)).thenAnswer((_) async {});
    final p = TreasuryDashboardPresenter(s);
    await p.load();
    return p;
  }

  group('overdrawn', () {
    test('float residue below a cent is zero, not overdrawn', () async {
      const residue = 1000.30 - 500.10 - 500.20; // about -5.7e-14
      expect(residue, lessThan(0));
      final p = await load(accounts: [acct('a1', residue)]);

      expect(p.overdrawnAccountIds, isEmpty);
      expect(p.dashboardAccountSublines['a1'], 'Bank');
      expect(formatPesoMinus(p.yoursByAccountId['a1']!), formatPeso(0));
    });

    test('a real negative balance is overdrawn', () async {
      final p = await load(accounts: [acct('a1', -0.01)]);

      expect(p.overdrawnAccountIds, {'a1'});
      expect(p.dashboardAccountSublines['a1'],
          'Overdrawn · check the last transfer');
    });

    test('held money above the balance keeps the held line, not overdrawn',
        () async {
      final p = await load(accounts: [
        acct('a1', 3000),
        acct('h1', 4000,
            category: AccountCategory.custodian, linkedAccountId: 'a1'),
      ]);

      expect(p.yoursByAccountId['a1'], -1000);
      expect(p.overdrawnAccountIds, isEmpty);
      expect(p.dashboardAccountSublines['a1'],
          'Bank · ${formatPeso(4000)} held · more than the balance');
    });

    test('held money within the balance reads as a plain held line', () async {
      final p = await load(accounts: [
        acct('a1', 5000),
        acct('h1', 2000,
            category: AccountCategory.custodian, linkedAccountId: 'a1'),
      ]);

      expect(
          p.dashboardAccountSublines['a1'], 'Bank · ${formatPeso(2000)} held');
    });

    test('a negative balance with money held is still overdrawn', () async {
      final p = await load(accounts: [
        acct('a1', -200),
        acct('h1', 500,
            category: AccountCategory.custodian, linkedAccountId: 'a1'),
      ]);

      expect(p.overdrawnAccountIds, {'a1'});
      expect(p.dashboardAccountSublines['a1'],
          'Overdrawn · check the last transfer');
    });
  });

  group('empty state', () {
    test('no accounts and nothing this month: empty state only', () async {
      final p = await load();

      expect(p.showsOnlyEmptyState, isTrue);
      expect(p.accountsEmptyTitle, 'No accounts yet');
    });

    test('archived accounts only: full dashboard, "No active accounts"',
        () async {
      final p = await load(accounts: [acct('a1', 500, isActive: false)]);

      expect(p.hasAccounts, isFalse);
      expect(p.showsOnlyEmptyState, isFalse);
      expect(p.hasOnlyArchivedAccounts, isTrue);
      expect(p.accountsEmptyTitle, 'No active accounts');
    });

    test('no accounts but a bill this month: full dashboard', () async {
      final p = await load(bills: [
        Bill(
          id: 'b1',
          name: 'Internet',
          billType: BillType.utility,
          amount: 1699,
          dueDay: 1,
          month: month,
          categoryId: '',
        ),
      ]);

      expect(p.showsOnlyEmptyState, isFalse);
      expect(p.hasBills, isTrue);
      expect(p.accountsEmptyTitle, 'No accounts yet');
    });

    test('no accounts but a budget or a transaction this month: full dashboard',
        () async {
      final withBudget = await load(budgets: [
        Budget(
          id: 'g1',
          categoryId: 'groceries',
          month: month,
          allocatedAmount: 5000,
          group: 'needs',
          budgetType: BudgetType.monthly,
        ),
      ]);
      final withTxn = await load(
        transactions: [txn('t1', 200, TransactionType.outflow)],
      );

      expect(withBudget.showsOnlyEmptyState, isFalse);
      expect(withTxn.showsOnlyEmptyState, isFalse);
    });
  });

  group('savings-rate tone', () {
    test('positive is positive, none is neutral', () async {
      final positive = await load(
        accounts: [
          acct('a1', 0),
          acct('sav', 0, category: AccountCategory.savings),
        ],
        transactions: [
          txn('salary', 10000, TransactionType.inflow),
          txn('in', 2000, TransactionType.inflow,
              accountId: 'sav', transferGroupId: 'g1'),
          txn('out', 2000, TransactionType.outflow, transferGroupId: 'g1'),
        ],
      );
      final none = await load(accounts: [acct('a1', 0)]);

      expect(positive.savingsRateTone, RateTone.positive);
      expect(none.savingsRateTone, RateTone.neutral);
    });

    test('negative is a warning, zero is neutral', () async {
      final negative = await load(
        accounts: [
          acct('a1', 0),
          acct('sav', 0, category: AccountCategory.savings),
        ],
        transactions: [
          txn('salary', 10000, TransactionType.inflow),
          txn('raid', 2000, TransactionType.outflow,
              accountId: 'sav', transferGroupId: 'g1'),
        ],
      );
      final zero = await load(
        accounts: [acct('a1', 0)],
        transactions: [txn('salary', 10000, TransactionType.inflow)],
      );

      expect(negative.savingsRate, closeTo(-0.2, 1e-9));
      expect(negative.savingsRateTone, RateTone.warning);
      expect(zero.savingsRate, 0);
      expect(zero.savingsRateTone, RateTone.neutral);
    });
  });

  test('income equal to spending reads "₱0.00", neutral', () async {
    final p = await load(
      accounts: [acct('a1', 0)],
      transactions: [
        txn('in', 0.3, TransactionType.inflow),
        txn('out1', 0.1, TransactionType.outflow),
        txn('out2', 0.2, TransactionType.outflow),
      ],
    );

    // 0.3 − (0.1 + 0.2) leaves about −5.5e-17.
    expect(p.monthNetCashFlow, lessThan(0));
    expect(p.monthNetCashFlowNegative, isFalse);
    expect(p.monthNetCashFlowLabel, formatPeso(0));
  });

  group('credit available', () {
    test('an over-limit card does not cancel another card\'s room', () async {
      final p = await load(accounts: [
        acct('a1', 100),
        acct('c1', 13000,
            category: AccountCategory.creditCard, creditLimit: 10000),
        acct('c2', 0, category: AccountCategory.creditCard, creditLimit: 10000),
      ]);

      expect(p.totalCreditAvailable, 10000);
      expect(p.creditSummaryLabel,
          'Owe ${formatPeso(13000)} · ${formatPeso(10000)} available');
    });

    test('an over-limit card alone shows ₱0.00 available, never ₱-', () async {
      final p = await load(accounts: [
        acct('a1', 100),
        acct('c1', 13000,
            category: AccountCategory.creditCard, creditLimit: 10000),
      ]);

      expect(p.creditSummaryLabel,
          'Owe ${formatPeso(13000)} · ${formatPeso(0)} available');
      final card = p.creditAccounts.single;
      expect(p.creditAvailableLabel(card),
          '−${formatPeso(3000)} of ${formatPeso(10000)} available');
    });
  });

  group('formatPeso helpers round to cents before the sign', () {
    test('residue reads as zero', () {
      expect(formatPesoSigned(-1e-12), formatPeso(0));
      expect(formatPesoSigned(1e-12), formatPeso(0));
      expect(formatPesoMinus(-5.7e-14), formatPeso(0));
      expect(formatPesoMinus(-0.004), formatPeso(0));
    });

    test('real amounts keep their sign', () {
      expect(formatPesoSigned(-0.01), '−${formatPeso(0.01)}');
      expect(formatPesoSigned(3904), '+${formatPeso(3904)}');
      expect(formatPesoMinus(-1234), '−${formatPeso(1234)}');
      expect(formatPesoMinus(1234), formatPeso(1234));
    });
  });
}
