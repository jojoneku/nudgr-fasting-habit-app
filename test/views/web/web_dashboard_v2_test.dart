import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/dashboard/web_account_inventory_dialog.dart';
import 'package:intermittent_fasting/views/web/pages/dashboard/web_dashboard_page_v2.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 Dashboard (Plan 063, Phase 3) against the preview seed: every
/// canvas action is keyed and present, the outlook statement carries the six
/// presenter figures with signs on the amounts, the accounts table lists the
/// liquid and credit accounts, the Trends card shows exactly one chart at a
/// time, and the two dialogs the page opens still open.
void main() {
  const widths = [1440.0, 1100.0];
  const modes = [true, false];
  String mode(bool dark) => dark ? 'dark' : 'light';

  late LocalStorageService storage;
  late MockStatsPresenter stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(PreviewSeed.userId);
    await PreviewSeed.seedInto(storage);
    stats = MockStatsPresenter();
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  /// Builds the seeded presenter pair on the real clock — the ledger's async
  /// load never settles under the test binding's fake clock.
  Future<(TreasuryDashboardPresenter, BillsReceivablesPresenter)> seeded(
      WidgetTester tester) async {
    late TreasuryDashboardPresenter dash;
    late BillsReceivablesPresenter bills;
    await tester.runAsync(() async {
      dash = TreasuryDashboardPresenter(storage);
      await dash.load();
      final ledger = LedgerPresenter(storage, stats);
      bills = BillsReceivablesPresenter(storage, ledger, stats);
      await bills.load();
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    return (dash, bills);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required TreasuryDashboardPresenter presenter,
    required BillsReceivablesPresenter bills,
    double width = 1440,
    bool dark = true,
    VoidCallback? onOpenSetup,
    VoidCallback? onAddTransaction,
  }) async {
    // Tall enough that nothing needs scrolling into view before a tap.
    tester.view.physicalSize = Size(width, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebDashboardPageV2(
          presenter: presenter,
          billsPresenter: bills,
          onOpenSetup: onOpenSetup,
          onAddTransaction: onAddTransaction,
          onOpenLedger: () {},
          onOpenBills: () {},
          onOpenBudget: () {},
          onOpenGoals: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Every parity key the page attaches with seeded data.
  const parityKeys = <Key>[
    WebKeys.dashboardAddTransaction,
    WebKeys.dashboardNetWorthHero,
    WebKeys.dashboardOutlook,
    WebKeys.dashboardAllAccounts,
    WebKeys.dashboardTrendsSwitch,
    WebKeys.dashboardTrendNetWorth,
    WebKeys.dashboardCashFlow,
    WebKeys.dashboardBudgetHealth,
    WebKeys.dashboardOpenBudget,
    WebKeys.dashboardSpendingDonut,
    WebKeys.dashboardAllCards,
    WebKeys.dashboardSavingsGoals,
    WebKeys.dashboardOpenGoals,
  ];

  group('daysLeft', () {
    test('counts the days after today in the current month', () {
      expect(
          WebDashboardPageV2.daysLeft('2026-10', DateTime(2026, 10, 10)), 21);
      expect(WebDashboardPageV2.daysLeft('2026-10', DateTime(2026, 10, 31)), 0);
      expect(WebDashboardPageV2.daysLeft('2026-02', DateTime(2026, 2, 1)), 27);
    });

    test('is 0 for a month other than today\'s', () {
      expect(WebDashboardPageV2.daysLeft('2026-09', DateTime(2026, 10, 10)), 0);
    });
  });

  group('parity', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets('header, keys and cards at $width px in ${mode(dark)}',
            (tester) async {
          final (dash, bills) = await seeded(tester);
          await pumpPage(tester,
              presenter: dash, bills: bills, width: width, dark: dark);

          expect(find.text('Dashboard'), findsOneWidget);
          final left =
              WebDashboardPageV2.daysLeft(dash.currentMonth, DateTime.now());
          expect(
            find.text(
                '${monthLabel(dash.currentMonth)} · $left ${left == 1 ? 'day' : 'days'} left'),
            findsOneWidget,
          );
          expect(find.text('Add transaction'), findsOneWidget);

          for (final key in parityKeys) {
            expect(find.byKey(key), findsOneWidget, reason: '$key');
          }
          // One Pay now per credit line.
          expect(find.byKey(WebKeys.dashboardPayCard),
              findsNWidgets(dash.creditAccounts.length));

          for (final title in [
            'Accounts',
            'Cash flow',
            'Budget health',
            'Trends',
            'Where your money goes',
            'Savings goals',
            'Month-end outlook',
          ]) {
            expect(find.text(title), findsOneWidget, reason: title);
          }
          expect(find.text('NET WORTH'), findsOneWidget);
          expect(find.text(formatPeso(dash.netWorth)), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('month-end outlook', () {
    testWidgets('renders the six presenter figures with signs on the amounts',
        (tester) async {
      final (dash, bills) = await seeded(tester);
      await pumpPage(tester, presenter: dash, bills: bills);

      final outlook = find.byKey(WebKeys.dashboardOutlook);
      Finder inOutlook(String text) =>
          find.descendant(of: outlook, matching: find.text(text));

      final projected = dash.forecastedNetBalance;
      final expected = <String, String>{
        'Liquid now': formatPeso(dash.totalLiquidCash),
        'To receive': '+${formatPeso(dash.pendingReceivables)}',
        'Upcoming bills': '−${formatPeso(dash.monthUnpaidBills)}',
        'Set-asides due': '−${formatPeso(dash.budgetedExpensesRemaining)}',
        'Budget left': '−${formatPeso(dash.budgetRemainingNetOfObligations)}',
        'Projected month-end': projected < 0
            ? '−${formatPeso(projected.abs())}'
            : formatPeso(projected),
      };
      for (final entry in expected.entries) {
        // Labels carry no +/−/= of their own; the sign is on the figure.
        expect(inOutlook(entry.key), findsOneWidget, reason: entry.key);
        expect(inOutlook(entry.value), findsOneWidget,
            reason: '${entry.key} → ${entry.value}');
      }
      // The seed has money owed and bills due, so the signs are exercised.
      expect(dash.pendingReceivables, greaterThan(0));
      expect(dash.monthUnpaidBills, greaterThan(0));
    });
  });

  group('accounts', () {
    testWidgets('lists every liquid and credit account, credit as available',
        (tester) async {
      final (dash, bills) = await seeded(tester);
      await pumpPage(tester, presenter: dash, bills: bills);

      expect(dash.liquidAccounts, isNotEmpty);
      expect(dash.creditAccounts, isNotEmpty);
      for (final a in dash.liquidAccounts) {
        expect(find.text(a.name), findsOneWidget, reason: a.name);
      }
      // A credit line is named twice: the Accounts table and the Credit card.
      for (final a in dash.creditAccounts) {
        expect(find.text(a.name), findsNWidgets(2), reason: a.name);
      }
      expect(find.text('available'), findsNWidgets(dash.creditAccounts.length));
      expect(find.text('Credit'), findsNWidgets(dash.creditAccounts.length + 1),
          reason: 'one Type cell per credit line plus the card title');
      // The overdrawn seed account is flagged, not silently negative.
      expect(find.text('Overdrawn · check the last transfer'), findsOneWidget);
      expect(find.text('All ${dash.accountInventoryCount} ›'), findsOneWidget);
    });

    testWidgets('"All N ›" opens the account inventory dialog', (tester) async {
      final (dash, bills) = await seeded(tester);
      await pumpPage(tester, presenter: dash, bills: bills);

      await tester.tap(find.byKey(WebKeys.dashboardAllAccounts));
      await tester.pumpAndSettle();

      expect(find.byType(WebAccountInventoryDialog), findsOneWidget);
      expect(find.text('All accounts'), findsOneWidget);
      expect(
        find.textContaining('${dash.accountInventoryCount} total'),
        findsOneWidget,
      );
    });
  });

  group('trends', () {
    testWidgets('shows exactly one chart and switches between the three',
        (tester) async {
      final (dash, bills) = await seeded(tester);
      await pumpPage(tester, presenter: dash, bills: bills);

      void expectOnly(Key visible) {
        for (final key in [
          WebKeys.dashboardTrendNetWorth,
          WebKeys.dashboardTrendIncomeExpenses,
          WebKeys.dashboardTrendDailySpending,
        ]) {
          expect(
              find.byKey(key), key == visible ? findsOneWidget : findsNothing,
              reason: '$key while $visible is selected');
        }
      }

      expectOnly(WebKeys.dashboardTrendNetWorth);

      await tester.tap(find.text('Income vs expenses'));
      await tester.pumpAndSettle();
      expectOnly(WebKeys.dashboardTrendIncomeExpenses);

      await tester.tap(find.text('Daily spending'));
      await tester.pumpAndSettle();
      expectOnly(WebKeys.dashboardTrendDailySpending);
      expect(find.textContaining('Last 7 days'), findsOneWidget);

      await tester.tap(find.text('Net worth'));
      await tester.pumpAndSettle();
      expectOnly(WebKeys.dashboardTrendNetWorth);
      expect(tester.takeException(), isNull);
    });
  });

  group('credit', () {
    testWidgets('"Pay now" opens the quick-pay dialog for that card',
        (tester) async {
      final (dash, bills) = await seeded(tester);
      await pumpPage(tester, presenter: dash, bills: bills);

      final owed = dash.creditAccounts.firstWhere((a) => a.currentPayable > 0);
      final cleared =
          dash.creditAccounts.where((a) => a.currentPayable <= 0).toList();
      expect(cleared, isNotEmpty, reason: 'seed has a zero-balance line');

      final buttons = tester
          .widgetList<OutlinedButton>(find.byKey(WebKeys.dashboardPayCard))
          .toList();
      expect(
          buttons.where((b) => b.onPressed == null), hasLength(cleared.length),
          reason: 'Pay now is disabled when nothing is owed');

      await tester.tap(find.byKey(WebKeys.dashboardPayCard).first);
      await tester.pumpAndSettle();

      expect(find.text('Pay ${owed.name}'), findsOneWidget);
      expect(find.text('Pay from'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pay'), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets('offers "Add your first account" when there are no accounts',
        (tester) async {
      final empty = MockStorageService();
      when(empty.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(empty.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[]);
      when(empty.loadTransactions())
          .thenAnswer((_) async => <TransactionRecord>[]);
      when(empty.loadBills()).thenAnswer((_) async => []);
      when(empty.loadReceivables()).thenAnswer((_) async => []);
      when(empty.loadBudgets()).thenAnswer((_) async => []);
      when(empty.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(empty.loadFinanceCategories()).thenAnswer((_) async => []);
      when(empty.loadBudgetGroups()).thenAnswer((_) async => []);
      when(empty.loadMonthlySummaries())
          .thenAnswer((_) async => <MonthlySummary>[]);
      when(empty.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(empty.saveAccounts(any)).thenAnswer((_) async {});
      final dash = TreasuryDashboardPresenter(empty);
      await dash.load();

      var opened = 0;
      await pumpPage(
        tester,
        presenter: dash,
        bills: MockBillsReceivablesPresenter(),
        onOpenSetup: () => opened++,
      );

      expect(find.text('No accounts yet'), findsOneWidget);
      expect(find.byKey(WebKeys.dashboardNetWorthHero), findsNothing);
      await tester.tap(find.byKey(WebKeys.dashboardAddFirstAccount));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('header', () {
    testWidgets('"Add transaction" fires onAddTransaction', (tester) async {
      final (dash, bills) = await seeded(tester);
      var added = 0;
      await pumpPage(tester,
          presenter: dash, bills: bills, onAddTransaction: () => added++);

      await tester.tap(find.byKey(WebKeys.dashboardAddTransaction));
      await tester.pump();
      expect(added, 1);
    });
  });
}
