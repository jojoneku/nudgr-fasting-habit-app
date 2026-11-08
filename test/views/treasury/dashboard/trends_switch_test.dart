import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/spending_analytics_card.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// The Trends switch on the mobile spending card (Plan 071 Phase 10b):
/// Spending · Net worth · Income vs expenses, each view reading its
/// presenter series, an empty line when a series has fewer than two points,
/// and three segments that fit at 360 dp with 44 dp targets.
void main() {
  final month = toMonthKey(DateTime.now());
  final prev = previousMonth(month);

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

  MonthlySummary summary(String m, {double netWorth = 50000}) => MonthlySummary(
        month: m,
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
        endingCash: netWorth,
        netWorth: netWorth,
        accountSnapshots: const {},
        categorySpend: const {},
      );

  Future<TreasuryDashboardPresenter> presenterWith({
    List<MonthlySummary> summaries = const [],
  }) async {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'a1',
            name: 'Bank',
            category: AccountCategory.bank,
            balance: 60000,
            colorHex: '#2E90FA',
            icon: 'wallet',
          ),
        ]);
    when(s.loadTransactions()).thenAnswer((_) async => [
          txn('t1', 34000, TransactionType.inflow),
          txn('t2', 12000, TransactionType.outflow),
        ]);
    when(s.loadBills()).thenAnswer((_) async => []);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => []);
    when(s.loadBudgetGroups()).thenAnswer((_) async => []);
    when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(s.loadFinanceCategories()).thenAnswer((_) async => []);
    when(s.loadMonthlySummaries()).thenAnswer((_) async => summaries);
    when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(s.saveAccounts(any)).thenAnswer((_) async {});
    final p = TreasuryDashboardPresenter(s);
    await p.load();
    return p;
  }

  Future<void> pumpCard(
    WidgetTester tester,
    TreasuryDashboardPresenter presenter, {
    double width = 400,
    bool dark = true,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            // The dashboard list's own padding.
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SpendingAnalyticsCard(presenter: presenter),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder segment(DashboardTrend t) =>
      find.byKey(ValueKey('dashboard.trend.switch.${t.name}'));
  Finder view(DashboardTrend t) =>
      find.byKey(ValueKey('dashboard.trend.view.${t.name}'));
  const viewFull = ValueKey('dashboard.spending.viewFull');

  Future<void> choose(WidgetTester tester, DashboardTrend t) async {
    await tester.tap(segment(t));
    await tester.pumpAndSettle();
  }

  void expectOnly(DashboardTrend visible) {
    for (final t in DashboardTrend.values) {
      expect(view(t), t == visible ? findsOneWidget : findsNothing,
          reason: '${t.name} while ${visible.name} is selected');
    }
  }

  testWidgets('switching shows each view, one at a time', (tester) async {
    final p = await presenterWith(summaries: [summary(prev)]);
    await pumpCard(tester, p);

    expect(find.text('Trends'), findsOneWidget);
    expectOnly(DashboardTrend.spending);
    expect(find.byKey(viewFull), findsOneWidget);

    await choose(tester, DashboardTrend.netWorth);
    expectOnly(DashboardTrend.netWorth);
    // "View full" opens the spending history, so only Spending offers it.
    expect(find.byKey(viewFull), findsNothing);

    await choose(tester, DashboardTrend.incomeExpenses);
    expectOnly(DashboardTrend.incomeExpenses);
    expect(find.byKey(viewFull), findsNothing);

    await choose(tester, DashboardTrend.spending);
    expectOnly(DashboardTrend.spending);
    expect(find.byKey(viewFull), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('net worth view reads netWorthTrendSummary', (tester) async {
    final p = await presenterWith(summaries: [summary(prev, netWorth: 50000)]);
    final s = p.netWorthTrendSummary();
    expect(s.hasChart, isTrue);
    await pumpCard(tester, p);
    await choose(tester, DashboardTrend.netWorth);

    Finder inView(String text) => find.descendant(
        of: view(DashboardTrend.netWorth), matching: find.text(text));
    expect(inView(s.caption), findsOneWidget);
    expect(inView(s.currentCompactLabel), findsOneWidget);
    expect(inView(s.startLabel), findsOneWidget);
    expect(inView(s.changeLabel), findsOneWidget);
    // 60,000 now against 50,000 last month-end.
    expect(s.changeLabel, '↑ ${formatPesoCompact(10000)} (2 mo)');
    expect(inView(s.emptyText), findsNothing);
  });

  testWidgets('income vs expenses view reads incomeExpenseTrendSummary',
      (tester) async {
    final p = await presenterWith(summaries: [summary(prev)]);
    final s = p.incomeExpenseTrendSummary();
    expect(s.hasChart, isTrue);
    await pumpCard(tester, p);
    await choose(tester, DashboardTrend.incomeExpenses);

    Finder inView(String text) => find.descendant(
        of: view(DashboardTrend.incomeExpenses), matching: find.text(text));
    expect(inView(s.caption), findsOneWidget);
    expect(inView(s.avgIncomeLabel), findsOneWidget);
    expect(inView(s.avgExpenseLabel), findsOneWidget);
    expect(inView(s.avgNetLabel), findsOneWidget);
    expect(inView(s.emptyText), findsNothing);
    // Averages leave out the live month (₱34k in so far): only last month's
    // ₱30k in and ₱20k out count.
    expect(s.avgIncomeLabel, formatPesoCompact(30000));
    expect(s.avgExpenseLabel, formatPesoCompact(20000));
    expect(s.months.last.month, month);
  });

  testWidgets('a series with fewer than two points shows the empty text',
      (tester) async {
    // No closed months: each series has only the current month.
    final p = await presenterWith();
    expect(p.netWorthTrendSummary().hasChart, isFalse);
    expect(p.incomeExpenseTrendSummary().hasChart, isFalse);
    await pumpCard(tester, p);

    await choose(tester, DashboardTrend.netWorth);
    expect(find.text(p.netWorthTrendSummary().emptyText), findsOneWidget);

    await choose(tester, DashboardTrend.incomeExpenses);
    expect(find.text(p.incomeExpenseTrendSummary().emptyText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [true, false]) {
    testWidgets(
        'the switch fits at 360 dp with 44 dp targets '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      final p = await presenterWith(summaries: [summary(prev)]);
      await pumpCard(tester, p, width: 360, dark: dark);

      final rects = [
        for (final t in DashboardTrend.values) tester.getRect(segment(t)),
      ];
      for (var i = 0; i < rects.length; i++) {
        final r = rects[i];
        expect(r.height, greaterThanOrEqualTo(44), reason: '$i height');
        expect(r.width, greaterThanOrEqualTo(44), reason: '$i width');
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        // One row: every segment on the same line.
        expect(r.top, rects.first.top);
      }
      // Every view lays out at this width without overflow.
      for (final t in DashboardTrend.values) {
        await choose(tester, t);
        expect(tester.takeException(), isNull, reason: t.name);
      }
    });
  }

  testWidgets('short labels carry the full name for screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    final p = await presenterWith(summaries: [summary(prev)]);
    await pumpCard(tester, p);

    expect(find.text('In vs out'), findsOneWidget);
    expect(find.bySemanticsLabel('Income vs expenses'), findsOneWidget);
    expect(find.bySemanticsLabel('Net worth'), findsOneWidget);
    handle.dispose();
  });
}
