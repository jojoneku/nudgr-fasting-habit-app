import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/daily_nutrition_log.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';

class NutritionHistoryScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const NutritionHistoryScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => AppPageScaffold(
        title: 'History',
        padding: EdgeInsets.zero,
        body: presenter.history.isEmpty
            ? const AppEmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'No history yet',
                body: 'Log meals for 2+ days to see your chart',
              )
            : _HistoryContent(
                history: presenter.history,
                goalCalories: presenter.effectiveGoal,
              ),
      ),
    );
  }
}

// ─── History Content ──────────────────────────────────────────────────────────

class _HistoryContent extends StatelessWidget {
  final List<DailyNutritionLog> history;
  final int goalCalories;

  const _HistoryContent({required this.history, required this.goalCalories});

  List<DailyNutritionLog> get _last7 =>
      history.take(7).toList().reversed.toList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _WeeklyChart(days: _last7, goalCalories: goalCalories),
        const SizedBox(height: 24),
        AppSection(
          title: 'Recent days',
          child: Column(
            children: history
                .map((log) =>
                    _HistoryRow(log: log, goalCalories: goalCalories))
                .toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Weekly Bar Chart ─────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  final List<DailyNutritionLog> days;
  final int goalCalories;

  const _WeeklyChart({required this.days, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '7-day overview',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: const Size(double.infinity, 120),
              painter:
                  _BarChartPainter(days: days, goalCalories: goalCalories),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: days.map((log) {
              final dt = DateTime.tryParse(log.date) ?? DateTime.now();
              return Expanded(
                child: Text(
                  DateFormat('E').format(dt).substring(0, 1),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyNutritionLog> days;
  final int goalCalories;

  _BarChartPainter({required this.days, required this.goalCalories});

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final maxCal = math.max(
      goalCalories.toDouble(),
      days.fold(0.0, (m, d) => math.max(m, d.totalCalories.toDouble())),
    );
    if (maxCal == 0) return;

    final barWidth = size.width / (days.length * 2 - 1);
    final goalY = size.height * (1 - goalCalories / maxCal);

    canvas.drawLine(
      Offset(0, goalY),
      Offset(size.width, goalY),
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    for (int i = 0; i < days.length; i++) {
      final cal = days[i].totalCalories;
      final barH = size.height * (cal / maxCal).clamp(0.0, 1.0);
      final left = i * barWidth * 2;
      final isGoalMet = goalCalories > 0 && cal >= goalCalories;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barH, barWidth, barH),
          const Radius.circular(4),
        ),
        Paint()
          ..color = isGoalMet
              ? AppColors.gold
              : AppColors.gold.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.days != days || old.goalCalories != goalCalories;
}

// ─── History Row ──────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final DailyNutritionLog log;
  final int goalCalories;

  static final _dateFmt = DateFormat('EEE, MMM d');
  static final _calFmt = NumberFormat('#,###');

  const _HistoryRow({required this.log, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cal = log.totalCalories;
    final goalMet = goalCalories > 0 && cal >= goalCalories;
    final isOver = goalCalories > 0 && cal > goalCalories * 1.2;
    final ratio =
        goalCalories > 0 ? (cal / goalCalories).clamp(0.0, 1.5) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dateFmt.format(DateTime.parse(log.date)),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_calFmt.format(cal)} kcal',
                  style: TextStyle(
                    color: goalMet
                        ? AppColors.gold
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                if (isOver)
                  AppBadge(text: 'Over', color: theme.colorScheme.error)
                else if (goalMet)
                  const AppBadge(text: 'Hit target', color: AppColors.gold)
                else
                  AppBadge(
                    text: 'Under',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AppLinearProgress(
              value: ratio.clamp(0.0, 1.0),
              height: 3,
              color: goalMet
                  ? AppColors.gold
                  : AppColors.gold.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
