import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/full_spending_history_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

class SpendingAnalyticsCard extends StatelessWidget {
  final TreasuryDashboardPresenter presenter;

  const SpendingAnalyticsCard({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final days = presenter.last7DaysSpending;
    final peak = presenter.peakDaySpend7;
    final avg = presenter.avgDailySpend7;
    final hasData = days.any((d) => d.amount > 0);

    return AppSection(
      title: 'Spending — Last 7 Days',
      trailing: GestureDetector(
        onTap: () => FullSpendingHistorySheet.show(context, presenter),
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
            SizedBox(
              height: 120,
              child: hasData
                  ? _BarChart(days: days, peak: peak)
                  : AppEmptyState(
                      icon: Icons.bar_chart_rounded,
                      title: 'No spending recorded yet',
                      iconSize: 36,
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
              peakDay: presenter.peakSpendDay,
              todaySpend: days.isNotEmpty ? days.last.amount : 0.0,
            ),
          ],
        ),
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

  static const double _labelHeight = 20.0;
  static const double _topPad = 16.0;
  static const double _barRadius = 4.0;
  static const double _barSpacing = 6.0;
  // Softer red — avoids the hallation/vibration of pure #FF1744 on dark bg
  static const Color _peakColor = Color(0xFFEF9A9A);

  _BarChartPainter({
    required this.days,
    required this.peak,
    required this.progress,
    required this.primaryColor,
    required this.onSurfaceVariantColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final barAreaTop = _topPad;
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
        barColor = _peakColor;
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
            style: const TextStyle(
              color: _peakColor,
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
                color: primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w800)
            : labelStyle,
      );
      final tp = TextPainter(
        text: labelSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
            x + barWidth / 2 - tp.width / 2, size.height - _labelHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.progress != progress || old.peak != peak;
}

class _StatsRow extends StatelessWidget {
  final double avgDaily;
  final double peak;
  final DateTime? peakDay;
  final double todaySpend;

  const _StatsRow({
    required this.avgDaily,
    required this.peak,
    required this.peakDay,
    required this.todaySpend,
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
          label: 'TODAY',
          value: formatPesoCompact(todaySpend),
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
              ? const Color(0xFFEF9A9A)
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
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}
