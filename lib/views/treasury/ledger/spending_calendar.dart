import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

final _dayKeyFmt = DateFormat('yyyy-MM-dd');

class SpendingCalendar extends StatelessWidget {
  final LedgerPresenter presenter;
  final ValueChanged<DateTime> onDaySelected;

  const SpendingCalendar({
    super.key,
    required this.presenter,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final parts = presenter.selectedMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final focusedDay = presenter.selectedDate ?? firstDay;

    final outflowMap = presenter.dailyOutflowMap;
    final inflowMap = presenter.dailyInflowMap;
    final avg = presenter.averageDailyOutflow;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: TableCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: focusedDay,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          selectedDayPredicate: (day) => isSameDay(day, presenter.selectedDate),
          onDaySelected: (selected, _) => onDaySelected(selected),
          headerVisible: false,
          rowHeight: 46,
          daysOfWeekHeight: 28,
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            weekendStyle: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            defaultTextStyle:
                TextStyle(color: AppColors.textPrimary, fontSize: 13),
            weekendTextStyle:
                TextStyle(color: AppColors.textPrimary, fontSize: 13),
            todayDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent, width: 1.5),
            ),
            todayTextStyle: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700),
            selectedDecoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.25),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent),
            ),
            selectedTextStyle: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) => _HeatmapCell(
                day: day,
                outflowMap: outflowMap,
                inflowMap: inflowMap,
                avg: avg,
                isSelected: false,
                isToday: false),
            todayBuilder: (context, day, focusedDay) => _HeatmapCell(
                day: day,
                outflowMap: outflowMap,
                inflowMap: inflowMap,
                avg: avg,
                isSelected: false,
                isToday: true),
            selectedBuilder: (context, day, focusedDay) => _HeatmapCell(
                day: day,
                outflowMap: outflowMap,
                inflowMap: inflowMap,
                avg: avg,
                isSelected: true,
                isToday: false),
            outsideBuilder: (context, day, focusedDay) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  final DateTime day;
  final Map<String, double> outflowMap;
  final Map<String, double> inflowMap;
  final double avg;
  final bool isSelected;
  final bool isToday;

  const _HeatmapCell({
    required this.day,
    required this.outflowMap,
    required this.inflowMap,
    required this.avg,
    required this.isSelected,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final key = _dayKeyFmt.format(day);
    final outflow = outflowMap[key] ?? 0;
    final inflow = inflowMap[key] ?? 0;
    final hasOutflow = outflow > 0;
    final hasInflow = inflow > 0;
    final hasBoth = hasOutflow && hasInflow;

    Color? bgColor;
    Color textColor = AppColors.textPrimary;

    if (hasOutflow && outflow >= inflow) {
      final opacity = (outflow / avg).clamp(0.15, 0.90);
      bgColor = AppColors.danger.withOpacity(opacity);
      if (opacity > 0.5) textColor = Colors.white;
    } else if (hasInflow) {
      final opacity = (inflow / avg).clamp(0.15, 0.70);
      bgColor = AppColors.success.withOpacity(opacity);
      if (opacity > 0.5) textColor = Colors.white;
    }

    Border? border;
    if (isSelected) {
      border = Border.all(color: AppColors.accent, width: 1.5);
      bgColor = (bgColor ?? Colors.transparent).withOpacity(
        bgColor != null ? 0.6 : 0.2,
      );
    } else if (isToday) {
      border = Border.all(color: AppColors.accent.withOpacity(0.7), width: 1.5);
    }

    return Tooltip(
      message: _buildTooltip(outflow, inflow),
      child: Center(
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: border,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  color: isSelected ? AppColors.accent : textColor,
                  fontSize: 12,
                  fontWeight:
                      isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (hasBoth)
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: outflow >= inflow
                          ? AppColors.success.withOpacity(0.8)
                          : AppColors.danger.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildTooltip(double outflow, double inflow) {
    if (outflow == 0 && inflow == 0) return '';
    final parts = <String>[];
    if (inflow > 0) parts.add('+${formatPeso(inflow)}');
    if (outflow > 0) parts.add('-${formatPeso(outflow)}');
    return parts.join('  ');
  }
}
