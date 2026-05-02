import 'package:flutter/material.dart';
import '../../../presenters/quest_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import 'hub_card_header.dart';

class QuestsHubCard extends StatelessWidget {
  const QuestsHubCard({
    super.key,
    required this.quests,
    required this.onNavigate,
    required this.onMarkComplete,
  });

  final QuestPresenter quests;
  final VoidCallback onNavigate;
  final VoidCallback onMarkComplete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: quests,
      builder: (context, _) {
        final isActive = quests.hasUrgentQuest;
        return AppCard(
          onTap: onNavigate,
          header: HubCardHeader(
            icon: isActive ? Icons.assignment_late : Icons.assignment_outlined,
            title: 'Quests',
            accentColor: AppColors.secondary,
            isActive: isActive,
          ),
          footer: isActive
              ? AppPrimaryButton(
                  label: 'Mark done',
                  height: 44,
                  onPressed: onMarkComplete,
                )
              : null,
          child: isActive
              ? _ActiveSnapshot(quests: quests)
              : _IdleSnapshot(quests: quests),
        );
      },
    );
  }
}

class _IdleSnapshot extends StatelessWidget {
  const _IdleSnapshot({required this.quests});
  final QuestPresenter quests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = quests.todayActiveQuests.length;
    final completed = quests.todayCompletedQuests.length;
    final total = active + completed;

    if (total == 0) {
      return Text(
        'No missions today',
        style: AppTextStyles.bodyMedium.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$completed / $total done',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppLinearProgress(
          value: total > 0 ? completed / total : 0.0,
          height: 4,
          color: AppColors.success,
        ),
      ],
    );
  }
}

class _ActiveSnapshot extends StatelessWidget {
  const _ActiveSnapshot({required this.quests});
  final QuestPresenter quests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quest = quests.nextUrgentQuest;
    final overdueCount = quests.todayOverdueQuests.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                quest?.title ?? 'Overdue quest',
                style: AppTextStyles.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppStatPill(
              value: '${quest?.xpReward ?? 0} XP',
              color: AppStatColor.warning,
              size: AppStatSize.small,
            ),
          ],
        ),
        if (overdueCount > 1) ...[
          const SizedBox(height: 4),
          Text(
            '+${overdueCount - 1} more overdue',
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
