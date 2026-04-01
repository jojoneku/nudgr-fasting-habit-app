import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/daily_nutrition_log.dart';
import '../../presenters/nutrition_presenter.dart';

class NutritionHistoryScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const NutritionHistoryScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'NUTRITION HISTORY',
          style: TextStyle(letterSpacing: 2.5, fontSize: 13),
        ),
        centerTitle: true,
      ),
      body: presenter.history.isEmpty
          ? const _EmptyHistory()
          : _HistoryContent(
              history: presenter.history,
              goalCalories: presenter.effectiveGoal,
            ),
    );
  }
}

// ── Main content: chart + list ─────────────────────────────────────────────────

class _HistoryContent extends StatelessWidget {
  final List<DailyNutritionLog> history;
  final int goalCalories;

  const _HistoryContent(
      {required this.history, required this.goalCalories});

  /// Last 7 days from history (most-recent first → reverse for chart left→right).
  List<DailyNutritionLog> get _last7 => history.take(7).toList().reversed.toList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Weekly bar chart ──────────────────────────────────────────────
        _WeeklyChart(days: _last7, goalCalories: goalCalories),
        const SizedBox(height: 24),

        // ── Streak badges ─────────────────────────────────────────────────
        _SectionHeader('RECENT DAYS'),
        const SizedBox(height: 10),

        // ── Daily list ────────────────────────────────────────────────────
        ...history.map((log) => _HistoryRow(
              log: log,
              goalCalories: goalCalories,
            )),
      ],
    );
  }
}

// ── Weekly bar chart ──────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  final List<DailyNutritionLog> days;
  final int goalCalories;

  const _WeeklyChart({required this.days, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('7-DAY OVERVIEW',
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 10,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: CustomPaint(
              size: const Size(double.infinity, 120),
              painter: _BarChartPainter(days: days, goalCalories: goalCalories),
            ),
          ),
          const SizedBox(height: 8),
          // Day labels
          Row(
            children: days.map((log) {
              final dt = DateTime.tryParse(log.date) ?? DateTime.now();
              return Expanded(
                child: Text(
                  DateFormat('E').format(dt).substring(0, 1),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      letterSpacing: 0.5),
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

    final barWidth  = size.width / (days.length * 2 - 1);
    final goalY     = size.height * (1 - goalCalories / maxCal);

    // Goal line
    final goalPaint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(0, goalY), Offset(size.width, goalY), goalPaint);

    // Bars
    for (int i = 0; i < days.length; i++) {
      final cal    = days[i].totalCalories;
      final ratio  = (cal / maxCal).clamp(0.0, 1.0);
      final barH   = size.height * ratio;
      final left   = i * barWidth * 2;
      final rect   = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - barH, barWidth, barH),
        const Radius.circular(4),
      );

      final isGoalMet = goalCalories > 0 && cal >= goalCalories;
      final barColor = isGoalMet
          ? AppColors.gold
          : AppColors.gold.withValues(alpha: 0.3);

      canvas.drawRRect(rect, Paint()..color = barColor);
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.days != days || old.goalCalories != goalCalories;
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: AppColors.gold.withValues(alpha: 0.75),
          fontSize: 10,
          letterSpacing: 2.0,
          fontWeight: FontWeight.w700,
        ),
      );
}

// ── History row ───────────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  final DailyNutritionLog log;
  final int goalCalories;

  static final _dateFmt = DateFormat('EEE, MMM d');
  static final _calFmt  = NumberFormat('#,###');

  const _HistoryRow({required this.log, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final cal       = log.totalCalories;
    final goalMet   = goalCalories > 0 && cal >= goalCalories;
    final ratio     = goalCalories > 0 ? (cal / goalCalories).clamp(0.0, 1.5) : 0.0;
    final barColor  = goalMet ? AppColors.gold : AppColors.gold.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                _dateFmt.format(DateTime.parse(log.date)),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${_calFmt.format(cal)} kcal',
              style: TextStyle(
                  color: goalMet ? AppColors.gold : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
            if (goalMet) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle,
                  color: AppColors.gold, size: 14),
            ],
          ]),
          const SizedBox(height: 8),
          // Mini progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: AppColors.background,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart, color: AppColors.textSecondary, size: 48),
          SizedBox(height: 16),
          Text(
            'No history yet',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Log meals for 2+ days to see your chart',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
