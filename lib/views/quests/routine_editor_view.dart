import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../app_colors.dart';
import '../../models/habit_routine.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
import 'widgets/quest_mission_tile.dart' show linkedStatColor, linkedStatIcon;

class RoutineEditorView extends StatefulWidget {
  final QuestPresenter presenter;
  final HabitRoutine? routine;

  const RoutineEditorView({super.key, required this.presenter, this.routine});

  @override
  State<RoutineEditorView> createState() => _RoutineEditorViewState();
}

class _RoutineEditorViewState extends State<RoutineEditorView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late TimeOfDay _time;
  late List<String> _selectedQuestIds;
  String _selectedColor = '#29B6F6';
  String _selectedIcon = 'lightning-bolt';

  static const _colorOptions = [
    '#29B6F6',
    '#66BB6A',
    '#CE93D8',
    '#FFCA28',
    '#EF5350',
    '#26C6DA',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.routine;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _time = r != null
        ? TimeOfDay(hour: r.scheduledHour, minute: r.scheduledMinute)
        : const TimeOfDay(hour: 7, minute: 0);
    _selectedQuestIds = r != null ? List.from(r.questIds) : [];
    _selectedColor = r?.colorHex ?? '#29B6F6';
    _selectedIcon = r?.icon ?? 'lightning-bolt';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.routine != null;
    final allQuests = widget.presenter.quests;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Group' : 'New Quest Group'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Name
            const Text('Group Name',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g., Morning Ritual',
                errorStyle: TextStyle(color: AppColors.danger, fontSize: 11),
              ),
              autofocus: !isEditing,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Group name is required'
                  : null,
            ),
          const SizedBox(height: 20),

          // Suggested start time
          const Text('Suggested Start Time',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          _TimeTile(time: _time, onChanged: (t) => setState(() => _time = t)),
          const SizedBox(height: 20),

          // Color
          const Text('Color',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          _ColorPicker(
            colors: _colorOptions,
            selected: _selectedColor,
            onChanged: (c) => setState(() => _selectedColor = c),
          ),
          const SizedBox(height: 24),

          // Quest selection
          const Text('Quests in this Group',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),

          if (allQuests.isEmpty)
            const Text('No quests available. Add quests first.',
                style: TextStyle(color: AppColors.textSecondary))
          else
            ...allQuests.map((q) => _QuestPickerTile(
                  quest: q,
                  isSelected: _selectedQuestIds.contains(q.id.toString()),
                  onToggle: (selected) {
                    setState(() {
                      final id = q.id.toString();
                      if (selected) {
                        if (!_selectedQuestIds.contains(id)) {
                          _selectedQuestIds.add(id);
                        }
                      } else {
                        _selectedQuestIds.remove(id);
                      }
                    });
                  },
                )),

          // Order info
          if (_selectedQuestIds.length > 1) ...[
            const SizedBox(height: 8),
            const Text(
              '💡 Quests execute in the order selected above.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    ));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();

    final existing = widget.routine;
    final messenger = ScaffoldMessenger.of(context);

    if (existing != null) {
      await widget.presenter.updateRoutine(existing.copyWith(
        name: name,
        colorHex: _selectedColor,
        icon: _selectedIcon,
        questIds: _selectedQuestIds,
        scheduledHour: _time.hour,
        scheduledMinute: _time.minute,
      ));
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      await widget.presenter.addRoutine(HabitRoutine(
        id: id,
        name: name,
        icon: _selectedIcon,
        colorHex: _selectedColor,
        questIds: _selectedQuestIds,
        scheduledHour: _time.hour,
        scheduledMinute: _time.minute,
      ));
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 12),
            Text(
              existing != null
                  ? 'Group updated.'
                  : '⚡ Group "$name" added!',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _TimeTile extends StatelessWidget {
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimeTile({required this.time, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(time.format(context), style: const TextStyle(fontSize: 16)),
            const Icon(Icons.access_time, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    TimeOfDay temp = time;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Time'),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.dark,
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle:
                    TextStyle(color: AppColors.textPrimary, fontSize: 20),
              ),
            ),
            child: CupertinoDatePicker(
              backgroundColor: AppColors.surface,
              mode: CupertinoDatePickerMode.time,
              initialDateTime: DateTime(2024, 1, 1, time.hour, time.minute),
              onDateTimeChanged: (dt) => temp = TimeOfDay.fromDateTime(dt),
              use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                onChanged(temp);
                Navigator.pop(ctx);
              },
              child: const Text('OK')),
        ],
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final List<String> colors;
  final String selected;
  final ValueChanged<String> onChanged;

  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: colors.map((hex) {
        final color = _hexToColor(hex);
        final isSelected = hex == selected;
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.5), blurRadius: 8)
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  static Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}

class _QuestPickerTile extends StatelessWidget {
  final Quest quest;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  const _QuestPickerTile({
    required this.quest,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final statColor = quest.linkedStat != null
        ? linkedStatColor(quest.linkedStat!)
        : AppColors.neutral;
    return CheckboxListTile(
      value: isSelected,
      onChanged: (v) => onToggle(v ?? false),
      activeColor: AppColors.primary,
      title: Text(quest.title),
      subtitle: Text(
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context),
        style: const TextStyle(fontSize: 12),
      ),
      secondary: Icon(
        quest.linkedStat != null
            ? linkedStatIcon(quest.linkedStat!)
            : Icons.circle,
        color: statColor,
        size: 20,
      ),
    );
  }
}
