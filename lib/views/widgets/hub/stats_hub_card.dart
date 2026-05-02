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
  });

  final StatsPresenter stats;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stats,
      builder: (context, _) => AppCard(
        onTap: onNavigate,
        header: const HubCardHeader(
          icon: Icons.person_outlined,
          title: 'Character',
        ),
        child: _Snapshot(stats: stats),
      ),
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
          height: 6,
          color: AppColors.gold,
        ),
      ],
    );
  }
}
