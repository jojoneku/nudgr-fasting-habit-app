import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/treasury_module_view.dart';

import '../../mocks.mocks.dart';

/// The Treasury module's tab surface.
///
/// Two things are pinned here. First, an enclosing shell can append its own tab
/// and open on a chosen index — that's how the web build stops losing your
/// place (and your only way to sign out) when the window crosses the desktop
/// breakpoint. Second, the seven built-in tabs are all still present.
void main() {
  MockStorageService buildStorage() {
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
    when(s.loadMonthlySummaries()).thenAnswer((_) async => []);
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

  Future<void> pumpModule(
    WidgetTester tester, {
    List<TreasuryModuleTab> extraTabs = const [],
    int initialTabIndex = 0,
    ValueChanged<int>? onTabChanged,
  }) async {
    final storage = buildStorage();
    final stats = MockStatsPresenter();
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());

    final ledger = LedgerPresenter(storage, stats);
    final dash = TreasuryDashboardPresenter(storage, ledger);
    final budget = BudgetPresenter(storage, stats, ledger);
    final bills = BillsReceivablesPresenter(storage, ledger, stats,
        dashboard: dash, budget: budget);
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
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();

    expect(seen, contains(3));
  });
}
