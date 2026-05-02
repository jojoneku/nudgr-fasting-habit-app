import 'package:flutter/material.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
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
          icon: Icons.restaurant_outlined,
          title: 'Nutrition',
        ),
        footer: AppPrimaryButton(label: 'Log meal', height: 44, onPressed: onLogMeal, variant: AppButtonVariant.tonal),
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
    final barColor = p.isOverGoal ? AppColors.danger : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CALORIES',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        AppLinearProgress(value: p.netCalorieProgress, color: barColor, height: 3),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Cell(value: '${p.todayCalories}', label: 'Eaten'),
            _Cell(value: '${p.remainingCalories}', label: 'Remaining', alignRight: true),
          ],
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label, this.alignRight = false});

  final String value;
  final String label;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final align = alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
        children: [
          Text(
            value,
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
    );
  }
}
