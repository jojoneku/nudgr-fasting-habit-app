import 'package:flutter/material.dart';
import '../../../models/quest.dart';
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
    required this.onCompleteQuest,
  });

  final QuestPresenter quests;
  final VoidCallback onNavigate;

  /// Completes a specific surfaced quest (per-row check action).
  final void Function(Quest quest) onCompleteQuest;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: quests,
      builder: (context, _) {
        final isActive = quests.hasUrgentQuest;
        return AppCard(
          onTap: onNavigate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          header: HubCardHeader(
            icon: isActive ? Icons.assignment_late : Icons.assignment_outlined,
            title: 'Quests',
            accentColor: Theme.of(context).colorScheme.secondary,
            isActive: isActive,
          ),
          child: isActive
              ? _ActiveSnapshot(quests: quests, onComplete: onCompleteQuest)
              : _IdleSnapshot(quests: quests, onComplete: onCompleteQuest),
        );
      },
    );
  }
}

class _IdleSnapshot extends StatelessWidget {
  const _IdleSnapshot({required this.quests, required this.onComplete});
  final QuestPresenter quests;
  final void Function(Quest quest) onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = quests.todayActiveQuests;
    final completed = quests.todayCompletedQuests.length;
    final total = active.length + completed;

    if (total == 0) {
      return Text(
        'No missions today',
        style: AppTextStyles.bodyMedium.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final preview = active.take(3).toList();
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
          height: 6,
          color: context.appColors.success,
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ...preview.map((q) => _QuoteItem(
                quest: q,
                accent: theme.colorScheme.secondary,
                onComplete: () => onComplete(q),
              )),
          if (active.length > preview.length)
            _SeeMore(
              count: active.length - preview.length,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ],
    );
  }
}

class _ActiveSnapshot extends StatelessWidget {
  const _ActiveSnapshot({required this.quests, required this.onComplete});
  final QuestPresenter quests;
  final void Function(Quest quest) onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = quests.todayOverdueQuests;
    final preview = overdue.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Each surfaced quest carries its own check → completes THAT quest in
        // place (clearer than one button that doesn't name its target). Capped
        // at 3 to avoid crowding; the rest are reachable via the card.
        ...preview.map((q) => _QuoteItem(
              quest: q,
              accent: theme.colorScheme.error,
              showXp: true,
              onComplete: () => onComplete(q),
            )),
        if (overdue.length > preview.length)
          _SeeMore(
            count: overdue.length - preview.length,
            color: theme.colorScheme.error,
            suffix: 'overdue',
          ),
      ],
    );
  }
}

class _SeeMore extends StatelessWidget {
  const _SeeMore({
    required this.count,
    required this.color,
    this.suffix,
  });

  final int count;
  final Color color;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final label =
        suffix == null ? 'See $count more' : 'See $count more $suffix';
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 14, color: color),
        ],
      ),
    );
  }
}

/// Block-quote style row: thin vertical accent bar + indent.
class _QuoteItem extends StatelessWidget {
  const _QuoteItem({
    required this.quest,
    required this.accent,
    this.showXp = false,
    this.onComplete,
  });

  final Quest quest;
  final Color accent;
  final bool showXp;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quest.title,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 11, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(
                        timeStr,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (quest.streakCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '🔥 ${quest.streakCount}',
                          style: AppTextStyles.labelSmall,
                        ),
                      ],
                      if (quest.linkedStat != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _statLabel(quest.linkedStat!),
                          style: AppTextStyles.labelSmall.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (showXp) ...[
              const SizedBox(width: AppSpacing.xs),
              AppStatPill(
                value: '${quest.xpReward} XP',
                color: AppStatColor.warning,
                size: AppStatSize.small,
              ),
            ],
            if (onComplete != null) ...[
              const SizedBox(width: 2),
              IconButton(
                onPressed: onComplete,
                icon: const Icon(Icons.check_circle_outline),
                iconSize: 22,
                color: accent,
                tooltip: 'Mark "${quest.title}" done',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _statLabel(LinkedStat stat) => switch (stat) {
        LinkedStat.str => 'STR',
        LinkedStat.vit => 'VIT',
        LinkedStat.agi => 'AGI',
        LinkedStat.intl => 'INT',
        LinkedStat.sen => 'SEN',
      };
}
