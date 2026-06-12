import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
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

    final ring = AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _DonutPainter(
            slices: widget.slices,
            total: total,
            progress: _animation.value,
            centerLabel: widget.centerLabel,
            centerValue: widget.centerValue,
            labelColor: cs.onSurfaceVariant,
            valueColor: cs.onSurface,
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
  final List<WebChartSlice> slices;
  final double total;
  final double progress;
  final String? centerLabel;
  final String? centerValue;
  final Color labelColor;
  final Color valueColor;

  static const double _gapAngle = 0.04;
  static const double _strokeWidth = 22.0;

  _DonutPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.centerLabel,
    required this.centerValue,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - _strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;
    final totalGap = _gapAngle * slices.length;
    final availableAngle = (2 * math.pi - totalGap) * progress;

    for (final slice in slices) {
      final sweepAngle = (slice.value / total) * availableAngle;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweepAngle + _gapAngle;
    }

    if (progress > 0.8 && (centerLabel != null || centerValue != null)) {
      if (centerLabel != null) {
        final lp = TextPainter(
          text: TextSpan(
            text: centerLabel!.toUpperCase(),
            style: TextStyle(
              color: labelColor,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        lp.paint(canvas, center - Offset(lp.width / 2, lp.height + 1));
      }
      if (centerValue != null) {
        final vp = TextPainter(
          text: TextSpan(
            text: centerValue!,
            style: TextStyle(
              color: valueColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        vp.paint(canvas, center - Offset(vp.width / 2, -2));
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.total != total || old.slices != slices;
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
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  final labels = bottomLabels;
                  if (labels == null || i < 0 || i >= labels.length) {
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
          lineTouchData: const LineTouchData(enabled: false),
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
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
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
              barTouchData: BarTouchData(enabled: false),
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
            duration: const Duration(milliseconds: 280),
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
