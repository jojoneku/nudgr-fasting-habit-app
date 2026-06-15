import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';

/// One slice of a [WebDonutChart] / one legend entry.
class WebChartSlice {
  final String label;
  final double value;
  final Color color;

  const WebChartSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  // Value equality so the donut painter's `listEquals` guard actually short-
  // circuits when the dashboard rebuilds an identical slice list. (P3)
  @override
  bool operator ==(Object other) =>
      other is WebChartSlice &&
      other.label == label &&
      other.value == value &&
      other.color == color;

  @override
  int get hashCode => Object.hash(label, value, color);
}

/// A ring donut with a two-line center label and an optional ranked legend on
/// the right (rank #, color dot, name, amount, percent). Mirrors the Treasury
/// dashboard donut: animated sweep, small gaps between slices.
///
/// Used by dashboard "Where Your Money Goes" and budget "Allocation by Group".
/// Lays out as `Row( donut, Expanded legend )` when [showLegend] is true.
class WebDonutChart extends StatefulWidget {
  final List<WebChartSlice> slices;

  /// Small caption above [centerValue], e.g. "SPENT".
  final String? centerLabel;

  /// Large figure in the ring center, e.g. "₱15k".
  final String? centerValue;

  /// Show the ranked legend to the right of the ring.
  final bool showLegend;

  /// Diameter of the ring in logical pixels.
  final double size;

  const WebDonutChart({
    super.key,
    required this.slices,
    this.centerLabel,
    this.centerValue,
    this.showLegend = true,
    this.size = 160,
  });

  @override
  State<WebDonutChart> createState() => _WebDonutChartState();
}

class _WebDonutChartState extends State<WebDonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = widget.slices.fold<double>(0, (s, e) => s + e.value);

    if (widget.slices.isEmpty || total <= 0) {
      return SizedBox(
        height: widget.size,
        child: Center(
          child: Text(
            'No data',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    // Derive the center-label styles from the theme so they honor text scaling
    // and theme switches instead of hardcoding size/weight in the painter. (T7)
    final centerLabelStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600);
    final centerValueStyle = (theme.textTheme.titleMedium ?? const TextStyle())
        .copyWith(color: cs.onSurface, fontWeight: FontWeight.w700);

    // Pass the animation to the painter via `repaint:` instead of rebuilding the
    // whole subtree each tick with AnimatedBuilder — the painter is now created
    // ~once per data/theme change (not per frame), so its reusable Paint and
    // cached TextPainters survive the sweep. Wrapped in a RepaintBoundary so the
    // ticking ring never dirties the surrounding card layer. (P4, P8)
    final ring = RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _DonutPainter(
            animation: _animation,
            slices: widget.slices,
            total: total,
            centerLabel: widget.centerLabel,
            centerValue: widget.centerValue,
            centerLabelStyle: centerLabelStyle,
            centerValueStyle: centerValueStyle,
          ),
        ),
      ),
    );

    if (!widget.showLegend) return ring;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ring,
        const SizedBox(width: WebInsets.xl),
        Expanded(child: _DonutLegend(slices: widget.slices, total: total)),
      ],
    );
  }
}

class _DonutLegend extends StatelessWidget {
  final List<WebChartSlice> slices;
  final double total;

