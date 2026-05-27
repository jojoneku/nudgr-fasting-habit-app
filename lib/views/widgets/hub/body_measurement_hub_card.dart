import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/dashboard_status.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../utils/app_spacing.dart';
import '../system/system.dart';
import 'hub_card_header.dart';

class BodyMeasurementHubCard extends StatelessWidget {
  const BodyMeasurementHubCard({
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
          icon: Icons.straighten_outlined,
          title: 'Body',
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
    final latest = nutrition.latestMeasurement;

    if (latest == null) {
      return Text(
        'Log a measurement to track body composition',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final waist = latest.waistCm;
    final bf = nutrition.estimatedBodyFatPercent;
    final trend = nutrition.waistTrendDirection;
    final primary = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (waist != null) ...[
              Text(
                'Waist  ${nutrition.formatMeasurement(waist)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (bf != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '~${bf.toStringAsFixed(0)} % BF',
                  style: (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11))
                      .copyWith(
                    fontWeight: FontWeight.w600,
                    color: primary,
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
            if (trend != MeasurementTrendDirection.insufficient) ...[
              const SizedBox(width: 8),
              Text(
                _trendLabel(trend),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: trend == MeasurementTrendDirection.down
                      ? primary
                      : trend == MeasurementTrendDirection.up
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

  String _trendLabel(MeasurementTrendDirection d) => switch (d) {
        MeasurementTrendDirection.down => '↓ Waist trending down',
        MeasurementTrendDirection.up => '↑ Waist trending up',
        MeasurementTrendDirection.stable => '→ Waist stable',
        MeasurementTrendDirection.insufficient => '',
      };
}
