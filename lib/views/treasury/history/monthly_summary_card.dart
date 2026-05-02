import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class MonthlySummaryCard extends StatelessWidget {
  final MonthlySummary summary;
  final bool isLive;
  final VoidCallback? onTap;

  const MonthlySummaryCard({
    super.key,
    required this.summary,
    this.isLive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final netPositive = summary.netSavings >= 0;
    final netColor = netPositive ? cs.tertiary : cs.error;
    final allBillsPaid =
        summary.billsPaidCount == summary.billCount && summary.billCount > 0;

    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel(summary.month),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (isLive) ...[
                AppBadge(
                  text: 'LIVE',
                  variant: AppBadgeVariant.tonal,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
            ],
          ),
          const SizedBox(height: 12),

          // Top row: Net Savings + Ending Cash
          Row(
            children: [
              Expanded(
                child: AppNumberDisplay(
                  value: formatPesoCompact(summary.netSavings.abs()),
                  prefix: netPositive ? '+' : '−',
                  label: 'Net Savings',
                  size: AppNumberSize.body,
                  color: netColor,
                  textAlign: TextAlign.start,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppNumberDisplay(
                  value: formatPesoCompact(summary.endingCash),
                  label: 'Ending Cash',
                  size: AppNumberSize.body,
                  color: cs.onSurface,
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Bottom row: Bills + Inflow + Outflow
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  icon: allBillsPaid
                      ? Icons.check_circle_outline
                      : Icons.pending_outlined,
                  label: 'Bills',
                  value: '${summary.billsPaidCount}/${summary.billCount} paid',
                  color: allBillsPaid ? cs.tertiary : cs.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(
                  icon: Icons.arrow_downward,
                  label: 'Inflow',
                  value: formatPesoCompact(summary.totalInflow),
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(
                  icon: Icons.arrow_upward,
                  label: 'Outflow',
                  value: formatPesoCompact(summary.totalOutflow),
                  color: cs.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 3),
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
