import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class FullCategoryBreakdownSheet extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const FullCategoryBreakdownSheet({super.key, required this.presenter});

  static void show(BuildContext context, TreasuryDashboardPresenter presenter) {
    AppBottomSheet.show(
      context: context,
      title: 'Expense Breakdown',
      useDraggableScrollableSheet: true,
      initialChildSize: 0.65,
      body: _BreakdownBody(presenter: presenter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BreakdownBody(presenter: presenter);
  }
}

class _BreakdownBody extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _BreakdownBody({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final slices = presenter.allCategorySpendThisMonth;
    final total = slices.fold(0.0, (s, e) => s + e.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'All Categories This Month',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TOTAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
                AppNumberDisplay(
                  value: formatPeso(total),
                  size: AppNumberSize.body,
                  color: colorScheme.error,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (slices.isEmpty)
          AppEmptyState(
            icon: Icons.pie_chart_outline_rounded,
            title: 'No expenses this month',
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: slices.length,
            itemBuilder: (context, i) => _CategoryRow(
              category: slices[i].$1,
              amount: slices[i].$2,
              total: total,
              index: i,
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final FinanceCategory category;
  final double amount;
  final double total;
  final int index;

  const _CategoryRow({
    required this.category,
    required this.amount,
    required this.total,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = resolveSliceColor(category.colorHex, index);
    final percent = total > 0 ? amount / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        variant: AppCardVariant.outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5), blurRadius: 4)
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppNumberDisplay(
                  value: formatPeso(amount),
                  size: AppNumberSize.body,
                  color: colorScheme.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppLinearProgress(
                    value: percent,
                    color: color,
                    backgroundColor:
                        colorScheme.surfaceContainerHighest,
                    height: 5,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(percent * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
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
