import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class GoalProgressCard extends StatelessWidget {
  final FinancialAccount account;

  const GoalProgressCard({super.key, required this.account});

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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        account.name,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitleText,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: account.goalTarget != null ? _ProgressIndicator(progress: _progress, color: color) : null,
    );
  }
}

class _ProgressIndicator extends StatelessWidget {
  final double progress;
  final Color color;

  const _ProgressIndicator({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeWidth: 3,
          ),
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
