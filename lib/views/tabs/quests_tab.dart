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

    if (widget.isEditing) {
      if (allQuests.isEmpty) {
        return _buildEmptyState();
      }
      return ListView.builder(
        itemCount: allQuests.length,
        itemBuilder: (context, index) => _buildQuestTile(allQuests[index]),
      );
    }
    
    // View Mode processing
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1 = Mon
    final today = DateTime(now.year, now.month, now.day);
    
    // Get ALL Today's Quests (Scheduled for Today)
    final todaysQuests = allQuests.where((q) {
       if (!q.isEnabled) return false;
       return q.days[todayWeekday - 1];
    }).toList();

    if (todaysQuests.isEmpty) {
      return _buildEmptyState();
    }
    
    // Filter out Already Completed
    final uncompletedQuests = todaysQuests.where((q) => !q.isCompletedOn(today)).toList();
    final finishedQuests = todaysQuests.where((q) => q.isCompletedOn(today)).toList();
    
    // Split Uncompleted into "Active" (Future) and "Missed/Overdue" (Past)
    // Active means Time is >= Now (or reasonably close)
    // Missed means Time < Now
    
    final activeQuests = <Quest>[];
    final missedQuests = <Quest>[];

    for (var q in uncompletedQuests) {
      final questTime = DateTime(now.year, now.month, now.day, q.hour, q.minute);
      if (questTime.isBefore(now)) {
        missedQuests.add(q);
      } else {
        activeQuests.add(q);
      }
    }
    
    // Sort lists
    midSort(Quest a, Quest b) {
      if (a.hour != b.hour) return a.hour.compareTo(b.hour);
      return a.minute.compareTo(b.minute);
    }
    activeQuests.sort(midSort);
    missedQuests.sort(midSort);
    finishedQuests.sort(midSort);

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
          ...activeQuests.map((q) => _buildQuestTile(q)),
        ],

        if (missedQuests.isNotEmpty) ...[
           Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text("Missed", // "Missed" technically means overdue for today
                  style: TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text("Tap to complete", style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
          ),
          ...missedQuests.map((q) => _buildQuestTile(q, isMissed: true)),
        ],
        
        if (finishedQuests.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text("Finished",
                style: TextStyle(
                    color: AppColors.neutral, fontWeight: FontWeight.bold)),
          ),
          ...finishedQuests.map((q) => _buildQuestTile(q)),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
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

  Widget _buildQuestTile(Quest item, {bool isMissed = false}) {
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
        key: Key("edit_${item.id}"),
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
      // View Mode
      // If isMissed = true, we are showing a missed quest (Overdue Today or Yesterday if we kept that)
      // Since we changed logic to "Missed Today" (Overdue), completion is for Today.
      
      final now = DateTime.now();
      // If we are dealing with "Missed (today)", the completion date is still Today.
      // Unlike "Missed (Yesterday)" where it was yesterday.
      final completionDate = DateTime.now();
          
      final isCompleted = item.isCompletedOn(completionDate);

      return ListTile(
          key: Key("view_${item.id}_${isMissed ? 'missed' : 'active'}"),
          
          leading: Icon(
            MdiIcons.circleDouble,
            color: isMissed 
                ? AppColors.error.withValues(alpha: 0.5)
                : (isCompleted ? AppColors.neutral : AppColors.primary),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? AppColors.neutral : (isMissed ? AppColors.error : null),
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    decorationThickness: 2.0,
                  ),
                ),
              ),
              if (!isCompleted) ...[ // Show XP reward if not done
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
            isMissed ? "Overdue • $timeStr" : timeStr,
            style: TextStyle(
              color: isCompleted ? AppColors.neutral : (isMissed ? AppColors.textSecondary : null),
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              isCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: isCompleted ? AppColors.neutral : (isMissed ? AppColors.error : AppColors.primary),
            ),
            onPressed: () async {
              // Pass the correct date!
              final xp = await presenter.completeQuest(originalIndex, date: completionDate);
              
              if (xp > 0 && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isMissed 
                        ? "Completed! +$xp XP" 
                        : "Quest Complete! +$xp XP"),
                    backgroundColor: isMissed ? AppColors.secondary : AppColors.success,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
      );
    }
  }
}
