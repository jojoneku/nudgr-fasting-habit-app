import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../app_colors.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
import 'widgets/quest_mission_tile.dart'
    show linkedStatColor, linkedStatIcon, linkedStatLabel;

class AddQuestSheet extends StatefulWidget {
  final QuestPresenter presenter;
  final Quest? quest; // null = new quest

  const AddQuestSheet({super.key, required this.presenter, this.quest});

  @override
  State<AddQuestSheet> createState() => _AddQuestSheetState();
}

class _AddQuestSheetState extends State<AddQuestSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _anchorCtrl;
  late final TextEditingController _minVersionCtrl;

  late TimeOfDay _time;
  late List<bool> _days;
  late bool _isOneTime;
  late int? _reminderMinutes;
  late LinkedStat? _linkedStat;

  @override
  void initState() {
    super.initState();
    final q = widget.quest;
    _titleCtrl = TextEditingController(text: q?.title ?? '');
    _anchorCtrl = TextEditingController(text: q?.anchorNote ?? '');
    _minVersionCtrl = TextEditingController(text: q?.minimumVersion ?? '');
    _time = q != null
        ? TimeOfDay(hour: q.hour, minute: q.minute)
        : const TimeOfDay(hour: 8, minute: 0);
    _days = q != null ? List.from(q.days) : List.filled(7, true);
    _isOneTime = q?.isOneTime ?? false;
    _reminderMinutes = q?.reminderMinutes;
    _linkedStat = q?.linkedStat;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _anchorCtrl.dispose();
    _minVersionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.quest != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(isEditing ? 'Edit Quest' : 'New Quest',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),

            // Title
            _label('Quest Title'),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(hintText: 'e.g., Morning Run'),
              autofocus: !isEditing,
            ),
            const SizedBox(height: 20),

            // Time picker
            _label('Time'),
            _TimePicker(
                time: _time, onChanged: (t) => setState(() => _time = t)),
            const SizedBox(height: 20),

            // Stat link
            _label('Trains Attribute (optional)'),
            _StatPicker(
              selected: _linkedStat,
              onChanged: (s) => setState(() => _linkedStat = s),
            ),
            const SizedBox(height: 20),

            // Reminder
            _label('Reminder'),
            DropdownButtonFormField<int?>(
              value: _reminderMinutes,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('None')),
                DropdownMenuItem(value: 5, child: Text('5 min before')),
                DropdownMenuItem(value: 30, child: Text('30 min before')),
                DropdownMenuItem(value: 60, child: Text('1 hour before')),
              ],
              onChanged: (v) => setState(() => _reminderMinutes = v),
            ),
            const SizedBox(height: 20),

            // Anchor note
            _label('Anchor (optional)'),
            TextField(
              controller: _anchorCtrl,
              decoration: const InputDecoration(
                  hintText: 'I do this after my morning coffee...'),
            ),
            const SizedBox(height: 20),

            // Minimum version
            _label('Minimum Version (optional)'),
            TextField(
              controller: _minVersionCtrl,
              decoration: const InputDecoration(
                  hintText: 'At minimum, I will do 5 push-ups'),
            ),
            const SizedBox(height: 20),

            // One-time toggle
            SwitchListTile(
              title: const Text('One-time Quest'),
              subtitle: const Text('Deleted after completion'),
              value: _isOneTime,
              onChanged: (v) => setState(() {
                _isOneTime = v;
                if (v) _days = List.filled(7, false);
              }),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),

            // Day picker
            Opacity(
              opacity: _isOneTime ? 0.4 : 1.0,
              child: _DayPicker(
                days: _days,
                enabled: !_isOneTime,
                onChanged: (d) => setState(() => _days = d),
              ),
            ),
            const SizedBox(height: 28),

            // Save button (thumb zone)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isEditing ? 'Save Changes' : 'Add Quest',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final existing = widget.quest;
    if (existing != null) {
      await widget.presenter.updateQuest(existing.copyWith(
        title: title,
        hour: _time.hour,
        minute: _time.minute,
        days: _days,
        isOneTime: _isOneTime,
        reminderMinutes: _reminderMinutes,
        clearReminderMinutes: _reminderMinutes == null,
        linkedStat: _linkedStat,
        clearLinkedStat: _linkedStat == null,
        anchorNote:
            _anchorCtrl.text.trim().isEmpty ? null : _anchorCtrl.text.trim(),
        clearAnchorNote: _anchorCtrl.text.trim().isEmpty,
        minimumVersion: _minVersionCtrl.text.trim().isEmpty
            ? null
            : _minVersionCtrl.text.trim(),
        clearMinimumVersion: _minVersionCtrl.text.trim().isEmpty,
      ));
    } else {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await widget.presenter.addQuest(Quest(
        id: id,
        title: title,
        hour: _time.hour,
        minute: _time.minute,
        days: _days,
        isOneTime: _isOneTime,
        reminderMinutes: _reminderMinutes,
        linkedStat: _linkedStat,
        anchorNote:
            _anchorCtrl.text.trim().isEmpty ? null : _anchorCtrl.text.trim(),
        minimumVersion: _minVersionCtrl.text.trim().isEmpty
            ? null
            : _minVersionCtrl.text.trim(),
      ));
    }

    if (mounted) Navigator.of(context).pop();
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimePicker({required this.time, required this.onChanged});

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
        title: const Text('Select Time'),
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

class _StatPicker extends StatelessWidget {
  final LinkedStat? selected;
  final ValueChanged<LinkedStat?> onChanged;

  const _StatPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _chip(null),
        ...LinkedStat.values.map(_chip),
      ],
    );
  }

  Widget _chip(LinkedStat? stat) {
    final isSelected = selected == stat;
    final color = stat != null ? linkedStatColor(stat) : AppColors.neutral;
    final label = stat != null ? linkedStatLabel(stat) : 'None';
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stat != null) ...[
            Icon(linkedStatIcon(stat),
                size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12)),
        ],
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: AppColors.surface,
      side: BorderSide(
          color: isSelected ? color : AppColors.neutral.withValues(alpha: 0.4)),
      onSelected: (_) => onChanged(stat),
    );
  }
}

class _DayPicker extends StatelessWidget {
  final List<bool> days;
  final bool enabled;
  final ValueChanged<List<bool>> onChanged;

  const _DayPicker({
    required this.days,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Repeat on',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final isSelected = days[i];
            return InkWell(
              onTap: enabled
                  ? () {
                      final updated = List<bool>.from(days);
                      updated[i] = !updated[i];
                      onChanged(updated);
                    }
                  : null,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                      color:
                          isSelected ? AppColors.primary : AppColors.neutral),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  labels[i].substring(0, 1),
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
