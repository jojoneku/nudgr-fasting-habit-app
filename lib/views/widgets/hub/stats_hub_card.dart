import 'package:flutter/material.dart';
import '../../../presenters/stats_presenter.dart';
import '../system/system.dart';
import '../../../app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import 'hub_card_header.dart';

class StatsHubCard extends StatelessWidget {
  const StatsHubCard({
    super.key,
    required this.stats,
    required this.onNavigate,
    this.isCompact = false,
  });

  final StatsPresenter stats;
  final VoidCallback onNavigate;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stats,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final level = stats.stats.level;
        final rank = stats.rank;

        if (isCompact) {
          return AppCard(
            onTap: onNavigate,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(Icons.person_outlined, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Character',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Level $level · $rank',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${stats.stats.currentXp} XP',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
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
          header: const HubCardHeader(
            icon: Icons.person_outlined,
            title: 'Character',
          ),
          child: _Snapshot(stats: stats),
        );
      },
    );
  }
}

class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.stats});
  final StatsPresenter stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = stats.stats.level;
    final currentXp = stats.stats.currentXp;
    final nextXp = stats.nextLevelXp;
    final xpProgress = nextXp > 0 ? (currentXp / nextXp).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppStatPill(
              label: 'Rank',
              value: stats.rank,
              color: AppStatColor.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Lv.$level',
              style: AppTextStyles.titleSmall.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppLinearProgress(
          label: 'XP',
          value: xpProgress,
          valueText: '$currentXp / $nextXp',
          height: 8,
          color: context.appColors.gold,
        ),
      ],
    );
  }
}
