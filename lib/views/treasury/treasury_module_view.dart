import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/presenters/sync_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/budget/budget_view.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goals_savings_screen.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';
import 'package:intermittent_fasting/views/treasury/grocery/grocery_cart_view.dart';
import 'package:intermittent_fasting/views/treasury/history/treasury_history_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

/// An extra tab appended after the seven built-in Treasury tabs.
///
/// Exists for the narrow-web surface: below the desktop breakpoint the browser
/// renders this module instead of the sidebar shell, and the sidebar is where
/// sign-out, the theme toggle and the advisor live. Without a slot here, a
/// mobile-web user had no way to reach any of them. Mobile passes none.
class TreasuryModuleTab {
  final IconData icon;
  final String label;
  final Widget page;

  /// True when [page] renders its own header, so the shared "TREASURY" app bar
  /// is hidden while it is active (matching the built-in tabs that do).
  final bool ownsHeader;

  const TreasuryModuleTab({
    required this.icon,
    required this.label,
    required this.page,
    this.ownsHeader = false,
  });
}

class TreasuryModuleView extends StatefulWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;
  final BillsReceivablesPresenter billsPresenter;
  final BudgetPresenter budgetPresenter;
  final TreasuryHistoryPresenter historyPresenter;
  final InstallmentPresenter installmentPresenter;
  final GroceryCartPresenter groceryCartPresenter;

  /// Nutrition presenter, when available — lets the ledger's photo-log button
  /// offer meal logging alongside receipt scanning. Null on finance-only
  /// surfaces (e.g. the web treasury app).
  final NutritionPresenter? nutritionPresenter;

  /// Drives the dashboard's sync pill. Null when signed out or no sync stack is
  /// running — the pill reports that rather than claiming "Synced".
  final SyncPresenter? syncPresenter;

  /// Extra tabs appended after the built-in seven. See [TreasuryModuleTab].
  final List<TreasuryModuleTab> extraTabs;

  /// Tab to open on first build. Lets the web shell hand over the destination
  /// the user was already on when the window crossed the desktop breakpoint,
  /// instead of dumping them back on Dashboard.
  final int initialTabIndex;

  /// Fired whenever the active tab settles, so an enclosing shell can mirror
  /// the position.
  final ValueChanged<int>? onTabChanged;

  const TreasuryModuleView({
    super.key,
    required this.dashPresenter,
    required this.ledgerPresenter,
    required this.billsPresenter,
    required this.budgetPresenter,
    required this.historyPresenter,
    required this.installmentPresenter,
    required this.groceryCartPresenter,
    this.nutritionPresenter,
    this.syncPresenter,
    this.extraTabs = const [],
    this.initialTabIndex = 0,
    this.onTabChanged,
  });

  @override
  State<TreasuryModuleView> createState() => _TreasuryModuleViewState();

  // Built-in tab count — keep in sync with the TabBar/TabBarView below.
  // [extraTabs] are appended on top of these.
  static const int tabCount = 7;
}

class _TreasuryModuleViewState extends State<TreasuryModuleView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Indices of tabs that own their in-page header — keep in sync with the
  // TabBar order below.
  static const int _ledgerTabIndex = 1;
  static const int _billsTabIndex = 2;
  static const int _budgetTabIndex = 3;
  static const int _historyTabIndex = 4;
  // Goals & Savings supplies its own in-page header (AppBar "Goals & Savings").
  static const int _goalsTabIndex = 6;

  // The redesigned Ledger, Bills and Budget tabs render their own in-page
  // headers (Ledger's "Ledger" title; Bills' header + month·year picker;
  // Budget's "Budget" title + month dropdown), so the shared "TREASURY" app bar
  // is hidden while any is active (per the reference frame). Other tabs keep the
  // app bar until they get the same treatment.
  bool _appBarHidden = false;

  int get _tabCount => TreasuryModuleView.tabCount + widget.extraTabs.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabCount - 1),
    );
    _tabController.addListener(_onTabChanged);
    _appBarHidden = _hidesAppBar(_tabController.index);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  bool _hidesAppBar(int index) {
    if (index >= TreasuryModuleView.tabCount) {
      return widget.extraTabs[index - TreasuryModuleView.tabCount].ownsHeader;
    }
    return index == _ledgerTabIndex ||
        index == _billsTabIndex ||
        index == _budgetTabIndex ||
        index == _historyTabIndex ||
        index == _goalsTabIndex;
  }

  void _onTabChanged() {
    // Toggle the app bar as soon as we cross into/out of a header-owning tab
    // (Ledger, Bills) — even mid-animation — so there's no flash of the shared
    // "TREASURY" bar over that tab's own in-page header.
    final index = _tabController.index;
    final hide = _hidesAppBar(index);
    if (hide != _appBarHidden) setState(() => _appBarHidden = hide);

    if (_tabController.indexIsChanging) return;
    widget.onTabChanged?.call(index);
    // Each tab keeps its own presenter cache. Reload on focus so cross-tab
    // mutations (e.g. mark-paid in Bills, transfer in Ledger) show up without
    // an app restart.
    switch (_tabController.index) {
      case 0:
        widget.dashPresenter.load();
        break;
      case 1:
        widget.ledgerPresenter.load();
        break;
      case 2:
        widget.billsPresenter.load();
        break;
      case 3:
        widget.budgetPresenter.load();
        break;
      case 4:
        widget.historyPresenter.load();
        break;
      case 5:
        widget.groceryCartPresenter.load();
        break;
      case 6:
        // Goals & Savings figures come from the dashboard presenter.
        widget.dashPresenter.load();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // Hidden on the Ledger and Bills tabs, which supply their own in-page
      // headers ("Ledger" title / "Bills" header + month·year picker).
      appBar: _appBarHidden
          ? null
          : AppBar(
              backgroundColor: theme.scaffoldBackgroundColor,
              title: Text(
                'TREASURY',
                style: theme.textTheme.titleSmall?.copyWith(
                  letterSpacing: 2.0,
                ),
              ),
              centerTitle: true,
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: _tabCount > TreasuryModuleView.tabCount,
          tabAlignment: _tabCount > TreasuryModuleView.tabCount
              ? TabAlignment.center
              : null,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: [
            const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            const Tab(icon: Icon(Icons.list_alt_outlined), text: 'Ledger'),
            const Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
            const Tab(icon: Icon(Icons.pie_chart_outline), text: 'Budget'),
            const Tab(icon: Icon(Icons.history_outlined), text: 'History'),
            const Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Cart'),
            const Tab(icon: Icon(Icons.savings_outlined), text: 'Goals'),
            for (final tab in widget.extraTabs)
              Tab(icon: Icon(tab.icon), text: tab.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          TreasuryDashboardView(
            presenter: widget.dashPresenter,
            billsPresenter: widget.billsPresenter,
            syncPresenter: widget.syncPresenter,
          ),
          LedgerView(
            presenter: widget.ledgerPresenter,
            nutrition: widget.nutritionPresenter,
          ),
          BillsReceivablesView(
            presenter: widget.billsPresenter,
            installmentPresenter: widget.installmentPresenter,
          ),
          BudgetView(presenter: widget.budgetPresenter),
          TreasuryHistoryView(presenter: widget.historyPresenter),
          GroceryCartView(presenter: widget.groceryCartPresenter),
          GoalsSavingsScreen(presenter: widget.dashPresenter),
          for (final tab in widget.extraTabs) tab.page,
        ],
      ),
    );
  }
}
