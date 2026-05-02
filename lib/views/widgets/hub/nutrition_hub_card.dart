import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
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
        header: const HubCardHeader(
          icon: Icons.science_outlined,
          title: 'Nutrition',
        ),
        footer: AppPrimaryButton(label: 'Log meal', height: 44, onPressed: onLogMeal),
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
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,###');
    final kcal = nutrition.todayCalories;
    final goal = nutrition.effectiveGoal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              fmt.format(kcal),
              style: AppTextStyles.numeric(fontSize: 22, weight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text(
              '/ ${fmt.format(goal)} kcal',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _MacroBar(
          label: 'P',
          value: nutrition.proteinProgress,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 4),
        _MacroBar(
          label: 'C',
          value: nutrition.carbsProgress,
          color: AppColors.gold,
        ),
        const SizedBox(height: 4),
        _MacroBar(
          label: 'F',
          value: nutrition.fatProgress,
          color: AppColors.secondary,
        ),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: AppLinearProgress(value: value, height: 4, color: color),
        ),
      ],
    );
  }
}
