import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// One budget rendered as its own card (Nudgr budget-cards redesign,
/// `Nutrition Focus Treasury.dc.html` Frame 4). Shows the category's icon + color
/// (the same identity it carries in the ledger and dashboard), the name with its
/// cadence badge inline, the progress bar below the name, and spent / allocated.
/// Tapping the card opens the budget's transactions in a ledger-style popup
/// scoped to this category; long-press edits the budget.
class BudgetCard extends StatelessWidget {
  final BudgetSectionRow row;
  final VoidCallback? onEdit;

  const BudgetCard({super.key, required this.row, this.onEdit});

  IconData get _icon {
    if (row.isSavings) {
      return row.isGoal ? Icons.flag_outlined : Icons.savings_outlined;
    }
    return categoryIcon(row.name, row.categoryType);
  }

  static String _budgetTypeLabel(BudgetType type) => switch (type) {
        BudgetType.monthly => 'MONTHLY',
        BudgetType.fixed => 'FIXED',
        BudgetType.goal => 'GOAL',
        BudgetType.variable => 'VAR',
      };

  void _showTransactions(BuildContext context) {
    AppBottomSheet.show(
      context: context,
      title: row.name,
      useDraggableScrollableSheet: true,
      initialChildSize: 0.6,
      body: _BudgetTransactions(row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // The category/account identity color — same resolution the ledger and
    // dashboard use, so a budget reads as "the same" category everywhere.
    final identity = resolveSliceColor(
      row.colorHex,
      row.colorIndex,
      brightness: theme.brightness,
    );

    // Progress/amount accent: danger when an expense is over, tertiary when a
    // savings goal is met or the row is income, otherwise the category's color.
    final Color accent;
    if (row.isOver) {
      accent = cs.error;
    } else if (row.isSavings && row.met) {
      accent = cs.tertiary;
    } else if (row.isIncome) {
      accent = cs.tertiary;
    } else {
      accent = identity;
    }

    final hasBudget = row.allocated > 0;
    final pct =
        hasBudget ? '${(row.actual / row.allocated * 100).round()}%' : '—';
    final overOrMet = row.isOver || (row.isSavings && row.met);

    return AppCard(
      variant: AppCardVariant.filled,
      padding: EdgeInsets.zero,
      onTap: () => _showTransactions(context),
      onLongPress: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon · name + cadence badge inline · spent / allocated
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _IconChip(icon: _icon, color: identity),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.name,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!row.isSavings) ...[
                        const SizedBox(width: 8),
                        AppBadge(
                          text: _budgetTypeLabel(row.budgetType),
                          variant: AppBadgeVariant.tonal,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AppNumberDisplay(
                      value: formatPesoCompact(row.actual),
                      size: AppNumberSize.body,
                      color: overOrMet ? accent : cs.onSurface,
                    ),
                    Text(
                      ' / ${formatPesoCompact(row.allocated)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Full-width progress bar + %
            Row(
              children: [
                Expanded(
                  child: AppLinearProgress(
                    value: row.progress,
                    color: accent,
                    height: 6,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  pct,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overOrMet ? accent : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            // Over-budget / goal note — otherwise a subtle "tap to view" hint so
            // the card reads as tappable (transactions open on tap).
            if (row.isOver) ...[
              const SizedBox(height: 8),
              _HintLine(
                icon: Icons.warning_amber_rounded,
                color: cs.error,
                text: 'Over by ${formatPeso(row.overBy)} — trim next week',
              ),
            ] else if (row.isSavings && row.met) ...[
              const SizedBox(height: 8),
              _HintLine(
                icon: Icons.check_circle_outline_rounded,
                color: cs.tertiary,
                text: 'Goal reached',
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Tap to see transactions',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The budget's transactions in a ledger-style popup, scoped to this category.
class _BudgetTransactions extends StatelessWidget {
  final BudgetSectionRow row;

  const _BudgetTransactions({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final identity = resolveSliceColor(
      row.colorHex,
      row.colorIndex,
      brightness: theme.brightness,
    );
    final accent = row.isOver
        ? cs.error
        : ((row.isSavings && row.met) || row.isIncome ? cs.tertiary : identity);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Spent-of-allocated summary + progress
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AppNumberDisplay(
                    value: formatPeso(row.actual),
                    size: AppNumberSize.title,
                    color: accent,
                  ),
                  Text(
                    ' of ${formatPeso(row.allocated)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppLinearProgress(value: row.progress, color: accent, height: 6),
            ],
          ),
        ),
        const Divider(height: 1),
        if (row.transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
            child: Text(
              'No transactions this month',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                for (final t in row.transactions)
                  _TransactionRow(transaction: t),
              ],
            ),
          ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconChip({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _HintLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _HintLine(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
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
