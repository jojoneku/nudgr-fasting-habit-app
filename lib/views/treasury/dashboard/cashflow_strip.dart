import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The cash flow strip below the NET WORTH hero: this month's income and
/// expense bars, then the net flow with how much of income was spent, and the
/// savings rate as a badge (same figures as web v2's Cash flow card).
///
/// Bars are sized against the larger of the two flows so the dominant flow
/// fills the track and the other reads proportionally. The two bar amounts are
/// the only place month inflow/outflow are shown on the dashboard.
///
/// The projected month-end cash is not repeated here: it lives in the
/// Month-End Outlook and as the Next Month Forecast's "Starts at".
class CashflowStrip extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const CashflowStrip({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;

    return AppCard(
      variant: AppCardVariant.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presenter.cashflowTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      presenter.daysLeftLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(
                key: const ValueKey('dashboard.cashflow.savingsRate'),
                text: presenter.savingsRateLabel,
                color: presenter.hasSavingsRate
                    ? appColors.success
                    : cs.onSurfaceVariant,
                variant: AppBadgeVariant.tonal,
                size: AppBadgeSize.medium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FlowBar(
            icon: Icons.arrow_downward_rounded,
            semanticLabel: 'Income',
            color: appColors.success,
            fraction: presenter.cashflowIncomeFraction,
            amount: presenter.monthTotalInflowLabel,
          ),
          const SizedBox(height: 9),
          _FlowBar(
            icon: Icons.arrow_upward_rounded,
            semanticLabel: 'Expenses',
            color: cs.error,
            fraction: presenter.cashflowExpenseFraction,
            amount: presenter.monthTotalOutflowLabel,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net flow',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appColors.textTertiary,
                      ),
                    ),
                    Text(
                      presenter.spentShareOfIncomeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                presenter.monthNetCashFlowLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: presenter.monthNetCashFlowNegative
                      ? cs.error
                      : cs.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowBar extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final Color color;
  final double fraction;
  final String amount;

  const _FlowBar({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    required this.fraction,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: color, semanticLabel: semanticLabel),
        const SizedBox(width: 9),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 8, color: cs.surfaceContainerHighest),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // A minimum, not a fixed width: at 74px a six-figure amount like
        // ₱46,500.00 wrapped onto a second line. The bar is Expanded, so
        // letting the amount take what it needs costs only track length.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 74),
          child: Text(
            amount,
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
