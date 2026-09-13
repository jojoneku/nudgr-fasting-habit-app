import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

final _fundedFmt = DateFormat('MMM d, yyyy');

class GoalProgressCard extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback? onTap;

  /// Invoked when the user says they spent a funded goal on what it was for.
  /// Null hides the action (plain savings, or a goal still being saved into).
  final VoidCallback? onMarkSpent;

  const GoalProgressCard({
    super.key,
    required this.account,
    this.onTap,
    this.onMarkSpent,
  });

  Color _parseColor(BuildContext context) {
    try {
      final hex = account.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.tertiary;
    }
  }

  /// Pinned at 100% once funded — see [FinancialAccount.goalProgress]. A goal
  /// that was reached and then spent is complete, not back to zero.
  double get _progress => account.hasGoalTarget
      ? account.goalProgress
      : (account.goalTarget == null || account.goalTarget! <= 0)
          ? 0
          : (account.balance / account.goalTarget!).clamp(0.0, 1.0);

  String get _subtitleText {
    final balanceStr = formatPeso(account.balance);
    if (account.goalTarget == null) return balanceStr;
    final target = formatPeso(account.goalTarget!);
    if (account.goalStage == GoalStage.funded) {
      final on = account.goalFundedAt;
      final when = on == null ? '' : ' · ${_fundedFmt.format(on)}';
      // Say what was achieved, not what is left in the jar: after the purchase
      // the balance is ₱0 and "₱0.00 / ₱6,000.00" would read as failure.
      return 'Funded $target$when';
    }
    return '$balanceStr / $target';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _parseColor(context);

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
                // The account's own badge — the icon the user picked in the
                // setup sheet. This used to hardcode flag/savings, so every
                // goal rendered the same generic bucket no matter what was
                // chosen. `AccountBadge` still falls back to the category
                // default (goal -> flag, savings -> piggy) when nothing is set.
                AccountBadge.of(account, size: 32, accent: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (account.goalStage == GoalStage.funded)
                  Icon(Icons.check_circle,
                      size: 20, color: context.appColors.success)
                else
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
              if (onMarkSpent != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (account.goalLooksSpent)
                      Expanded(
                        child: Text(
                          'Balance is now ${formatPeso(account.balance)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                      onPressed: onMarkSpent,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Mark as spent'),
                    ),
                  ],
                ),
              ],
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
