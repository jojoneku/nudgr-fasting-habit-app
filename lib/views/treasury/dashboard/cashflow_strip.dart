import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The cashflow strip below the NET WORTH hero (`Nutrition Focus Treasury.dc.html`,
/// Frame 1): the current month's income vs expense bars and the projected
/// month-end cash total. Bars are sized against the larger of the two flows so
/// the dominant flow fills the track and the other reads proportionally.
///
/// The two bar amounts are the only place month inflow/outflow are shown on the
/// dashboard — the Month-End Outlook grid no longer repeats them.
class CashflowStrip extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const CashflowStrip({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;

    final income = presenter.monthTotalInflow;
    final expenses = presenter.monthTotalOutflow;
    final peak = math.max(income, expenses);
    final incomeFrac = peak > 0 ? income / peak : 0.0;
    final expenseFrac = peak > 0 ? expenses / peak : 0.0;

    final spare = presenter.forecastedNetBalance;
    final daysLeft = presenter.daysLeftInMonth;
    final monthName = monthLabel(presenter.currentMonth).split(' ').first;

    return AppCard(
      variant: AppCardVariant.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$monthName cashflow',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                daysLeft == 0 ? 'Last day' : '$daysLeft days left',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: appColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FlowBar(
            icon: Icons.arrow_downward_rounded,
            color: appColors.success,
            fraction: incomeFrac,
            amount: formatPeso(income),
          ),
          const SizedBox(height: 9),
          _FlowBar(
            icon: Icons.arrow_upward_rounded,
            color: cs.error,
            fraction: expenseFrac,
            amount: formatPeso(expenses),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 11),
          Row(
            children: [
              Text(
                // Same wording and same accent as the Month-End Outlook tile
                // and the web dashboard — this is `forecastedNetBalance` on all
                // three surfaces, so it must not read as three different
                // figures. Previously "Projected spare", in the blue domain
                // accent.
                'Proj. month-end cash',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                formatPeso(spare),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: spare >= 0 ? appColors.success : cs.error,
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
  final Color color;
  final double fraction;
  final String amount;

  const _FlowBar({
    required this.icon,
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
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 8, color: cs.surfaceContainerHighest),
                FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
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
        SizedBox(
          width: 74,
          child: Text(
            amount,
            textAlign: TextAlign.right,
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
