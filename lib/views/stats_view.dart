import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../models/user_stats.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'widgets/level_up_overlay.dart';
import 'settings_screen.dart';
import 'widgets/system/system.dart';

class StatsView extends StatelessWidget {
  const StatsView({
    super.key,
    required this.presenter,
    required this.fastingPresenter,
    required this.authPresenter,
    required this.settingsPresenter,
    this.syncPresenter,
  });

  final StatsPresenter presenter;
  final FastingPresenter fastingPresenter;
  final AuthPresenter authPresenter;
  final SettingsPresenter settingsPresenter;
  final SyncPresenter? syncPresenter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([presenter, fastingPresenter]),
      builder: (context, _) {
        final stats = presenter.stats;
        return Stack(
          children: [
            AppPageScaffold.large(
              title: 'Character',
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        fastingPresenter: fastingPresenter,
                        authPresenter: authPresenter,
                        settingsPresenter: settingsPresenter,
                        syncPresenter: syncPresenter,
                      ),
                    ),
                  ),
                ),
              ],
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _HeaderCard(presenter: presenter, stats: stats),
                      const SizedBox(height: AppSpacing.md),
                      _StreaksSection(stats: stats, presenter: presenter),
                      const SizedBox(height: AppSpacing.md),
                      _AttributesSection(presenter: presenter, stats: stats),
                    ]),
                  ),
                ),
              ],
            ),
            if (presenter.showLevelUpDialog)
              LevelUpOverlay(
                newLevel: stats.level,
                onClose: presenter.dismissLevelUp,
              ),
          ],
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.presenter, required this.stats});
  final StatsPresenter presenter;
  final UserStats stats;

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(text: stats.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.trim().isNotEmpty) {
      presenter.updateName(newName.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hpPercent = (stats.currentHp / presenter.maxHp).clamp(0.0, 1.0);
    final xpPercent = (stats.currentXp / presenter.nextLevelXp).clamp(0.0, 1.0);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                presenter.rank,
                style: AppTextStyles.titleLarge.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _editName(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          stats.name,
                          style: AppTextStyles.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        presenter.jobTitle,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppStatPill(
                      label: 'Lv.',
                      value: '${stats.level}',
                      color: AppStatColor.primary,
                      size: AppStatSize.small,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppLinearProgress(
                  value: hpPercent,
                  label: 'HP',
                  valueText: '${stats.currentHp} / ${presenter.maxHp}',
                  color: theme.colorScheme.error,
                  height: 6,
                ),
                const SizedBox(height: AppSpacing.xs),
                AppLinearProgress(
                  value: xpPercent,
                  label: 'XP',
                  valueText: '${stats.currentXp} / ${presenter.nextLevelXp}',
                  height: 6,
                ),
                if (stats.statPoints > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppStatPill(
                    icon: Icons.add_circle_outline,
                    value: '${stats.statPoints} pts available',
                    color: AppStatColor.warning,
                    size: AppStatSize.small,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributesSection extends StatelessWidget {
  const _AttributesSection({required this.presenter, required this.stats});
  final StatsPresenter presenter;
  final UserStats stats;

  static const _attrDefs = [
    ('STR', Icons.fitness_center_rounded),
    ('VIT', Icons.favorite_rounded),
    ('AGI', Icons.directions_run_rounded),
    ('INT', Icons.psychology_rounded),
    ('SEN', Icons.sensors_rounded),
  ];

  int _value(String key) {
    final a = stats.attributes;
    return switch (key) {
      'STR' => a.str,
      'VIT' => a.vit,
      'AGI' => a.agi,
      'INT' => a.intl,
      'SEN' => a.sen,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final canSpend = stats.statPoints > 0;
    final rowCount = (_attrDefs.length + 1) ~/ 2;

    return AppSection(
      title: 'Attributes',
      child: Column(
        children: [
          ...List.generate(rowCount, (rowIdx) {
            final i = rowIdx * 2;
            return Padding(
              padding: EdgeInsets.only(top: rowIdx > 0 ? AppSpacing.sm : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _AttrCell(
                      label: _attrDefs[i].$1,
                      icon: _attrDefs[i].$2,
                      value: _value(_attrDefs[i].$1),
                      canSpend: canSpend,
                      onAllocate: () =>
                          presenter.allocatePoint(_attrDefs[i].$1),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: i + 1 < _attrDefs.length
                        ? _AttrCell(
                            label: _attrDefs[i + 1].$1,
                            icon: _attrDefs[i + 1].$2,
                            value: _value(_attrDefs[i + 1].$1),
                            canSpend: canSpend,
                            onAllocate: () =>
                                presenter.allocatePoint(_attrDefs[i + 1].$1),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AttrCell extends StatelessWidget {
  const _AttrCell({
    required this.label,
    required this.icon,
    required this.value,
    required this.canSpend,
    required this.onAllocate,
  });

  final String label;
  final IconData icon;
  final int value;
  final bool canSpend;
  final VoidCallback onAllocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          AppIconBadge(
            icon: icon,
            color: theme.colorScheme.primary,
            size: 32,
            iconSize: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppTextStyles.labelMedium),
                AppNumberDisplay(
                  value: '$value',
                  size: AppNumberSize.body,
                  color: theme.colorScheme.onSurface,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
          if (canSpend)
            GestureDetector(
              onTap: onAllocate,
              child: const AppIconBadge(
                icon: Icons.add,
                color: AppColors.gold,
                size: 28,
                iconSize: 14,
              ),
            ),
        ],
      ),
    );
  }
}

class _StreaksSection extends StatelessWidget {
  const _StreaksSection({required this.stats, required this.presenter});
  final UserStats stats;
  final StatsPresenter presenter;

  @override
  Widget build(BuildContext context) {
    return AppSection(
      title: 'Streaks',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AppStatPill(
              icon: Icons.local_fire_department_rounded,
              label: 'Streak',
              value: '${stats.streak}d',
              color: AppStatColor.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppStatPill(
              icon: Icons.workspace_premium_rounded,
              label: 'Rank',
              value: '${presenter.rank}-Rank',
              color: AppStatColor.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            AppStatPill(
              icon: Icons.bolt,
              label: 'Level',
              value: '${stats.level}',
              color: AppStatColor.success,
            ),
          ],
        ),
      ),
    );
  }
}
