import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/quest.dart';
import '../../models/quest_achievement.dart';
import '../../presenters/quest_presenter.dart';
import 'widgets/habit_heatmap.dart';
import 'widgets/streak_badge.dart';
import 'widgets/quest_mission_tile.dart' show linkedStatColor, linkedStatLabel;

class QuestDetailView extends StatelessWidget {
  final Quest quest;
  final QuestPresenter presenter;

  const QuestDetailView({
    super.key,
    required this.quest,
    required this.presenter,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(quest.title)),
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, _) {
          // Re-fetch from presenter to get latest data
          final latest = presenter.quests
              .where((q) => q.id == quest.id)
              .firstOrNull ?? quest;
          return _buildBody(context, latest);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Quest q) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _StatsRow(quest: q),
        const SizedBox(height: 24),
        _Section(
          title: 'Habit History',
          child: HabitHeatmap(
            dateStates: _buildDateStates(q),
            scheduledDays: q.days,
          ),
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'Streak Milestones',
          child: StreakBadgeRow(
            currentStreak: q.streakCount,
            unlockedMilestones: _unlockedMilestones(q.id),
          ),
        ),
        if (q.linkedStat != null) ...[
          const SizedBox(height: 24),
          _Section(
            title: 'Stat Contribution',
            child: _StatContributionBar(quest: q, presenter: presenter),
          ),
        ],
        if (q.anchorNote != null && q.anchorNote!.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Section(
            title: '⚓ Anchor',
            child: Text(
              q.anchorNote!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
        if (q.minimumVersion != null && q.minimumVersion!.isNotEmpty) ...[
          const SizedBox(height: 24),
          _Section(
            title: '🔩 Minimum Version',
            child: Text(
              q.minimumVersion!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
        const SizedBox(height: 40),
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
    // Mark scheduled days in last 12 weeks that aren't completed as missed
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
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final Quest quest;

  const _StatsRow({required this.quest});

  @override
  Widget build(BuildContext context) {
    final completionRate = _completionRate();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Stat(label: 'Current Streak', value: '${quest.streakCount} 🔥'),
        _Stat(label: '30-Day Rate', value: '${(completionRate * 100).round()}%'),
        _Stat(
            label: 'Total',
            value: '${quest.completedDates.length + quest.partialDates.length}'),
      ],
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _StatContributionBar extends StatelessWidget {
  final Quest quest;
  final QuestPresenter presenter;

  const _StatContributionBar(
      {required this.quest, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final progress = presenter.statProgressFor(quest.id);
    final stat = quest.linkedStat!;
    final color = linkedStatColor(stat);
    final label = linkedStatLabel(stat);
    final completions = (quest.streakCount % 21);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$completions / 21 completions toward +1 $label',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