  const _DonutLegend({required this.slices, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < slices.length; i++) ...[
          if (i > 0) const SizedBox(height: WebInsets.sm),
          Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  '${i + 1}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: slices[i].color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: WebInsets.sm),
              Expanded(
                child: Text(
                  slices[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: WebInsets.sm),
              Flexible(
                child: Text(
                  _peso(slices[i].value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: WebInsets.sm),
              SizedBox(
                width: 44,
                child: Text(
                  '${(slices[i].value / total * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _peso(double v) {
    final s = v.round().toString();
    final buf = StringBuffer('₱');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _DonutPainter extends CustomPainter {
  final Animation<double> animation;
  final List<WebChartSlice> slices;
  final double total;
  final String? centerLabel;
  final String? centerValue;
  final TextStyle centerLabelStyle;
  final TextStyle centerValueStyle;

  static const double _gapAngle = 0.04;
  static const double _strokeWidth = 22.0;

  // Reused across every slice and every animation tick — one allocation instead
  // of one Paint per slice per frame. (P4)
  final Paint _arcPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _strokeWidth
    ..strokeCap = StrokeCap.butt;

  // Built once (lazily) and reused — the text content/style is stable across
  // the sweep, so we don't lay out two TextPainters every tick. (P4)
  TextPainter? _labelPainter;
  TextPainter? _valuePainter;

  _DonutPainter({
    required this.animation,
    required this.slices,
    required this.total,
    required this.centerLabel,
    required this.centerValue,
    required this.centerLabelStyle,
    required this.centerValueStyle,
  }) : super(repaint: animation);

  double get progress => animation.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - _strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;
    final totalGap = _gapAngle * slices.length;
    // Clamp so a pathological slice count can never drive the sweep negative.
    final availableAngle =
        ((2 * math.pi - totalGap) * progress).clamp(0.0, 2 * math.pi);

    for (final slice in slices) {
      final sweepAngle = (slice.value / total) * availableAngle;
      _arcPaint.color = slice.color;
      canvas.drawArc(rect, startAngle, sweepAngle, false, _arcPaint);
      startAngle += sweepAngle + _gapAngle;
    }

    if (progress > 0.8 && (centerLabel != null || centerValue != null)) {
      // Fade the center text in with the tail of the sweep rather than popping.
      final opacity = ((progress - 0.8) / 0.2).clamp(0.0, 1.0);
      if (centerLabel != null) {
        final lp = _labelPainter ??= TextPainter(
          text: TextSpan(
              text: centerLabel!.toUpperCase(), style: centerLabelStyle),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        canvas.saveLayer(
            null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
        lp.paint(canvas, center - Offset(lp.width / 2, lp.height + 1));
        canvas.restore();
      }
      if (centerValue != null) {
        final vp = _valuePainter ??= TextPainter(
          text: TextSpan(text: centerValue!, style: centerValueStyle),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        canvas.saveLayer(
            null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
        vp.paint(canvas, center - Offset(vp.width / 2, -2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total ||
      old.centerLabel != centerLabel ||
      old.centerValue != centerValue ||
      old.centerLabelStyle != centerLabelStyle ||
      old.centerValueStyle != centerValueStyle ||
      !listEquals(old.slices, slices); // value compare, not identity (P3)
}

/// A smooth line chart (fl_chart) in [ColorScheme.primary] with an optional
/// area gradient fill, minimal grid, and muted axis labels.
///
/// Used by Net-Worth-Trend (area on) and Daily-Spending (curvy line).
class WebLineChart extends StatelessWidget {
  final List<double> values;

  /// Optional X-axis labels (one per value, sparse rendering allowed).
  final List<String>? bottomLabels;

  /// Draw a gradient area below the line.
  final bool area;

  /// Format the left-axis tick labels.
  final String Function(double)? leftLabelFormat;

  final double? minY;
  final double? maxY;
  final double height;

  const WebLineChart({
    super.key,
    required this.values,
    this.bottomLabels,
    this.area = true,
    this.leftLabelFormat,
    this.minY,
    this.maxY,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final spots = <FlSpot>[
      for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);

    // Show at most ~7 x-axis labels: with few points (6-month trend, 7-day
    // spending) every point is labelled; a long series (e.g. a 30-day sheet)
    // thins to every Nth label so they don't overlap.
    final labelCount = bottomLabels?.length ?? 0;
    final labelStep =
        labelCount == 0 ? 1 : (labelCount / 7).ceil().clamp(1, labelCount);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.7), width: 1),
              bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.7), width: 1),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: leftLabelFormat != null,
                reservedSize: 48,
                getTitlesWidget: (value, meta) {
                  if (value != meta.min && value != meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: WebInsets.sm),
                    child: Text(leftLabelFormat!(value), style: labelStyle),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: bottomLabels != null,
                reservedSize: 24,
                // Pin the interval to whole data points. Without this fl_chart
                // picks a fractional default and fires the builder at x = 0,
                // 0.45, 0.9, … — each rounds to the same index, repeating labels
                // ("Jan Jan Feb Feb …"). The integral guard + [labelStep] keep
                // exactly one label per (thinned) spot.
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  if (value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  final i = value.round();
                  final labels = bottomLabels;
                  if (labels == null ||
                      i < 0 ||
                      i >= labels.length ||
                      i % labelStep != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: WebInsets.sm),
                    child: Text(labels[i], style: labelStyle),
                  );
                },
              ),
            ),
          ),
          // Desktop users expect to hover a point and read its exact value. (U3)
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.round();
                final labels = bottomLabels;
                final prefix = (labels != null && i >= 0 && i < labels.length)
                    ? '${labels[i]}\n'
                    : '';
                final v = leftLabelFormat != null
                    ? leftLabelFormat!(s.y)
                    : s.y.toStringAsFixed(0);
                return LineTooltipItem(
                  '$prefix$v',
                  TextStyle(
                    color: cs.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: cs.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: area,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withValues(alpha: 0.25),
                    cs.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Honor the OS "reduce motion" setting. (C2)
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// One named, colored series for [WebMultiLineChart].
class WebLineSeries {
  final String label;
  final Color color;
  final List<double> values;
  const WebLineSeries({
    required this.label,
    required this.color,
    required this.values,
  });
}

/// A multi-series line chart (fl_chart) — several trend lines on shared axes
/// with a legend and per-series hover tooltips. Used by History to show how
/// income, expenses and net savings each move month-over-month.
///
/// Shares the minimal grid / muted-axis styling of [WebLineChart]; lines are
/// drawn unfilled (no area) so overlapping series stay legible.
class WebMultiLineChart extends StatelessWidget {
  final List<WebLineSeries> series;
  final List<String>? bottomLabels;
  final String Function(double)? leftLabelFormat;
  final double height;

  const WebMultiLineChart({
    super.key,
    required this.series,
    this.bottomLabels,
    this.leftLabelFormat,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final maxLen = series.fold<int>(0, (m, s) => math.max(m, s.values.length));
    if (series.isEmpty || maxLen == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    final labelCount = bottomLabels?.length ?? 0;
    final labelStep =
        labelCount == 0 ? 1 : (labelCount / 7).ceil().clamp(1, labelCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (maxLen - 1).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                      width: 1),
                  bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                      width: 1),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: leftLabelFormat != null,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) {
                      if (value != meta.min && value != meta.max) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: WebInsets.sm),
                        child: Text(leftLabelFormat!(value), style: labelStyle),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: bottomLabels != null,
                    reservedSize: 24,
                    interval: labelStep.toDouble(),
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      final i = value.round();
                      final labels = bottomLabels;
                      if (labels == null ||
                          i < 0 ||
                          i >= labels.length ||
                          i % labelStep != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: WebInsets.sm),
                        child: Text(labels[i], style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItems: (spots) => spots.map((s) {
                    final label = s.barIndex >= 0 && s.barIndex < series.length
                        ? series[s.barIndex].label
                        : '';
                    final v = leftLabelFormat != null
                        ? leftLabelFormat!(s.y)
                        : s.y.toStringAsFixed(0);
                    return LineTooltipItem(
                      '$label  $v',
                      TextStyle(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < s.values.length; i++)
                        FlSpot(i.toDouble(), s.values[i]),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: s.color,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
              ],
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: WebInsets.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: WebInsets.lg,
          runSpacing: WebInsets.sm,
          children: [
            for (final s in series) _LegendDot(color: s.color, label: s.label),
          ],
        ),
      ],
    );
  }
}

/// A grouped bar chart (fl_chart) with two bars per group — typically income
/// (green / [aColor]) vs expenses (muted / [bColor]) — plus a small legend.
class WebBarPairChart extends StatelessWidget {
  final List<({String label, double a, double b})> groups;
  final Color aColor;
  final Color bColor;

  /// Legend label for the `a` series. Defaults to "Income".
  final String aLabel;

  /// Legend label for the `b` series. Defaults to "Expenses".
  final String bLabel;

  final String Function(double)? leftLabelFormat;
  final double height;

  const WebBarPairChart({
    super.key,
    required this.groups,
    required this.aColor,
    required this.bColor,
    this.aLabel = 'Income',
    this.bLabel = 'Expenses',
    this.leftLabelFormat,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (groups.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No data',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final maxVal = groups.fold<double>(
      0,
      (m, g) => math.max(m, math.max(g.a, g.b)),
    );
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxVal <= 0 ? 1 : maxVal * 1.15,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  left: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                      width: 1),
                  bottom: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.7),
                      width: 1),
                ),
              ),
              // Hover a bar to read its series + exact value. (U3)
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final series = rodIndex == 0 ? aLabel : bLabel;
                    final v = leftLabelFormat != null
                        ? leftLabelFormat!(rod.toY)
                        : rod.toY.toStringAsFixed(0);
                    return BarTooltipItem(
                      '$series\n$v',
                      TextStyle(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: leftLabelFormat != null,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) {
                      if (value != meta.min && value != meta.max) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: WebInsets.sm),
                        child: Text(leftLabelFormat!(value), style: labelStyle),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= groups.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: WebInsets.sm),
                        child: Text(groups[i].label, style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (int i = 0; i < groups.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 6,
                    barRods: [
                      BarChartRodData(
                        toY: groups[i].a,
                        color: aColor,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                      BarChartRodData(
                        toY: groups[i].b,
                        color: bColor,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            // Honor the OS "reduce motion" setting. (C2)
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: WebInsets.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: aColor, label: aLabel),
            const SizedBox(width: WebInsets.lg),
            _LegendDot(color: bColor, label: bLabel),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
