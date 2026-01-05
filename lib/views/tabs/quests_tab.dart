import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../presenters/fasting_presenter.dart';
import '../../app_colors.dart';

import '../../models/quest.dart';

class QuestsTab extends StatefulWidget {
  final FastingPresenter presenter;
  final VoidCallback onAddQuest;
  final Function(Quest) onEditQuest;
  final bool isEditing;

  const QuestsTab({
    super.key,
    required this.presenter,
    required this.onAddQuest,
    required this.onEditQuest,
    required this.isEditing,
  });

  @override
  State<QuestsTab> createState() => _QuestsTabState();
}

class _QuestsTabState extends State<QuestsTab> {
  FastingPresenter get presenter => widget.presenter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, child) {
        return _buildQuestsView();
      },
    );
  }

  Widget _buildQuestsView() {
    final allQuests = presenter.quests;

    // Filter for today if not editing
    final visibleQuests = widget.isEditing
        ? allQuests
        : allQuests.where((q) {
            if (!q.isEnabled) return false;
            // Check if today is enabled
            final today = DateTime.now().weekday; // 1 = Mon, 7 = Sun
            // days list is 0-indexed (0=Mon, 6=Sun)
            return q.days[today - 1];
          }).toList();

    if (visibleQuests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(MdiIcons.swordCross, size: 64, color: AppColors.neutral),
            const SizedBox(height: 16),
            Text(widget.isEditing ? "No quests yet." : "No quests for today."),
            if (widget.isEditing)
              TextButton(
                  onPressed: widget.onAddQuest,
                  child: const Text("Add your first quest"))
          ],
        ),
      );
    }

    // Sort by time
    visibleQuests.sort((a, b) {
      if (a.hour != b.hour) return a.hour.compareTo(b.hour);
      return a.minute.compareTo(b.minute);
    });

    if (widget.isEditing) {
      return ListView.builder(
        itemCount: visibleQuests.length,
        itemBuilder: (context, index) => _buildQuestTile(visibleQuests[index]),
      );
    }

    // View Mode: Split into Active and Finished
    final activeQuests =
        visibleQuests.where((q) => !q.isCompletedToday).toList();
    final finishedQuests =
        visibleQuests.where((q) => q.isCompletedToday).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (activeQuests.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Active",
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          ...activeQuests.map(_buildQuestTile),
        ],
        if (finishedQuests.isNotEmpty) ...[
          if (activeQuests.isNotEmpty) const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Finished",
                style: TextStyle(
                    color: AppColors.neutral, fontWeight: FontWeight.bold)),
          ),
          ...finishedQuests.map(_buildQuestTile),
        ],
      ],
    );
  }

  Widget _buildQuestTile(Quest item) {
    final originalIndex = presenter.quests.indexOf(item);
    final timeOfDay = TimeOfDay(hour: item.hour, minute: item.minute);
    final timeStr = timeOfDay.format(context);

    // Generate Days Text string
    String daysText = "Daily";
    List<bool> days = item.days;
    if (days.every((d) => !d)) {
      daysText = "Never";
    } else if (!days.every((d) => d)) {
      const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
      daysText = "";
      for (int i = 0; i < 7; i++) {
        if (days[i]) daysText += "${labels[i]} ";
      }
    }

    final dismissBackground = Container(
      color: AppColors.error,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );

    if (widget.isEditing) {
      // Edit Mode: Show all quests, allow modal editing, keep switch, no right icons
      return Dismissible(
        key: Key(item.id.toString()),
        direction: DismissDirection.endToStart,
        background: dismissBackground,
        onDismissed: (direction) => presenter.deleteQuest(originalIndex),
        child: ListTile(
          leading: Icon(MdiIcons.swordCross, color: AppColors.neutral),
          title: Text(item.title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("$timeStr • $daysText"),
          trailing: Switch(
            value: item.isEnabled,
            onChanged: (val) => presenter.toggleQuest(originalIndex, val),
          ),
          onTap: () => widget.onEditQuest(item),
        ),
      );
    } else {
      // View Mode: Show only today's quests, circle check button, grey out completed, no right icons
      return Dismissible(
        key: Key(item.id.toString()),
        direction: DismissDirection.endToStart,
        background: dismissBackground,
        onDismissed: (direction) => presenter.deleteQuest(originalIndex),
        child: ListTile(
          leading: Icon(
            MdiIcons.circleDouble,
            color:
                item.isCompletedToday ? AppColors.neutral : AppColors.primary,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: item.isCompletedToday ? AppColors.neutral : null,
                    decoration:
                        item.isCompletedToday ? TextDecoration.lineThrough : null,
                    decorationThickness: 2.0,
                  ),
                ),
              ),
              if (!item.isCompletedToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.5), width: 0.5),
                  ),
                  child: Text(
                    "+${item.xpReward} XP",
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            timeStr,
            style: TextStyle(
              color: item.isCompletedToday ? AppColors.neutral : null,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              item.isCompletedToday
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color:
                  item.isCompletedToday ? AppColors.neutral : AppColors.primary,
            ),
            onPressed: () async {
              final xp = await presenter.completeQuest(originalIndex);
              if (xp > 0 && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Quest Complete! +$xp XP"),
                    backgroundColor: AppColors.success,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ),
      );
    }
  }
}
