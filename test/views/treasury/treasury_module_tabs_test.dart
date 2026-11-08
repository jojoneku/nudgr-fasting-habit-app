import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/history/monthly_summary_detail_view.dart';
import 'package:intermittent_fasting/views/treasury/treasury_module_view.dart';

import '../../mocks.mocks.dart';

/// The Treasury module's tab surface.
///
/// Two things are pinned here. First, an enclosing shell can append its own tab
/// and open on a chosen index — that's how the web build stops losing your
/// place (and your only way to sign out) when the window crosses the desktop
/// breakpoint. Second, the seven built-in tabs are all still present.
void main() {
  MockStorageService buildStorage({
    List<MonthlySummary> summaries = const [],
  }) {
    final s = MockStorageService();
    when(s.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(s.loadAccounts()).thenAnswer((_) async => []);
    when(s.loadTransactions()).thenAnswer((_) async => []);
    when(s.loadFinanceCategories()).thenAnswer((_) async => []);
    when(s.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(s.loadBills()).thenAnswer((_) async => []);
    when(s.loadReceivables()).thenAnswer((_) async => []);
    when(s.loadBudgets()).thenAnswer((_) async => []);
    when(s.loadBudgetGroups()).thenAnswer((_) async => []);
    when(s.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(s.loadMonthlySummaries()).thenAnswer((_) async => [...summaries]);
    when(s.loadInstallments()).thenAnswer((_) async => []);
    when(s.loadGroceryCart()).thenAnswer((_) async => []);
    when(s.loadGroceryPriceMemory()).thenAnswer((_) async => []);
    when(s.loadGroceryTripHistory()).thenAnswer((_) async => []);
    when(s.loadGroceryBudget()).thenAnswer((_) async => null);
    when(s.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(s.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(s.saveAccounts(any)).thenAnswer((_) async {});
    when(s.saveTransactions(any)).thenAnswer((_) async {});
    when(s.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(s.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(s.saveBills(any)).thenAnswer((_) async {});
    when(s.saveReceivables(any)).thenAnswer((_) async {});
    when(s.saveBudgets(any)).thenAnswer((_) async {});
    when(s.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(s.saveMonthlySummaries(any)).thenAnswer((_) async {});
    return s;
  }

  Future<LedgerPresenter> pumpModule(
    WidgetTester tester, {
    List<TreasuryModuleTab> extraTabs = const [],
    int initialTabIndex = 0,
    ValueChanged<int>? onTabChanged,
    AiCoachPresenter? aiCoach,
    List<MonthlySummary> summaries = const [],
  }) async {
    final storage = buildStorage(summaries: summaries);
    final stats = MockStatsPresenter();
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    // Owners first, then the dashboard that subscribes to them.
    final ledger = LedgerPresenter(storage, stats);
    final budget = BudgetPresenter(storage, stats, ledger);
    final bills = BillsReceivablesPresenter(storage, ledger, stats);
    final dash = TreasuryDashboardPresenter(storage, ledger, budget, bills);
    final history = TreasuryHistoryPresenter(storage);
    final installments = InstallmentPresenter(storage, ledger, stats);
    final cart = GroceryCartPresenter(storage, ledger: ledger);

    await tester.pumpWidget(MaterialApp(
      home: TreasuryModuleView(
        dashPresenter: dash,
        ledgerPresenter: ledger,
        billsPresenter: bills,
        budgetPresenter: budget,
        historyPresenter: history,
        installmentPresenter: installments,
        groceryCartPresenter: cart,
        extraTabs: extraTabs,
        initialTabIndex: initialTabIndex,
        onTabChanged: onTabChanged,
        aiCoachPresenter: aiCoach,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return ledger;
  }

  testWidgets('renders all seven built-in tabs', (tester) async {
    await pumpModule(tester);

    for (final label in const [
      'Dashboard',
      'Ledger',
      'Bills',
      'Budget',
      'History',
      'Cart',
      'Goals',
    ]) {
      expect(find.widgetWithText(Tab, label), findsOneWidget,
          reason: '$label tab should be reachable');
    }
  });

  testWidgets('an extra tab is appended after the built-in seven',
      (tester) async {
    // Eight tabs need more than the 800px default to all be on screen; the
    // bar scrolls in that case, which would put "More" out of tap range.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpModule(tester, extraTabs: [
      const TreasuryModuleTab(
        icon: Icons.more_horiz,
        label: 'More',
        ownsHeader: true,
        page: Scaffold(body: Center(child: Text('more-page'))),
      ),
    ]);

    expect(find.widgetWithText(Tab, 'More'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('more-page'), findsOneWidget);
  });

  testWidgets('opens on the handed-over tab instead of resetting to Dashboard',
      (tester) async {
    // Index 4 is History — this is the position the web shell hands over when
    // the window shrinks below the desktop breakpoint.
    await pumpModule(tester, initialTabIndex: 4);

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 4);
  });

  testWidgets('reports the settled tab back to the enclosing shell',
      (tester) async {
    final seen = <int>[];
    await pumpModule(tester, onTabChanged: seen.add);

    // The tab, not the dashboard's "Budget" line in the Next Month Forecast.
    await tester.tap(find.widgetWithText(Tab, 'Budget'));
    await tester.pumpAndSettle();

    expect(seen, contains(3));
  });

  // Plan 071 Phase 8: a closed month's detail screen hands over to the Ledger,
  // the same way the web History page does.
  group('History → Open in Ledger', () {
    MonthlySummary closedMonth(String month) => MonthlySummary(
          month: month,
          totalInflow: 1000,
          totalOutflow: 400,
          totalBills: 0,
          totalBillsPaid: 0,
          billCount: 0,
          billsPaidCount: 0,
          totalReceivables: 0,
          totalReceived: 0,
          receivableCount: 0,
          netSavings: 600,
          endingCash: 600,
          accountSnapshots: const {},
          categorySpend: const {},
        );

    testWidgets(
        'sets the ledger month, closes the detail and selects the Ledger tab',
        (tester) async {
      final ledger = await pumpModule(
        tester,
        initialTabIndex: 4, // History
        summaries: [closedMonth('2025-06')],
      );
      await tester.pumpAndSettle();
      expect(ledger.selectedMonth, isNot('2025-06'));

      await tester.tap(find.text('June 2025'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthlySummaryDetailView), findsOneWidget);

      final button = find.widgetWithText(OutlinedButton, 'Open in Ledger');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(ledger.selectedMonth, '2025-06');
      expect(find.byType(MonthlySummaryDetailView), findsNothing);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.controller!.index, 1);
    });

    testWidgets('clears the Ledger filters so its totals match the month',
        (tester) async {
      final ledger = await pumpModule(
        tester,
        initialTabIndex: 4, // History
        summaries: [closedMonth('2025-06')],
      );
      await tester.pumpAndSettle();
      // A GCash filter (plus a category, owed and day filter) left on from
      // an earlier Ledger visit.
      ledger.setAccount('gcash');
      ledger.setCategoryFilter('food');
      ledger.setOwedFilter(true);
      ledger.setSelectedDate(DateTime(2026, 1, 5));
      expect(ledger.activeFilterCount, greaterThan(0));

      await tester.tap(find.text('June 2025'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Open in Ledger'));
      await tester.pumpAndSettle();

      expect(ledger.selectedMonth, '2025-06');
      expect(ledger.selectedAccountIds, isEmpty);
      expect(ledger.selectedCategoryIds, isEmpty);
      expect(ledger.owedOnly, isFalse);
      expect(ledger.selectedDate, isNull);
      expect(ledger.activeFilterCount, 0);
    });

    testWidgets('a standalone detail screen shows no Open in Ledger button',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MonthlySummaryDetailView(
          summary: closedMonth('2025-06'),
          categories: const [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Open in Ledger'), findsNothing);
    });
  });

  // Nudgy used to be reachable only from the Hub's quick-log bar. The Ledger's
  // input bar now opens it too, through the sparkle in the input pill.
  group('Nudgy on the Ledger', () {
    AiCoachPresenter buildCoach() {
      final stats = MockStatsPresenter();
      final fasting = MockFastingPresenter();
      final service = MockAiCoachService();
      when(stats.stats).thenReturn(UserStats.initial());
      when(fasting.isFasting).thenReturn(false);
      when(fasting.fastingGoalHours).thenReturn(16);
      when(service.isAvailable).thenReturn(true);
      when(service.tier).thenReturn(AiCoachTier.cloud);
      return AiCoachPresenter(stats: stats, fasting: fasting, service: service);
    }

    testWidgets('the Ledger shows an "Ask Nudgy" button when wired in',
        (tester) async {
      await pumpModule(tester, initialTabIndex: 1, aiCoach: buildCoach());

      expect(find.byTooltip('Ask Nudgy'), findsOneWidget);
    });

    testWidgets('no Nudgy button when no coach is wired in', (tester) async {
      await pumpModule(tester, initialTabIndex: 1);

      expect(find.byTooltip('Ask Nudgy'), findsNothing);
    });
  });
}
