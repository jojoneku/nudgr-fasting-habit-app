import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/treasury_dashboard_view.dart';
import 'package:intermittent_fasting/views/treasury/ledger/ledger_view.dart';

class TreasuryModuleView extends StatefulWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;

  const TreasuryModuleView({
    super.key,
    required this.dashPresenter,
    required this.ledgerPresenter,
  });

  @override
  State<TreasuryModuleView> createState() => _TreasuryModuleViewState();
}

class _TreasuryModuleViewState extends State<TreasuryModuleView> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text(
            'TREASURY',
            style: TextStyle(letterSpacing: 2.0, fontSize: 14),
          ),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'Ledger'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
              Tab(icon: Icon(Icons.history_outlined), text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TreasuryDashboardView(presenter: widget.dashPresenter),
            LedgerView(presenter: widget.ledgerPresenter),
            const _PlaceholderTab(label: 'Bills & Budget'),
            const _PlaceholderTab(label: 'History'),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String label;

  const _PlaceholderTab({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_outlined, color: AppColors.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(
            'Coming Soon',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
