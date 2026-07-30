import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The Month-End Outlook grid — the four figures that make up the month-end
/// projection, in the same order and under the same labels the web companion
/// uses (`web_dashboard_page.dart` → `_MonthEndOutlookRow`), so the same number
/// carries the same name on both platforms.
///
/// The grid deliberately does NOT show raw [TreasuryDashboardPresenter.endingCash]:
/// it does not reserve the remaining monthly budget, so as a headline it reads
/// as a projection it isn't. The projection here is
/// [TreasuryDashboardPresenter.forecastedNetBalance], shown unconditionally —
/// previously the equivalent tile was hidden whenever the user had no budgets.
///
/// Month inflow/outflow are not repeated here; the cashflow strip above already
/// labels both amounts on its bars.
class MetricCardsGrid extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const MetricCardsGrid({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    final forecast = presenter.forecastedNetBalance;
    // Same signalling as the web tile and the cashflow strip's "Projected
    // spare": the success accent while the month still ends in the black, the
    // error accent once it doesn't.
    final forecastColor = forecast >= 0 ? appColors.success : colorScheme.error;

    return AppSection(
      title: 'Month-End Outlook',
      child: Column(
        children: [
          _MetricRow(
            left: _MetricCard(
              label: 'Upcoming Bills',
              value: formatPeso(presenter.monthUnpaidBills),
              sub: 'Unpaid this month',
              color: appColors.bills,
              icon: Icons.receipt_long_outlined,
            ),
            right: _MetricCard(
              label: 'To Receive',
              value: formatPeso(presenter.pendingReceivables),
              sub: 'Money owed to you',
              color: appColors.success,
              icon: Icons.south_rounded,
            ),
          ),
          const SizedBox(height: 8),
          _MetricRow(
            left: _MetricCard(
              label: 'Budget / Savings Due',
              value: formatPeso(presenter.budgetedExpensesRemaining),
              sub: 'Set-asides still to fund',
              color: appColors.treasury,
              icon: Icons.savings_outlined,
            ),
            right: _MetricCard(
              label: 'Proj. Month-End Cash',
              value: formatPeso(forecast),
              sub: 'After bills, budget & savings',
              color: forecastColor,
              icon: Icons.flag_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the 2×2 grid. [IntrinsicHeight] + stretch keeps the pair the same
/// height when one card's label or sub-copy wraps to a second line.
class _MetricRow extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _MetricRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  /// One line naming what the figure does or doesn't deduct — the grid's whole
  /// job is that no tile can be mistaken for a different one.
  final String sub;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    return AppCard(
      variant: AppCardVariant.elevated,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      // Icon badge on the left; label over value over sub-copy on the right.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppNumberDisplay(
                    value: value,
                    size: AppNumberSize.body,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
