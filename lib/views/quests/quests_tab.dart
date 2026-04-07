import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/habit_routine.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
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
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Quests' : 'Daily Missions'),
        actions: _isEditing
            ? [
                IconButton(
                  icon: const Icon(Icons.folder_special_outlined),
                  onPressed: () => _addRoutine(context),
                  tooltip: 'New Group',
                ),
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () => setState(() => _isEditing = false),
                  tooltip: 'Done',
                ),
              ]
            : [
                IconButton(
                  icon: Icon(MdiIcons.swordCross),
                  onPressed: () => setState(() => _isEditing = true),
                  tooltip: 'Manage',
                ),
              ],
      ),
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, _) => _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addQuest(context),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.add),
        label: const Text('Add Quest',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBody() {
    if (_isEditing) return _buildEditView();
    return _buildDailyView();
  }

  // ─── Daily view ─────────────────────────────────────────────────────────────

  Widget _buildDailyView() {
    final active = presenter.todayActiveQuests;
    final overdue = presenter.todayOverdueQuests;
    final completed = presenter.todayCompletedQuests;

    if (active.isEmpty && overdue.isEmpty && completed.isEmpty) {
      return _buildEmptyState();
    }

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

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _DailyProgressHeader(completed: completed.length, total: total),

        // Quest Groups first
        ...routineQuests.entries.map(
          (entry) => _QuestGroupSection(
            routine: entry.key,
            quests: entry.value,
            presenter: presenter,
          ),
        ),

        // Standalone active
        if (standaloneActive.isNotEmpty) ...[
          _sectionLabel('Active'),
          ...standaloneActive
              .map((q) => QuestMissionTile(quest: q, presenter: presenter)),
        ],

        // Missed
        if (standaloneOverdue.isNotEmpty) ...[
          _sectionLabel('Missed',
              color: AppColors.error, hint: 'Tap to complete'),
          ...standaloneOverdue.map((q) =>
              QuestMissionTile(quest: q, presenter: presenter, isMissed: true)),
        ],

        // Completed
        if (completed.isNotEmpty) ...[
          _sectionLabel('Completed', color: AppColors.neutral),
          ...completed
              .map((q) => QuestMissionTile(quest: q, presenter: presenter)),
        ],
      ],
    );
  }

  // ─── Edit view ──────────────────────────────────────────────────────────────

  Widget _buildEditView() {
    final allQuests = presenter.quests;
    final groups = presenter.routines;

    if (allQuests.isEmpty && groups.isEmpty) return _buildEmptyState();

    // Quests that belong to a group
    final groupedQuestIds = groups.expand((r) => r.questIds).toSet();
    final groupedQuests = allQuests
        .where((q) => groupedQuestIds.contains(q.id.toString()))
        .toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // ── Groups ─────────────────────────────────────────────────────────
        if (groups.isNotEmpty) ...[
          _editSectionLabel('Groups'),
          ...groups.map((r) {
            final members = groupedQuests
                .where((q) => r.questIds.contains(q.id.toString()))
                .toList();
            return _GroupEditTile(
              routine: r,
              memberCount: members.length,
              onEdit: () => _editRoutine(context, r),
              onDelete: () => presenter.deleteRoutine(r.id),
            );
          }),
          const Divider(
              indent: 16, endIndent: 16, height: 24, color: AppColors.neutral),
        ],

        // ── All Quests ─────────────────────────────────────────────────────
        _editSectionLabel('All Quests',
            hint: groups.isNotEmpty
                ? 'Grouped quests shown in their group above'
                : null),
        if (allQuests.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('No quests yet.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          )
        else
          ...allQuests.map((q) => QuestMissionTile(
                quest: q,
                presenter: presenter,
                isEditing: true,
                onEdit: () => _editQuest(context, q),
                onDelete: () => presenter.deleteQuest(q.id),
              )),
      ],
    );
  }

  // ─── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(MdiIcons.swordCross, size: 64, color: AppColors.neutral),
          const SizedBox(height: 16),
          Text(
            _isEditing ? 'No quests yet.' : 'No missions today.',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap  + Add Quest  to get started.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ─── Navigation helpers ─────────────────────────────────────────────────────

  void _addQuest(BuildContext context) => _showQuestSheet(context);
  void _editQuest(BuildContext context, Quest quest) =>
      _showQuestSheet(context, quest: quest);

  Future<void> _showQuestSheet(BuildContext context, {Quest? quest}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddQuestSheet(presenter: presenter, quest: quest),
    );
  }

  void _addRoutine(BuildContext context) => _showRoutineEditor(context);
  void _editRoutine(BuildContext context, HabitRoutine routine) =>
      _showRoutineEditor(context, routine: routine);

  Future<void> _showRoutineEditor(BuildContext context,
      {HabitRoutine? routine}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoutineEditorView(presenter: presenter, routine: routine),
    ));
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────────

  Widget _sectionLabel(String title,
      {Color color = AppColors.primary, String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.0)),
          const Spacer(),
          if (hint != null)
            Text(hint,
                style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 10)),
        ],
      ),
    );
  }

  Widget _editSectionLabel(String title, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.2)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

// ─── Daily Progress Header ─────────────────────────────────────────────────────

class _DailyProgressHeader extends StatelessWidget {
  final int completed;
  final int total;

  const _DailyProgressHeader({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final allDone = completed == total && total > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allDone
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                allDone ? 'All missions complete!' : 'Today\'s Missions',
                style: TextStyle(
                  color: allDone ? AppColors.success : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '$completed / $total',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (allDone) ...[
                const SizedBox(width: 6),
                const Icon(Icons.emoji_events,
                    size: 16, color: AppColors.success),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.neutral.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(
                allDone ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quest Group Section (daily view) ─────────────────────────────────────────

class _QuestGroupSection extends StatelessWidget {
  final HabitRoutine routine;
  final List<Quest> quests;
  final QuestPresenter presenter;

  const _QuestGroupSection({
    required this.routine,
    required this.quests,
    required this.presenter,
  });

  @override
  Widget build(BuildContext context) {
    final completedCount = quests
        .where((q) => presenter.todayCompletedQuests.any((c) => c.id == q.id))
        .length;
    final accentColor =
        Color(int.parse(routine.colorHex.replaceFirst('#', '0xFF')));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: accentColor.withValues(alpha: 0.25), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  // Colored pill accent
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      routine.name,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Text(
                    '$completedCount / ${quests.length}',
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Divider(
                height: 1,
                color: accentColor.withValues(alpha: 0.15),
                indent: 14,
                endIndent: 14),
            // Quests inside the group — with breathing room
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: quests.asMap().entries.map((entry) {
                  final isLast = entry.key == quests.length - 1;
                  return Column(
                    children: [
                      QuestMissionTile(
                        quest: entry.value,
                        presenter: presenter,
                        isInsideGroup: true,
                      ),
                      if (!isLast)
                        Divider(
                            height: 1,
                            color: AppColors.neutral.withValues(alpha: 0.1),
                            indent: 14,
                            endIndent: 14),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Group Edit Tile ───────────────────────────────────────────────────────────

class _GroupEditTile extends StatelessWidget {
  final HabitRoutine routine;
  final int memberCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupEditTile({
    required this.routine,
    required this.memberCount,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor =
        Color(int.parse(routine.colorHex.replaceFirst('#', '0xFF')));

    return Dismissible(
      key: Key('routine_${routine.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(routine.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          '$memberCount quest${memberCount != 1 ? 's' : ''} in this group',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.neutral, size: 20),
        onTap: onEdit,
      ),
    );
  }
}
