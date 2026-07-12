import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../presenters/nutrition_presenter.dart';

/// Header streak pill (flame + day count), driven by the nutrition log streak.
/// Hidden when there is no nutrition source or the streak is zero.
class HubStreakPill extends StatelessWidget {
  const HubStreakPill({super.key, required this.nutrition});

  final NutritionPresenter? nutrition;

  @override
  Widget build(BuildContext context) {
    final n = nutrition;
    if (n == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) {
        final count = n.logStreak;
        if (count <= 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department,
                  size: 15, color: context.appColors.bills),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }
}
