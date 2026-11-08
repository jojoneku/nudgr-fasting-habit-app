import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The accent for a [StatementTone] on mobile. Same accents on the
/// Month-End Outlook and the Next Month Forecast, so the same line reads the
/// same on both cards.
Color statementToneColor(BuildContext context, StatementTone tone) {
  final cs = Theme.of(context).colorScheme;
  final appColors = context.appColors;
  return switch (tone) {
    StatementTone.neutral => cs.onSurface,
    StatementTone.income => appColors.success,
    StatementTone.bills => appColors.bills,
    StatementTone.setAside => appColors.treasury,
    StatementTone.budget => appColors.weight,
    StatementTone.good => appColors.success,
    StatementTone.bad => cs.error,
  };
}

/// A signed statement card: a vertical list of [lines], then the ending
/// figure on a tinted panel. Shared by the Month-End Outlook and the Next
/// Month Forecast; each passes presenter-built lines and only lays them out.
class StatementCard extends StatelessWidget {
  final String title;
  final String? hint;
  final List<StatementLine> lines;
  final String endingTitle;
  final String endingCaption;
  final String endingAmount;
  final StatementTone endingTone;

  const StatementCard({
    super.key,
    required this.title,
    this.hint,
    required this.lines,
    required this.endingTitle,
    required this.endingCaption,
    required this.endingAmount,
    required this.endingTone,
  });

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: title,
      hint: hint,
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < lines.length; i++)
              StatementLineRow(
                line: lines[i],
                divider: i < lines.length - 1,
              ),
            const SizedBox(height: 8),
            StatementEndingPanel(
              title: endingTitle,
              caption: endingCaption,
              amount: endingAmount,
              color: statementToneColor(context, endingTone),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of a statement: label and caption on the left, the signed amount
/// on the right, a hairline under every line but the last.
class StatementLineRow extends StatelessWidget {
  final StatementLine line;
  final bool divider;

  const StatementLineRow({super.key, required this.line, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: divider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  line.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppNumberDisplay(
            value: line.amount,
            size: AppNumberSize.body,
            color: statementToneColor(context, line.tone),
          ),
        ],
      ),
    );
  }
}

/// The statement's one focal figure on a tinted panel in its accent.
class StatementEndingPanel extends StatelessWidget {
  final String title;
  final String caption;
  final String amount;
  final Color color;

  const StatementEndingPanel({
    super.key,
    required this.title,
    required this.caption,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: AppNumberDisplay(
                value: amount,
                size: AppNumberSize.title,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
