import 'package:flutter/material.dart';
import '../../../models/fasting_phase.dart';
import '../../../presenters/fasting_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import 'hub_card_header.dart';

class FastingHubCard extends StatelessWidget {
  const FastingHubCard({
    super.key,
    required this.fasting,
    required this.onNavigate,
    required this.onStartFast,
    required this.onEndFast,
    this.isCompact = false,
  });

  final FastingPresenter fasting;
  final VoidCallback onNavigate;
  // Tap-to-navigate now drives all primary actions; the inline buttons were
  // removed to keep the hub uniform across modules.
  final VoidCallback onStartFast;
  final VoidCallback onEndFast;
  final bool isCompact;

  String _formatHM(int totalSeconds) {
    final abs = totalSeconds.abs();
    final h = abs ~/ 3600;
    final m = (abs % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fasting,
      builder: (context, _) {
        final isActive = fasting.isFasting;
        final theme = Theme.of(context);

        if (isCompact) {
          final subtitle = isActive
              ? 'Elapsed ${_formatHM(fasting.elapsedSeconds)}'
              : 'Tap to start fasting';
          return AppCard(
            onTap: onNavigate,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isActive ? Icons.timer : Icons.timer_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Fasting',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  AppBadge(
                    text: 'ACTIVE',
                    color: context.appColors.success,
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          );
        }

        return AppCard(
          onTap: onNavigate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          header: HubCardHeader(
            icon: isActive ? Icons.timer : Icons.timer_outlined,
            title: 'Fasting',
            accentColor: theme.colorScheme.primary,
            isActive: isActive,
          ),
          child: isActive
              ? _ActiveSnapshot(fasting: fasting, formatHM: _formatHM)
              : _IdleSnapshot(fasting: fasting),
        );
      },
    );
  }
}

class _IdleSnapshot extends StatelessWidget {
  const _IdleSnapshot({required this.fasting});
  final FastingPresenter fasting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eatingWindow = 24 - fasting.fastingGoalHours;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ready to start', style: AppTextStyles.bodyMedium),
        const SizedBox(height: 2),
        Text(
          '${fasting.fastingGoalHours}:$eatingWindow protocol',
          style: AppTextStyles.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ActiveSnapshot extends StatelessWidget {
  const _ActiveSnapshot({required this.fasting, required this.formatHM});
  final FastingPresenter fasting;
  final String Function(int) formatHM;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = fasting.targetSeconds > 0
        ? (fasting.elapsedSeconds / fasting.targetSeconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = (fasting.targetSeconds - fasting.elapsedSeconds)
        .clamp(0, fasting.targetSeconds);
    final phase = fasting.currentPhase;

    return Row(
      children: [
        AppRingProgress(
          value: progress,
          size: 80,
          strokeWidth: 6,
          primaryColor: phase.color(context),
          center: Text(
            formatHM(remaining),
            style: AppTextStyles.numeric(fontSize: 11, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatHM(fasting.elapsedSeconds),
                style: AppTextStyles.numeric(
                    fontSize: 22, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                phase.label,
                style: AppTextStyles.labelMedium
                    .copyWith(color: phase.color(context)),
              ),
              Text(
                'of ${fasting.fastingGoalHours}h goal',
                style: AppTextStyles.bodySmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
