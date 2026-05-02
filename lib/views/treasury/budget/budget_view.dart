import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
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
      title: categoryId != null &&
              widget.presenter.budgetFor(categoryId) != null
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
        final hasAny = byGroup.values.any((list) => list.isNotEmpty);

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
                          for (final group in BudgetGroup.values)
                            if (byGroup[group]!.isNotEmpty)
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
      color: theme.colorScheme.surface,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AppCard(
        variant: AppCardVariant.filled,
        child: Row(
          children: [
            Expanded(
              child: AppNumberDisplay(
                value: formatPesoCompact(allocated),
                label: 'Allocated',
                size: AppNumberSize.body,
                color: cs.primary,
                textAlign: TextAlign.start,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppNumberDisplay(
                value: formatPesoCompact(spent),
                label: 'Spent',
                size: AppNumberSize.body,
                color: cs.onSurface,
                textAlign: TextAlign.start,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppNumberDisplay(
                value: formatPesoCompact(remaining.abs()),
                label: isOver ? 'Over by' : 'Remaining',
                size: AppNumberSize.body,
                color: isOver ? cs.error : cs.tertiary,
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
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
  };

  @override
  Widget build(BuildContext context) {
    final sectionAllocated = presenter.sectionAllocated(group);
    final sectionSpent = presenter.sectionSpent(group);

    return AppSection(
      title: _groupLabels[group]!,
      hint: '${formatPesoCompact(sectionSpent)} / ${formatPesoCompact(sectionAllocated)}',
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
