import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// One budget rendered as its own card (Nudgr budget-cards redesign,
/// `Nutrition Focus Treasury.dc.html` Frame 4). Shows the category's icon + color
/// (the same identity it carries in the ledger and dashboard), the name with its
/// spent / allocated inline, and the progress bar directly below the name — all
/// in the column beside the (vertically centered) icon. Long-press edits.
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
      onLongPress: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        // Icon centered against the name + progress block beside it, so nothing
        // hangs indented or full-width below the card.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _IconChip(icon: _icon, color: identity),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name + spent / allocated inline.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          row.name,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  const SizedBox(height: 8),
                  // Progress bar + % — directly below the name, aligned with it.
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
                  // Over-budget / goal note stays inside the column so it aligns
                  // with the name, not hanging under the icon.
                  if (row.isOver) ...[
                    const SizedBox(height: 6),
                    _HintLine(
                      icon: Icons.warning_amber_rounded,
                      color: cs.error,
                      text:
                          'Over by ${formatPeso(row.overBy)} — trim next week',
                    ),
                  ] else if (row.isSavings && row.met) ...[
                    const SizedBox(height: 6),
                    _HintLine(
                      icon: Icons.check_circle_outline_rounded,
                      color: cs.tertiary,
                      text: 'Goal reached',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
