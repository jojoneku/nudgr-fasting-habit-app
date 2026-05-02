import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

class FullSpendingHistorySheet extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const FullSpendingHistorySheet({super.key, required this.presenter});

  static void show(BuildContext context, TreasuryDashboardPresenter presenter) {
    AppBottomSheet.show(
      context: context,
      title: 'Daily Spending',
      useDraggableScrollableSheet: true,
      initialChildSize: 0.82,
      body: _SpendingHistoryBody(presenter: presenter),
    );
  }

  @override
  State<FullSpendingHistorySheet> createState() =>
      _FullSpendingHistorySheetState();
}

class _FullSpendingHistorySheetState extends State<FullSpendingHistorySheet> {
  @override
  Widget build(BuildContext context) {
    return _SpendingHistoryBody(presenter: widget.presenter);
  }
}

class _SpendingHistoryBody extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const _SpendingHistoryBody({required this.presenter});

  @override
  State<_SpendingHistoryBody> createState() => _SpendingHistoryBodyState();
}

class _SpendingHistoryBodyState extends State<_SpendingHistoryBody> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final data = widget.presenter.lastNDaysSpending(_days);
    final peak = data.fold(0.0, (m, d) => d.amount > m ? d.amount : m);
    final total = data.fold(0.0, (s, d) => s + d.amount);
    final nonZero = data.where((d) => d.amount > 0).toList();
    final avg = nonZero.isEmpty
        ? 0.0
        : nonZero.fold(0.0, (s, d) => s + d.amount) / nonZero.length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            total: total,
            avg: avg,
            peak: peak,
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(height: 8),
          _RangeSelector(
            selected: _days,
            onChanged: (v) => setState(() => _days = v),
            colorScheme: colorScheme,
            theme: theme,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: _FullBarChart(days: data, peak: peak),
          ),
          const SizedBox(height: 16),
          ...data.reversed
              .where((d) => d.amount > 0)
              .map((d) => _DayRow(day: d, peak: peak)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final double total;
  final double avg;
  final double peak;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _Header({
    required this.total,
    required this.avg,
    required this.peak,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppNumberDisplay(
                value: formatPeso(total),
                size: AppNumberSize.title,
                color: colorScheme.error,
              ),
              Text(
                'Avg ${formatPesoCompact(avg)}/day',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'PEAK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
            AppNumberDisplay(
              value: formatPesoCompact(peak),
              size: AppNumberSize.body,
              color: const Color(0xFFEF9A9A),
            ),
          ],
        ),
      ],
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _RangeSelector({
    required this.selected,
    required this.onChanged,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const options = [7, 14, 30, 90];
    const labels = ['7D', '2W', '30D', '90D'];

    return Row(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          GestureDetector(
            onTap: () => onChanged(options[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: selected == options[i]
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected == options[i]
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                labels[i],
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected == options[i]
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (i < options.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _FullBarChart extends StatefulWidget {
  final List<DailySpend> days;
  final double peak;

  const _FullBarChart({required this.days, required this.peak});

  @override
  State<_FullBarChart> createState() => _FullBarChartState();
}

class _FullBarChartState extends State<_FullBarChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_FullBarChart old) {
    super.didUpdateWidget(old);
    if (old.days.length != widget.days.length) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => CustomPaint(
        painter: _FullBarPainter(
          days: widget.days,
          peak: widget.peak,
          progress: _anim.value,
          primaryColor: colorScheme.primary,
          onSurfaceVariantColor: colorScheme.onSurfaceVariant,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FullBarPainter extends CustomPainter {
  final List<DailySpend> days;
  final double peak;
  final double progress;
  final Color primaryColor;
  final Color onSurfaceVariantColor;

  static const double _labelH = 16.0;
  static const double _topPad = 10.0;

  _FullBarPainter({
    required this.days,
    required this.peak,
    required this.progress,
    required this.primaryColor,
    required this.onSurfaceVariantColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final barAreaH = size.height - _labelH - _topPad;
    final totalBars = days.length;
    const spacing = 3.0;
    final barW = (size.width - spacing * (totalBars - 1)) / totalBars;
    final today = DateTime.now();

    for (int i = 0; i < totalBars; i++) {
      final day = days[i];
      final x = i * (barW + spacing);
      final isToday = day.date.day == today.day &&
          day.date.month == today.month &&
          day.date.year == today.year;

      final ratio = peak > 0 ? (day.amount / peak) * progress : 0.0;
      final barH = barAreaH * ratio;

      // Track
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, _topPad, barW, barAreaH),
          const Radius.circular(3),
        ),
        Paint()
          ..color = onSurfaceVariantColor.withValues(alpha: 0.07)
          ..style = PaintingStyle.fill,
      );

      if (barH > 0) {
        final barTop = _topPad + barAreaH - barH;
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, barTop, barW, barH),
          const Radius.circular(3),
        );
        final paint = Paint()..style = PaintingStyle.fill;
        if (isToday) {
          paint.shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              primaryColor.withValues(alpha: 0.6),
              primaryColor,
            ],
          ).createShader(Rect.fromLTWH(x, barTop, barW, barH));
        } else {
          paint.color = primaryColor.withValues(alpha: 0.38);
        }
        canvas.drawRRect(barRect, paint);
      }

      // Day labels — only show for certain intervals to avoid clutter
      final showLabel = totalBars <= 14 ||
          (totalBars <= 31 && day.date.day % 5 == 0) ||
          (totalBars > 31 && day.date.day % 10 == 0) ||
          isToday;

      if (showLabel) {
        final label = isToday
            ? '•'
            : DateFormat(totalBars <= 14 ? 'E' : 'd').format(day.date);
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: isToday
                  ? primaryColor
                  : onSurfaceVariantColor.withValues(alpha: 0.5),
              fontSize: totalBars <= 14 ? 9.0 : 8.0,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.normal,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (x + barW / 2 - tp.width / 2).clamp(0.0, size.width - tp.width),
            size.height - _labelH + 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FullBarPainter old) =>
      old.progress != progress ||
      old.peak != peak ||
      old.days.length != days.length;
}

class _DayRow extends StatelessWidget {
  final DailySpend day;
  final double peak;

  const _DayRow({required this.day, required this.peak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPeak = peak > 0 && day.amount == peak;
    final ratio = peak > 0 ? day.amount / peak : 0.0;
    final barColor = isPeak ? const Color(0xFFEF9A9A) : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              DateFormat('MMM d').format(day.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppLinearProgress(
              value: ratio,
              color: barColor,
              backgroundColor: colorScheme.surfaceContainerHighest,
              height: 6,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: AppNumberDisplay(
              value: formatPesoCompact(day.amount),
              size: AppNumberSize.body,
              color: isPeak ? const Color(0xFFEF9A9A) : colorScheme.onSurface,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
