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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          header: HubCardHeader(
            icon: isActive
                ? Icons.account_balance
                : Icons.account_balance_outlined,
            title: 'Finance',
            accentColor: context.appColors.gold,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCol(
                  label: 'EXPENSE',
                  value: formatPesoCompact(treasury.monthTotalOutflow),
                  color: theme.colorScheme.error,
                  align: CrossAxisAlignment.start,
                ),
              ),
              _Divider(theme: theme),
              Expanded(
                child: _StatCol(
                  label: 'INCOME',
                  value: formatPesoCompact(treasury.monthTotalInflow),
                  color: theme.colorScheme.tertiary,
                  align: CrossAxisAlignment.center,
                ),
              ),
              _Divider(theme: theme),
              Expanded(
                child: _StatCol(
                  label: 'ENDING',
                  value: formatPesoCompact(treasury.endingCash),
                  color: treasury.endingCash >= 0
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.error,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ),
        if (isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          _BillWarning(treasury: treasury),
        ],
      ],
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({
    required this.label,
    required this.value,
    required this.color,
    required this.align,
  });
  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment align;

  TextAlign get _textAlign => switch (align) {
        CrossAxisAlignment.end => TextAlign.end,
        CrossAxisAlignment.center => TextAlign.center,
        _ => TextAlign.start,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
          textAlign: _textAlign,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.numeric(fontSize: 16, weight: FontWeight.w700)
              .copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: _textAlign,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: AppSpacing.sm,
      thickness: 0.5,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
