import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/budget_overview_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/cashflow_strip.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/dashboard_header_link.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/month_end_outlook_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/net_worth_hero.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/next_month_forecast_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/spending_analytics_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/statement_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/upcoming_bills_card.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

import '../../../mocks.mocks.dart';

/// Widget-level smoke for the Nudgr Treasury dashboard redesign — proves the new
/// hero, cash flow strip, outlook statement and accounts list build and render
/// with seeded data.
void main() {
  final month = toMonthKey(DateTime.now());
  final prevMonth = previousMonth(month);

  FinancialAccount account(
    String id,
    String name,
    double balance, {
    AccountCategory category = AccountCategory.bank,
    double? creditLimit,
  }) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: balance,
        colorHex: '#2E90FA',
        icon: 'wallet',
        creditLimit: creditLimit,
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

  Budget budget(double allocated) => Budget(
        id: 'b1',
        categoryId: 'groceries',
        month: month,
        allocatedAmount: allocated,
        group: 'needs',
        budgetType: BudgetType.monthly,
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
    when(s.loadBudgetGroups()).thenAnswer((_) async => []);
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

  Future<TreasuryDashboardPresenter> pumpDashboard(
    WidgetTester tester, {
    MockStorageService? storage,
    MockBillsReceivablesPresenter? bills,
  }) async {
    final presenter = TreasuryDashboardPresenter(storage ?? buildStorage());
    await tester.pumpWidget(
      MaterialApp(
        home:
            TreasuryDashboardView(presenter: presenter, billsPresenter: bills),
      ),
    );
    // Let load() resolve and the ListenableBuilder rebuild out of isLoading.
    await tester.pumpAndSettle();
    return presenter;
  }

  Finder inOutlook(String text) => find.descendant(
        of: find.byType(MonthEndOutlookCard, skipOffstage: false),
        matching: find.text(text, skipOffstage: false),
      );

  Finder inStrip(String text) => find.descendant(
        of: find.byType(CashflowStrip, skipOffstage: false),
        matching: find.text(text, skipOffstage: false),
      );

  testWidgets('renders the NET WORTH hero, cash flow strip and accounts',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.text('NET WORTH'), findsOneWidget);
    expect(find.textContaining('cash flow'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('BPI Personal'), findsWidgets);
    // No SyncPresenter is wired here, so the status pill must say so rather
    // than claim "Synced" — it used to be a hardcoded green badge that read the
    // same offline, signed out, or with changes still queued.
    expect(find.text('Local only'), findsOneWidget);
  });

  testWidgets('hero shows net cash flow and total assets, compact',
      (tester) async {
    final presenter = await pumpDashboard(tester);

    // 34,000 in − 12,000 out; 60,500 across two bank accounts.
    expect(presenter.monthNetCashFlowCompactLabel, '↑ ₱22k');
    expect(presenter.totalAssetsCompactLabel, '₱60.5k');
    expect(
      find.descendant(
        of: find.byType(NetWorthHero),
        matching: find.text('↑ ₱22k'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NetWorthHero),
        matching: find.text('₱60.5k'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hero cells fit side by side at 360 dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDashboard(tester);

    expect(tester.takeException(), isNull);
    final flow = tester.getRect(
      find.byKey(const ValueKey('dashboard.hero.netCashFlow')),
    );
    final assets = tester.getRect(
      find.byKey(const ValueKey('dashboard.hero.totalAssets')),
    );
    expect(flow.top, assets.top, reason: 'one row, not stacked');
    expect(flow.right, lessThanOrEqualTo(assets.left));
    expect(assets.right, lessThanOrEqualTo(360));
  });

  testWidgets(
      'cash flow strip shows net flow, spent share and savings rate, '
      'not the projection', (tester) async {
    final presenter = await pumpDashboard(tester);

    expect(inStrip('Net flow'), findsOneWidget);
    expect(inStrip(presenter.monthNetCashFlowLabel), findsOneWidget);
    expect(presenter.monthNetCashFlowLabel, '+${formatPeso(22000)}');
    // 12,000 of 34,000 → 35%.
    expect(inStrip('Spent 35% of income'), findsOneWidget);
    expect(inStrip(presenter.savingsRateLabel), findsOneWidget);
    expect(inStrip('Proj. month-end cash'), findsNothing);
  });

  testWidgets('outlook renders the presenter lines in order, −₱ for negatives',
      (tester) async {
    final storage = buildStorage();
    // 80,000 still to spend against 60,500 liquid → the month ends below zero.
    when(storage.loadBudgets()).thenAnswer((_) async => [budget(80000)]);
    final presenter = await pumpDashboard(tester, storage: storage);

    expect(find.text('Month-end outlook', skipOffstage: false), findsOneWidget);

    final rows = tester
        .widgetList<StatementLineRow>(find.descendant(
          of: find.byType(MonthEndOutlookCard, skipOffstage: false),
          matching: find.byType(StatementLineRow, skipOffstage: false),
        ))
        .map((r) => r.line)
        .toList();

    expect(rows.map((l) => l.label), [
      'Liquid now',
      'To receive',
      'Upcoming bills',
      'Set-asides due',
      'Budget left',
    ]);
    expect(rows.map((l) => l.amount), [
      formatPeso(presenter.totalLiquidCash),
      '+${formatPeso(presenter.pendingReceivables)}',
      '−${formatPeso(presenter.monthUnpaidBills)}',
      '−${formatPeso(presenter.budgetedExpensesRemaining)}',
      '−${formatPeso(presenter.budgetRemainingNetOfObligations)}',
    ]);
    expect(rows.last.amount, '−₱80,000.00');

    // The projection itself is negative: typographic minus before the peso.
    expect(presenter.forecastedNetBalance, -19500);
    expect(inOutlook('Projected month-end'), findsOneWidget);
    expect(inOutlook('−₱19,500.00'), findsOneWidget);
    expect(find.textContaining('₱-', skipOffstage: false), findsNothing);

    // Raw ending cash is not a headline — it does not reserve the budget.
    expect(find.text('ENDING CASH', skipOffstage: false), findsNothing);
  });

  testWidgets('projected month-end cash appears once across strip + outlook',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadBudgets()).thenAnswer((_) async => [budget(8000)]);
    final presenter = await pumpDashboard(tester, storage: storage);

    // 60,500 liquid less the 8,000 still budgeted.
    expect(presenter.forecastedNetBalance, 52500);
    final label = presenter.monthEndOutlook.projectedLabel;
    final count = tester.widgetList(inStrip(label)).length +
        tester.widgetList(inOutlook(label)).length;
    expect(count, 1);
    expect(inOutlook(label), findsOneWidget);
    // The un-deducted 60,500 appears only as the chain's labelled start, with
    // the 8,000 it loses on screen as the deduction that does it.
    expect(inOutlook(formatPeso(60500)), findsOneWidget);
    expect(inOutlook('−${formatPeso(8000)}'), findsOneWidget);
    expect(presenter.budgetRemainingNetOfObligations, 8000);
  });

  testWidgets('projection renders even with no budgets set', (tester) async {
    // buildStorage() seeds no budgets, so presenter.hasBudget is false. The
    // projection used to be swapped for Liabilities in this case.
    final presenter = await pumpDashboard(tester);

    expect(inOutlook('Projected month-end'), findsOneWidget);
    // With nothing to deduct, the projection equals liquid now, so its
    // figure shows twice: once as the start, once in the ending panel.
    expect(
      find.descendant(
        of: find.byType(StatementEndingPanel, skipOffstage: false).first,
        matching: find.text(
          presenter.monthEndOutlook.projectedLabel,
          skipOffstage: false,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('LIABILITIES', skipOffstage: false), findsNothing);
  });

  testWidgets('Next month forecast sits under the outlook with its chain',
      (tester) async {
    final presenter = await pumpDashboard(tester);

    final title = find.text('Next month forecast', skipOffstage: false);
    expect(title, findsOneWidget);
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();

    final f = presenter.nextMonthForecast;
    expect(find.text(f.monthName), findsOneWidget);
    for (final label in [
      'Starts at',
      'To receive',
      'Bills',
      'Installments',
      'Set-asides',
      'Budget',
      f.endingTitle,
      f.changeLabel,
    ]) {
      expect(
        find.descendant(
          of: find.byType(NextMonthForecastCard),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    // It starts where this month's outlook ends.
    expect(f.startingCash, presenter.forecastedNetBalance);
    expect(find.text(f.endingLabel), findsWidgets);
    // Directly under the outlook, so the two read as a pair.
    expect(
      tester.getTopLeft(title).dy,
      greaterThan(tester
          .getTopLeft(find.text('Month-end outlook', skipOffstage: false))
          .dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no accounts: one empty state, every other card hidden',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    final presenter = await pumpDashboard(tester, storage: storage);

    expect(presenter.hasAccounts, isFalse);
    expect(find.byKey(const ValueKey('dashboard.emptyState')), findsOneWidget);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Add your first account'), findsOneWidget);
    for (final type in [
      NetWorthHero,
      CashflowStrip,
      MonthEndOutlookCard,
      NextMonthForecastCard,
      SpendingAnalyticsCard,
    ]) {
      expect(find.byType(type, skipOffstage: false), findsNothing,
          reason: '$type');
    }
    expect(find.text('Accounts', skipOffstage: false), findsNothing);
    // One action only: the FAB is hidden while the empty state shows.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
      'archived accounts only: full dashboard, "No active accounts" in the '
      'Accounts slot', (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'a1',
            name: 'Old bank',
            category: AccountCategory.bank,
            balance: 0,
            colorHex: '#2E90FA',
            icon: 'wallet',
            isActive: false,
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => [budget(5000)]);
    await pumpDashboard(tester, storage: storage);

    expect(find.byKey(const ValueKey('dashboard.emptyState')), findsNothing);
    expect(find.byType(NetWorthHero), findsOneWidget);
    final slot = find.byKey(
      const ValueKey('dashboard.accounts.empty'),
      skipOffstage: false,
    );
    expect(slot, findsOneWidget);
    expect(
      find.descendant(of: slot, matching: find.text('No active accounts')),
      findsOneWidget,
    );
    expect(find.text('No accounts yet', skipOffstage: false), findsNothing);
    expect(
      find.descendant(of: slot, matching: find.text('Add account')),
      findsOneWidget,
    );
    // The budget still shows.
    expect(
        find.byType(BudgetOverviewCard, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no accounts but a bill this month: the bill still shows',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => [
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
    await pumpDashboard(tester, storage: storage);

    expect(find.byKey(const ValueKey('dashboard.emptyState')), findsNothing);
    final slot = find.byKey(
      const ValueKey('dashboard.accounts.empty'),
      skipOffstage: false,
    );
    expect(
      find.descendant(of: slot, matching: find.text('No accounts yet')),
      findsOneWidget,
    );
    expect(find.byType(UpcomingBillsCard, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('held money above the balance shows the held line, not overdrawn',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 3000),
          FinancialAccount(
            id: 'h1',
            name: 'Mom',
            category: AccountCategory.custodian,
            balance: 4000,
            colorHex: '#2E90FA',
            icon: 'wallet',
            linkedAccountId: 'a1',
          ),
        ]);
    final presenter = await pumpDashboard(tester, storage: storage);

    expect(presenter.overdrawnAccountIds, isEmpty);
    expect(find.text('Overdrawn · check the last transfer'), findsNothing);
    expect(
      find.text('Bank · ${formatPeso(4000)} held · more than the balance'),
      findsOneWidget,
    );
  });

  testWidgets('a negative savings rate is not painted green', (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('sav', 'Savings', 1000, category: AccountCategory.savings),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => [
          txn('t1', 10000, TransactionType.inflow),
          TransactionRecord(
            id: 'raid',
            date: DateTime.now(),
            accountId: 'sav',
            categoryId: '',
            amount: 2000,
            type: TransactionType.outflow,
            description: 'Test',
            month: month,
            transferGroupId: 'g1',
          ),
        ]);
    final presenter = await pumpDashboard(tester, storage: storage);

    expect(presenter.savingsRateTone, RateTone.warning);
    final badge = tester.widget<AppBadge>(
      find.byKey(const ValueKey('dashboard.cashflow.savingsRate')),
    );
    final context = tester.element(find.byType(CashflowStrip));
    expect(badge.color, isNot(context.appColors.success));
    expect(badge.color, context.appColors.orange);
  });

  testWidgets('the empty state goes away once an account exists',
      (tester) async {
    await pumpDashboard(tester);

    expect(find.byKey(const ValueKey('dashboard.emptyState')), findsNothing);
    expect(find.byType(NetWorthHero), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('touch targets are at least 44×44', (tester) async {
    await pumpDashboard(tester);

    for (final r in SpendRange.values) {
      final key = find.byKey(
        ValueKey('dashboard.spending.range.${r.name}'),
        skipOffstage: false,
      );
      await tester.ensureVisible(key);
      expect(tester.getSize(key).height, greaterThanOrEqualTo(44),
          reason: r.name);
    }
    final viewFull = find.byKey(
      const ValueKey('dashboard.spending.viewFull'),
      skipOffstage: false,
    );
    await tester.ensureVisible(viewFull);
    final size = tester.getSize(viewFull);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('a header link is at least 44×44', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DashboardHeaderLink(
              key: const ValueKey('link'),
              label: 'View all',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(const ValueKey('link')));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('credit row says what is owed and available; Pay disabled at 0',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('c1', 'BPI Gold', 12000,
              category: AccountCategory.creditCard, creditLimit: 50000),
          account('c2', 'Metrobank', 0,
              category: AccountCategory.creditCard, creditLimit: 20000),
        ]);
    final presenter = await pumpDashboard(
      tester,
      storage: storage,
      bills: MockBillsReceivablesPresenter(),
    );

    final summary = find.byKey(
      const ValueKey('dashboard.credit.summary'),
      skipOffstage: false,
    );
    expect(
      tester.widget<Text>(summary).data,
      'Owe ${formatPeso(12000)} · ${formatPeso(58000)} available',
    );
    expect(presenter.creditSummaryLabel, tester.widget<Text>(summary).data);

    ButtonStyleButton pay(String id) => tester.widget<ButtonStyleButton>(
          find.byKey(ValueKey('dashboard.credit.pay.$id'), skipOffstage: false),
        );
    // Both cards keep the button; only the one with a balance can use it.
    expect(pay('c1').onPressed, isNotNull);
    expect(pay('c2').onPressed, isNull);
    expect(
        find.text('${formatPeso(38000)} of ${formatPeso(50000)} available',
            skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('an overdrawn account says so under its name', (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('a2', 'GCash', -250),
        ]);
    final presenter = await pumpDashboard(tester, storage: storage);

    expect(presenter.overdrawnAccountIds, {'a2'});
    expect(find.text('Overdrawn · check the last transfer'), findsOneWidget);
    expect(find.text('−${formatPeso(250)}'), findsOneWidget);
  });

  testWidgets('"All N accounts" expands the list beyond three accounts',
      (tester) async {
    final storage = buildStorage();
    when(storage.loadAccounts()).thenAnswer((_) async => [
          account('a1', 'BPI Personal', 42100),
          account('a2', 'GCash', 18400),
          account('a3', 'Maya', 9200),
          account('a4', 'Cash', 3000),
          account('a5', 'Seabank', 15000),
        ]);
    await pumpDashboard(tester, storage: storage);

    final link = find.byKey(const ValueKey('dashboard.accounts.all'));
    expect(find.text('All 5 accounts'), findsOneWidget);
    expect(find.text('Seabank'), findsNothing);
    expect(tester.getSize(link).height, greaterThanOrEqualTo(44));

    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('Seabank'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('dashboard copy is sentence case', (tester) async {
    await pumpDashboard(tester);

    expect(find.text('Month-End Outlook', skipOffstage: false), findsNothing);
    expect(
        find.text('Budget / Savings Due', skipOffstage: false), findsNothing);
    expect(find.text('Set-asides due', skipOffstage: false), findsOneWidget);
    expect(find.text('Goals & savings', skipOffstage: false), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
  });
}
