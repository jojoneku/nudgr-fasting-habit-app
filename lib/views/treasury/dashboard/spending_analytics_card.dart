import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/full_spending_history_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

enum _SpendRange {
  last7('7D'),
  last30('30D'),
  thisMonth('This mo'),
  lastMonth('Last mo');

  const _SpendRange(this.label);
  final String label;
}

class SpendingAnalyticsCard extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const SpendingAnalyticsCard({super.key, required this.presenter});

  @override
  State<SpendingAnalyticsCard> createState() => _SpendingAnalyticsCardState();
}

class _SpendingAnalyticsCardState extends State<SpendingAnalyticsCard> {
  _SpendRange _range = _SpendRange.last7;

  (DateTime, DateTime) _rangeDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _SpendRange.last7:
        return (today.subtract(const Duration(days: 6)), today);
      case _SpendRange.last30:
        return (today.subtract(const Duration(days: 29)), today);
      case _SpendRange.thisMonth:
        return (DateTime(now.year, now.month, 1), today);
      case _SpendRange.lastMonth:
        final lastEnd =
            DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
        return (DateTime(lastEnd.year, lastEnd.month, 1), lastEnd);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (start, end) = _rangeDates();
    final days = widget.presenter.dailySpendForRange(start, end);
    final hasData = days.any((d) => d.amount > 0);
    final peak = days.fold(0.0, (m, d) => d.amount > m ? d.amount : m);
    final nonZero = days.where((d) => d.amount > 0).toList();
    final avg = nonZero.isEmpty
        ? 0.0
        : nonZero.fold(0.0, (s, d) => s + d.amount) / nonZero.length;
    final total = days.fold(0.0, (s, d) => s + d.amount);
    final peakDay = hasData
        ? days.reduce((a, b) => a.amount >= b.amount ? a : b).date
        : null;

