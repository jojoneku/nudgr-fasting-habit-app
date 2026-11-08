import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intermittent_fasting/utils/account_category_label.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/account_badge_widget.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// The redesigned Accounts section (`Nutrition Focus Treasury.dc.html`, Frame 1):
/// a section header with total liquid cash, per-account rows (icon badge, name,
/// sub-line, balance), and an "All N accounts" link that expands the list when
/// it runs beyond [collapsedCount]. Tapping a row opens the existing edit sheet.
///
/// Mobile has no account inventory screen, so "All N" expands this list in
/// place; N is the number of accounts this list holds.
class DashboardAccountsList extends StatefulWidget {
  final List<FinancialAccount> accounts;

  /// The line under each name: the type and any held amount, or
  /// "Overdrawn · check the last transfer"
  /// ([TreasuryDashboardPresenter.dashboardAccountSublines]).
  final Map<String, String> sublineByAccountId;

  /// Accounts below zero; their amount takes the warning tone
  /// ([TreasuryDashboardPresenter.overdrawnAccountIds]).
  final Set<String> overdrawnAccountIds;

  /// The amount each row shows: the balance less what is held for others.
  final Map<String, double> yoursByAccountId;
  final double totalLiquidCash;
  final ValueChanged<FinancialAccount> onEdit;

  /// Accounts shown before the "All N" link appears.
  final int collapsedCount;

  const DashboardAccountsList({
    super.key,
    required this.accounts,
    required this.sublineByAccountId,
    required this.overdrawnAccountIds,
    required this.yoursByAccountId,
    required this.totalLiquidCash,
    required this.onEdit,
    this.collapsedCount = 3,
  });

  @override
  State<DashboardAccountsList> createState() => _DashboardAccountsListState();
}

class _DashboardAccountsListState extends State<DashboardAccountsList> {
  bool _expanded = false;

  bool get _hasOverflow => widget.accounts.length > widget.collapsedCount;

  List<FinancialAccount> get _visible => (!_hasOverflow || _expanded)
      ? widget.accounts
      : widget.accounts.take(widget.collapsedCount).toList();

  String get _expanderLabel =>
      _expanded ? 'Show less' : 'All ${widget.accounts.length} accounts';

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

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
                subline: widget.sublineByAccountId[account.id] ??
                    account.category.label,
                overdrawn: widget.overdrawnAccountIds.contains(account.id),
                yours: widget.yoursByAccountId[account.id] ?? account.balance,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onEdit(account);
                },
              ),
            ),
          if (_hasOverflow)
            _ExpanderRow(
              expanded: _expanded,
              label: _expanderLabel,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final FinancialAccount account;
  final String subline;
  final bool overdrawn;
  final double yours;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.subline,
    required this.overdrawn,
    required this.yours,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = context.appColors;

    return AppCard(
      variant: AppCardVariant.elevated,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          AccountBadge.of(account),
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
                  subline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overdrawn ? appColors.bills : appColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Only liquid accounts reach this list (credit has its own
          // section), so there is no liability branch here.
          AppNumberDisplay(
            value: formatPesoMinus(yours),
            size: AppNumberSize.body,
            color: overdrawn ? appColors.bills : cs.onSurface,
          ),
        ],
      ),
    );
  }
}

class _ExpanderRow extends StatelessWidget {
  final bool expanded;
  final String label;
  final VoidCallback onTap;

  const _ExpanderRow({
    required this.expanded,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.appColors.textMuted;
    return InkWell(
      key: const ValueKey('dashboard.accounts.all'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
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
