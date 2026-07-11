import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../models/meal_slot.dart';
import '../../widgets/system/system.dart';

/// Shared step-form widgets for the TDEE profile flow. Consumed by both
/// [TdeeSetupScreen] (the in-app editor) and the first-run onboarding wizard so
/// the two cannot drift. Pure presentation — the parent owns all state
/// (controllers / selected values) and passes it in.

/// A selectable radio-style tile with a gold-accented selected state. Public,
/// shared version of the tile the TDEE setup screen used privately.
class TdeeRadioTile<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final T value;
  final T groupValue;
  final void Function(T?) onChanged;
  const TdeeRadioTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = context.appColors.gold;
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? gold.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? gold.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Radio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: gold,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? gold : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body basics: weight / height / age row + a sex segmented control. The parent
/// owns the three controllers and the selected sex.
class BodyStatsForm extends StatelessWidget {
  final TextEditingController weightCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController ageCtrl;
  final String sex; // 'male' | 'female'
  final ValueChanged<String> onSexChanged;
  const BodyStatsForm({
    super.key,
    required this.weightCtrl,
    required this.heightCtrl,
    required this.ageCtrl,
    required this.sex,
    required this.onSexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
              child: AppTextField(
                  controller: weightCtrl,
                  label: 'Weight',
                  suffix: const Text('kg'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(
              child: AppTextField(
                  controller: heightCtrl,
                  label: 'Height',
                  suffix: const Text('cm'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(
              child: AppTextField(
                  controller: ageCtrl,
                  label: 'Age',
                  suffix: const Text('yrs'),
                  keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 20),
        Text(
          'Sex',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        AppSegmentedControl<String>(
          segments: const [
            (value: 'male', label: 'Male', icon: null),
            (value: 'female', label: 'Female', icon: null),
          ],
          selected: sex,
          onChanged: onSexChanged,
        ),
      ],
    );
  }
}

/// Human-readable description for each activity level (shared so both flows use
/// identical copy).
String activityLevelDescription(ActivityLevel level) {
  switch (level) {
    case ActivityLevel.sedentary:
      return 'Little or no exercise';
    case ActivityLevel.lightlyActive:
      return '1–3 days/week';
    case ActivityLevel.moderatelyActive:
      return '3–5 days/week';
    case ActivityLevel.veryActive:
      return '6–7 days/week';
  }
}

/// Activity-level radio list over [ActivityLevel.values].
class ActivityLevelSelector extends StatelessWidget {
  final ActivityLevel selected;
  final ValueChanged<ActivityLevel> onChanged;
  const ActivityLevelSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...ActivityLevel.values.map((level) => TdeeRadioTile<ActivityLevel>(
              label: level.label,
              subtitle: activityLevelDescription(level),
              value: level,
              groupValue: selected,
              onChanged: (v) => onChanged(v!),
            )),
      ],
    );
  }
}
