import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppNumberDisplay(
                  value: account.goalTarget != null
                      ? '${((_progress) * 100).round()}%'
                      : formatPeso(account.balance),
                  size: AppNumberSize.body,
                  color: color,
                ),
              ],
            ),
            if (account.goalTarget != null) ...[
              const SizedBox(height: 8),
              AppLinearProgress(
                value: _progress,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
                height: 6,
              ),
              const SizedBox(height: 4),
              AppNumberDisplay(
                value: _subtitleText,
                size: AppNumberSize.body,
                color: colorScheme.onSurfaceVariant,
              ),
            ] else ...[
              const SizedBox(height: 2),
              AppNumberDisplay(
                value: formatPeso(account.balance),
                size: AppNumberSize.body,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
