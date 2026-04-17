import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

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
    final bills = widget.presenter.upcomingBills;
    final total = bills.fold(0.0, (sum, b) => sum + b.amount);
    final hasOverdue = bills.any(widget.presenter.isBillOverdue);
    final shown = _expanded ? bills : bills.take(_previewCount).toList();
    final hiddenCount = bills.length - _previewCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'UPCOMING BILLS', hasOverdue: hasOverdue),
        const SizedBox(height: 8),
        Card(
          color: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: AppColors.textSecondary.withOpacity(0.1),
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
                  height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
              _TotalFooter(total: total, hasOverdue: hasOverdue),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool hasOverdue;

  const _SectionHeader({required this.label, required this.hasOverdue});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: hasOverdue ? AppColors.danger : AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hasOverdue) ...[
          const SizedBox(width: 6),
          _OverduePulse(),
        ],
      ],
    );
  }
}

class _OverduePulse extends StatefulWidget {
  @override
  State<_OverduePulse> createState() => _OverduePulseState();
}

class _OverduePulseState extends State<_OverduePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'OVERDUE',
          style: TextStyle(
            color: AppColors.danger,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
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
    final nameColor = isOverdue ? AppColors.danger : AppColors.textPrimary;
    final dueLabel = isOverdue ? 'Overdue' : 'Due ${bill.dueDay}';
    final dueLabelColor =
        isOverdue ? AppColors.danger : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 16,
            color: isOverdue ? AppColors.danger : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  dueLabel,
                  style: TextStyle(color: dueLabelColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            formatPeso(bill.amount),
            style: AppTextStyles.mono(
              textStyle: TextStyle(
                color: isOverdue ? AppColors.danger : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.expand_more, size: 16, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              '+ $count more',
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.expand_less, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Show less',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Total unpaid',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            formatPeso(total),
            style: AppTextStyles.mono(
              textStyle: TextStyle(
                color: hasOverdue ? AppColors.danger : AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
