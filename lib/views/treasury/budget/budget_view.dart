import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/budget/add_budget_sheet.dart';
import 'package:intermittent_fasting/views/treasury/budget/category_budget_tile.dart';

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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AddBudgetSheet(
          presenter: widget.presenter,
          preselectedCategoryId: categoryId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final byGroup = widget.presenter.categoriesByGroup;
        final hasAny =
            byGroup.values.any((list) => list.isNotEmpty);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              _MonthSelector(presenter: widget.presenter),
              _SummaryBanner(presenter: widget.presenter),
              Expanded(
                child: hasAny
                    ? ListView(
                        children: [
                          for (final group in BudgetGroup.values)
                            if (byGroup[group]!.isNotEmpty)
                              _GroupSection(
                                group: group,
                                presenter: widget.presenter,
                                categories: byGroup[group]!,
                                onTapCategory: _showAddBudgetSheet,
                              ),
                          const SizedBox(height: 80),
                        ],
                      )
                    : _EmptyState(onAdd: _showAddBudgetSheet),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddBudgetSheet(),
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.background,
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
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_left,
                  color: AppColors.textSecondary),
              onPressed: () =>
                  presenter.setMonth(previousMonth(presenter.selectedMonth)),
            ),
          ),
          Text(
            monthLabel(presenter.selectedMonth),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onPressed: () =>
                  presenter.setMonth(nextMonth(presenter.selectedMonth)),
            ),
          ),
        ],
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
    final allocated = presenter.totalAllocated;
    final spent = presenter.totalSpent;
    final remaining = presenter.totalRemaining;
    final isOver = remaining < 0;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _BannerStat(
              label: 'Allocated',
              value: formatPesoCompact(allocated),
              color: AppColors.accent),
          const SizedBox(width: 8),
          _BannerStat(
              label: 'Spent',
              value: formatPesoCompact(spent),
              color: AppColors.textPrimary),
          const SizedBox(width: 8),
          _BannerStat(
              label: isOver ? 'Over by' : 'Remaining',
              value: formatPesoCompact(remaining.abs()),
              color: isOver ? AppColors.danger : AppColors.success),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BannerStat(
      {required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            Text(label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.textSecondary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            label: _groupLabels[group]!,
            allocated: sectionAllocated,
            spent: sectionSpent,
          ),
          const Divider(
              height: 1, color: Color(0xFF2A3240)),
          ...categories.map((cat) => Column(
                children: [
                  CategoryBudgetTile(
                    category: cat,
                    budget: presenter.budgetFor(cat.id),
                    spent: presenter.spentFor(cat.id),
                    received: presenter.receivedFor(cat.id),
                    isIncome: presenter.isCategoryIncome(cat.id),
                    transactions:
                        presenter.transactionsForCategory(cat.id),
                  ),
                  const Divider(
                      height: 1,
                      color: Color(0xFF2A3240)),
                ],
              )),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final double allocated;
  final double spent;

  const _SectionHeader({
    required this.label,
    required this.allocated,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text(
            '${formatPesoCompact(spent)} / ${formatPesoCompact(allocated)}',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: AppColors.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(
            'No budgets yet',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to set spending limits',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Set Budget'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
