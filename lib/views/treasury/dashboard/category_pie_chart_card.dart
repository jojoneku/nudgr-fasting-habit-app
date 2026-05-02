import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/full_category_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

class CategoryPieChartCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const CategoryPieChartCard({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final slices = presenter.categorySpendThisMonth;
    final total = slices.fold(0.0, (s, e) => s + e.$2);
    final hasMore = presenter.allCategorySpendThisMonth.length > slices.length;

    return AppSection(
      title: 'Expense Breakdown',
      trailing: hasMore
          ? GestureDetector(
              onTap: () => FullCategoryBreakdownSheet.show(context, presenter),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'View All',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right,
                        color: colorScheme.primary, size: 16),
                  ],
                ),
              ),
            )
          : null,
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: slices.isEmpty
            ? AppEmptyState(
                icon: Icons.pie_chart_outline_rounded,
                title: 'No expenses this month',
                iconSize: 32,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PieChart(slices: slices, total: total),
                  const SizedBox(width: 20),
                  Expanded(child: _Legend(slices: slices, total: total)),
                ],
              ),
      ),
    );
  }
}

class _PieChart extends StatefulWidget {
  final List<(FinanceCategory, double)> slices;
  final double total;

  const _PieChart({required this.slices, required this.total});

  @override
  State<_PieChart> createState() => _PieChartState();
}

class _PieChartState extends State<_PieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.value == 0 && !_controller.isAnimating) {
      if (MediaQuery.of(context).disableAnimations) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
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
      builder: (context, _) => SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          painter: _PieChartPainter(
            slices: widget.slices,
            total: widget.total,
            progress: _animation.value,
            textPrimaryColor: colorScheme.onSurface,
            textSecondaryColor: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<(FinanceCategory, double)> slices;
  final double total;
  final double progress;
  final Color textPrimaryColor;
  final Color textSecondaryColor;

  static const double _gapAngle = 0.04;
  static const double _strokeWidth = 22.0;

  _PieChartPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0 || slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - _strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;
    final totalGap = _gapAngle * slices.length;
    final availableAngle = (2 * math.pi - totalGap) * progress;

    for (int i = 0; i < slices.length; i++) {
      final (cat, amount) = slices[i];
      final sweepAngle = (amount / total) * availableAngle;
      final color = resolveSliceColor(cat.colorHex, i);

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.butt,
      );

      // Subtle glow
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth + 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..strokeCap = StrokeCap.butt,
      );

      startAngle += sweepAngle + _gapAngle;
    }

    // Center label
    if (progress > 0.8) {
      final label = formatPesoCompact(total);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: textPrimaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: 'DM Mono',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height + 1));

      final subTp = TextPainter(
        text: TextSpan(
          text: 'spent',
          style: TextStyle(
            color: textSecondaryColor,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      subTp.paint(canvas, center - Offset(subTp.width / 2, -3));
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.progress != progress || old.total != total;
}

class _Legend extends StatelessWidget {
  final List<(FinanceCategory, double)> slices;
  final double total;

  const _Legend({required this.slices, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < slices.length; i++) ...[
          _LegendRow(
            color: resolveSliceColor(slices[i].$1.colorHex, i),
            name: slices[i].$1.name,
            amount: slices[i].$2,
            percent: total > 0 ? slices[i].$2 / total : 0.0,
          ),
          if (i < slices.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String name;
  final double amount;
  final double percent;

  const _LegendRow({
    required this.color,
    required this.name,
    required this.amount,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)
            ],
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${(percent * 100).round()}%',
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        AppNumberDisplay(
          value: formatPesoCompact(amount),
          size: AppNumberSize.body,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
