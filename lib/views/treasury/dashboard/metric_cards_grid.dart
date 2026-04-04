import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class MetricCardsGrid extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const MetricCardsGrid({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final forecastColor = presenter.forecastedNetBalance >= 0
        ? AppColors.accent
        : AppColors.danger;

    final fourthLabel = presenter.hasBudget ? 'Forecast' : 'Liabilities';
    final fourthValue = presenter.hasBudget
        ? formatPeso(presenter.forecastedNetBalance)
        : formatPeso(presenter.totalLiabilities);
    final fourthColor = presenter.hasBudget
        ? forecastColor
        : (presenter.totalLiabilities > 0
            ? AppColors.danger
            : AppColors.textSecondary);

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _MetricCard(
                label: 'ENDING CASH',
                value: formatPeso(presenter.endingCash),
                color: AppColors.accent,
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 8),
              _MetricCard(
                label: 'MONTH OUT',
                value: formatPeso(presenter.monthTotalOutflow),
                color: AppColors.danger,
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
                color: AppColors.success,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withOpacity(0.08), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 2, color: color),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      textStyle: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
