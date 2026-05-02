import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/habit_routine.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../widgets/system/system.dart';
import 'widgets/quest_mission_tile.dart';
import 'add_quest_sheet.dart';
import 'routine_editor_view.dart';

class QuestsTab extends StatefulWidget {
  final QuestPresenter presenter;

  const QuestsTab({super.key, required this.presenter});

  @override
  State<QuestsTab> createState() => _QuestsTabState();
}

class _QuestsTabState extends State<QuestsTab> {
  QuestPresenter get presenter => widget.presenter;
  bool _isManaging = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _isManaging ? _buildManageView() : _buildDailyView(),
    );
  }

  // ─── Daily view ─────────────────────────────────────────────────────────────

  Widget _buildDailyView() {
    final active = presenter.todayActiveQuests;
    final overdue = presenter.todayOverdueQuests;
    final completed = presenter.todayCompletedQuests;
    final isEmpty = active.isEmpty && overdue.isEmpty && completed.isEmpty;

    final routineQuests = <HabitRoutine, List<Quest>>{};
    final standaloneActive = <Quest>[];
    final standaloneOverdue = <Quest>[];

    for (final q in [...active, ...overdue]) {
      if (q.routineId != null) {
        final routine =
            presenter.routines.where((r) => r.id == q.routineId).firstOrNull;
        if (routine != null) {
          routineQuests.putIfAbsent(routine, () => []).add(q);
          continue;
        }
      }
      if (overdue.contains(q)) {
        standaloneOverdue.add(q);
      } else {
        standaloneActive.add(q);
      }
    }

    final total = active.length + overdue.length + completed.length;

    return AppPageScaffold.large(
      title: 'Quests',
      actions: [
        IconButton(
          icon: const Icon(Icons.tune_outlined),
          onPressed: () => setState(() => _isManaging = true),
          tooltip: 'Manage',
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuestSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Quest'),
      ),
      slivers: [
        if (isEmpty)
          SliverFillRemaining(
            child: AppEmptyState(
              icon: MdiIcons.swordCross,
              title: 'No quests yet',
              body: 'Add a quest to start building habits.',
              actionLabel: 'Create one',
              onAction: () => _showQuestSheet(context),
            ),
          )
        else ...[
          // Progress header
          SliverToBoxAdapter(
            child: _DailyProgressHeader(
              completed: completed.length,
              total: total,
            ),
          ),

          // Quest groups
          if (routineQuests.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverList.separated(
                itemCount: routineQuests.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final entry = routineQuests.entries.elementAt(i);
                  return _QuestGroupCard(
                    routine: entry.key,
                    quests: entry.value,
                    presenter: presenter,
                    onEditQuest: (q) => _showQuestSheet(context, quest: q),
                  );
                },
              ),
            ),

          // Today section
          if (standaloneActive.isNotEmpty)
            _QuestSection(
              title: 'Today',
              quests: standaloneActive,
              presenter: presenter,
              onEditQuest: (q) => _showQuestSheet(context, quest: q),
            ),

          // Missed section
          if (standaloneOverdue.isNotEmpty)
            _QuestSection(
              title: 'Missed',
              quests: standaloneOverdue,
              isMissed: true,
              presenter: presenter,
              onEditQuest: (q) => _showQuestSheet(context, quest: q),
            ),

          // Completed section
          if (completed.isNotEmpty)
            _QuestSection(
              title: 'Completed',
              quests: completed,
              presenter: presenter,
              onEditQuest: (q) => _showQuestSheet(context, quest: q),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ],
    );
  }

  // ─── Manage view ─────────────────────────────────────────────────────────────

  Widget _buildManageView() {
    final allQuests = presenter.quests;
    final groups = presenter.routines;
    final isEmpty = allQuests.isEmpty && groups.isEmpty;

    return AppPageScaffold.large(
      title: 'Manage',
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _isManaging = false),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.folder_special_outlined),
          onPressed: () => _showRoutineEditor(context),
          tooltip: 'New group',
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuestSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Quest'),
      ),
      slivers: [
        if (isEmpty)
          SliverFillRemaining(
            child: AppEmptyState(
              icon: MdiIcons.swordCross,
              title: 'No quests yet',
              body: 'Add a quest to start building habits.',
              actionLabel: 'Create one',
              onAction: () => _showQuestSheet(context),
            ),
          )
        else ...[
          // Groups
          if (groups.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.mdGenerous, AppSpacing.md, 0),
              sliver: SliverToBoxAdapter(
                child: AppSection(
                  title: 'Groups',
                  child: Column(
                    children: groups.map((r) {
                      final members = allQuests
                          .where((q) => r.questIds.contains(q.id.toString()))
                          .toList();
                      return _GroupEditTile(
                        routine: r,
                        memberCount: members.length,
                        onEdit: () => _showRoutineEditor(context, routine: r),
                        onDelete: () => presenter.deleteRoutine(r.id),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

          // All quests
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.mdGenerous, AppSpacing.md, 0),
            sliver: SliverToBoxAdapter(
              child: AppSection(
                title: 'All Quests',
                hint: groups.isNotEmpty
                    ? 'Grouped quests appear above'
                    : null,
                child: allQuests.isEmpty
                    ? Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Text(
                          'No quests yet.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Column(
                        children: allQuests.map((q) {
                          return QuestMissionTile(
                            quest: q,
                            presenter: presenter,
                            isEditing: true,
                            onEdit: () => _showQuestSheet(context, quest: q),
                            onDelete: () => presenter.deleteQuest(q.id),
                          );
                        }).toList(),
                      ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ],
    );
  }

  // ─── Navigation helpers ──────────────────────────────────────────────────────

  Future<void> _showQuestSheet(BuildContext context, {Quest? quest}) async {
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

  Future<void> _showRoutineEditor(BuildContext context,
      {HabitRoutine? routine}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutineEditorView(presenter: presenter, routine: routine),
    ));
  }
}

// ─── Daily progress header ─────────────────────────────────────────────────────

class _DailyProgressHeader extends StatelessWidget {
  const _DailyProgressHeader({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final allDone = total > 0 && completed == total;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  allDone ? 'All done!' : "Today's progress",
                  style: AppTextStyles.titleSmall.copyWith(
                    color: allDone
                        ? AppColors.success
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '$completed / $total',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (allDone) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.emoji_events,
                      size: 16, color: AppColors.success),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppLinearProgress(
              value: progress,
              color: allDone ? AppColors.success : null,
              height: 4,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quest section sliver ─────────────────────────────────────────────────────

class _QuestSection extends StatelessWidget {
  const _QuestSection({
    required this.title,
    required this.quests,
    required this.presenter,
    required this.onEditQuest,
    this.isMissed = false,
  });

  final String title;
  final List<Quest> quests;
  final QuestPresenter presenter;
  final ValueChanged<Quest> onEditQuest;
  final bool isMissed;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.mdGenerous, AppSpacing.md, 0),
      sliver: SliverToBoxAdapter(
        child: AppSection(
          title: title,
          child: Column(
            children: quests
                .map((q) => QuestMissionTile(
                      quest: q,
                      presenter: presenter,
                      isMissed: isMissed,
                      onEdit: () => onEditQuest(q),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Quest group card (daily view) ────────────────────────────────────────────

class _QuestGroupCard extends StatelessWidget {
  const _QuestGroupCard({
    required this.routine,
    required this.quests,
    required this.presenter,
    required this.onEditQuest,
  });

  final HabitRoutine routine;
  final List<Quest> quests;
  final QuestPresenter presenter;
  final ValueChanged<Quest> onEditQuest;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        Color(int.parse(routine.colorHex.replaceFirst('#', '0xFF')));
    final completedCount = quests
        .where((q) => presenter.todayCompletedQuests.any((c) => c.id == q.id))
        .length;

    return AppCard(
      variant: AppCardVariant.outlined,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    routine.name,
                    style: AppTextStyles.titleSmall.copyWith(
                      color: accentColor,
                    ),
                  ),
                ),
                AppBadge(
                  text: '$completedCount / ${quests.length}',
                  color: accentColor,
                  variant: AppBadgeVariant.tonal,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: accentColor.withValues(alpha: 0.15),
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
          ),
          // Quests inside group
          ...quests.asMap().entries.map((entry) {
            final isLast = entry.key == quests.length - 1;
            return Column(
              children: [
                QuestMissionTile(
                  quest: entry.value,
                  presenter: presenter,
                  isInsideGroup: true,
                  onEdit: () => onEditQuest(entry.value),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                  ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

// ─── Group edit tile (manage view) ────────────────────────────────────────────

class _GroupEditTile extends StatelessWidget {
  const _GroupEditTile({
    required this.routine,
    required this.memberCount,
    required this.onEdit,
    required this.onDelete,
  });

  final HabitRoutine routine;
  final int memberCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accentColor =
        Color(int.parse(routine.colorHex.replaceFirst('#', '0xFF')));

    return AppListTile(
      key: Key('routine_${routine.id}'),
      leading: Container(
        width: 4,
        height: 40,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: Text(routine.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '$memberCount quest${memberCount != 1 ? 's' : ''} in this group'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onEdit,
      onDelete: () async {
        final confirmed = await AppConfirmDialog.confirm(
          context: context,
          title: 'Delete group?',
          body: '"${routine.name}" will be deleted. Quests will remain.',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) onDelete();
        return confirmed;
      },
    );
  }
}
