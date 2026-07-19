import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
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

  Color _parseColor(BuildContext context) {
    try {
      final hex = account.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.tertiary;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = _parseColor(context);

    final hasHeld = heldAmount > 0 && !account.isLiability;
    final shownBalance =
        hasHeld ? account.balance - heldAmount : account.balance;
    return Semantics(
      label:
          "${account.name}, ${account.isLiability ? 'Owed' : (hasHeld ? 'Yours' : 'Balance')}: ${formatPeso(shownBalance)}",
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          // Fill the grid cell instead of forcing 140px — on a 360px phone the
          // 3-column cell is only ~110px wide, so a fixed width clipped the
          // name and balance. The grid's mainAxisExtent already fixes height.
          width: double.infinity,
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

  const _CardHeader({
    required this.account,
    required this.accentColor,
    required this.categoryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AccountBadge.of(account, size: 30),
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
    final hasHeld = heldAmount > 0 && !account.isLiability;
    final yours = account.balance - heldAmount;

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
        // Full peso amounts can be wider than the ~110px 3-column cell, so
        // scale the number down to fit rather than clip or overflow.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AppNumberDisplay(
            value: account.isLiability
                ? 'Owed: ${formatPeso(account.balance)}'
                : formatPeso(hasHeld ? yours : account.balance),
            size: AppNumberSize.body,
            color: account.isLiability
                ? colorScheme.error
                : colorScheme.onSurfaceVariant,
          ),
        ),
        if (hasHeld) ...[
          const SizedBox(height: 2),
          Text(
            'of ${formatPeso(account.balance)} · '
            '${formatPeso(heldAmount)} held',
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
