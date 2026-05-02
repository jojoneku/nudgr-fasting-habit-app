import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../../app_colors.dart';
import '../../../models/quest.dart';
import '../../../presenters/quest_presenter.dart';
import '../../../utils/app_motion.dart';
import '../../../utils/app_spacing.dart';
import '../../widgets/system/system.dart';
import '../quest_detail_view.dart';

Color linkedStatColor(LinkedStat stat) => switch (stat) {
      LinkedStat.str => const Color(0xFFEF5350),
      LinkedStat.vit => const Color(0xFF66BB6A),
      LinkedStat.agi => const Color(0xFF29B6F6),
      LinkedStat.intl => const Color(0xFFCE93D8),
      LinkedStat.sen => const Color(0xFFFFCA28),
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

enum _QuestAction { edit, delete }

class QuestMissionTile extends StatelessWidget {
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

  final Quest quest;
  final QuestPresenter presenter;
  final bool isMissed;
  final bool isEditing;
  final bool isInsideGroup;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      return _EditTile(quest: quest, onEdit: onEdit, onDelete: onDelete);
    }
    return _QuestTile(
      key: ValueKey(quest.id),
      quest: quest,
      presenter: presenter,
      isMissed: isMissed,
      isInsideGroup: isInsideGroup,
      onEdit: onEdit,
    );
  }
}

// ─── Daily tile ───────────────────────────────────────────────────────────────

class _QuestTile extends StatefulWidget {
  const _QuestTile({
    super.key,
    required this.quest,
    required this.presenter,
    required this.isMissed,
    required this.isInsideGroup,
    this.onEdit,
  });

  final Quest quest;
  final QuestPresenter presenter;
  final bool isMissed;
  final bool isInsideGroup;
  final VoidCallback? onEdit;

  @override
  State<_QuestTile> createState() => _QuestTileState();
}

