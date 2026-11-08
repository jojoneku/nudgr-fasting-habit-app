import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/app_spacing.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/dashboard_header_link.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/full_spending_history_sheet.dart';
import 'package:intermittent_fasting/views/treasury/dashboard/statement_card.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';
import 'package:intl/intl.dart';

/// The Trends card: a switch between Spending · Net worth · Income vs
/// expenses, then the chosen view. Spending keeps its "View full" link.
///
/// The chosen view is local state for the life of the widget; it is not
/// stored. Every figure each view shows comes from the presenter
/// ([TreasuryDashboardPresenter.spendingSummary],
/// [TreasuryDashboardPresenter.netWorthTrendSummary],
/// [TreasuryDashboardPresenter.incomeExpenseTrendSummary]).
class SpendingAnalyticsCard extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const SpendingAnalyticsCard({super.key, required this.presenter});

  @override
  State<SpendingAnalyticsCard> createState() => _SpendingAnalyticsCardState();
}

class _SpendingAnalyticsCardState extends State<SpendingAnalyticsCard> {
  DashboardTrend _view = DashboardTrend.spending;

  @override
  Widget build(BuildContext context) {
    final presenter = widget.presenter;
    return AppSection(
      title: 'Trends',
      trailing: _view.hasFullHistory
          ? DashboardHeaderLink(
              key: const ValueKey('dashboard.spending.viewFull'),
              label: 'View full',
              onPressed: () =>
                  FullSpendingHistorySheet.show(context, presenter),
            )
          : null,
      child: AppCard(
        variant: AppCardVariant.elevated,
        child: Column(
          children: [
            _Segmented<DashboardTrend>(
              values: DashboardTrend.values,
              value: _view,
              label: (t) => t.label,
              semanticLabel: (t) => t.semanticLabel,
              keyFor: (t) => ValueKey('dashboard.trend.switch.${t.name}'),
              onChanged: (t) => setState(() => _view = t),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: switch (_view) {
                DashboardTrend.spending => _SpendingBody(
                    key: const ValueKey('dashboard.trend.view.spending'),
                    presenter: presenter,
                  ),
                DashboardTrend.netWorth => _NetWorthBody(
                    key: const ValueKey('dashboard.trend.view.netWorth'),
                    summary: presenter.netWorthTrendSummary(),
                  ),
                DashboardTrend.incomeExpenses => _IncomeExpensesBody(
                    key: const ValueKey('dashboard.trend.view.incomeExpenses'),
                    summary: presenter.incomeExpenseTrendSummary(),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Daily spend over a chosen window: the range selector, the bar chart and
/// the total / average / peak row. Every figure is
/// [TreasuryDashboardPresenter.spendingSummary]; only the chosen range is
/// local state.
class _SpendingBody extends StatefulWidget {
  final TreasuryDashboardPresenter presenter;

  const _SpendingBody({super.key, required this.presenter});

  @override
  State<_SpendingBody> createState() => _SpendingBodyState();
}

class _SpendingBodyState extends State<_SpendingBody> {
  SpendRange _range = SpendRange.last7;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = widget.presenter.spendingSummary(_range);

    return Column(
      children: [
        _Segmented<SpendRange>(
          values: SpendRange.values,
          value: _range,
          label: (r) => r.label,
          keyFor: (r) => ValueKey('dashboard.spending.range.${r.name}'),
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 120,
          child: summary.hasData
              ? _BarChart(days: summary.days, peak: summary.peak)
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
        _StatsRow(summary: summary),
      ],
    );
  }
}

/// Compact segmented control: the trends switch and the spending window.
/// Segments share the row equally and each is at least 44 dp tall; a label
/// scales down rather than clipping on a narrow screen. [semanticLabel]
/// gives a screen reader the full name when the visible label is short.
class _Segmented<T> extends StatelessWidget {
  final List<T> values;
  final T value;
  final String Function(T) label;
  final String Function(T)? semanticLabel;
  final Key Function(T) keyFor;
  final ValueChanged<T> onChanged;

  const _Segmented({
    super.key,
    required this.values,
    required this.value,
    required this.label,
    required this.keyFor,
    required this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                label: semanticLabel?.call(v),
                excludeSemantics: semanticLabel != null,
                child: GestureDetector(
                  key: keyFor(v),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: v == value ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label(v),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              v == value ? FontWeight.w700 : FontWeight.w600,
                          color:
                              v == value ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
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

/// A one-line caption above a trends chart ("Last 6 months · …").
class _TrendCaption extends StatelessWidget {
  final String text;

  const _TrendCaption(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The empty state inside a 120 dp chart slot: a small icon and one short
/// line, so a two-line message still fits.
class _TrendEmpty extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrendEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Month-end net worth as a line, then now / start / change. Every figure
/// is [NetWorthTrendSummary].
class _NetWorthBody extends StatelessWidget {
  final NetWorthTrendSummary summary;

  const _NetWorthBody({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _TrendCaption(summary.caption),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: summary.hasChart
              ? _GrowIn(
                  builder: (progress) => CustomPaint(
                    painter: _LineChartPainter(
                      values: summary.normalizedValues,
                      baseline: summary.normalizedBaseline,
                      labels: summary.labels,
                      progress: progress,
                      lineColor: cs.primary,
                      labelColor: cs.onSurfaceVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                )
              : _TrendEmpty(
                  icon: Icons.show_chart_rounded,
                  text: summary.emptyText,
                ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatChip(
              label: 'NOW',
              value: summary.currentCompactLabel,
              color: cs.primary,
            ),
            _StatDivider(),
            _StatChip(
              label: 'START',
              value: summary.startLabel,
              color: cs.onSurfaceVariant,
            ),
            _StatDivider(),
            _StatChip(
              label: 'CHANGE',
              value: summary.changeLabel,
              color: statementToneColor(context, summary.changeTone),
            ),
          ],
        ),
      ],
    );
  }
}

/// Income and expenses per month as paired bars, then the monthly averages.
/// Every figure is [IncomeExpenseTrendSummary].
class _IncomeExpensesBody extends StatelessWidget {
  final IncomeExpenseTrendSummary summary;

  const _IncomeExpensesBody({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final incomeColor = statementToneColor(context, StatementTone.income);
    final expenseColor = cs.primary;
    return Column(
      children: [
        _TrendCaption(summary.caption),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: summary.hasChart
              ? _GrowIn(
                  builder: (progress) => CustomPaint(
                    painter: _PairBarPainter(
                      income: summary.incomeFractions,
                      expense: summary.expenseFractions,
                      labels: summary.labels,
                      progress: progress,
                      incomeColor: incomeColor,
                      expenseColor: expenseColor,
                      labelColor: cs.onSurfaceVariant,
                    ),
                    child: const SizedBox.expand(),
                  ),
                )
              : _TrendEmpty(
                  icon: Icons.bar_chart_rounded,
                  text: summary.emptyText,
                ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatChip(
              label: 'AVG IN',
              value: summary.avgIncomeLabel,
              color: incomeColor,
            ),
            _StatDivider(),
            _StatChip(
              label: 'AVG OUT',
              value: summary.avgExpenseLabel,
              color: expenseColor,
            ),
            _StatDivider(),
            _StatChip(
              label: 'AVG NET',
              value: summary.avgNetLabel,
              color: statementToneColor(context, summary.avgNetTone),
            ),
          ],
        ),
      ],
    );
  }
}

/// Runs [builder] from 0 to 1 over 300 ms when it first appears; straight
/// to 1 when the platform asks for reduced motion.
class _GrowIn extends StatelessWidget {
  final Widget Function(double progress) builder;

  const _GrowIn({required this.builder});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1.0 : 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => builder(progress),
    );
  }
}

/// A line over points already placed between 0 (bottom) and 1 (top), with a
/// soft area between it and [baseline] and a label under each point. Drawn
/// left to right as [progress] runs.
class _LineChartPainter extends CustomPainter {
  final List<double> values;

  /// Where the area fill stops, 0 (bottom) to 1 (top): the zero line once
  /// the series goes negative, so a negative stretch fills downward from it.
  final double baseline;
  final List<String> labels;
  final double progress;
  final Color lineColor;
  final Color labelColor;

  static const double _labelHeight = 20.0;
  static const double _topPad = 8.0;
  static const double _inset = 6.0;

  _LineChartPainter({
    required this.values,
    required this.baseline,
    required this.labels,
    required this.progress,
    required this.lineColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const top = _topPad;
    final bottom = size.height - _labelHeight - 4;
    final h = bottom - top;
    final w = size.width - _inset * 2;
    final step = w / (values.length - 1);
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(_inset + i * step, bottom - values[i] * h),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final baseY = bottom - baseline.clamp(0.0, 1.0) * h;
    final area = Path.from(line)
      ..lineTo(points.last.dx, baseY)
      ..lineTo(points.first.dx, baseY)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.28),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < points.length; i++) {
      final last = i == points.length - 1;
      canvas.drawCircle(points[i], last ? 4 : 2.5, Paint()..color = lineColor);
    }
    canvas.restore();

    _paintLabels(canvas, size, [for (final p in points) p.dx], labels,
        labelColor, _labelHeight);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.progress != progress ||
      old.baseline != baseline ||
      old.lineColor != lineColor ||
      old.labelColor != labelColor ||
      !listEquals(old.values, values) ||
      !listEquals(old.labels, labels);
}

/// Income and expense bars side by side for each month, heights already
/// given as a share (0–1) of the tallest bar. They grow as [progress] runs.
class _PairBarPainter extends CustomPainter {
  final List<double> income;
  final List<double> expense;
  final List<String> labels;
  final double progress;
  final Color incomeColor;
  final Color expenseColor;
  final Color labelColor;

  static const double _labelHeight = 20.0;
  static const double _topPad = 8.0;
  static const double _gap = 3.0;
  static const double _maxBar = 14.0;
  static const double _radius = 3.0;

  _PairBarPainter({
    required this.income,
    required this.expense,
    required this.labels,
    required this.progress,
    required this.incomeColor,
    required this.expenseColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = income.length;
    if (n == 0) return;
    final bottom = size.height - _labelHeight - 4;
    final h = bottom - _topPad;
    final groupW = size.width / n;
    final barW = (groupW * 0.3).clamp(2.0, _maxBar);
    final centers = <double>[];

    void bar(double left, double fraction, Color color) {
      final barH = h * fraction * progress;
      if (barH <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, bottom - barH, barW, barH),
          topLeft: const Radius.circular(_radius),
          topRight: const Radius.circular(_radius),
        ),
        Paint()..color = color,
      );
    }

    for (var i = 0; i < n; i++) {
      final center = groupW * i + groupW / 2;
      centers.add(center);
      bar(center - _gap / 2 - barW, income[i], incomeColor);
      bar(center + _gap / 2, expense[i], expenseColor);
    }
    // Baseline.
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = labelColor.withValues(alpha: 0.2)
        ..strokeWidth = 1,
    );

    _paintLabels(canvas, size, centers, labels, labelColor, _labelHeight);
  }

  @override
  bool shouldRepaint(_PairBarPainter old) =>
      old.progress != progress ||
      old.incomeColor != incomeColor ||
      old.expenseColor != expenseColor ||
      old.labelColor != labelColor ||
      !listEquals(old.income, income) ||
      !listEquals(old.expense, expense) ||
      !listEquals(old.labels, labels);
}

/// Month labels along the bottom, each centred under its x and kept inside
/// the chart.
void _paintLabels(
  Canvas canvas,
  Size size,
  List<double> xs,
  List<String> labels,
  Color color,
  double labelHeight,
) {
  final style = TextStyle(
    color: color.withValues(alpha: 0.7),
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );
  for (var i = 0; i < xs.length && i < labels.length; i++) {
    final tp = TextPainter(
      text: TextSpan(text: labels[i], style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final room = math.max(0.0, size.width - tp.width);
    final x = (xs[i] - tp.width / 2).clamp(0.0, room);
    tp.paint(canvas, Offset(x, size.height - labelHeight + 4));
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
  final SpendingRangeSummary summary;

  const _StatsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _StatChip(
          label: 'TOTAL',
          value: summary.totalLabel,
          color: colorScheme.primary,
        ),
        _StatDivider(),
        _StatChip(
          label: 'AVG / DAY',
          value: summary.avgDailyLabel,
          color: colorScheme.onSurfaceVariant,
        ),
        _StatDivider(),
        _StatChip(
          label: 'PEAK DAY',
          value: summary.peakDayLabel,
          subValue: summary.peakAmountLabel,
          color: summary.hasData
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

    // Each chip takes a third of the row and scales down rather than
    // overflowing: at 360 dp a peak day like "Wed, Sep 24" ran 22 px wide.
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _chip(theme, colorScheme),
      ),
    );
  }

  Widget _chip(ThemeData theme, ColorScheme colorScheme) {
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
