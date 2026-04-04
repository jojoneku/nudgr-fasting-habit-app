import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: _TotalLiquidRow(presenter: presenter),
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
          style: GoogleFonts.jetBrainsMono(
            textStyle: const TextStyle(
              color: AppColors.accent,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              shadows: [
                Shadow(color: AppColors.accentGlow, blurRadius: 16),
                Shadow(color: AppColors.accentGlow, blurRadius: 32),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Net Worth  ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            Text(
              formatPeso(presenter.netWorth),
              style: GoogleFonts.jetBrainsMono(
                textStyle: TextStyle(
                  color: presenter.netWorth >= 0
                      ? AppColors.success
                      : AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
