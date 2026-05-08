import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class CashSummaryBanner extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const CashSummaryBanner({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.elevated,
      child: _TotalLiquidRow(presenter: presenter),
    );
  }
}

class _TotalLiquidRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _TotalLiquidRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final held = presenter.totalHeldForOthers;
    final hasHeld = held > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasHeld ? 'CASH (YOURS)' : 'TOTAL LIQUID CASH',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        AppNumberDisplay(
          value: formatPeso(presenter.totalLiquidCash),
          size: AppNumberSize.headline,
          color: colorScheme.primary,
        ),
        if (hasHeld) ...[
          const SizedBox(height: 2),
          Text(
            'of ${formatPeso(presenter.totalLiquidCashGross)} total · '
            '${formatPeso(held)} held for others',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Net Worth  ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            AppNumberDisplay(
              value: formatPeso(presenter.netWorth),
              size: AppNumberSize.body,
              color: presenter.netWorth >= 0
                  ? colorScheme.tertiary
                  : colorScheme.error,
            ),
          ],
        ),
      ],
    );
  }
}
