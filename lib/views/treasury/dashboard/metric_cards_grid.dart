import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class MetricCardsGrid extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const MetricCardsGrid({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final forecastColor = presenter.forecastedNetBalance >= 0
        ? colorScheme.primary
        : colorScheme.error;

    final fourthLabel = presenter.hasBudget ? 'Forecast' : 'Liabilities';
    final fourthValue = presenter.hasBudget
        ? formatPeso(presenter.forecastedNetBalance)
        : formatPeso(presenter.totalLiabilities);
    final fourthColor = presenter.hasBudget
        ? forecastColor
        : (presenter.totalLiabilities > 0
            ? colorScheme.error
            : colorScheme.onSurfaceVariant);

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _MetricCard(
                label: 'ENDING CASH',
                value: formatPeso(presenter.endingCash),
                color: colorScheme.primary,
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 8),
              _MetricCard(
                label: 'MONTH OUT',
                value: formatPeso(presenter.monthTotalOutflow),
                color: colorScheme.error,
                icon: Icons.arrow_upward_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              _MetricCard(
                label: 'MONTH IN',
                value: formatPeso(presenter.monthTotalInflow),
                color: colorScheme.tertiary,
                icon: Icons.arrow_downward_rounded,
              ),
              const SizedBox(height: 8),
              _MetricCard(
                label: fourthLabel.toUpperCase(),
                value: fourthValue,
                color: fourthColor,
                icon: presenter.hasBudget
                    ? Icons.track_changes_outlined
                    : Icons.credit_card_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      variant: AppCardVariant.elevated,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon in a tinted badge — the same identity treatment the budget,
          // account and category cards use (one icon with a background).
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          AppNumberDisplay(
            value: value,
            size: AppNumberSize.body,
            color: color,
          ),
        ],
      ),
    );
  }
}
