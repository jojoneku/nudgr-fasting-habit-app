import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../../app_colors.dart';
import '../../../models/quest.dart';
import '../../../presenters/quest_presenter.dart';
import '../quest_detail_view.dart';

/// Colors for each linked stat.
Color linkedStatColor(LinkedStat stat) => switch (stat) {
      LinkedStat.str => const Color(0xFFEF5350), // red
      LinkedStat.vit => const Color(0xFF66BB6A), // green
      LinkedStat.agi => const Color(0xFF29B6F6), // cyan
      LinkedStat.intl => const Color(0xFFCE93D8), // purple
      LinkedStat.sen => const Color(0xFFFFCA28), // amber
    };

IconData linkedStatIcon(LinkedStat stat) => switch (stat) {
      LinkedStat.str => MdiIcons.weightLifter,
      LinkedStat.vit => MdiIcons.heart,
      LinkedStat.agi => MdiIcons.run,
      LinkedStat.intl => MdiIcons.brain,
      LinkedStat.sen => MdiIcons.eye,
    };

String linkedStatLabel(LinkedStat stat) => switch (stat) {
      LinkedStat.str => 'STR',
      LinkedStat.vit => 'VIT',
      LinkedStat.agi => 'AGI',
      LinkedStat.intl => 'INT',
      LinkedStat.sen => 'SEN',
    };

