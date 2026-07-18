import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The redesigned Accounts section (`Nutrition Focus Treasury.dc.html`, Frame 1):
/// a section header with total liquid cash, per-account rows (icon badge, name,
/// type subtitle, balance), and a "+N more accounts" expander when the list runs
/// beyond [collapsedCount]. Tapping a row opens the existing edit sheet.
class DashboardAccountsList extends StatefulWidget {
  final List<FinancialAccount> accounts;
  final Map<String, double> heldByAccountId;
  final double totalLiquidCash;
  final ValueChanged<FinancialAccount> onEdit;

  /// Accounts shown before the "+N more" expander appears.
  final int collapsedCount;

  const DashboardAccountsList({
    super.key,
    required this.accounts,
    required this.heldByAccountId,
    required this.totalLiquidCash,
    required this.onEdit,
    this.collapsedCount = 3,
  });

  @override
  State<DashboardAccountsList> createState() => _DashboardAccountsListState();
}

class _DashboardAccountsListState extends State<DashboardAccountsList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts;
    final overflow = accounts.length - widget.collapsedCount;
    final hasOverflow = overflow > 0;
    final visible = (!hasOverflow || _expanded)
        ? accounts
        : accounts.take(widget.collapsedCount).toList();

    return AppSection(
      title: 'Accounts',
      trailing: Text(
        '${formatPeso(widget.totalLiquidCash)} liquid',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: context.appColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
      ),
      child: Column(
        children: [
          for (final account in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _AccountRow(
                account: account,
                heldAmount: widget.heldByAccountId[account.id] ?? 0.0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onEdit(account);
                },
              ),
            ),
          if (hasOverflow)
            _ExpanderRow(
              expanded: _expanded,
              overflow: overflow,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final FinancialAccount account;
  final double heldAmount;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.heldAmount,
    required this.onTap,
  });

  Color _accent(BuildContext context) {
    try {
      final hex = account.colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = _accent(context);
    final hasHeld = heldAmount > 0 && !account.isLiability;
    final shown = hasHeld ? account.balance - heldAmount : account.balance;

    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _accountIcon(account.category),
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasHeld
                      ? '${_accountCategoryLabel(account.category)} · ${formatPeso(heldAmount)} held'
                      : _accountCategoryLabel(account.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppNumberDisplay(
            value: account.isLiability
                ? 'Owed: ${formatPeso(account.balance)}'
                : formatPeso(shown),
            size: AppNumberSize.body,
            color: account.isLiability ? cs.error : cs.onSurface,
          ),
        ],
      ),
    );
  }
}

class _ExpanderRow extends StatelessWidget {
  final bool expanded;
  final int overflow;
  final VoidCallback onTap;

  const _ExpanderRow({
    required this.expanded,
    required this.overflow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.appColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? 'Show less' : '+$overflow more accounts',
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _accountIcon(AccountCategory category) => switch (category) {
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

String _accountCategoryLabel(AccountCategory category) => switch (category) {
      AccountCategory.bank => 'Bank',
      AccountCategory.ewallet => 'eWallet',
      AccountCategory.cash => 'Cash',
      AccountCategory.savings => 'Savings',
      AccountCategory.goal => 'Goal',
      AccountCategory.timeDeposit => 'Time deposit',
      AccountCategory.creditCard => 'Credit card',
      AccountCategory.creditLine => 'Credit line',
      AccountCategory.bnpl => 'BNPL',
      AccountCategory.investment => 'Investment',
      AccountCategory.custodian => 'External',
    };
