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
/// (the same identity it carries in the ledger and dashboard), the name, spent /
/// allocated, a progress bar with %, an "Over by ₱x" hint when exceeded, and a
/// tap-to-expand transaction list. Tapping the card body edits the budget.
class BudgetCard extends StatefulWidget {
  final BudgetSectionRow row;
  final VoidCallback? onEdit;

  const BudgetCard({super.key, required this.row, this.onEdit});

  @override
  State<BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<BudgetCard> {
  bool _expanded = false;

  IconData get _icon {
    final row = widget.row;
    if (row.isSavings) {
      return row.isGoal ? Icons.flag_outlined : Icons.savings_outlined;
    }
    return categoryIcon(row.name, row.categoryType);
  }

  String _budgetTypeLabel(BudgetType type) => switch (type) {
        BudgetType.monthly => 'MONTHLY',
        BudgetType.fixed => 'FIXED',
        BudgetType.goal => 'GOAL',
        BudgetType.variable => 'VAR',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = widget.row;

    // The category/account identity color — same resolution the ledger and
    // dashboard use, so a budget reads as "the same" category everywhere.
    final identity = resolveSliceColor(
      row.colorHex,
      row.colorIndex,
      brightness: theme.brightness,
    );

    // Progress/amount accent: danger when an expense is over, tertiary when a
    // savings goal is met, otherwise the category's own color.
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
    // True ratio (can exceed 100% when over) — the bar itself stays clamped.
    final pct =
        hasBudget ? '${(row.actual / row.allocated * 100).round()}%' : '—';
    final txnCount = row.transactions.length;

    return AppCard(
      variant: AppCardVariant.filled,
      padding: EdgeInsets.zero,
      onTap: widget.onEdit,
      onLongPress: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: icon chip · name · spent / allocated
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconChip(icon: _icon, color: identity),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            row.name,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Budget cadence badge — expense rows only, matching
                          // the label the old category tile showed.
                          if (!row.isSavings) ...[
                            const SizedBox(height: 4),
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
                          color: (row.isOver || (row.isSavings && row.met))
                              ? accent
                              : cs.onSurface,
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
                // Progress bar + %
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
                    SizedBox(
                      width: 36,
                      child: Text(
                        pct,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: (row.isOver || (row.isSavings && row.met))
                              ? accent
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                // Over-budget hint (expense) / goal-reached note (savings)
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
                ],
              ],
            ),
          ),
          // Transactions expander
          _ExpanderBar(
            expanded: _expanded,
            count: txnCount,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: row.transactions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                      child: Text(
                        'No transactions this month',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : Column(
                      children: [
                        for (final t in row.transactions)
                          _TransactionRow(transaction: t),
                      ],
                    ),
            ),
        ],
      ),
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

  const _HintLine({required this.icon, required this.color, required this.text});

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

class _ExpanderBar extends StatelessWidget {
  final bool expanded;
  final int count;
  final VoidCallback onTap;

  const _ExpanderBar({
    required this.expanded,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              expanded
                  ? 'Hide transactions'
                  : '$count transaction${count == 1 ? '' : 's'}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 2),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
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
