import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/budget_overview_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/cashflow_strip.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/dashboard_accounts_list.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goal_progress_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goals_savings_screen.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/category_pie_chart_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/metric_cards_grid.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/net_worth_hero.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/spending_analytics_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/upcoming_bills_card.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_setup_view.dart';
import 'package:intermittent_fasting/views/treasury/shared/quick_pay_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class TreasuryDashboardView extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// Optional — supplied by the Treasury module so the Credit section (now the
  /// single home for credit cards) can offer a quick Pay action. Null-safe: the
  /// dashboard still builds standalone (e.g. in tests) without a Pay button.
  final BillsReceivablesPresenter? billsPresenter;

  const TreasuryDashboardView({
    super.key,
    required this.presenter,
    this.billsPresenter,
  });

  void _showQuickPay(BuildContext context, FinancialAccount card) {
    final bills = billsPresenter;
    if (bills == null) return;
    showQuickPaySheet(context, card: card, presenter: bills);
  }

  void _showAccountSheet(BuildContext context, [FinancialAccount? existing]) {
    AppBottomSheet.show(
      context: context,
      title: existing == null ? 'Add Account' : 'Edit Account',
      body: AccountSetupView(presenter: presenter, existing: existing),
    );
  }

  void _showGoalSavingsSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Add Goal or Savings',
      body: AccountSetupView(
        presenter: presenter,
        initialCategory: AccountCategory.savings,
      ),
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
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _DashboardScrollBody(
            presenter: presenter,
            onAddAccount: () => _showAccountSheet(context),
            onEditAccount: (account) => _showAccountSheet(context, account),
            onAddGoalSavings: () => _showGoalSavingsSheet(context),
            onPayCredit: billsPresenter == null
                ? null
                : (card) => _showQuickPay(context, card),
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
      label: const Text(
        'Add Account',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DashboardScrollBody extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final VoidCallback onAddAccount;
  final ValueChanged<FinancialAccount> onEditAccount;
  final VoidCallback onAddGoalSavings;

  /// Null when no bills presenter is wired (no quick-pay available).
  final ValueChanged<FinancialAccount>? onPayCredit;

  const _DashboardScrollBody({
    required this.presenter,
    required this.onAddAccount,
    required this.onEditAccount,
    required this.onAddGoalSavings,
    this.onPayCredit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GreetingHeader(),
          const SizedBox(height: 14),
          NetWorthHero(presenter: presenter),
          const SizedBox(height: 12),
          CashflowStrip(presenter: presenter),
          const SizedBox(height: 16),
          if (!presenter.hasAccounts)
            _EmptyAccountsCard(onAddAccount: onAddAccount)
          else
            DashboardAccountsList(
              accounts: presenter.liquidAccounts,
              heldByAccountId: presenter.heldAmountByAccountId,
              totalLiquidCash: presenter.totalLiquidCash,
              onEdit: onEditAccount,
            ),
          // Credit cards live here, directly under Accounts — a card balance is
          // an account, not a monthly bill (moved off the Bills tab).
          if (presenter.creditAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _CreditSection(
              presenter: presenter,
              onEdit: onEditAccount,
              onPay: onPayCredit,
            ),
          ],
          const SizedBox(height: 16),
          // Retained from the pre-redesign dashboard: exact month figures plus
          // Ending Cash / Forecast, which the hero + strip summarize but don't
          // enumerate. Kept per the "don't drop existing features" rule.
          MetricCardsGrid(presenter: presenter),
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
          _GoalSection(
            presenter: presenter,
            onEdit: onEditAccount,
            onAdd: onAddGoalSavings,
          ),
          const SizedBox(height: 16),
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

/// Greeting line + "Synced" status pill at the top of the dashboard body.
/// The "Treasury" title itself is provided by the module app bar. The pill is a
/// static status indicator for this increment (live sync state is wired later).
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            _greeting(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const _SyncedPill(),
      ],
    );
  }
}

/// Time-of-day greeting (pure presentation).
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

class _SyncedPill extends StatelessWidget {
  const _SyncedPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = context.appColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'Synced',
            style: theme.textTheme.labelSmall?.copyWith(
              color: green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;
  final VoidCallback onAdd;

  const _GoalSection({
    required this.presenter,
    required this.onEdit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final goals = [...presenter.goalAccounts, ...presenter.savingsAccounts];

    return AppSection(
      title: 'Goals & Savings',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GoalsSavingsScreen(
                    presenter: presenter,
                    onEdit: onEdit,
                    onAdd: onAdd,
                  ),
                ),
              );
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('See all'),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 20, color: colorScheme.primary),
            tooltip: 'Add Goal or Savings',
            onPressed: onAdd,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      child: goals.isEmpty
          ? AppCard(
              variant: AppCardVariant.elevated,
              child: AppEmptyState(
                icon: Icons.savings_outlined,
                title: 'No goals or savings yet',
                body:
                    'Add a savings account or financial goal to track progress',
                actionLabel: 'Add Goal / Savings',
                onAction: onAdd,
                iconSize: 40,
              ),
            )
          : AppCard(
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
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Dedicated Credit section — one row card per credit account showing the
/// current payable, a remaining-credit utilization meter, and the due date.
class _CreditSection extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;

  /// Quick-pay a card; null when no bills presenter is wired.
  final ValueChanged<FinancialAccount>? onPay;

  const _CreditSection({
    required this.presenter,
    required this.onEdit,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accounts = presenter.creditAccounts;

    return AppSection(
      title: 'Credit',
      trailing: Text(
        'Owe ${formatPeso(presenter.totalCreditOwed)}',
        style: theme.textTheme.labelMedium?.copyWith(color: colorScheme.error),
      ),
      child: Column(
        children: [
          for (int i = 0; i < accounts.length; i++) ...[
            _CreditAccountCard(
              account: accounts[i],
              dueInfo: presenter.creditDueInfo(accounts[i]),
              minimumDue: presenter.creditMinimumDue(accounts[i]),
              onTap: () {
                HapticFeedback.selectionClick();
                onEdit(accounts[i]);
              },
              onPay: onPay,
            ),
            if (i < accounts.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CreditAccountCard extends StatelessWidget {
  final FinancialAccount account;
  final ({String label, bool imminent})? dueInfo;
  final double? minimumDue;
  final VoidCallback onTap;
  final ValueChanged<FinancialAccount>? onPay;

  const _CreditAccountCard({
    required this.account,
    required this.dueInfo,
    required this.minimumDue,
    required this.onTap,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final utilization = account.utilization;
    final available = account.availableCredit;

    return AppCard(
      variant: AppCardVariant.outlined,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card_outlined, color: cs.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.name,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Owe',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  AppNumberDisplay(
                    value: formatPeso(account.currentPayable),
                    size: AppNumberSize.body,
                    color: cs.error,
                  ),
                ],
              ),
            ],
          ),
          if (utilization != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: utilization.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: utilization >= 0.9 ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPeso(available ?? 0)} of ${formatPeso(account.creditLimit ?? 0)} available',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (dueInfo != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 14,
                  color: dueInfo!.imminent ? cs.error : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  minimumDue != null
                      ? '${dueInfo!.label} · min ${formatPeso(minimumDue!)}'
                      : dueInfo!.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: dueInfo!.imminent ? cs.error : cs.onSurfaceVariant,
                    fontWeight:
                        dueInfo!.imminent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
          if (onPay != null && account.currentPayable > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => onPay!(account),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary.withValues(alpha: 0.14),
                  foregroundColor: cs.primary,
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Pay',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
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
                  Icon(
                    Icons.swap_horiz_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 16,
                  ),
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
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant,
                      size: 16,
                    ),
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
