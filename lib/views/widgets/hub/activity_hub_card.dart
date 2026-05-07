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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StepsColumn(activity: activity)),
          VerticalDivider(
            width: AppSpacing.md,
            thickness: 0.5,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Expanded(child: _DistanceColumn(activity: activity)),
        ],
      ),
    );
  }
}

class _StepsColumn extends StatelessWidget {
  const _StepsColumn({required this.activity});
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
        Text(
          'STEPS',
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
            Flexible(
              child: Text(
                fmt.format(steps),
                style: AppTextStyles.numeric(
                    fontSize: 20, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '/${fmt.format(goal)}',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppLinearProgress(
          value: progress,
          height: 5,
          color: activity.isGoalMet
              ? context.appColors.success
              : theme.colorScheme.primary,
        ),
      ],
    );
  }
}

class _DistanceColumn extends StatelessWidget {
  const _DistanceColumn({required this.activity});
  final ActivityPresenter activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meters = activity.todayLog.distanceMeters ?? 0.0;
    final km = meters / 1000.0;
    final goalMeters = activity.goals.dailyDistanceGoalMeters;
    final goalKm = goalMeters / 1000.0;
    final progress = activity.distanceProgress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DISTANCE',
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
            Flexible(
              child: Text(
                km.toStringAsFixed(km >= 10 ? 1 : 2),
                style: AppTextStyles.numeric(
                    fontSize: 20, weight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              goalMeters > 0 ? '/${goalKm.toStringAsFixed(1)} km' : 'km',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppLinearProgress(
          value: progress,
          height: 5,
          color: activity.isDistanceGoalMet
              ? context.appColors.success
              : theme.colorScheme.primary,
        ),
      ],
    );
  }
}
