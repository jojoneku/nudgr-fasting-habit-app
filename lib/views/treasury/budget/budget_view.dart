import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/budget/add_budget_sheet.dart';
import 'package:intermittent_fasting/views/treasury/budget/category_budget_tile.dart';
import 'package:intermittent_fasting/views/treasury/budget/manage_groups_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetView extends StatefulWidget {
  final BudgetPresenter presenter;

  const BudgetView({super.key, required this.presenter});

  @override
  State<BudgetView> createState() => _BudgetViewState();
}

class _BudgetViewState extends State<BudgetView> {
  @override
  void initState() {
    super.initState();
    widget.presenter.load();
  }

  void _showAddBudgetSheet([String? categoryId]) {
    AppBottomSheet.show(
      context: context,
      title:
          categoryId != null && widget.presenter.budgetFor(categoryId) != null
              ? 'Edit Budget'
              : 'Set Budget',
      body: AddBudgetSheet(
        presenter: widget.presenter,
        preselectedCategoryId: categoryId,
      ),
    );
  }

  void _showManageGroups() {
    AppBottomSheet.show(
      context: context,
      title: 'Manage Groups',
      body: ManageGroupsSheet(presenter: widget.presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final byGroup = widget.presenter.categoriesByGroup;
        final savings = widget.presenter.savingsBudgets;
        final hasAny =
            byGroup.values.any((list) => list.isNotEmpty) || savings.isNotEmpty;

        return Scaffold(
          body: Column(
            children: [
              _MonthSelector(
                presenter: widget.presenter,
                onManageGroups: _showManageGroups,
              ),
              if (hasAny)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    children: [
                      _BudgetPaceHero(presenter: widget.presenter),
                      if (widget.presenter.isCurrentMonth) ...[
                        const SizedBox(height: 10),
                        _SafeToSpendCallout(presenter: widget.presenter),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: hasAny
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        children: [
                          for (final group
                              in widget.presenter.expenseGroups) ...[
                            if ((byGroup[group.id] ?? const []).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _GroupSection(
                                  group: group,
                                  presenter: widget.presenter,
                                  categories: byGroup[group.id]!,
                                  onTapCategory: _showAddBudgetSheet,
                                ),
                              ),
                          ],
                          if (savings.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _SavingsSection(
                                presenter: widget.presenter,
                                rows: savings,
                                onTap: _showAddBudgetSheet,
                              ),
                            ),
                        ],
                      )
                    : AppEmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'No budgets yet',
                        body: 'Tap + to set spending limits',
                        actionLabel: 'Set Budget',
                        onAction: () => _showAddBudgetSheet(),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddBudgetSheet(),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

// ─── Month Selector ───────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  final BudgetPresenter presenter;
  final VoidCallback? onManageGroups;

  const _MonthSelector({required this.presenter, this.onManageGroups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    presenter.setMonth(previousMonth(presenter.selectedMonth)),
              ),
            ),
            Text(
              monthLabel(presenter.selectedMonth),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onManageGroups != null)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      icon: const Icon(Icons.category_outlined),
                      tooltip: 'Manage groups',
                      onPressed: onManageGroups,
                    ),
                  ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () =>
                        presenter.setMonth(nextMonth(presenter.selectedMonth)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pace Ring Hero ───────────────────────────────────────────────────────────

/// The pace-aware budget hero (`Nutrition Focus Treasury.dc.html`, Frame 4): a
/// spent-percentage ring beside the SPENT / of-allocated figures and an
/// "Ahead of pace" / "Over pace" pill. Conveys the old summary banner's
/// allocated + spent + remaining relationship in one glance.
class _BudgetPaceHero extends StatelessWidget {
  final BudgetPresenter presenter;

  const _BudgetPaceHero({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;
    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final pct = presenter.percentUsed;
    final over = spent > allocated && allocated > 0;
    final ringColor = over ? cs.error : appColors.fast;

    return AppCard(
      variant: AppCardVariant.elevated,
      child: Row(
        children: [
          AppRingProgress(
            value: pct.clamp(0.0, 1.0),
            size: 104,
            strokeWidth: 12,
            primaryColor: ringColor,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(pct * 100).round()}%',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'spent',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: appColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPENT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPeso(spent),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'of ${formatPeso(allocated)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: appColors.textMuted),
                ),
                if (presenter.isCurrentMonth) ...[
                  const SizedBox(height: 10),
                  _PacePill(ahead: presenter.isAheadOfPace, over: over),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PacePill extends StatelessWidget {
  final bool ahead;
  final bool over;

  const _PacePill({required this.ahead, required this.over});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final good = ahead && !over;
    final color = good ? context.appColors.success : cs.error;
    final label = over
        ? 'Over budget'
        : ahead
            ? 'Ahead of pace'
            : 'Over pace';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              good
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              size: 13,
              color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Blue-tinted "safe to spend / day" callout — remaining budget spread over the
/// days left this month. Shown only for the current month.
class _SafeToSpendCallout extends StatelessWidget {
  final BudgetPresenter presenter;

  const _SafeToSpendCallout({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blue = context.appColors.fast;
    final days = presenter.daysLeftInSelectedMonth;

    return Container(
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.07),
        border: Border.all(color: blue.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.savings_outlined, size: 20, color: blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safe to spend · ${days == 0 ? 'last day' : '$days days left'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: context.appColors.textMuted),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatPeso(presenter.safeToSpendPerDay),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: ' / day',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: context.appColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Group Section ────────────────────────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final BudgetGroupDef group;
  final BudgetPresenter presenter;
  final List categories;
  final ValueChanged<String> onTapCategory;

  const _GroupSection({
    required this.group,
    required this.presenter,
    required this.categories,
    required this.onTapCategory,
  });

  @override
  Widget build(BuildContext context) {
    final sectionAllocated = presenter.sectionAllocated(group.id);
    final sectionSpent = presenter.sectionSpent(group.id);

    return AppSection(
      title: group.name.toUpperCase(),
      hint:
          '${formatPesoCompact(sectionSpent)} / ${formatPesoCompact(sectionAllocated)}',
      child: AppCard(
        variant: AppCardVariant.outlined,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              CategoryBudgetTile(
                category: categories[i],
                budget: presenter.budgetFor(categories[i].id),
                spent: presenter.spentFor(categories[i].id),
                received: presenter.receivedFor(categories[i].id),
                isIncome: presenter.isCategoryIncome(categories[i].id),
                transactions:
                    presenter.transactionsForCategory(categories[i].id),
                onTap: () => onTapCategory(categories[i].id),
              ),
              if (i < categories.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Savings Section ──────────────────────────────────────────────────────────

class _SavingsSection extends StatelessWidget {
  final BudgetPresenter presenter;
  final List<({Budget budget, FinancialAccount account})> rows;
  final ValueChanged<String> onTap;

  const _SavingsSection({
    required this.presenter,
    required this.rows,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allocated = presenter.sectionAllocated(BudgetGroupDef.idSavings);
    final saved = presenter.sectionSpent(BudgetGroupDef.idSavings);

    return AppSection(
      title: 'SAVINGS / GOALS',
      hint: '${formatPesoCompact(saved)} / ${formatPesoCompact(allocated)}',
      child: AppCard(
        variant: AppCardVariant.outlined,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              _SavingsTile(
                budget: rows[i].budget,
                account: rows[i].account,
                contributed: presenter.contributedTo(rows[i].account.id),
                onTap: () => onTap(rows[i].account.id),
              ),
              if (i < rows.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: cs.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavingsTile extends StatelessWidget {
  final Budget budget;
  final FinancialAccount account;
  final double contributed;
  final VoidCallback onTap;

  const _SavingsTile({
    required this.budget,
    required this.account,
    required this.contributed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allocated = budget.allocatedAmount;
    final progress =
        allocated > 0 ? (contributed / allocated).clamp(0.0, 1.5) : 0.0;
    final met = contributed >= allocated && allocated > 0;
    final color = met ? cs.tertiary : cs.primary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  account.category == AccountCategory.goal
                      ? Icons.flag_outlined
                      : Icons.savings_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    account.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${formatPesoCompact(contributed)} / ${formatPesoCompact(allocated)}',
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppLinearProgress(
              value: progress.clamp(0.0, 1.0),
              height: 4,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
