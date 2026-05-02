import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class TreasuryDashboardView extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const TreasuryDashboardView({super.key, required this.presenter});

  void _showAccountSheet(BuildContext context, [FinancialAccount? existing]) {
    AppBottomSheet.show(
      context: context,
      title: existing == null ? 'Add Account' : 'Edit Account',
      body: AccountSetupView(presenter: presenter, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        if (presenter.isLoading) {
          return Center(
            child: CircularProgressIndicator(color: colorScheme.primary),
          );
        }
        return Scaffold(
          backgroundColor: colorScheme.surface,
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
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      icon: const Icon(Icons.add),
      label: const Text('Add Account',
          style: TextStyle(fontWeight: FontWeight.w600)),
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
            AppSection(
              title: 'Accounts',
              child: _LiquidAccountsRow(
                presenter: presenter,
                onEdit: onEditAccount,
              ),
            ),
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
          if (presenter.goalAccounts.isNotEmpty ||
              presenter.savingsAccounts.isNotEmpty)
            _GoalSection(presenter: presenter, onEdit: onEditAccount),
          if (presenter.goalAccounts.isNotEmpty ||
              presenter.savingsAccounts.isNotEmpty)
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
    return AppCard(
      variant: AppCardVariant.elevated,
      child: AppEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No accounts yet',
        body: 'Add your first account to get started',
        actionLabel: 'Add Account',
        onAction: onAddAccount,
        iconSize: 48,
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        mainAxisExtent: 90,
      ),
      itemCount: accounts.length,
      itemBuilder: (context, index) {
        return AccountCardWidget(
          account: accounts[index],
          heldAmount: held[accounts[index].id] ?? 0.0,
          onTap: () {
            HapticFeedback.selectionClick();
            onEdit(accounts[index]);
          },
        );
      },
    );
  }
}

class _GoalSection extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _GoalSection({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goals = [...presenter.goalAccounts, ...presenter.savingsAccounts];

    return AppSection(
      title: 'Goals & Savings',
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < goals.length; i++) ...[
              GoalProgressCard(
                account: goals[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  onEdit(goals[i]);
                },
              ),
              if (i < goals.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiabilitiesCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  const _LiabilitiesCard({required this.presenter, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final liabilities = presenter.liabilityAccounts;

    return AppCard(
      variant: AppCardVariant.elevated,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        leading:
            AppIconBadge(icon: Icons.credit_card_outlined, color: colorScheme.error),
        title: Text(
          'LIABILITIES',
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 1.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: AppNumberDisplay(
          value: formatPeso(presenter.totalLiabilities),
          size: AppNumberSize.body,
          color: colorScheme.error,
        ),
        iconColor: colorScheme.onSurfaceVariant,
        collapsedIconColor: colorScheme.onSurfaceVariant,
        children: [
          for (final account in liabilities)
            _LiabilityListTile(
              account: account,
              onTap: () {
                HapticFeedback.selectionClick();
                onEdit(account);
              },
            ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppListTile(
      onTap: onTap,
      title: Text(
        account.name,
        style: theme.textTheme.bodyMedium,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppNumberDisplay(
            value: formatPeso(account.balance),
            size: AppNumberSize.body,
            color: colorScheme.error,
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant, size: 16),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accounts = presenter.custodianAccounts;
    final total = accounts.fold(0.0, (sum, a) => sum + a.balance);

    return AppSection(
      title: 'External',
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      color: colorScheme.onSurfaceVariant, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Not included in net worth',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  AppNumberDisplay(
                    value: formatPeso(total),
                    size: AppNumberSize.body,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            for (int i = 0; i < accounts.length; i++) ...[
              AppListTile(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onEdit(accounts[i]);
                },
                title: Text(
                  accounts[i].name,
                  style: theme.textTheme.bodyMedium,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppNumberDisplay(
                      value: formatPeso(accounts[i].balance),
                      size: AppNumberSize.body,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant, size: 16),
                  ],
                ),
              ),
              if (i < accounts.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
