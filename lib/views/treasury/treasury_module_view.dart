import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/budget/budget_view.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';
import 'package:intermittent_fasting/views/treasury/grocery/grocery_cart_view.dart';
import 'package:intermittent_fasting/views/treasury/history/treasury_history_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

class TreasuryModuleView extends StatefulWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;
  final BillsReceivablesPresenter billsPresenter;
  final BudgetPresenter budgetPresenter;
  final TreasuryHistoryPresenter historyPresenter;
  final InstallmentPresenter installmentPresenter;
  final GroceryCartPresenter groceryCartPresenter;

  const TreasuryModuleView({
    super.key,
    required this.dashPresenter,
    required this.ledgerPresenter,
    required this.billsPresenter,
    required this.budgetPresenter,
    required this.historyPresenter,
    required this.installmentPresenter,
    required this.groceryCartPresenter,
  });

  @override
  State<TreasuryModuleView> createState() => _TreasuryModuleViewState();

  // Tab count — keep in sync with the TabBar/TabBarView below.
  static const int tabCount = 6;
}

class _TreasuryModuleViewState extends State<TreasuryModuleView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Indices of tabs that own their in-page header — keep in sync with the
  // TabBar order below.
  static const int _ledgerTabIndex = 1;
  static const int _billsTabIndex = 2;
  static const int _budgetTabIndex = 3;

  // The redesigned Ledger, Bills and Budget tabs render their own in-page
  // headers (Ledger's "Ledger" title; Bills' header + month·year picker;
  // Budget's "Budget" title + month dropdown), so the shared "TREASURY" app bar
  // is hidden while any is active (per the reference frame). Other tabs keep the
  // app bar until they get the same treatment.
  bool _appBarHidden = false;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: TreasuryModuleView.tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Toggle the app bar as soon as we cross into/out of a header-owning tab
    // (Ledger, Bills) — even mid-animation — so there's no flash of the shared
    // "TREASURY" bar over that tab's own in-page header.
    final index = _tabController.index;
    final hide = index == _ledgerTabIndex ||
        index == _billsTabIndex ||
        index == _budgetTabIndex;
    if (hide != _appBarHidden) setState(() => _appBarHidden = hide);

    if (_tabController.indexIsChanging) return;
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
          indicatorColor: colorScheme.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Ledger'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
            Tab(icon: Icon(Icons.pie_chart_outline), text: 'Budget'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
            Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Cart'),
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
          ),
          LedgerView(presenter: widget.ledgerPresenter),
          BillsReceivablesView(
            presenter: widget.billsPresenter,
            installmentPresenter: widget.installmentPresenter,
          ),
          BudgetView(presenter: widget.budgetPresenter),
          TreasuryHistoryView(presenter: widget.historyPresenter),
          GroceryCartView(presenter: widget.groceryCartPresenter),
        ],
      ),
    );
  }
}
