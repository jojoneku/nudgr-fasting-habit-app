import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/bills_receivables_view.dart';
import 'package:intermittent_fasting/views/treasury/budget/budget_view.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';
import 'package:intermittent_fasting/views/treasury/history/treasury_history_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

class TreasuryModuleView extends StatefulWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;
  final BillsReceivablesPresenter billsPresenter;
  final BudgetPresenter budgetPresenter;
  final TreasuryHistoryPresenter historyPresenter;
  final InstallmentPresenter installmentPresenter;

  const TreasuryModuleView({
    super.key,
    required this.dashPresenter,
    required this.ledgerPresenter,
    required this.billsPresenter,
    required this.budgetPresenter,
    required this.historyPresenter,
    required this.installmentPresenter,
  });

  @override
  State<TreasuryModuleView> createState() => _TreasuryModuleViewState();

  // Tab count — keep in sync with the TabBar/TabBarView below.
  static const int tabCount = 5;
}

class _TreasuryModuleViewState extends State<TreasuryModuleView> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: TreasuryModuleView.tabCount,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text(
            'TREASURY',
            style: TextStyle(letterSpacing: 2.0, fontSize: 14),
          ),
          centerTitle: true,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              top: BorderSide(color: AppColors.accent.withOpacity(0.18), width: 1),
            ),
          ),
          child: const TabBar(
            indicatorColor: AppColors.accent,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'Ledger'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
              Tab(icon: Icon(Icons.pie_chart_outline), text: 'Budget'),
              Tab(icon: Icon(Icons.history_outlined), text: 'History'),
            ],
          ),
        ),

        body: TabBarView(
          children: [
            TreasuryDashboardView(presenter: widget.dashPresenter),
            LedgerView(presenter: widget.ledgerPresenter),
            BillsReceivablesView(
              presenter: widget.billsPresenter,
              installmentPresenter: widget.installmentPresenter,
            ),
            BudgetView(presenter: widget.budgetPresenter),
            TreasuryHistoryView(presenter: widget.historyPresenter),
          ],
        ),
      ),
    );
  }
}
