import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import '../../widgets/web_widgets.dart';

/// Human labels for the budget groups (static lookup — no logic in build()).
const Map<BudgetGroup, String> kBudgetGroupLabels = {
  BudgetGroup.nonNegotiables: 'Non-Negotiables',
  BudgetGroup.livingExpense: 'Living',
  BudgetGroup.variableOptional: 'Variable',
  BudgetGroup.savings: 'Savings',
};

const List<BudgetGroup> kBudgetGroupOrder = [
  BudgetGroup.nonNegotiables,
  BudgetGroup.livingExpense,
  BudgetGroup.variableOptional,
  BudgetGroup.savings,
];

/// Donut chart of this-month spend by category, with a legend.
class ExpenseByCategoryDonut extends StatelessWidget {
  final List<(FinanceCategory, double)> slices;
  const ExpenseByCategoryDonut({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (slices.isEmpty) {
      return const _ChartEmpty(label: 'No expenses logged this month.');
    }

    final total = slices.fold<double>(0, (sum, s) => sum + s.$2);
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < slices.length; i++) {
      final color = resolveSliceColor(slices[i].$1.colorHex, i);
      sections.add(
        PieChartSectionData(
          value: slices[i].$2,
          color: color,
          radius: 58,
          showTitle: false,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 56,
                  sectionsSpace: 3,
                  startDegreeOffset: -90,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  Text(formatPesoCompact(total),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: WebInsets.lg),
        Wrap(
          spacing: WebInsets.lg,
          runSpacing: WebInsets.sm,
          children: [
            for (var i = 0; i < slices.length; i++)
              _LegendDot(
                color: resolveSliceColor(slices[i].$1.colorHex, i),
                label: slices[i].$1.name,
                value: formatPesoCompact(slices[i].$2),
              ),
          ],
        ),
      ],
    );
  }
}

/// Bar chart of the last 30 days of daily spending.
class Last30DaySpendChart extends StatelessWidget {
  final List<DailySpend> days;
  const Last30DaySpendChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (days.isEmpty || days.every((d) => d.amount == 0)) {
      return const _ChartEmpty(label: 'No spending in the last 30 days.');
    }

    final maxY = days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final spots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].amount),
    ];

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.32,
              preventCurveOverShooting: true,
              color: cs.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.primary.withValues(alpha: 0.32),
                    cs.primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY <= 0 ? 1 : maxY / 2,
            getDrawingHorizontalLine: (_) => FlLine(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItems: (spots) => spots.map((s) {
                final d = days[s.x.toInt()];
                return LineTooltipItem(
                  '${d.date.month}/${d.date.day}\n${formatPeso(s.y)}',
                  theme.textTheme.labelSmall!
                      .copyWith(color: cs.onInverseSurface),
                );
              }).toList(),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: maxY <= 0 ? 1 : maxY,
                getTitlesWidget: (value, _) => Text(
                  formatPesoCompact(value),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 7,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  final d = days[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: WebInsets.xs),
                    child: Text('${d.date.month}/${d.date.day}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grouped bars comparing allocated vs spent per budget group.
class BudgetByGroupChart extends StatelessWidget {
  final Map<BudgetGroup, double> allocated;
  final Map<BudgetGroup, double> spent;
  const BudgetByGroupChart({
    super.key,
    required this.allocated,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final present = kBudgetGroupOrder
        .where((g) => (allocated[g] ?? 0) > 0 || (spent[g] ?? 0) > 0)
        .toList();

    if (present.isEmpty) {
      return const _ChartEmpty(label: 'No budget allocated this month.');
    }

    var maxY = 0.0;
    for (final g in present) {
      final a = allocated[g] ?? 0;
      final s = spent[g] ?? 0;
      if (a > maxY) maxY = a;
      if (s > maxY) maxY = s;
    }

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < present.length; i++) {
      final g = present[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 4,
          barRods: [
            BarChartRodData(
              toY: allocated[g] ?? 0,
              width: 18,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [cs.primary.withValues(alpha: 0.65), cs.primary],
              ),
            ),
            BarChartRodData(
              toY: spent[g] ?? 0,
              width: 18,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [cs.tertiary.withValues(alpha: 0.65), cs.tertiary],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY * 1.15,
              barGroups: groups,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY <= 0 ? 1 : maxY / 2,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final label = rodIndex == 0 ? 'Allocated' : 'Spent';
                    return BarTooltipItem(
                      '$label\n${formatPeso(rod.toY)}',
                      theme.textTheme.labelSmall!
                          .copyWith(color: cs.onInverseSurface),
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
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY <= 0 ? 1 : maxY,
                    getTitlesWidget: (value, _) => Text(
                      formatPesoCompact(value),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) {
                      final i = value.toInt();
                      if (i < 0 || i >= present.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: WebInsets.xs),
                        child: Text(
                          kBudgetGroupLabels[present[i]] ?? '',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WebInsets.lg),
        Wrap(
          spacing: WebInsets.lg,
          runSpacing: WebInsets.sm,
          children: [
            _LegendDot(color: cs.primary, label: 'Allocated'),
            _LegendDot(color: cs.tertiary, label: 'Spent'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final String? value;
  const _LegendDot({required this.color, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: WebInsets.sm),
        Text(label, style: theme.textTheme.bodySmall),
        if (value != null) ...[
          const SizedBox(width: WebInsets.xs),
          Text(value!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  final String label;
  const _ChartEmpty({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
      ),
    );
  }
}
