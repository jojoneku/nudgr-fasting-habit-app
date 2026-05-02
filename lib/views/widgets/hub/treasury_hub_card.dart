import 'package:flutter/material.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../../../utils/finance_format.dart';
import 'hub_card_header.dart';

class TreasuryHubCard extends StatelessWidget {
  const TreasuryHubCard({
    super.key,
    required this.treasury,
    required this.onNavigate,
  });

  final TreasuryDashboardPresenter treasury;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: treasury,
      builder: (context, _) {
        final isActive = treasury.hasBillImminent;
        return AppCard(
          onTap: onNavigate,
          header: HubCardHeader(
            icon: isActive
                ? Icons.account_balance
                : Icons.account_balance_outlined,
            title: 'Finance',
            accentColor: AppColors.gold,
            isActive: isActive,
          ),
          child: _Snapshot(treasury: treasury, isActive: isActive),
        );
      },
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.treasury, required this.isActive});
  final TreasuryDashboardPresenter treasury;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todaySpend = treasury.todayOutflow;
    final remaining = treasury.totalBudgetRemaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatPesoCompact(todaySpend),
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(width: 6),
            Text(
              'today',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (treasury.hasBudget) ...[
          const SizedBox(height: AppSpacing.xs),
          AppStatPill(
            label: 'Budget left',
            value: formatPesoCompact(remaining),
            color: remaining > 0 ? AppStatColor.success : AppStatColor.error,
            size: AppStatSize.small,
          ),
        ],
        if (isActive) ...[
          const SizedBox(height: AppSpacing.xs),
          _BillWarning(treasury: treasury),
        ],
      ],
    );
  }
}

class _BillWarning extends StatelessWidget {
  const _BillWarning({required this.treasury});
  final TreasuryDashboardPresenter treasury;

  @override
  Widget build(BuildContext context) {
    final bill = treasury.imminentBill;
    if (bill == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final today = DateTime.now().day;
    final label = bill.dueDay == today ? 'Due today' : 'Due tomorrow';

    return Row(
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 14, color: theme.colorScheme.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label · ${bill.name}',
            style: AppTextStyles.bodySmall
                .copyWith(color: theme.colorScheme.error),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
