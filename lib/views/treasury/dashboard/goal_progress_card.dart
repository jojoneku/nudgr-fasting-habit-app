import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class GoalProgressCard extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback? onTap;

  const GoalProgressCard({super.key, required this.account, this.onTap});

  Color _parseColor() {
    try {
      final hex = account.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  double get _progress {
    if (account.goalTarget == null || account.goalTarget! <= 0) return 0;
    return (account.balance / account.goalTarget!).clamp(0.0, 1.0);
  }

  String get _subtitleText {
    final balanceStr = formatPeso(account.balance);
    if (account.goalTarget != null) {
      return '$balanceStr / ${formatPeso(account.goalTarget!)}';
    }
    return balanceStr;
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    account.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  account.goalTarget != null
                      ? '${((_progress) * 100).round()}%'
                      : formatPeso(account.balance),
                  style: GoogleFonts.jetBrainsMono(
                    textStyle: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (account.goalTarget != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: color.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitleText,
                style: GoogleFonts.jetBrainsMono(
                  textStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 2),
              Text(
                formatPeso(account.balance),
                style: GoogleFonts.jetBrainsMono(
                  textStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
