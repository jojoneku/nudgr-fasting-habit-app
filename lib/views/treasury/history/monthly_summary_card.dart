import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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
    final netPositive = summary.netSavings >= 0;
    final netColor = netPositive ? AppColors.success : AppColors.danger;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLive
                ? AppColors.accent.withOpacity(0.4)
                : AppColors.textSecondary.withOpacity(0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    monthLabel(summary.month),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      'LIVE',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SummaryMetric(
                  label: 'Net Savings',
                  value: formatPeso(summary.netSavings),
                  color: netColor,
                  prefix: netPositive ? '+' : '',
                ),
                const SizedBox(width: 8),
                _SummaryMetric(
                  label: 'Ending Cash',
                  value: formatPesoCompact(summary.endingCash),
                  color: AppColors.textPrimary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _SummaryMetric(
                  label: 'Bills',
                  value:
                      '${summary.billsPaidCount}/${summary.billCount} paid',
                  color: summary.billsPaidCount == summary.billCount
                      ? AppColors.success
                      : AppColors.gold,
                  icon: Icons.receipt_long_outlined,
                ),
                const SizedBox(width: 8),
                _SummaryMetric(
                  label: 'Inflow',
                  value: formatPesoCompact(summary.totalInflow),
                  color: AppColors.success,
                  icon: Icons.arrow_downward,
                ),
                const SizedBox(width: 8),
                _SummaryMetric(
                  label: 'Outflow',
                  value: formatPesoCompact(summary.totalOutflow),
                  color: AppColors.danger,
                  icon: Icons.arrow_upward,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String prefix;
  final IconData? icon;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
    this.prefix = '',
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: color, size: 12),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$prefix$value',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
