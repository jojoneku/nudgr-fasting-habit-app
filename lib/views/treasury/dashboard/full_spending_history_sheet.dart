import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intermittent_fasting/utils/app_text_styles.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intl/intl.dart';

class FullSpendingHistorySheet extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const FullSpendingHistorySheet({super.key, required this.presenter});

  static void show(BuildContext context, TreasuryDashboardPresenter presenter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FullSpendingHistorySheet(presenter: presenter),
    );
  }

  @override
  State<FullSpendingHistorySheet> createState() =>
      _FullSpendingHistorySheetState();
}

class _FullSpendingHistorySheetState extends State<FullSpendingHistorySheet> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final data = widget.presenter.lastNDaysSpending(_days);
    final peak = data.fold(0.0, (m, d) => d.amount > m ? d.amount : m);
    final total = data.fold(0.0, (s, d) => s + d.amount);
    final nonZero = data.where((d) => d.amount > 0).toList();
    final avg = nonZero.isEmpty
        ? 0.0
        : nonZero.fold(0.0, (s, d) => s + d.amount) / nonZero.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _Handle(),
          _Header(total: total, avg: avg, peak: peak),
          _RangeSelector(
              selected: _days, onChanged: (v) => setState(() => _days = v)),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  SizedBox(
                    height: 160,
                    child: _FullBarChart(days: data, peak: peak),
                  ),
                  const SizedBox(height: 16),
                  ...data.reversed
                      .where((d) => d.amount > 0)
                      .map((d) => _DayRow(day: d, peak: peak)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final double total;
  final double avg;
  final double peak;

  const _Header({required this.total, required this.avg, required this.peak});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAILY SPENDING',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatPeso(total),
                  style: AppTextStyles.mono(
                    textStyle: TextStyle(
                      color: AppColors.danger,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Avg ${formatPesoCompact(avg)}/day',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
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
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                formatPesoCompact(peak),
                style: AppTextStyles.mono(
                  textStyle: const TextStyle(
                    color: Color(0xFFEF9A9A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _RangeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [7, 14, 30, 90];
    const labels = ['7D', '2W', '30D', '90D'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            GestureDetector(
              onTap: () => onChanged(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: selected == options[i]
                      ? AppColors.accent.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected == options[i]
                        ? AppColors.accent
                        : AppColors.textSecondary.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: selected == options[i]
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (i < options.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
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
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => CustomPaint(
        painter: _FullBarPainter(
            days: widget.days, peak: widget.peak, progress: _anim.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FullBarPainter extends CustomPainter {
  final List<DailySpend> days;
  final double peak;
  final double progress;

  static const double _labelH = 16.0;
  static const double _topPad = 10.0;

  _FullBarPainter(
      {required this.days, required this.peak, required this.progress});

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
          ..color = AppColors.textSecondary.withOpacity(0.07)
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
            colors: [AppColors.accent.withOpacity(0.6), AppColors.accent],
          ).createShader(Rect.fromLTWH(x, barTop, barW, barH));
        } else {
          paint.color = AppColors.accent.withOpacity(0.38);
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
                  ? AppColors.accent
                  : AppColors.textSecondary.withOpacity(0.5),
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
    final isPeak = peak > 0 && day.amount == peak;
    final ratio = peak > 0 ? day.amount / peak : 0.0;
    final barColor = isPeak ? const Color(0xFFEF9A9A) : AppColors.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              DateFormat('MMM d').format(day.date),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: AppColors.textSecondary.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(barColor),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              formatPesoCompact(day.amount),
              textAlign: TextAlign.right,
              style: AppTextStyles.mono(
                textStyle: TextStyle(
                  color:
                      isPeak ? const Color(0xFFEF9A9A) : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
