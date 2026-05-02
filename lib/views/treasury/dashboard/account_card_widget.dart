import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class AccountCardWidget extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback? onTap;
  final double heldAmount;

  const AccountCardWidget({
    super.key,
    required this.account,
    this.onTap,
    this.heldAmount = 0.0,
  });

  Color _parseColor() {
    try {
      final hex = account.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.accent;
    }
  }

  String _categoryLabel() {
    switch (account.category) {
      case AccountCategory.bank:
        return 'Bank';
      case AccountCategory.ewallet:
        return 'eWallet';
      case AccountCategory.cash:
        return 'Cash';
      case AccountCategory.savings:
        return 'Savings';
      case AccountCategory.goal:
        return 'Goal';
      case AccountCategory.timeDeposit:
        return 'TD';
      case AccountCategory.creditCard:
        return 'Credit';
      case AccountCategory.creditLine:
        return 'Credit Line';
      case AccountCategory.bnpl:
        return 'BNPL';
      case AccountCategory.investment:
        return 'Invest';
      case AccountCategory.custodian:
        return 'External';
    }
  }

  IconData _categoryIcon() => switch (account.category) {
        AccountCategory.bank => Icons.account_balance_outlined,
        AccountCategory.ewallet => Icons.phone_android_outlined,
        AccountCategory.cash => Icons.payments_outlined,
        AccountCategory.savings => Icons.savings_outlined,
        AccountCategory.goal => Icons.flag_outlined,
        AccountCategory.timeDeposit => Icons.lock_clock_outlined,
        AccountCategory.creditCard => Icons.credit_card_outlined,
        AccountCategory.creditLine => Icons.credit_score_outlined,
        AccountCategory.bnpl => Icons.shopping_bag_outlined,
        AccountCategory.investment => Icons.trending_up_rounded,
        AccountCategory.custodian => Icons.swap_horiz_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = _parseColor();

    return Semantics(
      label:
          "${account.name}, ${account.isLiability ? 'Owed' : 'Balance'}: ${formatPesoCompact(account.balance)}",
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          width: 140,
          height: 90,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  color: accentColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _CardHeader(
                          account: account,
                          accentColor: accentColor,
                          categoryLabel: _categoryLabel(),
                          categoryIcon: _categoryIcon(),
                        ),
                        _CardBalance(
                          account: account,
                          heldAmount: heldAmount,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final FinancialAccount account;
  final Color accentColor;
  final String categoryLabel;
  final IconData categoryIcon;

  const _CardHeader({
    required this.account,
    required this.accentColor,
    required this.categoryLabel,
    required this.categoryIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(categoryIcon, color: accentColor, size: 18),
        AppBadge(
          text: categoryLabel,
          color: accentColor,
          variant: AppBadgeVariant.tonal,
          size: AppBadgeSize.small,
        ),
      ],
    );
  }
}

class _CardBalance extends StatelessWidget {
  final FinancialAccount account;
  final double heldAmount;
  final ColorScheme colorScheme;

  const _CardBalance({
    required this.account,
    this.heldAmount = 0.0,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        AppNumberDisplay(
          value: account.isLiability
              ? 'Owed: ${formatPesoCompact(account.balance)}'
              : formatPesoCompact(account.balance),
          size: AppNumberSize.body,
          color: account.isLiability
              ? colorScheme.error
              : colorScheme.onSurfaceVariant,
        ),
        if (heldAmount > 0) ...[
          const SizedBox(height: 2),
          Text(
            '${formatPesoCompact(heldAmount)} held',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              fontStyle: FontStyle.italic,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}
