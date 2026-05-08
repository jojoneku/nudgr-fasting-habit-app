import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/budget/add_budget_sheet.dart';
import 'package:intermittent_fasting/views/treasury/budget/category_budget_tile.dart';
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
              _MonthSelector(presenter: widget.presenter),
              _SummaryBanner(presenter: widget.presenter),
              Expanded(
                child: hasAny
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        children: [
                          for (final group in BudgetGroup.values) ...[
                            if (group == BudgetGroup.savings &&
                                savings.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _SavingsSection(
                                  presenter: widget.presenter,
                                  rows: savings,
                                  onTap: _showAddBudgetSheet,
                                ),
                              )
                            else if (group != BudgetGroup.savings &&
                                (byGroup[group] ?? const []).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _GroupSection(
                                  group: group,
                                  presenter: widget.presenter,
                                  categories: byGroup[group]!,
                                  onTapCategory: _showAddBudgetSheet,
                                ),
                              ),
                          ],
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

  const _MonthSelector({required this.presenter});

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
      ),
    );
  }
}

// ─── Summary Banner ───────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final BudgetPresenter presenter;

  const _SummaryBanner({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final remaining = presenter.totalRemaining;
    final isOver = remaining < 0;

    return Container(
      width: double.infinity,
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: AppNumberDisplay(
              value: formatPesoCompact(allocated),
              label: 'Allocated',
              size: AppNumberSize.body,
              color: cs.primary,
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: AppNumberDisplay(
              value: formatPesoCompact(spent),
              label: 'Spent',
              size: AppNumberSize.body,
              color: cs.onSurface,
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            width: 1,
            height: 32,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(
            child: AppNumberDisplay(
              value: formatPesoCompact(remaining.abs()),
              label: isOver ? 'Over by' : 'Remaining',
              size: AppNumberSize.body,
              color: isOver ? cs.error : cs.tertiary,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Group Section ────────────────────────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final BudgetGroup group;
  final BudgetPresenter presenter;
  final List categories;
  final ValueChanged<String> onTapCategory;

  const _GroupSection({
    required this.group,
    required this.presenter,
    required this.categories,
    required this.onTapCategory,
  });

  static const _groupLabels = {
    BudgetGroup.nonNegotiables: 'NON-NEGOTIABLES',
    BudgetGroup.livingExpense: 'LIVING EXPENSE',
    BudgetGroup.variableOptional: 'VARIABLE / OPTIONAL',
    BudgetGroup.savings: 'SAVINGS / GOALS',
  };

  @override
  Widget build(BuildContext context) {
    final sectionAllocated = presenter.sectionAllocated(group);
    final sectionSpent = presenter.sectionSpent(group);

    return AppSection(
      title: _groupLabels[group]!,
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
    final allocated = presenter.sectionAllocated(BudgetGroup.savings);
    final saved = presenter.sectionSpent(BudgetGroup.savings);

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
