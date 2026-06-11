import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../../widgets/web_widgets.dart';

/// Grouped bar chart of Allocated vs. Spent per [BudgetGroup] (Plan 050-D).
///
/// Presentational only — all figures arrive pre-aggregated via [bars] from
/// `BudgetPresenter.groupBars`. Colors come from [Theme.of] (dual-theme safe).
class BudgetAllocationChart extends StatelessWidget {
  final List<WebBudgetGroupBar> bars;

  const BudgetAllocationChart({super.key, required this.bars});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (bars.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No allocations to chart yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final maxValue = bars
        .map((b) => b.allocated > b.spent ? b.allocated : b.spent)
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final bar = bars[group.x.toInt()];
                    final isAllocated = rodIndex == 0;
                    return BarTooltipItem(
                      '${bar.label}\n'
                      '${isAllocated ? 'Allocated' : 'Spent'} '
                      '${formatPeso(rod.toY)}',
                      theme.textTheme.bodySmall!.copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(right: WebInsets.xs),
                      child: Text(
                        formatPesoCompact(value),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= bars.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: WebInsets.sm),
                        child: Text(
                          bars[i].label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < bars.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: WebInsets.xs,
                    barRods: [
                      BarChartRodData(
                        toY: bars[i].allocated,
                        color: cs.primary,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      BarChartRodData(
                        toY: bars[i].spent,
                        color: bars[i].spent > bars[i].allocated
                            ? cs.error
                            : cs.secondary,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WebInsets.lg),
        Wrap(
          spacing: WebInsets.lg,
          runSpacing: WebInsets.sm,
          children: [
            _LegendDot(color: cs.primary, label: 'Allocated'),
            _LegendDot(color: cs.secondary, label: 'Spent'),
            _LegendDot(color: cs.error, label: 'Over budget'),
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
