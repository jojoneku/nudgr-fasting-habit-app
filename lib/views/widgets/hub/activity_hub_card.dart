import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../presenters/activity_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import 'hub_card_header.dart';

class ActivityHubCard extends StatelessWidget {
  const ActivityHubCard({
    super.key,
    required this.activity,
    required this.onNavigate,
  });

  final ActivityPresenter activity;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: activity,
      builder: (context, _) => AppCard(
        onTap: onNavigate,
        header: const HubCardHeader(
          icon: Icons.directions_run_outlined,
          title: 'Activity',
        ),
        child: _Snapshot(activity: activity),
      ),
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.activity});
  final ActivityPresenter activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,###');
    final steps = activity.todaySteps;
    final goal = activity.goals.dailyStepGoal;
    final progress = activity.stepProgress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              fmt.format(steps),
              style: AppTextStyles.numeric(fontSize: 22, weight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text(
              '/ ${fmt.format(goal)} steps',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AppLinearProgress(
          value: progress,
          height: 4,
          color: activity.isGoalMet ? AppColors.success : theme.colorScheme.primary,
        ),
        if (activity.todayLog.activeCalories != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${activity.todayLog.activeCalories!.toStringAsFixed(0)} kcal active',
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
