import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../models/meal_slot.dart';
import '../../../utils/app_motion.dart';
import '../../../utils/app_spacing.dart';
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
              // groupValue/onChanged now come from the RadioGroup ancestor
              // supplied by the parent selector (new Flutter Radio API).
              value: value,
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
    return RadioGroup<ActivityLevel>(
      groupValue: selected,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      child: Column(
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
      ),
    );
  }
}

/// Step heading: bold title + muted subtitle with a trailing gap. Shared so the
/// onboarding wizard and the in-app TDEE editor read identically.
class TdeeHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const TdeeHeading(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Generic selectable card (goal / protocol). [accent] overrides the default
/// [AppThemeExtension.fast] highlight; leave null to keep the onboarding look.
class TdeeSelectCard extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  const TdeeSelectCard({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fast = accent ?? context.appColors.fast;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? fast.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? fast.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ] else if (icon != null) ...[
              Icon(icon,
                  color: selected ? fast : theme.colorScheme.onSurfaceVariant,
                  size: 22),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? theme.colorScheme.onSurface : null,
                      )),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: fast, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Small labelled stat card (e.g. BMR / TDEE).
class TdeeStatTile extends StatelessWidget {
  final String label;
  final String value;
  const TdeeStatTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Coloured macro grams tile (Protein / Carbs / Fat).
class TdeeMacroTile extends StatelessWidget {
  final String label;
  final int grams;
  final Color color;
  const TdeeMacroTile(
      {super.key,
      required this.label,
      required this.grams,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${grams}g',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

/// Count-up number (reveal ≤400ms) with an optional muted suffix.
class TdeeCountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String suffix;
  const TdeeCountUp(
      {super.key, required this.value, this.style, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: AppMotion.modal, // 300ms, within the ≤400ms budget
      curve: AppMotion.decelerate,
      builder: (context, v, _) {
        final theme = Theme.of(context);
        return RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: _fmt(v.round()),
            style: style,
            children: [
              TextSpan(
                text: suffix,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
