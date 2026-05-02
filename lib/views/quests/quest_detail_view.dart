import 'package:flutter/material.dart';
import '../../models/quest.dart';
import '../../models/quest_achievement.dart';
import '../../presenters/quest_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../widgets/system/system.dart';
import 'add_quest_sheet.dart';
import 'widgets/habit_heatmap.dart';
import 'widgets/streak_badge.dart';
import 'widgets/quest_mission_tile.dart' show linkedStatColor, linkedStatLabel;

class QuestDetailView extends StatelessWidget {
  const QuestDetailView({
    super.key,
    required this.quest,
    required this.presenter,
  });

  final Quest quest;
  final QuestPresenter presenter;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: quest.title,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _showEdit(context),
          tooltip: 'Edit',
        ),
      ],
      padding: EdgeInsets.zero,
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, _) {
          final latest =
              presenter.quests.where((q) => q.id == quest.id).firstOrNull ??
                  quest;
          return _buildBody(context, latest);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Quest q) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
      children: [
        // Stats card
        AppCard(
          child: _StatsRow(quest: q),
        ),
        const SizedBox(height: AppSpacing.mdGenerous),

        // Habit history
        AppSection(
          title: 'Habit history',
          child: HabitHeatmap(
            dateStates: _buildDateStates(q),
            scheduledDays: q.days,
          ),
        ),
        const SizedBox(height: AppSpacing.mdGenerous),

        // Streak milestones
        AppSection(
          title: 'Streak milestones',
          child: StreakBadgeRow(
            currentStreak: q.streakCount,
            unlockedMilestones: _unlockedMilestones(q.id),
          ),
        ),

        // Stat contribution
        if (q.linkedStat != null) ...[
          const SizedBox(height: AppSpacing.mdGenerous),
          AppSection(
            title: 'Stat contribution',
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: _StatContributionBar(quest: q, presenter: presenter),
            ),
          ),
        ],

        // Anchor note
        if (q.anchorNote?.isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.mdGenerous),
          AppSection(
            title: 'Anchor',
            child: Text(
              q.anchorNote!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],

        // Minimum version
        if (q.minimumVersion?.isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.mdGenerous),
          AppSection(
            title: 'Minimum version',
            child: Text(
              q.minimumVersion!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Map<String, String> _buildDateStates(Quest q) {
    final states = <String, String>{};
    for (final d in q.completedDates) {
      states[d] = 'full';
    }
    for (final d in q.partialDates) {
      states[d] = 'partial';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 84));
    for (int i = 0; i < 84; i++) {
      final date = start.add(Duration(days: i));
      final key = date.toIso8601String().split('T')[0];
      if (!states.containsKey(key) && q.days[date.weekday - 1]) {
        states[key] = 'missed';
      }
    }
    return states;
  }

  Set<int> _unlockedMilestones(int questId) {
    return presenter.quests
        .expand((_) => <QuestAchievement>[])
        .where((a) => a.questId == questId)
        .map((a) => a.streakMilestone)
        .toSet();
  }

  Future<void> _showEdit(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddQuestSheet(presenter: presenter, quest: quest),
    );
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final rate = _completionRate();
    return IntrinsicHeight(
      child: Row(
        children: [
          _StatCell(
            value: '${quest.streakCount}',
            suffix: '🔥',
            label: 'Streak',
          ),
          VerticalDivider(
            width: AppSpacing.mdGenerous,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _StatCell(
            value: '${(rate * 100).round()}%',
            label: '30-day rate',
          ),
          VerticalDivider(
            width: AppSpacing.mdGenerous,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _StatCell(
            value:
                '${quest.completedDates.length + quest.partialDates.length}',
            label: 'Total',
          ),
        ],
      ),
    );
  }

  double _completionRate() {
    final now = DateTime.now();
    int scheduled = 0;
    int completed = 0;
    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      if (!quest.days[date.weekday - 1]) continue;
      scheduled++;
      final key = date.toIso8601String().split('T')[0];
      if (quest.completedDates.contains(key) ||
          quest.partialDates.contains(key)) {
        completed++;
      }
    }
    if (scheduled == 0) return 1.0;
    return completed / scheduled;
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.suffix});

  final String value;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            suffix != null ? '$value $suffix' : value,
            style: AppTextStyles.headlineSmall.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Stat contribution bar ────────────────────────────────────────────────────

class _StatContributionBar extends StatelessWidget {
  const _StatContributionBar({required this.quest, required this.presenter});

  final Quest quest;
  final QuestPresenter presenter;

  @override
  Widget build(BuildContext context) {
    final progress = presenter.statProgressFor(quest.id);
    final stat = quest.linkedStat!;
    final color = linkedStatColor(stat);
    final label = linkedStatLabel(stat);
    final completions = quest.streakCount % 21;

    return AppLinearProgress(
      value: progress,
      color: color,
      label: '$completions / 21 completions toward +1 $label',
      valueText: '${(progress * 100).round()}%',
      height: 8,
    );
  }
}
