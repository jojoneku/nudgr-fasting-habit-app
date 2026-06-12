import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// Net-cash-flow trend across closed months, with income and expense series
/// overlaid (Plan 050-E). All data is pre-computed by the presenter; this widget
/// only maps it onto `fl_chart` primitives.
class HistoryTrendChart extends StatelessWidget {
  final List<HistoryTrendPoint> points;

  /// Symmetric vertical bound — the chart spans [-bound, +bound] so a negative
  /// net month dips below the zero line.
  final double bound;

  const HistoryTrendChart({
    super.key,
    required this.points,
    required this.bound,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final gridColor = cs.outlineVariant.withValues(alpha: 0.3);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    final maxX = (points.length - 1).toDouble();
    final interval = bound / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX < 0 ? 0 : maxX,
              minY: -bound,
              maxY: bound,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval <= 0 ? null : interval,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: value == 0
                      ? cs.outlineVariant.withValues(alpha: 0.7)
                      : gridColor,
                  strokeWidth: value == 0 ? 1.2 : 0.8,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: interval <= 0 ? null : interval,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min || value == meta.max) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          formatPesoCompact(value),
                          style: labelStyle,
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortMonth(points[i].month),
                          style: labelStyle,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItems: (spots) => spots.map((s) {
                    final p = points[s.x.round()];
                    return LineTooltipItem(
                      '${monthLabel(p.month)}\n'
                      'Net ${formatPesoCompact(p.net)}',
                      theme.textTheme.bodySmall!.copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                _series(
                  points.map((p) => FlSpot(p.index, p.inflow)).toList(),
                  cs.tertiary,
                  fill: false,
                ),
                _series(
                  points.map((p) => FlSpot(p.index, p.outflow)).toList(),
                  cs.error,
                  fill: false,
                ),
                _series(
                  points.map((p) => FlSpot(p.index, p.net)).toList(),
                  cs.primary,
                  fill: true,
                  fillColor: cs.primary.withValues(alpha: 0.12),
                  width: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend(color: cs.primary, label: 'Net cash flow'),
            _Legend(color: cs.tertiary, label: 'Income'),
            _Legend(color: cs.error, label: 'Expenses'),
          ],
        ),
      ],
    );
  }

  LineChartBarData _series(
    List<FlSpot> spots,
    Color color, {
    required bool fill,
    Color? fillColor,
    double width = 2,
  }) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      color: color,
      barWidth: width,
      dotData: FlDotData(
        show: spots.length <= 12,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3,
          color: color,
          strokeWidth: 0,
        ),
      ),
      belowBarData: BarAreaData(
        show: fill,
        color: fillColor,
      ),
    );
  }

  static String _shortMonth(String monthKey) {
    // 'YYYY-MM' → "MMM 'yy"
    final date = DateTime.parse('$monthKey-01');
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return "${months[date.month - 1]} '$yy";
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