    return AppSection(
      title: 'Spending',
      trailing: GestureDetector(
        onTap: () => FullSpendingHistorySheet.show(context, widget.presenter),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Text(
                'View Full',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, color: colorScheme.primary, size: 16),
            ],
          ),
        ),
      ),
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            _RangeSelector(
              value: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 120,
              child: hasData
                  ? _BarChart(days: days, peak: peak)
                  : const AppEmptyState(
                      icon: Icons.bar_chart_rounded,
                      title: 'No spending in this range',
                      iconSize: 36,
                      padding: EdgeInsets.all(AppSpacing.md),
                    ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            _StatsRow(
              avgDaily: avg,
              peak: peak,
              peakDay: peakDay,
              total: total,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact segmented control for the spending window.
class _RangeSelector extends StatelessWidget {
  final _SpendRange value;
  final ValueChanged<_SpendRange> onChanged;

  const _RangeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final r in _SpendRange.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == value ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          r == value ? FontWeight.w700 : FontWeight.w600,
                      color: r == value ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarChart extends StatefulWidget {
  final List<DailySpend> days;
  final double peak;

  const _BarChart({required this.days, required this.peak});

  @override
  State<_BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<_BarChart>
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
      builder: (context, _) => CustomPaint(
        painter: _BarChartPainter(
          days: widget.days,
          peak: widget.peak,
          progress: _animation.value,
          primaryColor: colorScheme.primary,
          onSurfaceVariantColor: colorScheme.onSurfaceVariant,
          peakColor: colorScheme.errorContainer,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailySpend> days;
  final double peak;
  final double progress;
  final Color primaryColor;
  final Color onSurfaceVariantColor;
  final Color peakColor;

  static const double _labelHeight = 20.0;
  static const double _topPad = 16.0;
  static const double _barRadius = 4.0;
  static const double _barSpacing = 6.0;

  _BarChartPainter({
    required this.days,
    required this.peak,
    required this.progress,
    required this.primaryColor,
    required this.onSurfaceVariantColor,
    required this.peakColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const barAreaTop = _topPad;
    final barAreaBottom = size.height - _labelHeight - 4;
    final barAreaH = barAreaBottom - barAreaTop;

    final totalBars = days.length;
    final barWidth = (size.width - (_barSpacing * (totalBars - 1))) / totalBars;
    final today = DateTime.now();

    final labelStyle = TextStyle(
      color: onSurfaceVariantColor.withValues(alpha: 0.7),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < totalBars; i++) {
      final day = days[i];
      final x = i * (barWidth + _barSpacing);
      final isToday = day.date.day == today.day &&
          day.date.month == today.month &&
          day.date.year == today.year;
      final isPeak = peak > 0 && day.amount == peak;

      final ratio = peak > 0 ? (day.amount / peak) * progress : 0.0;
      final barH = barAreaH * ratio;

      // Colors
      final Color barColor;
      if (isToday) {
        barColor = primaryColor;
      } else if (isPeak) {
        barColor = peakColor;
      } else if (day.amount > 0) {
        barColor = primaryColor.withValues(alpha: 0.4);
      } else {
        barColor = onSurfaceVariantColor.withValues(alpha: 0.1);
      }

      // Background track
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, barAreaTop, barWidth, barAreaH),
          const Radius.circular(_barRadius),
        ),
        Paint()
          ..color = onSurfaceVariantColor.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );

      // Bar
      if (barH > 0) {
        final barTop = barAreaBottom - barH;
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, barTop, barWidth, barH),
          const Radius.circular(_barRadius),
        );

        final barPaint = Paint()..style = PaintingStyle.fill;
        if (isToday) {
          barPaint.shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              primaryColor.withValues(alpha: 0.6),
              primaryColor,
            ],
          ).createShader(Rect.fromLTWH(x, barTop, barWidth, barH));
        } else {
          barPaint.color = barColor;
        }

        canvas.drawRRect(barRect, barPaint);

        // Glow for today's bar
        if (isToday && barH > 4) {
          canvas.drawRRect(
            barRect,
            Paint()
              ..color = primaryColor.withValues(alpha: 0.18)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }

        // Peak value label above bar
        if (isPeak && progress > 0.9) {
          final amountSpan = TextSpan(
            text: formatPesoCompact(day.amount),
            style: TextStyle(
              color: peakColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          );
          final tp = TextPainter(
            text: amountSpan,
            textDirection: ui.TextDirection.ltr,
          )..layout();
          final labelX = (x + barWidth / 2 - tp.width / 2)
              .clamp(0.0, size.width - tp.width);
          final labelY = (barTop - tp.height - 2).clamp(0.0, barTop);
          tp.paint(canvas, Offset(labelX, labelY));
        }
      }

      // Day label at bottom
      final dayLabel = DateFormat('E').format(day.date).substring(0, 1);
      final labelSpan = TextSpan(
        text: isToday ? '•' : dayLabel,
        style: isToday
            ? TextStyle(
                color: primaryColor, fontSize: 11, fontWeight: FontWeight.w800)
            : labelStyle,
      );
      final tp = TextPainter(
        text: labelSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x + barWidth / 2 - tp.width / 2, size.height - _labelHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.progress != progress ||
      old.peak != peak ||
      old.peakColor != peakColor;
}

class _StatsRow extends StatelessWidget {
  final double avgDaily;
  final double peak;
  final DateTime? peakDay;
  final double total;

  const _StatsRow({
    required this.avgDaily,
    required this.peak,
    required this.peakDay,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final peakLabel =
        peakDay != null ? DateFormat('EEE, MMM d').format(peakDay!) : '—';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatChip(
          label: 'TOTAL',
          value: formatPesoCompact(total),
          color: colorScheme.primary,
        ),
        _StatDivider(),
        _StatChip(
          label: 'AVG / DAY',
          value: formatPesoCompact(avgDaily),
          color: colorScheme.onSurfaceVariant,
        ),
        _StatDivider(),
        _StatChip(
          label: 'PEAK DAY',
          value: peakLabel,
          subValue: formatPesoCompact(peak),
          color: peak > 0
              ? colorScheme.errorContainer
              : colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 3),
        AppNumberDisplay(
          value: value,
          size: AppNumberSize.body,
          color: color,
        ),
        if (subValue != null) ...[
          const SizedBox(height: 1),
          AppNumberDisplay(
            value: subValue!,
            size: AppNumberSize.body,
            color: color.withValues(alpha: 0.75),
          ),
        ],
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}
