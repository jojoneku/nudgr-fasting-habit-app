import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The Next Month Forecast — the Month-End Outlook carried one month on,
/// placed directly under [MetricCardsGrid] so the two read as a pair.
///
/// It starts where this month's outlook ends (Proj. Month-End Cash) and runs
/// the same chain, line for line:
///
///   Starts at + To Receive − Bills − Installments − Set-asides − Budget
///     = Projected end of next month
///
/// Every figure is [TreasuryDashboardPresenter.nextMonthForecast]; this widget
/// only lays it out. Colours match the outlook tiles, so the same line carries
/// the same accent on both cards.
class NextMonthForecastCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const NextMonthForecastCard({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final f = presenter.nextMonthForecast;
    final endingColor = f.endsNegative ? colorScheme.error : appColors.success;

    return AppSection(
      title: 'Next Month Forecast',
      hint: f.monthName,
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ForecastLine(
              label: 'Starts at',
              caption: 'This month’s projected end',
              amount: f.startingCashLabel,
              color: colorScheme.onSurface,
            ),
            _ForecastLine(
              label: 'To Receive',
              caption: 'Expected next month',
              amount: '+ ${formatPeso(f.toReceive)}',
              color: appColors.success,
            ),
            _ForecastLine(
              label: 'Bills',
              caption: 'Incl. card statements',
              amount: '− ${formatPeso(f.bills)}',
              color: appColors.bills,
            ),
            _ForecastLine(
              label: 'Installments',
              caption: 'Not on a statement yet',
              amount: '− ${formatPeso(f.installments)}',
              color: appColors.bills,
            ),
            _ForecastLine(
              label: 'Set-asides',
              caption: 'Still to fund',
              amount: '− ${formatPeso(f.setAsides)}',
              color: appColors.treasury,
            ),
            _ForecastLine(
              label: 'Budget',
              caption: f.budgetCaption,
              amount: '− ${formatPeso(f.budget)}',
              color: appColors.weight,
              divider: false,
            ),
            const SizedBox(height: 8),
            _EndingPanel(
              forecast: f,
              color: endingColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the chain: label and caption on the left, the signed amount
/// on the right, a hairline under every line but the last.
class _ForecastLine extends StatelessWidget {
  final String label;
  final String caption;
  final String amount;
  final Color color;
  final bool divider;

  const _ForecastLine({
    required this.label,
    required this.caption,
    required this.amount,
    required this.color,
    this.divider = true,
  });

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
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  caption,
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
            value: amount,
            size: AppNumberSize.body,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// The projected end of next month and how it moves against this month's,
/// on a tinted panel in the ending's accent — the card's one focal figure.
class _EndingPanel extends StatelessWidget {
  final NextMonthForecast forecast;
  final Color color;

  const _EndingPanel({required this.forecast, required this.color});

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
                  forecast.endingTitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  forecast.changeLabel,
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
                value: forecast.endingLabel,
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
