import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/shared/budget_status_color.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class BudgetOverviewCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  /// Switches the Treasury module to the Budget tab. Null hides the link
  /// (e.g. a standalone mount in tests).
  final VoidCallback? onOpenBudget;

  const BudgetOverviewCard({
    super.key,
    required this.presenter,
    this.onOpenBudget,
  });

  @override
  Widget build(BuildContext context) {
    // Expense groups only (savings has its own card), with groups that have
    // nothing allocated and nothing spent left out. The Total uses expense
    // totals so it reconciles with the rows below it.
    final rows = presenter.budgetHealthRows(includeSavings: false);
    final total = presenter.budgetHealthExpenseTotal;

    return AppSection(
      title: 'Budget This Month',
      trailing: onOpenBudget == null
          ? null
          : TextButton(
              key: const ValueKey('dashboard.budget.open'),
              onPressed: onOpenBudget,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: const Text('Open budget'),
            ),
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            _BudgetProgressRow(row: total, isTotal: true),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < rows.length; i++) ...[
              _BudgetProgressRow(row: rows[i], isTotal: false),
              if (i < rows.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetProgressRow extends StatelessWidget {
  final BudgetHealthRow row;
  final bool isTotal;

  const _BudgetProgressRow({required this.row, required this.isTotal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Same status rule and tones as the Budget tab and web: Watch and Over in
    // the warning tone, with the status also written out below the bar.
    final barColor = budgetStatusColor(context, row.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon badge — same tinted treatment as the other dashboard cards.
        Container(
          width: isTotal ? 34 : 30,
          height: isTotal ? 34 : 30,
          decoration: BoxDecoration(
            color: barColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            isTotal
                ? Icons.account_balance_wallet_outlined
                : Icons.pie_chart_outline_rounded,
            size: isTotal ? 17 : 15,
            color: barColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: (isTotal
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodySmall)
                          ?.copyWith(
                        fontWeight: isTotal ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    row.percentLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: barColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppNumberDisplay(
                    value:
                        '${formatPesoCompact(row.spent)} / ${formatPesoCompact(row.allocated)}',
                    size: AppNumberSize.body,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _AnimatedProgressBar(
                ratio: row.progress,
                color: barColor,
                height: isTotal ? 6.0 : 4.0,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(budgetStatusIcon(row.status), size: 12, color: barColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      row.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: barColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
