import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// The labels and decisions the mobile dashboard cards read (Plan 071
/// Phase 7), so no card computes them in `build()`.
void main() {
  TransactionRecord out(String id, DateTime date, double amount) =>
      TransactionRecord(
        id: id,
        date: date,
        accountId: 'a1',
        categoryId: '',
        amount: amount,
        type: TransactionType.outflow,
        description: 'Spend',
        month: toMonthKey(date),
      );

  Future<TreasuryDashboardPresenter> load({
    List<TransactionRecord> transactions = const [],
    double balance = 1000,
  }) async {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'a1',
            name: 'Bank',
            category: AccountCategory.bank,
            balance: balance,
            colorHex: '#2E90FA',
            icon: 'wallet',
          ),
        ]);
    when(s.loadTransactions()).thenAnswer((_) async => transactions);
    when(s.loadBills()).thenAnswer((_) async => []);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => []);
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

  test('no income: spent share and savings rate read "—"', () async {
    final p = await load(transactions: [out('t1', DateTime.now(), 500)]);

    expect(p.spentShareOfIncomeLabel, 'Spent — of income');
    expect(p.hasSavingsRate, isFalse);
    expect(p.savingsRateLabel, 'Savings rate —');
    expect(p.monthNetCashFlowNegative, isTrue);
    expect(p.monthNetCashFlowLabel, '−${formatPeso(500)}');
    expect(p.monthNetCashFlowCompactLabel, '↓ ${formatPeso(500)}');
    expect(p.cashflowIncomeFraction, 0);
    expect(p.cashflowExpenseFraction, 1);
  });

  test('outlook lines keep the web order and signs', () async {
    final p = await load(balance: -300);
    final lines = p.monthEndOutlook.lines;

    expect(lines.first.label, 'Liquid now');
    expect(lines.first.amount, '−${formatPeso(300)}');
    expect(lines.map((l) => l.tone), [
      StatementTone.neutral,
      StatementTone.income,
      StatementTone.bills,
      StatementTone.setAside,
      StatementTone.budget,
    ]);
    expect(p.monthEndOutlook.projectedTone, StatementTone.bad);
    expect(p.monthEndOutlook.projectedLabel, '−${formatPeso(300)}');
  });

  test('a cleared card cannot be paid; one with a balance can', () async {
    final p = await load();
    FinancialAccount card(double balance) => FinancialAccount(
          id: 'c',
          name: 'Card',
          category: AccountCategory.creditCard,
          balance: balance,
          colorHex: '#000000',
          icon: 'card',
          creditLimit: 10000,
        );

    expect(p.canPayCredit(card(0)), isFalse);
    expect(p.canPayCredit(card(-50)), isFalse);
    expect(p.canPayCredit(card(2000)), isTrue);
    expect(p.creditNearLimit(card(9500)), isTrue);
    expect(p.creditNearLimit(card(2000)), isFalse);
    expect(p.creditAvailableLabel(card(2000)),
        '${formatPeso(8000)} of ${formatPeso(10000)} available');
  });

  test('spending summary covers last month and picks the first peak day',
      () async {
    final now = DateTime(2026, 3, 10);
    final p = await load(transactions: [
      out('t1', DateTime(2026, 2, 3), 400),
      out('t2', DateTime(2026, 2, 9), 400),
      out('t3', DateTime(2026, 2, 20), 100),
      out('t4', DateTime(2026, 3, 1), 999),
    ]);

    final s = p.spendingSummary(SpendRange.lastMonth, now: now);
    expect(s.days.first.date, DateTime(2026, 2, 1));
    expect(s.days.last.date, DateTime(2026, 2, 28));
    expect(s.total, 900);
    expect(s.avgDaily, 300);
    expect(s.peak, 400);
    expect(s.peakDay, DateTime(2026, 2, 3));
    expect(s.peakDayLabel, 'Tue, Feb 3');
    expect(s.hasData, isTrue);

    final empty =
        p.spendingSummary(SpendRange.last7, now: DateTime(2025, 1, 1));
    expect(empty.hasData, isFalse);
    expect(empty.peakDayLabel, '—');
  });

  test('days-left label', () async {
    final p = await load();
    final left = p.daysLeftInMonth;
    expect(
      p.daysLeftLabel,
      left == 0 ? 'Last day' : '$left ${left == 1 ? 'day' : 'days'} left',
    );
    expect(p.cashflowTitle, endsWith(' cash flow'));
  });
}
