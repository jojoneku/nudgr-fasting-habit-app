import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class CashSummaryBanner extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const CashSummaryBanner({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TotalLiquidRow(presenter: presenter),
            const Divider(height: 24),
            _SummaryMetricsRow(presenter: presenter),
          ],
        ),
      ),
    );
  }
}

class _TotalLiquidRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _TotalLiquidRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOTAL LIQUID CASH',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatPeso(presenter.totalLiquidCash),
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Net Worth  ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            Text(
              formatPeso(presenter.netWorth),
              style: TextStyle(
                color: presenter.netWorth >= 0 ? AppColors.success : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryMetricsRow extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const _SummaryMetricsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MetricItem(
          label: 'Ending Cash',
          value: formatPeso(presenter.endingCash),
          color: AppColors.accent,
        ),
        _VerticalDivider(),
        _MetricItem(
          label: 'Month In',
          value: formatPeso(presenter.monthTotalInflow),
          color: AppColors.success,
        ),
        _VerticalDivider(),
        _MetricItem(
          label: 'Month Out',
          value: formatPeso(presenter.monthTotalOutflow),
          color: AppColors.danger,
        ),
      ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.textSecondary.withOpacity(0.2),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
