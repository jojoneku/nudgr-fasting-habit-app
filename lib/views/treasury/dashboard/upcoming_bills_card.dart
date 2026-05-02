import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class UpcomingBillsCard extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const UpcomingBillsCard({super.key, required this.presenter});

  @override
  State<UpcomingBillsCard> createState() => _UpcomingBillsCardState();
}

class _UpcomingBillsCardState extends State<UpcomingBillsCard> {
  bool _expanded = false;

  static const int _previewCount = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bills = widget.presenter.upcomingBills;
    final total = bills.fold(0.0, (sum, b) => sum + b.amount);
    final hasOverdue = bills.any(widget.presenter.isBillOverdue);
    final shown = _expanded ? bills : bills.take(_previewCount).toList();
    final hiddenCount = bills.length - _previewCount;

    return AppSection(
      title: 'Upcoming Bills',
      trailing: hasOverdue
          ? AppBadge(
              text: 'Overdue',
              color: colorScheme.error,
              variant: AppBadgeVariant.tonal,
              size: AppBadgeSize.small,
            )
          : null,
      child: AppCard(
        variant: AppCardVariant.elevated,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (int i = 0; i < shown.length; i++) ...[
              _BillRow(
                bill: shown[i],
                isOverdue: widget.presenter.isBillOverdue(shown[i]),
              ),
              if (i < shown.length - 1 || !_expanded && hiddenCount > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
            ],
            if (!_expanded && hiddenCount > 0)
              _ExpandRow(
                count: hiddenCount,
                onTap: () => setState(() => _expanded = true),
              ),
            if (_expanded && bills.length > _previewCount)
              _CollapseRow(onTap: () => setState(() => _expanded = false)),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _TotalFooter(total: total, hasOverdue: hasOverdue),
          ],
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final Bill bill;
  final bool isOverdue;

  const _BillRow({required this.bill, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final nameColor = isOverdue ? colorScheme.error : colorScheme.onSurface;
    final dueLabel = isOverdue ? 'Overdue' : 'Due ${bill.dueDay}';
    final dueLabelColor = isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant;

    return AppListTile(
      leading: Icon(
        Icons.receipt_long_outlined,
        size: 16,
        color: isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
      title: Text(
        bill.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: nameColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        dueLabel,
        style: theme.textTheme.bodySmall?.copyWith(color: dueLabelColor),
      ),
      trailing: AppNumberDisplay(
        value: formatPeso(bill.amount),
        size: AppNumberSize.body,
        color: isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ExpandRow extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ExpandRow({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.expand_more, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '+ $count more',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapseRow extends StatelessWidget {
  final VoidCallback onTap;

  const _CollapseRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.expand_less, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Show less',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalFooter extends StatelessWidget {
  final double total;
  final bool hasOverdue;

  const _TotalFooter({required this.total, required this.hasOverdue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total unpaid',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          AppNumberDisplay(
            value: formatPeso(total),
            size: AppNumberSize.body,
            color: hasOverdue ? colorScheme.error : colorScheme.onSurface,
          ),
        ],
      ),
    );
  }
}
