import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../presenters/fasting_presenter.dart';
import '../../app_colors.dart';
import '../../models/quest.dart';

class QuestsTab extends StatefulWidget {
  final FastingPresenter presenter;

  const QuestsTab({super.key, required this.presenter});

  @override
  State<QuestsTab> createState() => _QuestsTabState();
}

class _QuestsTabState extends State<QuestsTab> {
  FastingPresenter get presenter => widget.presenter;
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quest Board'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : MdiIcons.swordCross),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addQuest,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: presenter,
        builder: (context, child) => _buildQuestsView(),
      ),
    );
  }

  Widget _buildQuestsView() {
    final allQuests = presenter.quests;

    if (_isEditing) {
      if (allQuests.isEmpty) return _buildEmptyState();
      return ListView.builder(
        itemCount: allQuests.length,
        itemBuilder: (context, index) => _buildQuestTile(allQuests[index]),
      );
    }

    // View Mode processing
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1 = Mon
    final today = DateTime(now.year, now.month, now.day);

    final todaysQuests = allQuests.where((q) {
      if (!q.isEnabled) return false;
      return q.days[todayWeekday - 1];
    }).toList();

    if (todaysQuests.isEmpty) return _buildEmptyState();

    final uncompletedQuests =
        todaysQuests.where((q) => !q.isCompletedOn(today)).toList();
    final finishedQuests =
        todaysQuests.where((q) => q.isCompletedOn(today)).toList();

    final activeQuests = <Quest>[];
    final missedQuests = <Quest>[];

    for (var q in uncompletedQuests) {
      final questTime =
          DateTime(now.year, now.month, now.day, q.hour, q.minute);
      if (questTime.isBefore(now)) {
        missedQuests.add(q);
      } else {
        activeQuests.add(q);
      }
    }

    int midSort(Quest a, Quest b) {
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
            child: Text('Active',
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
                const Text('Missed',
                    style: TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Tap to complete',
                    style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          ),
          ...missedQuests.map((q) => _buildQuestTile(q, isMissed: true)),
        ],
        if (finishedQuests.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Finished',
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
          Text(_isEditing ? 'No quests yet.' : 'No quests for today.'),
          if (_isEditing)
            TextButton(
                onPressed: _addQuest,
                child: const Text('Add your first quest')),
        ],
      ),
    );
  }

  Widget _buildQuestTile(Quest item, {bool isMissed = false}) {
    final originalIndex = presenter.quests.indexOf(item);
    final timeOfDay = TimeOfDay(hour: item.hour, minute: item.minute);
    final timeStr = timeOfDay.format(context);

    String daysText = 'Daily';
    List<bool> days = item.days;
    if (days.every((d) => !d)) {
      daysText = 'Never';
    } else if (!days.every((d) => d)) {
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      daysText = '';
      for (int i = 0; i < 7; i++) {
        if (days[i]) daysText += '${labels[i]} ';
      }
    }

    final dismissBackground = Container(
      color: AppColors.error,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete, color: Colors.white),
    );

    if (_isEditing) {
      return Dismissible(
        key: Key('edit_${item.id}'),
        direction: DismissDirection.endToStart,
        background: dismissBackground,
        onDismissed: (direction) => presenter.deleteQuest(originalIndex),
        child: ListTile(
          leading: Icon(MdiIcons.swordCross, color: AppColors.neutral),
          title: Text(item.title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('$timeStr • $daysText'),
          trailing: Switch(
            value: item.isEnabled,
            onChanged: (val) => presenter.toggleQuest(originalIndex, val),
          ),
          onTap: () => _editQuest(item),
        ),
      );
    } else {
      final completionDate = DateTime.now();
      final isCompleted = item.isCompletedOn(completionDate);

      return ListTile(
        key: Key('view_${item.id}_${isMissed ? 'missed' : 'active'}'),
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
                  color: isCompleted
                      ? AppColors.neutral
                      : (isMissed ? AppColors.error : null),
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  decorationThickness: 2.0,
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
                  '+${item.xpReward} XP',
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
          isMissed ? 'Overdue • $timeStr' : timeStr,
          style: TextStyle(
            color: isCompleted
                ? AppColors.neutral
                : (isMissed ? AppColors.textSecondary : null),
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted
                ? AppColors.neutral
                : (isMissed ? AppColors.error : AppColors.primary),
          ),
          onPressed: () async {
            final xp = await presenter.completeQuest(originalIndex,
                date: completionDate);
            if (xp > 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isMissed
                      ? 'Completed! +$xp XP'
                      : 'Quest Complete! +$xp XP'),
                  backgroundColor:
                      isMissed ? AppColors.secondary : AppColors.success,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      );
    }
  }

  void _addQuest() => _showQuestDialog();
  void _editQuest(Quest quest) => _showQuestDialog(quest: quest);

  Future<void> _showQuestDialog({Quest? quest}) async {
    final isEditing = quest != null;
    String? title = quest?.title;
    TimeOfDay time = quest != null
        ? TimeOfDay(hour: quest.hour, minute: quest.minute)
        : const TimeOfDay(hour: 8, minute: 0);
    List<bool> days =
        quest != null ? List.from(quest.days) : List.filled(7, true);
    bool isOneTime = quest?.isOneTime ?? false;
    int? reminderMinutes = quest?.reminderMinutes;
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    bool submitted = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final controller = TextEditingController(text: title);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isEditing ? 'Edit Quest' : 'New Quest'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Title'),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                          hintText: 'e.g., Jogging, Meds'),
                      autofocus: true,
                      onChanged: (val) => title = val,
                    ),
                    const SizedBox(height: 20),
                    const Text('Time'),
                    InkWell(
                      onTap: () async {
                        TimeOfDay tempTime = time;
                        await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Select Time'),
                              content: SizedBox(
                                width: double.maxFinite,
                                height: 200,
                                child: CupertinoTheme(
                                  data: const CupertinoThemeData(
                                    brightness: Brightness.dark,
                                    textTheme: CupertinoTextThemeData(
                                      dateTimePickerTextStyle: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                  child: CupertinoDatePicker(
                                    backgroundColor: AppColors.surface,
                                    mode: CupertinoDatePickerMode.time,
                                    initialDateTime: DateTime(
                                        2024, 1, 1, time.hour, time.minute),
                                    onDateTimeChanged: (DateTime dt) {
                                      tempTime = TimeOfDay.fromDateTime(dt);
                                    },
                                    use24hFormat: MediaQuery.of(context)
                                        .alwaysUse24HourFormat,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() => time = tempTime);
                                    Navigator.pop(context);
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.neutral),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(time.format(context),
                                style: const TextStyle(fontSize: 16)),
                            const Icon(Icons.access_time, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Reminder'),
                    DropdownButtonFormField<int?>(
                      initialValue: reminderMinutes,
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('None')),
                        DropdownMenuItem(
                            value: 5, child: Text('5 minutes before')),
                        DropdownMenuItem(
                            value: 30, child: Text('30 minutes before')),
                        DropdownMenuItem(
                            value: 60, child: Text('1 hour before')),
                      ],
                      onChanged: (val) => setState(() => reminderMinutes = val),
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      title: const Text('One-time Quest'),
                      subtitle: const Text('Deletes after completion'),
                      value: isOneTime,
                      onChanged: (val) => setState(() => isOneTime = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: isOneTime ? 0.5 : 1.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Repeat on'),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(7, (index) {
                              final isSelected = days[index];
                              return Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: InkWell(
                                  onTap: isOneTime
                                      ? null
                                      : () => setState(
                                          () => days[index] = !days[index]),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      border: Border.all(
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.neutral),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      dayLabels[index].substring(0, 1),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    title = controller.text.trim();
                    if (title == null || title!.isEmpty) return;
                    submitted = true;
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    final safeTitle = title;
    if (!submitted || safeTitle == null || safeTitle.isEmpty) return;

    if (quest != null) {
      final index = presenter.quests.indexOf(quest);
      if (index != -1) {
        await presenter.updateQuest(
            index, safeTitle, time.hour, time.minute, days,
            isOneTime: isOneTime, reminderMinutes: reminderMinutes);
      }
    } else {
      await presenter.addQuest(safeTitle, time.hour, time.minute, days,
          isOneTime: isOneTime, reminderMinutes: reminderMinutes);
    }
  }
}
