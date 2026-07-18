import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
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
    expect(find.text('Projected spare'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('BPI Personal'), findsWidgets);
    expect(find.text('Synced'), findsOneWidget);
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
