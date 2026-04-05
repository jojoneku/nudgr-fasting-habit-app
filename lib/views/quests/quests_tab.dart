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
        title: const Text('Daily Missions'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _addRoutine(context),
              tooltip: 'Add Routine',
            ),
          IconButton(
            icon: Icon(_isEditing ? Icons.check : MdiIcons.swordCross),
            onPressed: () => setState(() => _isEditing = !_isEditing),
            tooltip: _isEditing ? 'Done' : 'Manage',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addQuest(context),
            tooltip: 'Add Quest',
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, _) => _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isEditing) return _buildEditView();
    return _buildDailyView();
  }

  // ─── Daily view ────────────────────────────────────────────────────────────

  Widget _buildDailyView() {
    final active = presenter.todayActiveQuests;
    final overdue = presenter.todayOverdueQuests;
    final completed = presenter.todayCompletedQuests;

    if (active.isEmpty && overdue.isEmpty && completed.isEmpty) {
      return _buildEmptyState();
    }

    // Group active/overdue by routine
    final routineQuests = <HabitRoutine, List<Quest>>{};
    final standaloneActive = <Quest>[];
    final standaloneOverdue = <Quest>[];

    for (final q in [...active, ...overdue]) {
      if (q.routineId != null) {
        final routine = presenter.routines
            .where((r) => r.id == q.routineId)
            .firstOrNull;
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Routine sections
        ...routineQuests.entries.map(
          (entry) => _RoutineSection(
            routine: entry.key,
            quests: entry.value,
            presenter: presenter,
          ),
        ),

        // Standalone active
        if (standaloneActive.isNotEmpty) ...[
          _sectionHeader('Active', AppColors.primary),
          ...standaloneActive.map((q) => QuestMissionTile(
                quest: q,
                presenter: presenter,
              )),
        ],

        // Overdue standalone
        if (standaloneOverdue.isNotEmpty) ...[
          _sectionHeader('Missed', AppColors.error,
              trailing: 'Tap to complete'),
          ...standaloneOverdue.map((q) => QuestMissionTile(
                quest: q,
                presenter: presenter,
                isMissed: true,
              )),
        ],

        // Completed
        if (completed.isNotEmpty) ...[
          _sectionHeader('Completed', AppColors.neutral),
          ...completed.map((q) => QuestMissionTile(
                quest: q,
                presenter: presenter,
              )),
        ],
      ],
    );
  }

  // ─── Edit view ────────────────────────────────────────────────────────────

  Widget _buildEditView() {
    final allQuests = presenter.quests;
    if (allQuests.isEmpty) return _buildEmptyState();

    return ListView(
      children: [
        if (presenter.routines.isNotEmpty) ...[
          _sectionHeader('Routines', AppColors.accent),
          ...presenter.routines.map((r) => _RoutineEditTile(
                routine: r,
                presenter: presenter,
                onEdit: () => _editRoutine(context, r),
                onDelete: () => presenter.deleteRoutine(r.id),
              )),
          const Divider(color: AppColors.neutral, height: 24),
        ],
        _sectionHeader('All Quests', AppColors.textSecondary),
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

  // ─── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(MdiIcons.swordCross, size: 64, color: AppColors.neutral),
          const SizedBox(height: 16),
          Text(
            _isEditing ? 'No quests yet.' : 'No missions today.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (_isEditing)
            TextButton(
              onPressed: () => _addQuest(context),
              child: const Text('Add your first quest'),
            ),
        ],
      ),
    );
  }

  // ─── Navigation helpers ────────────────────────────────────────────────────

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

  void _addRoutine(BuildContext context) =>
      _showRoutineEditor(context);
  void _editRoutine(BuildContext context, HabitRoutine routine) =>
      _showRoutineEditor(context, routine: routine);

  Future<void> _showRoutineEditor(BuildContext context,
      {HabitRoutine? routine}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          RoutineEditorView(presenter: presenter, routine: routine),
    ));
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, Color color, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.8)),
          const Spacer(),
          if (trailing != null)
            Text(trailing,
                style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Routine Section ──────────────────────────────────────────────────────────

class _RoutineSection extends StatelessWidget {
  final HabitRoutine routine;
  final List<Quest> quests;
  final QuestPresenter presenter;

  const _RoutineSection({
    required this.routine,
    required this.quests,
    required this.presenter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(MdiIcons.flash, color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text(
                routine.name.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.2), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: quests.asMap().entries.map((entry) {
              final isLast = entry.key == quests.length - 1;
              return Column(
                children: [
                  QuestMissionTile(
                    quest: entry.value,
                    presenter: presenter,
                  ),
                  if (!isLast)
                    Divider(
                        height: 1,
                        color: AppColors.neutral.withValues(alpha: 0.15),
                        indent: 16,
                        endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Routine Edit Tile ────────────────────────────────────────────────────────

class _RoutineEditTile extends StatelessWidget {
  final HabitRoutine routine;
  final QuestPresenter presenter;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutineEditTile({
    required this.routine,
    required this.presenter,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final questCount = routine.questIds.length;
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
        leading: Icon(MdiIcons.flash, color: AppColors.accent),
        title: Text(routine.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$questCount quest${questCount != 1 ? 's' : ''}'),
        trailing: const Icon(Icons.chevron_right, color: AppColors.neutral),
        onTap: onEdit,
      ),
    );
  }
}
