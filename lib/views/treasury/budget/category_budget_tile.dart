import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class CategoryBudgetTile extends StatefulWidget {
  final FinanceCategory category;
  final Budget? budget;
  final double spent;
  final double received;
  final bool isIncome;
  final List<TransactionRecord> transactions;
  final VoidCallback? onTap;

  const CategoryBudgetTile({
    super.key,
    required this.category,
    required this.budget,
    required this.spent,
    required this.received,
    required this.isIncome,
    required this.transactions,
    this.onTap,
  });

  @override
  State<CategoryBudgetTile> createState() => _CategoryBudgetTileState();
}

class _CategoryBudgetTileState extends State<CategoryBudgetTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final allocated = widget.budget?.allocatedAmount ?? 0.0;
    final actual = widget.isIncome ? widget.received : widget.spent;
    final progress = allocated > 0 ? (actual / allocated).clamp(0.0, 2.0) : 0.0;
    final isOver = actual > allocated && allocated > 0;

    Color progressColor;
    if (widget.isIncome) {
      progressColor = isOver ? cs.tertiary : cs.tertiary;
    } else {
      if (isOver) {
        progressColor = cs.error;
      } else if (progress > 0.85) {
        progressColor = cs.errorContainer;
      } else {
        progressColor = cs.primary;
      }
    }

    final pct = allocated > 0 ? '${(actual / allocated * 100).round()}%' : '—';

    return InkWell(
      onTap: widget.onTap,
      onLongPress: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.category.name,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (widget.budget != null) ...[
                      AppBadge(
                        text: _budgetTypeLabel(widget.budget!.budgetType),
                        variant: AppBadgeVariant.tonal,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Actual / Allocated
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AppNumberDisplay(
                          value: formatPesoCompact(actual),
                          size: AppNumberSize.body,
                          color: isOver
                              ? (widget.isIncome ? cs.tertiary : cs.error)
                              : cs.onSurface,
                        ),
                        Text(
                          ' / ${formatPesoCompact(allocated)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progress row
                Row(
                  children: [
                    Expanded(
                      child: AppLinearProgress(
                        value: progress.clamp(0.0, 1.0),
                        color: progressColor,
                        height: 5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      pct,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOver
                            ? (widget.isIncome ? cs.tertiary : cs.error)
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Expand/collapse transactions via tap on expand button
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _expanded
                        ? 'Hide transactions'
                        : '${widget.transactions.length} transaction${widget.transactions.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Transactions list
          if (_expanded) ...[
            if (widget.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'No transactions this month',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              )
            else
              ...widget.transactions.map(
                (t) => _TransactionRow(transaction: t),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  String _budgetTypeLabel(BudgetType type) => switch (type) {
        BudgetType.monthly => 'MONTHLY',
        BudgetType.fixed => 'FIXED',
        BudgetType.goal => 'GOAL',
        BudgetType.variable => 'VAR',
      };
}

class _TransactionRow extends StatelessWidget {
  final TransactionRecord transaction;

  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isInflow = transaction.type == TransactionType.inflow;

    return AppListTile(
      dense: true,
      leading: Container(
        width: 3,
        height: 28,
        decoration: BoxDecoration(
          color: isInflow
              ? cs.tertiary.withValues(alpha: 0.5)
              : cs.error.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: Text(
        transaction.description,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('MMM d').format(transaction.date),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            '${isInflow ? '+' : '−'}${formatPesoCompact(transaction.amount)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isInflow ? cs.tertiary : cs.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