class QuestMissionTile extends StatelessWidget {
  final Quest quest;
  final QuestPresenter presenter;
  final bool isMissed;
  final bool isEditing;
  final bool isInsideGroup;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const QuestMissionTile({
    super.key,
    required this.quest,
    required this.presenter,
    this.isMissed = false,
    this.isEditing = false,
    this.isInsideGroup = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = quest.isCompletedToday;
    final isPartial = quest.isPartialToday;
    final statColor = quest.linkedStat != null
        ? linkedStatColor(quest.linkedStat!)
        : AppColors.primary;

    if (isEditing) {
      return _EditTile(
          quest: quest,
          onEdit: onEdit,
          onDelete: onDelete,
          statColor: statColor);
    }

    // Inside a group: no outer card wrapping, just a compact ListTile
    if (isInsideGroup) {
      return GestureDetector(
        onLongPress: () => _showDetail(context),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minVerticalPadding: 0,
          leading: _StatRing(
            quest: quest,
            presenter: presenter,
            statColor: statColor,
            isCompleted: isCompleted,
            isMissed: isMissed,
          ),
          title: _TitleRow(
              quest: quest, isCompleted: isCompleted, isMissed: isMissed),
          subtitle: _SubtitleRow(
              quest: quest, isMissed: isMissed, isCompleted: isCompleted),
          trailing: _CompletionButton(
            quest: quest,
            presenter: presenter,
            isCompleted: isCompleted,
            isPartial: isPartial,
            isMissed: isMissed,
            statColor: statColor,
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted
                ? AppColors.neutral.withValues(alpha: 0.3)
                : isMissed
                    ? AppColors.error.withValues(alpha: 0.4)
                    : statColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: _StatRing(
            quest: quest,
            presenter: presenter,
            statColor: statColor,
            isCompleted: isCompleted,
            isMissed: isMissed,
          ),
          title: _TitleRow(
              quest: quest, isCompleted: isCompleted, isMissed: isMissed),
          subtitle: _SubtitleRow(
              quest: quest, isMissed: isMissed, isCompleted: isCompleted),
          trailing: _CompletionButton(
            quest: quest,
            presenter: presenter,
            isCompleted: isCompleted,
            isPartial: isPartial,
            isMissed: isMissed,
            statColor: statColor,
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestDetailView(quest: quest, presenter: presenter),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatRing extends StatelessWidget {
  final Quest quest;
  final QuestPresenter presenter;
  final Color statColor;
  final bool isCompleted;
  final bool isMissed;

  const _StatRing({
    required this.quest,
    required this.presenter,
    required this.statColor,
    required this.isCompleted,
    required this.isMissed,
  });

  @override
  Widget build(BuildContext context) {
    final progress = presenter.statProgressFor(quest.id);
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (quest.linkedStat != null)
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: statColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                isCompleted
                    ? AppColors.neutral.withValues(alpha: 0.4)
                    : statColor,
              ),
            ),
          Icon(
            quest.linkedStat != null
                ? linkedStatIcon(quest.linkedStat!)
                : MdiIcons.circleDouble,
            color: isCompleted
                ? AppColors.neutral
                : isMissed
                    ? AppColors.error.withValues(alpha: 0.6)
                    : statColor,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final Quest quest;
  final bool isCompleted;
  final bool isMissed;

  const _TitleRow({
    required this.quest,
    required this.isCompleted,
    required this.isMissed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            quest.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCompleted
                  ? AppColors.neutral
                  : isMissed
                      ? AppColors.error
                      : AppColors.textPrimary,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              decorationThickness: 2.0,
              decorationColor: AppColors.neutral,
            ),
          ),
        ),
        if (!isCompleted) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.5), width: 0.5),
            ),
            child: Text(
              '+${quest.xpReward} XP',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  final Quest quest;
  final bool isMissed;
  final bool isCompleted;

  const _SubtitleRow({
    required this.quest,
    required this.isMissed,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context);
    final infoRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isMissed ? 'Overdue • $timeStr' : timeStr,
          style: TextStyle(
            color: isCompleted ? AppColors.neutral : AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        if (quest.streakCount > 0) ...[
          const SizedBox(width: 8),
          Text(
            '🔥 ${quest.streakCount}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
        if (quest.streakFreezes > 0) ...[
          const SizedBox(width: 4),
          Text(
            '❄️' * quest.streakFreezes,
            style: const TextStyle(fontSize: 11),
          ),
        ],
        if (quest.linkedStat != null) ...[
          const SizedBox(width: 8),
          Text(
            linkedStatLabel(quest.linkedStat!),
            style: TextStyle(
              fontSize: 11,
              color: linkedStatColor(quest.linkedStat!).withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );

    final note = quest.anchorNote?.isNotEmpty == true ? quest.anchorNote : null;

    if (note == null) return infoRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        infoRow,
        const SizedBox(height: 2),
        Text(
          note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.55),
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _CompletionButton extends StatelessWidget {
  final Quest quest;
  final QuestPresenter presenter;
  final bool isCompleted;
  final bool isPartial;
  final bool isMissed;
  final Color statColor;

  const _CompletionButton({
    required this.quest,
    required this.presenter,
    required this.isCompleted,
    required this.isPartial,
    required this.isMissed,
    required this.statColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showCompletionMenu(context),
      child: IconButton(
        iconSize: 28,
        icon: Icon(
          isCompleted
              ? Icons.check_circle
              : isPartial
                  ? Icons.adjust
                  : Icons.radio_button_unchecked,
          color: isCompleted
              ? AppColors.neutral
              : isPartial
                  ? AppColors.secondary
                  : isMissed
                      ? AppColors.error
                      : statColor,
        ),
        onPressed: () => _onTap(context),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final (xp, isCritical) = await presenter.completeQuest(quest.id);
    if (xp > 0 && context.mounted) {
      _showCompletionSnack(context, xp, isCritical);
    }
  }

  void _showCompletionMenu(BuildContext context) {
    if (quest.minimumVersion == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.neutral,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.check_circle, color: AppColors.success),
              title: const Text('Full Completion'),
              subtitle: Text('+${quest.xpReward} XP'),
              onTap: () {
                Navigator.pop(context);
                _onTap(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.adjust, color: AppColors.secondary),
              title: const Text('Minimum Version'),
              subtitle: Text(quest.minimumVersion ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                Navigator.pop(context);
                HapticFeedback.lightImpact();
                final (xp, _) = await presenter.completeQuest(
                  quest.id,
                  type: CompletionType.partial,
                );
                if (xp > 0 && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Minimum logged — streak preserved. +$xp XP'),
                    backgroundColor: AppColors.secondary,
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCompletionSnack(BuildContext context, int xp, bool isCritical) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isCritical
          ? '⚡ CRITICAL COMPLETION! +$xp XP (×2 Bonus!)'
          : isMissed
              ? 'Completed! +$xp XP'
              : 'Mission Complete! +$xp XP'),
      backgroundColor: isCritical
          ? AppColors.gold
          : isMissed
              ? AppColors.secondary
              : AppColors.success,
      duration: Duration(seconds: isCritical ? 3 : 2),
    ));
  }
}

class _EditTile extends StatelessWidget {
  final Quest quest;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Color statColor;

  const _EditTile({
    required this.quest,
    required this.onEdit,
    required this.onDelete,
    required this.statColor,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String daysText = 'Daily';
    if (quest.days.every((d) => !d)) {
      daysText = 'Never';
    } else if (!quest.days.every((d) => d)) {
      daysText = quest.days
          .asMap()
          .entries
          .where((e) => e.value)
          .map((e) => labels[e.key])
          .join(' ');
    }

    return Dismissible(
      key: Key('edit_${quest.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete?.call(),
      child: ListTile(
        leading: Icon(
          quest.linkedStat != null
              ? linkedStatIcon(quest.linkedStat!)
              : MdiIcons.swordCross,
          color: statColor,
        ),
        title: Text(quest.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$timeStr • $daysText'),
        trailing: Switch(
          value: quest.isEnabled,
          onChanged: (val) => onEdit?.call(),
        ),
        onTap: onEdit,
      ),
    );
  }
}
