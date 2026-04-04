import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/account_card_widget.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/budget_overview_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/cash_summary_banner.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goal_progress_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/category_pie_chart_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/metric_cards_grid.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/spending_analytics_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/upcoming_bills_card.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';

class TreasuryDashboardView extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const TreasuryDashboardView({super.key, required this.presenter});

  void _showAccountSheet(BuildContext context, [FinancialAccount? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AccountSetupView(presenter: presenter, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          body: _DashboardScrollBody(
            presenter: presenter,
            onAddAccount: () => _showAccountSheet(context),
            onEditAccount: (account) => _showAccountSheet(context, account),
          ),
          floatingActionButton: _AddAccountFab(
            onTap: () => _showAccountSheet(context),
          ),
        );
      },
    );
  }
}

class _AddAccountFab extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.background,
      icon: const Icon(Icons.add),
      label: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _DashboardScrollBody extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final VoidCallback onAddAccount;
  final ValueChanged<FinancialAccount> onEditAccount;

  const _DashboardScrollBody({
    required this.presenter,
    required this.onAddAccount,
    required this.onEditAccount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CashSummaryBanner(presenter: presenter),
          const SizedBox(height: 8),
          MetricCardsGrid(presenter: presenter),
          const SizedBox(height: 16),
          if (!presenter.hasAccounts)
            _EmptyAccountsCard(onAddAccount: onAddAccount)
          else ...[
            _SectionHeader(label: 'ACCOUNTS'),
            const SizedBox(height: 8),
            _LiquidAccountsRow(presenter: presenter, onEdit: onEditAccount),
          ],
          const SizedBox(height: 16),
          SpendingAnalyticsCard(presenter: presenter),
          const SizedBox(height: 16),
          if (presenter.hasCategorySpend) ...[
            CategoryPieChartCard(presenter: presenter),
            const SizedBox(height: 16),
          ],
          if (presenter.hasBills) ...[
            UpcomingBillsCard(presenter: presenter),
            const SizedBox(height: 16),
          ],
          if (presenter.hasBudget) ...[
            BudgetOverviewCard(presenter: presenter),
            const SizedBox(height: 16),
          ],
          if (presenter.goalAccounts.isNotEmpty || presenter.savingsAccounts.isNotEmpty)
            _GoalSection(presenter: presenter, onEdit: onEditAccount),
          if (presenter.goalAccounts.isNotEmpty || presenter.savingsAccounts.isNotEmpty)
            const SizedBox(height: 16),
          if (presenter.liabilityAccounts.isNotEmpty)
            _LiabilitiesCard(presenter: presenter, onEdit: onEditAccount),
          if (presenter.custodianAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _HeldFundsCard(presenter: presenter, onEdit: onEditAccount),
          ],
        ],
      ),
    );
  }
}

class _EmptyAccountsCard extends StatelessWidget {
  final VoidCallback onAddAccount;

  const _EmptyAccountsCard({required this.onAddAccount});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary, size: 48),
            const SizedBox(height: 12),
            Text(
              'No accounts yet',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Add your first account to get started',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: onAddAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidAccountsRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _LiquidAccountsRow({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final accounts = presenter.liquidAccounts;
    final held = presenter.heldAmountByAccountId;
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        itemBuilder: (context, index) {
          return AccountCardWidget(
            account: accounts[index],
            heldAmount: held[accounts[index].id] ?? 0.0,
            onTap: () { HapticFeedback.selectionClick(); onEdit(accounts[index]); },
          );
        },
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _GoalSection({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final goals = [...presenter.goalAccounts, ...presenter.savingsAccounts];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'GOALS & SAVINGS'),
        const SizedBox(height: 8),
        Card(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              for (int i = 0; i < goals.length; i++) ...[
                GoalProgressCard(
                  account: goals[i],
                  onTap: () { HapticFeedback.selectionClick(); onEdit(goals[i]); },
                ),
                if (i < goals.length - 1)
                  Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.textSecondary.withOpacity(0.1)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LiabilitiesCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _LiabilitiesCard({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final liabilities = presenter.liabilityAccounts;

    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.credit_card_outlined, color: AppColors.danger),
        title: const Text('LIABILITIES', style: TextStyle(letterSpacing: 1.0, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          formatPeso(presenter.totalLiabilities),
          style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
        ),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textSecondary,
        children: [
          for (final account in liabilities)
            _LiabilityListTile(account: account, onTap: () { HapticFeedback.selectionClick(); onEdit(account); }),
        ],
      ),
    );
  }
}

class _LiabilityListTile extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback onTap;

  const _LiabilityListTile({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(account.name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatPeso(account.balance),
            style: GoogleFonts.jetBrainsMono(
              textStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 16),
        ],
      ),
    );
  }
}

class _HeldFundsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _HeldFundsCard({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final accounts = presenter.custodianAccounts;
    final total = accounts.fold(0.0, (sum, a) => sum + a.balance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'EXTERNAL'),
        const SizedBox(height: 8),
        Card(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: AppColors.textSecondary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Not included in net worth',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      formatPeso(total),
                      style: GoogleFonts.jetBrainsMono(
                        textStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
              for (int i = 0; i < accounts.length; i++) ...[
                ListTile(
                  onTap: () { HapticFeedback.selectionClick(); onEdit(accounts[i]); },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  title: Text(accounts[i].name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatPeso(accounts[i].balance),
                        style: GoogleFonts.jetBrainsMono(
                          textStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 16),
                    ],
                  ),
                ),
                if (i < accounts.length - 1)
                  Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.textSecondary.withOpacity(0.1)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
