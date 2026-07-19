import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/goal_progress_card.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Dedicated Goals & Savings screen (`Nutrition Focus Treasury.dc.html`,
/// Frame 12): a TOTAL SAVED hero, the active goals (progress cards) and plain
/// savings accounts, with an add-goal FAB. Pushed from the Dashboard's goals
/// section. All figures come from [TreasuryDashboardPresenter].
class GoalsSavingsScreen extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;
  final ValueChanged<FinancialAccount> onEdit;
  final VoidCallback onAdd;

  const GoalsSavingsScreen({
    super.key,
    required this.presenter,
    required this.onEdit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) {
        // Goals (with a target) and savings holding a target render as progress
        // cards; plain savings (no target) render as simple balance rows.
        final activeGoals = [
          ...presenter.goalAccounts,
          ...presenter.savingsAccounts.where((a) => (a.goalTarget ?? 0) > 0),
        ];
        final plainSavings = presenter.savingsAccounts
            .where((a) => (a.goalTarget ?? 0) <= 0)
            .toList();

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            title: const Text('Goals & Savings'),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: onAdd,
            backgroundColor: context.appColors.success,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Goal',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _TotalSavedHero(total: presenter.totalSavingsAndGoals),
              const SizedBox(height: 20),
              if (activeGoals.isEmpty && plainSavings.isEmpty)
                const AppCard(
                  variant: AppCardVariant.elevated,
                  child: AppEmptyState(
                    icon: Icons.savings_outlined,
                    title: 'No goals or savings yet',
                    body: 'Add a savings account or goal to track progress',
                  ),
                ),
              if (activeGoals.isNotEmpty)
                AppSection(
                  title: 'Active goals',
                  child: AppCard(
                    variant: AppCardVariant.elevated,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < activeGoals.length; i++) ...[
                          GoalProgressCard(
                            account: activeGoals[i],
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onEdit(activeGoals[i]);
                            },
                          ),
                          if (i < activeGoals.length - 1)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (plainSavings.isNotEmpty) ...[
                const SizedBox(height: 4),
                AppSection(
                  title: 'Savings accounts',
                  child: Column(
                    children: [
                      for (final a in plainSavings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _SavingsRow(
                            account: a,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onEdit(a);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TotalSavedHero extends StatelessWidget {
  final double total;
  const _TotalSavedHero({required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final green = context.appColors.success;

    Color blend(double a) =>
        Color.alphaBlend(green.withValues(alpha: a), cs.surface);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [blend(0.22), blend(0.10), cs.surface],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          Icon(Icons.savings_rounded, size: 30, color: green),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL SAVED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: green,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatPeso(total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavingsRow extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback onTap;

  const _SavingsRow({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AccountBadge.of(account, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              account.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          AppNumberDisplay(
            value: formatPeso(account.balance),
            size: AppNumberSize.body,
            color: cs.onSurface,
          ),
        ],
      ),
    );
  }
}