class _QuestTileState extends State<_QuestTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl = AnimationController(
    vsync: this,
    duration: AppMotion.appear,
  );
  late final Animation<double> _scale =
      Tween<double>(begin: 1.0, end: 0.94).animate(
    CurvedAnimation(parent: _scaleCtrl, curve: AppMotion.easeOut),
  );

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Quest get q => widget.quest;
  QuestPresenter get presenter => widget.presenter;

  Color get _statColor =>
      q.linkedStat != null ? linkedStatColor(q.linkedStat!) : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final isCompleted = q.isCompletedToday;
    final isPartial = q.isPartialToday;

    return AnimatedOpacity(
      opacity: isCompleted ? 0.45 : 1.0,
      duration: AppMotion.appear,
      child: ScaleTransition(
        scale: _scale,
        child: AppListTile(
          key: Key('quest_${q.id}'),
          leading: _buildLeading(isCompleted),
          title: Text(
            q.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              decorationThickness: 1.5,
            ),
          ),
          subtitle: _buildSubtitle(context, isCompleted),
          trailing: _buildTrailing(context, isCompleted, isPartial),
          onTap: () => _showDetail(context),
          onLongPress: () => _showActionSheet(context),
          onDelete: () async {
            final confirmed = await AppConfirmDialog.confirm(
              context: context,
              title: 'Delete quest?',
              body: '"${q.title}" will be permanently deleted.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirmed) await presenter.deleteQuest(q.id);
            return confirmed;
          },
          contentPadding: EdgeInsets.symmetric(
            horizontal: widget.isInsideGroup ? AppSpacing.md : AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(bool isCompleted) {
    final progress =
        q.linkedStat != null ? presenter.statProgressFor(q.id) : 0.0;
    return AppCircularProgress(
      value: progress,
      size: 44,
      color: isCompleted ? null : _statColor,
      backgroundColor:
          isCompleted ? null : _statColor.withValues(alpha: 0.12),
      centerChild: Icon(
        q.linkedStat != null
            ? linkedStatIcon(q.linkedStat!)
            : MdiIcons.circleDouble,
        size: 20,
        color: isCompleted ? null : _statColor,
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context, bool isCompleted) {
    final timeStr =
        TimeOfDay(hour: q.hour, minute: q.minute).format(context);
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(widget.isMissed ? 'Overdue · $timeStr' : timeStr),
        if (q.streakCount > 0) Text('🔥 ${q.streakCount}'),
        if (q.streakFreezes > 0) Text('❄️' * q.streakFreezes),
        if (q.linkedStat != null)
          Text(
            linkedStatLabel(q.linkedStat!),
            style: TextStyle(
              fontSize: 11,
              color: _statColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        if (q.anchorNote?.isNotEmpty == true)
          Text(
            q.anchorNote!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
      ],
    );
  }

  Widget _buildTrailing(
      BuildContext context, bool isCompleted, bool isPartial) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isCompleted) ...[
          AppBadge(
            text: '+${q.xpReward} XP',
            color: AppColors.gold,
            variant: AppBadgeVariant.tonal,
          ),
          const SizedBox(width: 4),
        ],
        GestureDetector(
          onLongPress: q.minimumVersion != null
              ? _showMinVersionSheet
              : null,
          child: IconButton(
            iconSize: 28,
            icon: Icon(
              isCompleted
                  ? Icons.check_circle
                  : isPartial
                      ? Icons.adjust
                      : Icons.radio_button_unchecked,
              color: isCompleted
                  ? null
                  : isPartial
                      ? AppColors.secondary
                      : widget.isMissed
                          ? AppColors.error
                          : _statColor,
            ),
            onPressed: _onComplete,
          ),
        ),
      ],
    );
  }

  void _showDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestDetailView(quest: q, presenter: presenter),
      ),
    );
  }

  Future<void> _showActionSheet(BuildContext context) async {
    final action = await AppActionSheet.show<_QuestAction>(
      context: context,
      title: q.title,
      actions: [
        if (widget.onEdit != null)
          const AppActionSheetItem(
            label: 'Edit',
            value: _QuestAction.edit,
            icon: Icons.edit_outlined,
          ),
        const AppActionSheetItem(
          label: 'Delete',
          value: _QuestAction.delete,
          icon: Icons.delete_outline,
          isDestructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _QuestAction.edit:
        widget.onEdit?.call();
      case _QuestAction.delete:
        final confirmed = await AppConfirmDialog.confirm(
          context: context,
          title: 'Delete quest?',
          body: '"${q.title}" will be permanently deleted.',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) await presenter.deleteQuest(q.id);
      case null:
        break;
    }
  }

  void _showMinVersionSheet() {
    AppBottomSheet.show<void>(
      context: context,
      title: 'Complete as...',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppListTile(
            leading:
                const Icon(Icons.check_circle_outline, color: AppColors.success),
            title: const Text('Full completion'),
            subtitle: Text('+${q.xpReward} XP'),
            onTap: () {
              Navigator.of(context).pop();
              _onComplete();
            },
          ),
          AppListTile(
            leading: const Icon(Icons.adjust, color: AppColors.secondary),
            title: const Text('Minimum version'),
            subtitle: Text(
              q.minimumVersion ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              Navigator.of(context).pop();
              HapticFeedback.lightImpact();
              final (xp, _) = await presenter.completeQuest(
                q.id,
                type: CompletionType.partial,
              );
              if (xp > 0 && mounted) {
                AppToast.show(
                    context, 'Minimum logged — streak preserved. +$xp XP');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onComplete() async {
    _scaleCtrl.forward().then((_) => _scaleCtrl.reverse());
    HapticFeedback.mediumImpact();
    final (xp, isCritical) = await presenter.completeQuest(q.id);
    if (xp > 0 && mounted) {
      AppToast.success(
        context,
        isCritical ? 'Critical hit! +$xp XP (×2)' : '+$xp XP earned',
      );
    }
  }
}

// ─── Edit mode tile ───────────────────────────────────────────────────────────

class _EditTile extends StatelessWidget {
  const _EditTile({required this.quest, this.onEdit, this.onDelete});

  final Quest quest;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final statColor = quest.linkedStat != null
        ? linkedStatColor(quest.linkedStat!)
        : AppColors.neutral;
    final timeStr =
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context);
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String daysText = 'Daily';
    if (quest.days.every((d) => !d)) {
      daysText = 'Never';
    } else if (!quest.days.every((d) => d)) {
      daysText = quest.days
          .asMap()
          .entries
          .where((e) => e.value)
          .map((e) => dayLabels[e.key])
          .join(' ');
    }

    return AppListTile(
      key: Key('edit_${quest.id}'),
      leading: Icon(
        quest.linkedStat != null
            ? linkedStatIcon(quest.linkedStat!)
            : MdiIcons.swordCross,
        color: statColor,
      ),
      title: Text(quest.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$timeStr · $daysText'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onEdit,
      onDelete: onDelete != null
          ? () async {
              final confirmed = await AppConfirmDialog.confirm(
                context: context,
                title: 'Delete quest?',
                body: '"${quest.title}" will be permanently deleted.',
                confirmLabel: 'Delete',
                isDestructive: true,
              );
              if (confirmed) onDelete!();
              return confirmed;
            }
          : null,
    );
  }
}
