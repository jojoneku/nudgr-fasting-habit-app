import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/dashboard_status.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../utils/app_spacing.dart';
import '../system/system.dart';
import 'hub_card_header.dart';

class WeightHubCard extends StatelessWidget {
  const WeightHubCard({
    super.key,
    required this.nutrition,
    required this.onNavigate,
  });

  final NutritionPresenter nutrition;
  final VoidCallback onNavigate;

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
          icon: Icons.monitor_weight_outlined,
          title: 'Weight',
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
    final theme = Theme.of(context);
    final latest = nutrition.latestWeight;
    final delta = nutrition.weightDelta;
    final trend = nutrition.weightTrendDirection;

    if (latest == null) {
      return Text(
        'Log your first weight entry',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final isDown = delta != null && delta < 0;
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              latest.weightKg.toStringAsFixed(1),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'kg',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDown ? primary : theme.colorScheme.onSurfaceVariant)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDown
                        ? primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              DateFormat('MMM d').format(latest.loggedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (trend != WeightTrendDirection.insufficient) ...[
              const SizedBox(width: 8),
              Text(
                _trendLabel(trend),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: trend == WeightTrendDirection.down
                      ? primary
                      : trend == WeightTrendDirection.up
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _trendLabel(WeightTrendDirection d) => switch (d) {
        WeightTrendDirection.down => '↓ Trending down',
        WeightTrendDirection.up => '↑ Trending up',
        WeightTrendDirection.stable => '→ Stable',
        WeightTrendDirection.insufficient => '',
      };
}
