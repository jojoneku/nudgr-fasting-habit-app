import 'package:flutter/material.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../system/system.dart';
import 'hub_card_header.dart';

class NutritionHubCard extends StatelessWidget {
  const NutritionHubCard({
    super.key,
    required this.nutrition,
    required this.onNavigate,
    required this.onLogMeal,
  });

  final NutritionPresenter nutrition;
  final VoidCallback onNavigate;
  final VoidCallback onLogMeal;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: nutrition,
      builder: (context, _) => AppCard(
        onTap: onNavigate,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        header: const HubCardHeader(
          icon: Icons.restaurant_outlined,
          title: 'Nutrition',
        ),
        child: _Snapshot(nutrition: nutrition),
      ),
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.nutrition});
  final NutritionPresenter nutrition;

  @override
  Widget build(BuildContext context) {
    final p = nutrition;
    final theme = Theme.of(context);
    final barColor =
        p.isOverGoal ? theme.colorScheme.error : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CALORIES',
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${p.todayCalories}',
              style:
                  AppTextStyles.numeric(fontSize: 20, weight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            Text(
              '/${p.effectiveGoal} kcal',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppLinearProgress(
            value: p.netCalorieProgress, color: barColor, height: 6),
        const SizedBox(height: 14),
        Text(
          'MACROS',
          style: AppTextStyles.labelSmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        _MacrosRow(nutrition: p),
      ],
    );
  }
}

class _MacrosRow extends StatelessWidget {
  const _MacrosRow({required this.nutrition});
  final NutritionPresenter nutrition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _Macro(
            label: 'P',
            grams: nutrition.todayProtein,
            goal: nutrition.proteinGoal,
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Macro(
            label: 'C',
            grams: nutrition.todayCarbs,
            goal: nutrition.carbsGoal,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Macro(
            label: 'F',
            grams: nutrition.todayFat,
            goal: nutrition.fatGoal,
            color: theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({
    required this.label,
    required this.grams,
    required this.goal,
    required this.color,
  });

  final String label;
  final double grams;
  final int? goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        goal != null && goal! > 0 ? (grams / goal!).clamp(0.0, 1.0) : 0.0;
    final valueText = goal != null && goal! > 0
        ? '${grams.round()}/${goal}g'
        : '${grams.round()}g';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                valueText,
                style: AppTextStyles.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AppLinearProgress(value: progress, color: color, height: 5),
      ],
    );
  }
}
