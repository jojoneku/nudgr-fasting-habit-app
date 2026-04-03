import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

class AccountCardWidget extends StatelessWidget {
  final FinancialAccount account;
  final VoidCallback? onTap;

  const AccountCardWidget({super.key, required this.account, this.onTap});

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
        return 'Custodian';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _parseColor();

    return Semantics(
      label: "${account.name}, ${account.isLiability ? 'Owed' : 'Balance'}: ${formatPesoCompact(account.balance)}",
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 160,
            height: 130,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: accentColor, width: 3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CardHeader(account: account, accentColor: accentColor, categoryLabel: _categoryLabel()),
                  _CardBalance(account: account),
                ],
              ),
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
        Icon(Icons.account_balance_wallet, color: accentColor, size: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            categoryLabel,
            style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _CardBalance extends StatelessWidget {
  final FinancialAccount account;

  const _CardBalance({required this.account});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          account.isLiability
              ? 'Owed: ${formatPesoCompact(account.balance)}'
              : formatPesoCompact(account.balance),
          style: TextStyle(
            color: account.isLiability ? AppColors.danger : AppColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
