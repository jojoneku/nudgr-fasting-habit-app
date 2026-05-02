import 'package:flutter/material.dart';
import '../../../presenters/fasting_presenter.dart';
import '../system/system.dart';
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
  });

  final FastingPresenter fasting;
  final VoidCallback onNavigate;
  final VoidCallback onStartFast;
  final VoidCallback onEndFast;

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
        return AppCard(
          onTap: onNavigate,
          header: HubCardHeader(
            icon: isActive ? Icons.timer : Icons.timer_outlined,
            title: 'Fasting',
            accentColor: theme.colorScheme.primary,
            isActive: isActive,
          ),
          footer: isActive
              ? AppPrimaryButton(label: 'End fast', height: 44, onPressed: onEndFast, variant: AppButtonVariant.tonal)
              : AppPrimaryButton(label: 'Start fast', height: 44, onPressed: onStartFast, variant: AppButtonVariant.tonal),
          child: isActive ? _ActiveSnapshot(fasting: fasting, formatHM: _formatHM) : _IdleSnapshot(fasting: fasting),
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
    final remaining =
        (fasting.targetSeconds - fasting.elapsedSeconds).clamp(0, fasting.targetSeconds);
    final phase = fasting.currentPhase;

    return Row(
      children: [
        AppRingProgress(
          value: progress,
          size: 80,
          strokeWidth: 6,
          primaryColor: phase.color,
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
                style: AppTextStyles.numeric(fontSize: 22, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                phase.label,
                style: AppTextStyles.labelMedium.copyWith(color: phase.color),
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
