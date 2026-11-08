import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/category_icon.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/treasury/shared/budget_status_color.dart';
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

    // Progress/amount accent: the shared status color once a row needs a look
    // or is done (Watch, Over, Funded — the same tones web uses), tertiary for
    // income, otherwise the category's own color.
    final flagged = row.status != BudgetStatus.onTrack;
    final Color accent = flagged
        ? budgetStatusColor(context, row.status)
        : (row.isIncome ? cs.tertiary : identity);

    final hasBudget = row.allocated > 0;
    final pct =
        hasBudget ? '${(row.actual / row.allocated * 100).round()}%' : '—';

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
            // Savings rows carry a real account, so they get that account's
            // badge — the icon picked in the setup sheet, or its category
            // default. Hardcoding flag/piggy here meant every fund rendered
            // the same generic bucket. Expense/income rows have no account and
            // keep resolving their glyph from the category name.
            if (row.isSavings && row.accountCategory != null)
              AccountBadge(
                category: row.accountCategory!,
                name: row.name,
                iconKey: row.iconKey,
                colorHex: row.colorHex,
                size: 40,
                accent: identity,
              )
            else
              _IconChip(
                icon: categoryIcon(row.name, row.categoryType),
                color: identity,
              ),
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
                        color: flagged ? accent : cs.onSurface,
                      ),
                      Text(
                        ' / ${formatPesoCompact(row.allocated)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  // A target the user cannot edit here has to name where it IS
                  // edited, or the row reads as ignoring what they typed on
                  // this page. It sits on its own line rather than beside the
                  // amount: inline it split the "spent / allocated" pair apart
                  // mid-row and stole width from the name's ellipsis, and it
                  // read as part of the figure instead of a note about it.
                  if (row.targetFromSetAside) ...[
                    const SizedBox(height: 3),
                    _HintLine(
                      icon: Icons.link_rounded,
                      color: cs.onSurfaceVariant,
                      text: "Target from this month's set-aside",
                    ),
                  ],
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
                          color: flagged ? accent : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  // The status in words (Watch · 82%, Over by ₱1,200, Funded,
                  // Received), so it is never shown by color alone. It stays
                  // inside the column so it aligns with the name.
                  if (flagged) ...[
                    const SizedBox(height: 6),
                    _HintLine(
                      icon: budgetStatusIcon(row.status),
                      color: accent,
                      text: row.statusLabel,
                    ),
                  ],
                  // Money drawn out of a fund no longer subtracts from its
                  // progress — spending a fund on what it is for is the fund
                  // working. It still has to be visible, though: netted into
                  // the bar it was silent, and the row read as underfunded.
                  if (row.isSavings && row.withdrawn > 0) ...[
                    const SizedBox(height: 6),
                    _HintLine(
                      icon: Icons.call_made_rounded,
                      color: cs.onSurfaceVariant,
                      text: '${formatPeso(row.withdrawn)} used from this fund '
                          'this month',
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
