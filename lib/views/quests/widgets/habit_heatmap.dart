import 'package:flutter/material.dart';
import '../../../app_colors.dart';

/// 12-week rolling heatmap of quest completions.
/// Green = full completion, amber = partial, grey = missed, transparent = not scheduled.
class HabitHeatmap extends StatelessWidget {
  /// Keys are 'YYYY-MM-DD'. Values: 'full', 'partial', or 'missed'.
  final Map<String, String> dateStates;

  /// Which weekdays (0=Mon..6=Sun) this quest is scheduled on.
  final List<bool> scheduledDays;

  const HabitHeatmap({
    super.key,
    required this.dateStates,
    required this.scheduledDays,
  });

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDayLabels(),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weeks
              .map((week) => Column(
                    children: week
                        .map((day) => _DayCell(
                              date: day,
                              state: day != null
                                  ? dateStates[_key(day)]
                                  : null,
                              isScheduled: day != null &&
                                  scheduledDays[day.weekday - 1],
                            ))
                        .toList(),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        _buildLegend(),
      ],
    );
  }

  Widget _buildDayLabels() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Spacer(),
        ...labels.map((l) => SizedBox(
              width: 18,
              child: Text(l,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            )),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendDot(color: AppColors.success, label: 'Full'),
        const SizedBox(width: 12),
        _LegendDot(color: AppColors.gold, label: 'Partial'),
        const SizedBox(width: 12),
        _LegendDot(
            color: AppColors.neutral.withValues(alpha: 0.3), label: 'Missed'),
      ],
    );
  }

  /// Builds 12 weeks (columns), each with 7 days (rows).
  List<List<DateTime?>> _buildWeeks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Start from Monday 12 weeks ago
    final firstMonday =
        today.subtract(Duration(days: today.weekday - 1 + 7 * 11));

    final weeks = <List<DateTime?>>[];
    for (int w = 0; w < 12; w++) {
      final week = <DateTime?>[];
      for (int d = 0; d < 7; d++) {
        final date = firstMonday.add(Duration(days: w * 7 + d));
        week.add(date.isAfter(today) ? null : date);
      }
      weeks.add(week);
    }
    return weeks;
  }

  static String _key(DateTime date) => date.toIso8601String().split('T')[0];
}

class _DayCell extends StatelessWidget {
  final DateTime? date;
  final String? state; // 'full', 'partial', 'missed', null
  final bool isScheduled;

  const _DayCell({this.date, this.state, required this.isScheduled});

  @override
  Widget build(BuildContext context) {
    final color = _cellColor();
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Color _cellColor() {
    if (date == null) return Colors.transparent;
    if (!isScheduled) return AppColors.surface;
    return switch (state) {
      'full' => AppColors.success.withValues(alpha: 0.85),
      'partial' => AppColors.gold.withValues(alpha: 0.7),
      'missed' => AppColors.neutral.withValues(alpha: 0.25),
      _ => AppColors.neutral.withValues(alpha: 0.15),
    };
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
