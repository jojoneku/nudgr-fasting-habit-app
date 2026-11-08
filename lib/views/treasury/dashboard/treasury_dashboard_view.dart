import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/sync_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/budget_overview_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/cashflow_strip.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/dashboard_accounts_list.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goal_progress_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goals_savings_screen.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/category_pie_chart_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/month_end_outlook_card.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/next_month_forecast_card.dart';
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

  /// Drives the header's sync pill. Null when no sync stack is wired (signed
  /// out, or a standalone/test mount) — the pill then says so instead of
  /// claiming everything is synced.
  final SyncPresenter? syncPresenter;

  /// Switches the module to the Budget tab, for the Budget card's
  /// "Open budget" link. Null hides the link.
  final VoidCallback? onOpenBudget;

  const TreasuryDashboardView({
    super.key,
    required this.presenter,
    this.billsPresenter,
    this.syncPresenter,
    this.onOpenBudget,
  });

  void _showQuickPay(BuildContext context, FinancialAccount card) {
    final bills = billsPresenter;
    if (bills == null) return;
    showQuickPaySheet(context, card: card, presenter: bills);
  }

  void _showAccountSheet(BuildContext context, [FinancialAccount? existing]) {
    AppBottomSheet.show(
      context: context,
      title: existing == null ? 'Add account' : 'Edit account',
      body: AccountSetupView(presenter: presenter, existing: existing),
    );
  }

  void _showGoalSavingsSheet(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: 'Add goal or savings',
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
        // A brand-new Treasury (no accounts, nothing logged this month): one
        // empty state with one "Add your first account" action, and nothing
        // else — every other card would read ₱0.00. Archived-only accounts,
        // or bills / budgets / transactions this month, keep the dashboard.
        if (presenter.showsOnlyEmptyState) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: _DashboardEmptyBody(
              syncPresenter: syncPresenter,
              onAddAccount: () => _showAccountSheet(context),
            ),
          );
        }
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _DashboardScrollBody(
            presenter: presenter,
            syncPresenter: syncPresenter,
            onEditAccount: (account) => _showAccountSheet(context, account),
            onAddAccount: () => _showAccountSheet(context),
            onAddGoalSavings: () => _showGoalSavingsSheet(context),
            onPayCredit: billsPresenter == null
                ? null
                : (card) => _showQuickPay(context, card),
            onOpenBudget: onOpenBudget,
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
        'Add account',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The dashboard with no accounts: the greeting, then one empty state. The
/// hero, cash flow strip, outlook, forecast and spending cards stay hidden
/// until there is an account for them to describe.
class _DashboardEmptyBody extends StatelessWidget {
  final SyncPresenter? syncPresenter;
  final VoidCallback onAddAccount;

  const _DashboardEmptyBody({
    required this.onAddAccount,
    this.syncPresenter,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GreetingHeader(syncPresenter: syncPresenter),
          const SizedBox(height: 14),
          AppCard(
            key: const ValueKey('dashboard.emptyState'),
            variant: AppCardVariant.elevated,
            child: AppEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              body: 'Add a bank, e-wallet or cash account to see your net '
                  'worth, cash flow and month-end outlook.',
              actionLabel: 'Add your first account',
              onAction: onAddAccount,
              iconSize: 48,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardScrollBody extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final SyncPresenter? syncPresenter;
  final ValueChanged<FinancialAccount> onEditAccount;
  final VoidCallback onAddAccount;
  final VoidCallback onAddGoalSavings;

  /// Null when no bills presenter is wired (no quick-pay available).
  final ValueChanged<FinancialAccount>? onPayCredit;

  /// Null hides the Budget card's "Open budget" link.
  final VoidCallback? onOpenBudget;

  const _DashboardScrollBody({
    required this.presenter,
    required this.onEditAccount,
    required this.onAddAccount,
    required this.onAddGoalSavings,
    this.syncPresenter,
    this.onPayCredit,
    this.onOpenBudget,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GreetingHeader(syncPresenter: syncPresenter),
          const SizedBox(height: 14),
          NetWorthHero(presenter: presenter),
          const SizedBox(height: 12),
          CashflowStrip(presenter: presenter),
          const SizedBox(height: 16),
          // No active account (every one archived, or none left while bills
          // and budgets remain): an empty card holds the Accounts slot.
          if (!presenter.hasAccounts)
            _EmptyAccountsCard(
              title: presenter.accountsEmptyTitle,
              body: presenter.accountsEmptyBody,
              onAddAccount: onAddAccount,
            )
          else
            DashboardAccountsList(
              accounts: presenter.liquidAccounts,
              sublineByAccountId: presenter.dashboardAccountSublines,
              overdrawnAccountIds: presenter.overdrawnAccountIds,
              yoursByAccountId: presenter.yoursByAccountId,
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
          // Every term of the month-end projection, as a signed statement.
          // The only place (with Next Month's "Starts at") that shows it.
          MonthEndOutlookCard(presenter: presenter),
          const SizedBox(height: 16),
          // Directly under the outlook, so this month's end and next month's
          // read as a pair.
          NextMonthForecastCard(presenter: presenter),
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
            BudgetOverviewCard(
              presenter: presenter,
              onOpenBudget: onOpenBudget,
            ),
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

/// The Accounts slot when no account is active: "No accounts yet", or
/// "No active accounts" when every account is archived, with an Add action.
class _EmptyAccountsCard extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback onAddAccount;

  const _EmptyAccountsCard({
    required this.title,
    required this.body,
    required this.onAddAccount,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('dashboard.accounts.empty'),
      variant: AppCardVariant.elevated,
      child: AppEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: title,
        body: body,
        actionLabel: 'Add account',
        onAction: onAddAccount,
        iconSize: 48,
      ),
    );
  }
}

/// Greeting line + sync status pill at the top of the dashboard body.
/// The "Treasury" title itself is provided by the module app bar.
class _GreetingHeader extends StatelessWidget {
  final SyncPresenter? syncPresenter;

  const _GreetingHeader({this.syncPresenter});

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
        _SyncedPill(presenter: syncPresenter),
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

/// Live sync status.
///
/// This used to be a hardcoded green "Synced" badge — it read the same offline,
/// with a queue of unpushed changes, or signed out. On a finance screen that is
/// the worst possible thing to be wrong about, so it now reports what
/// [SyncPresenter] actually knows, and tapping it forces a sync.
class _SyncedPill extends StatelessWidget {
  final SyncPresenter? presenter;

  const _SyncedPill({this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    if (p == null) {
      // No sync stack wired (signed out, or a standalone mount). Say that
      // rather than implying the data is safely in the cloud.
      return _pill(
        context,
        label: 'Local only',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final (Color color, bool spinning) = switch (p) {
          _ when p.syncError != null => (cs.error, false),
          _ when p.isSyncing => (cs.primary, true),
          _ when p.pendingCount > 0 => (context.appColors.orange, false),
          _ => (context.appColors.success, false),
        };
        return _pill(
          context,
          label: p.syncError != null ? 'Sync failed' : p.statusLabel,
          color: color,
          spinning: spinning,
          onTap: p.isSyncing ? null : () => p.forceSync().catchError((_) {}),
        );
      },
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    required Color color,
    bool spinning = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinning)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Sync now',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: pill,
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
    final goals = presenter.goalAndSavingsAccounts;

    return AppSection(
      title: 'Goals & savings',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GoalsSavingsScreen(presenter: presenter),
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
            tooltip: 'Add goal or savings',
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
                actionLabel: 'Add goal or savings',
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
                      paletteIndex: i,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Under the title rather than beside it: "Owe ₱X · ₱Y available"
          // is too long to share a row with the title at 360 dp.
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              presenter.creditSummaryLabel,
              key: const ValueKey('dashboard.credit.summary'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (int i = 0; i < accounts.length; i++) ...[
            _CreditAccountCard(
              account: accounts[i],
              availableLabel: presenter.creditAvailableLabel(accounts[i]),
              nearLimit: presenter.creditNearLimit(accounts[i]),
              canPay: presenter.canPayCredit(accounts[i]),
              dueInfo: presenter.creditDueInfo(accounts[i]),
              cycleNote: presenter.creditCycleNote(accounts[i]),
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

  /// "₱A of ₱L available" under the utilization meter.
  final String availableLabel;

  /// True at 90% of the limit or more — the meter turns to the error tone.
  final bool nearLimit;

  /// False when nothing is owed: Pay stays visible but disabled.
  final bool canPay;

  /// The unpaid statement's due line, self-contained ("Due Nov 4 · min ₱850",
  /// "Due Nov 4 · ₱12,000 in full") or "No payment due". Rendered as-is.
  final ({String label, bool imminent})? dueInfo;

  /// Where this card sits in its statement cycle — "Statement closes Oct 20 ·
  /// due Nov 4" — or a warning that it has no billing cycle and so is never
  /// billed.
  final ({String label, bool warning})? cycleNote;
  final VoidCallback onTap;
  final ValueChanged<FinancialAccount>? onPay;

  const _CreditAccountCard({
    required this.account,
    required this.availableLabel,
    required this.nearLimit,
    required this.canPay,
    required this.dueInfo,
    required this.cycleNote,
    required this.onTap,
    this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final utilization = account.utilization;
    final pay = onPay;

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
                    value: formatPesoMinus(account.totalDebt),
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
                color: nearLimit ? cs.error : cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              availableLabel,
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
                Expanded(
                  child: Text(
                    dueInfo!.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: dueInfo!.imminent ? cs.error : cs.onSurfaceVariant,
                      fontWeight:
                          dueInfo!.imminent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (cycleNote != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  cycleNote!.warning
                      ? Icons.warning_amber_rounded
                      : Icons.hourglass_bottom,
                  size: 14,
                  color: cycleNote!.warning
                      ? context.appColors.orange
                      : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cycleNote!.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cycleNote!.warning
                          ? context.appColors.orange
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Pay stays visible when nothing is owed, but disabled — same as
          // web — so the card's layout does not jump when it is paid off.
          if (pay != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: ValueKey('dashboard.credit.pay.${account.id}'),
                onPressed: canPay ? () => pay(account) : null,
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
    final total = presenter.totalHeldForOthers;

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
