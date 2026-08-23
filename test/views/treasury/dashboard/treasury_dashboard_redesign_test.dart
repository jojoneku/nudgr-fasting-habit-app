import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/metric_cards_grid.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';

import '../../../mocks.mocks.dart';

/// Widget-level smoke for the Nudgr Treasury dashboard redesign — proves the new
/// hero, cashflow strip, and accounts list build and render with seeded data.
void main() {
  final month = toMonthKey(DateTime.now());
  final prevMonth = previousMonth(month);

  FinancialAccount account(String id, String name, double balance) =>
      FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.bank,
        balance: balance,
        colorHex: '#2E90FA',
        icon: 'wallet',
      );

  TransactionRecord txn(String id, double amount, TransactionType type) =>
      TransactionRecord(
        id: id,
        date: DateTime.now(),
        accountId: 'a1',
        categoryId: '',
        amount: amount,
        type: type,
        description: 'Test',
        month: month,
      );

  MockStorageService buildStorage() {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('a2', 'GCash', 18400),
        ]);
    when(s.loadTransactions()).thenAnswer((_) async => [
          txn('t1', 34000, TransactionType.inflow),
          txn('t2', 12000, TransactionType.outflow),
        ]);
    when(s.loadBills()).thenAnswer((_) async => []);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => []);
    when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(s.loadFinanceCategories()).thenAnswer((_) async => []);
    // A prior month-end summary so netWorthTrend() has two points (hero pill +
    // sparkline render).
    when(s.loadMonthlySummaries()).thenAnswer((_) async => [
          MonthlySummary(
            month: prevMonth,
            totalInflow: 30000,
            totalOutflow: 20000,
            totalBills: 0,
            totalBillsPaid: 0,
            billCount: 0,
            billsPaidCount: 0,
            totalReceivables: 0,
            totalReceived: 0,
            receivableCount: 0,
            netSavings: 10000,
            endingCash: 50000,
            netWorth: 55000,
            accountSnapshots: const {},
            categorySpend: const {},
          ),
        ]);
    when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(s.saveAccounts(any)).thenAnswer((_) async {});
    return s;
  }

  Future<void> pumpDashboard(WidgetTester tester) async {
    final presenter = TreasuryDashboardPresenter(buildStorage());
    await tester.pumpWidget(
      MaterialApp(home: TreasuryDashboardView(presenter: presenter)),
    );
    // Let load() resolve and the ListenableBuilder rebuild out of isLoading.
    await tester.pumpAndSettle();
  }

  testWidgets('renders the NET WORTH hero, cashflow strip and accounts',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('NET WORTH'), findsOneWidget);
    expect(find.textContaining('cashflow'), findsOneWidget);
    expect(find.text('Proj. month-end cash'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('BPI Personal'), findsWidgets);
    // No SyncPresenter is wired here, so the status pill must say so rather
    // than claim "Synced" — it used to be a hardcoded green badge that read the
    // same offline, signed out, or with changes still queued.
    expect(find.text('Local only'), findsOneWidget);
  });

  testWidgets('Month-End Outlook shows every term of the projection',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Month-End Outlook'), findsOneWidget);
    // The full chain: start, one tile per adjustment, result. Every deduction
    // is on screen so the drop from liquid cash to the projection reconciles —
    // "Budget Left" in particular used to be deducted invisibly.
    expect(find.text('LIQUID NOW'), findsOneWidget);
    expect(find.text('TO RECEIVE'), findsOneWidget);
    expect(find.text('UPCOMING BILLS'), findsOneWidget);
    expect(find.text('BUDGET / SAVINGS DUE'), findsOneWidget);
    expect(find.text('BUDGET LEFT'), findsOneWidget);
    expect(find.text('PROJ. MONTH-END CASH'), findsOneWidget);

    // Raw ending cash is no longer a headline tile — it does not reserve the
    // remaining budget, so it read as a projection it isn't.
    expect(find.text('ENDING CASH'), findsNothing);
    // Month in/out live on the cashflow strip's bars, not in this grid.
    expect(find.text('MONTH IN'), findsNothing);
    expect(find.text('MONTH OUT'), findsNothing);
  });

  testWidgets('projection tile renders even with no budgets set',
      (tester) async {
    // buildStorage() seeds no budgets and no budgeted expenses, so
    // presenter.hasBudget is false. The tile used to be swapped for Liabilities
    // in this case, hiding the forecast from exactly the users who never set a
    // budget.
    await pumpDashboard(tester);

    expect(find.text('PROJ. MONTH-END CASH'), findsOneWidget);
    expect(find.text('LIABILITIES'), findsNothing);
  });

  testWidgets('projected cash deducts the remaining budget', (tester) async {
    final storage = buildStorage();
    when(storage.loadBudgets()).thenAnswer((_) async => [
          Budget(
            id: 'b1',
            categoryId: 'groceries',
            month: month,
            allocatedAmount: 8000,
            group: 'needs',
            budgetType: BudgetType.monthly,
          ),
        ]);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    final presenter = TreasuryDashboardPresenter(storage);
    await tester.pumpWidget(
      MaterialApp(home: TreasuryDashboardView(presenter: presenter)),
    );
    await tester.pumpAndSettle();

    // 60,500 liquid, no bills or receivables, nothing spent against the 8,000
    // budget → ending cash 60,500 but only 52,500 genuinely uncommitted.
    expect(presenter.endingCash, 60500);
    expect(presenter.forecastedNetBalance, 52500);

    // The grid shows the whole chain, so both figures appear — but each under a
    // label that says which it is, and the un-deducted one never unlabelled.
    // Scoped to the grid deliberately: 60,500 is also this fixture's net worth,
    // which the hero legitimately shows.
    Finder inGrid(String text) => find.descendant(
          of: find.byType(MetricCardsGrid),
          matching: find.text(text),
        );
    // The projection itself: budget deducted, no sign prefix.
    expect(inGrid(formatPeso(52500)), findsOneWidget);
    // The un-deducted figure appears only as the chain's labelled starting
    // point, and the 8,000 it loses is on screen as the deduction that does it.
    expect(inGrid(formatPeso(60500)), findsOneWidget);
    expect(inGrid('LIQUID NOW'), findsOneWidget);
    expect(inGrid('BUDGET LEFT'), findsOneWidget);
    expect(inGrid('− ${formatPeso(8000)}'), findsOneWidget);
    expect(presenter.budgetRemainingNetOfObligations, 8000);
  });

  testWidgets('shows the account overflow expander beyond three accounts',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('a2', 'GCash', 18400),
          account('a3', 'Maya', 9200),
          account('a4', 'Cash', 3000),
          account('a5', 'Seabank', 15000),
        ]);
    final presenter = TreasuryDashboardPresenter(storage);
    await tester.pumpWidget(
      MaterialApp(home: TreasuryDashboardView(presenter: presenter)),
    );
    await tester.pumpAndSettle();

    // Two accounts beyond the collapsed 3 → "+2 more accounts".
    expect(find.textContaining('more accounts'), findsOneWidget);
    expect(find.text('Seabank'), findsNothing);

    await tester.ensureVisible(find.textContaining('more accounts'));
    await tester.tap(find.textContaining('more accounts'));
    await tester.pumpAndSettle();
    expect(find.text('Seabank'), findsOneWidget);
  });
}
