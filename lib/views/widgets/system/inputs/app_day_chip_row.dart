import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_text_styles.dart';
import '../foundation/app_pressable.dart';

/// Selectable day-of-week chip row (Mon–Sun). Used by nutrition day picker.
class AppDayChipRow extends StatelessWidget {
  const AppDayChipRow({
    super.key,
    required this.selectedDate,
    required this.weekStart,
    required this.onSelected,
    this.highlightToday = true,
  });

  final DateTime selectedDate;
  final DateTime weekStart;
  final ValueChanged<DateTime> onSelected;
  final bool highlightToday;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = weekStart.add(Duration(days: i));
        final isSelected =
            DateUtils.dateOnly(day) == DateUtils.dateOnly(selectedDate);
        final isToday = highlightToday && DateUtils.dateOnly(day) == today;

        Color bg = Colors.transparent;
        Color fg = theme.colorScheme.onSurfaceVariant;
        Border? border;

        if (isSelected) {
          bg = theme.colorScheme.primary;
          fg = theme.colorScheme.onPrimary;
        } else if (isToday) {
          border = Border.all(color: theme.colorScheme.primary);
          fg = theme.colorScheme.primary;
        }

        return AppPressable(
          onTap: () => onSelected(day),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadii.smBorder,
              border: border,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_labels[i],
                    style: AppTextStyles.labelSmall.copyWith(color: fg)),
                Text(
                  '${day.day}',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: fg,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
