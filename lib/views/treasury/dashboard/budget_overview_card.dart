import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetOverviewCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const BudgetOverviewCard({super.key, required this.presenter});

  static const _groups = [
    BudgetGroup.nonNegotiables,
    BudgetGroup.livingExpense,
    BudgetGroup.variableOptional,
  ];

  static const _groupLabels = {
    BudgetGroup.nonNegotiables: 'Non-Negotiables',
    BudgetGroup.livingExpense: 'Living Expenses',
    BudgetGroup.variableOptional: 'Variable',
  };

  @override
  Widget build(BuildContext context) {
    final allocated = presenter.budgetAllocatedByGroup;
    final spent = presenter.budgetSpentByGroup;
    final totalAllocated = presenter.totalBudgetAllocated;
    final totalSpent = presenter.totalBudgetSpent;

    return AppSection(
      title: 'Budget This Month',
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            _BudgetProgressRow(
              label: 'Total',
              allocated: totalAllocated,
              spent: totalSpent,
              isTotal: true,
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            for (final group in _groups) ...[
              _BudgetProgressRow(
                label: _groupLabels[group]!,
                allocated: allocated[group] ?? 0.0,
                spent: spent[group] ?? 0.0,
                isTotal: false,
              ),
              if (group != _groups.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetProgressRow extends StatelessWidget {
  final String label;
  final double allocated;
  final double spent;
  final bool isTotal;

  const _BudgetProgressRow({
    required this.label,
    required this.allocated,
    required this.spent,
    required this.isTotal,
  });

  Color _progressColor(double ratio, ColorScheme colorScheme) {
    if (ratio >= 1.0) return colorScheme.error;
    if (ratio >= 0.75) return const Color(0xFFFFB300);
    return colorScheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ratio = allocated > 0 ? (spent / allocated).clamp(0.0, 1.0) : 0.0;
    final barColor =
        _progressColor(allocated > 0 ? spent / allocated : 0.0, colorScheme);
    final percentText =
        allocated > 0 ? '${(spent / allocated * 100).round()}%' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: (isTotal
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                  fontWeight:
                      isTotal ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              percentText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: barColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            AppNumberDisplay(
              value: '${formatPesoCompact(spent)} / ${formatPesoCompact(allocated)}',
              size: AppNumberSize.body,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 5),
        _AnimatedProgressBar(
          ratio: ratio,
          color: barColor,
          height: isTotal ? 6.0 : 4.0,
        ),
      ],
    );
  }
}

class _AnimatedProgressBar extends StatefulWidget {
  final double ratio;
  final Color color;
  final double height;

  const _AnimatedProgressBar({
    required this.ratio,
    required this.color,
    required this.height,
  });

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0.0, end: widget.ratio).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ratio != widget.ratio) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.ratio,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => AppLinearProgress(
        value: _animation.value,
        color: widget.color,
        backgroundColor: colorScheme.surfaceContainerHighest,
        height: widget.height,
      ),
    );
  }
}
