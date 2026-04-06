import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../app_colors.dart';
import '../../models/habit_routine.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
import 'routine_editor_view.dart';
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _anchorCtrl;
  late final TextEditingController _minVersionCtrl;

  late TimeOfDay _time;
  late List<bool> _days;
  late bool _isOneTime;
  late int? _reminderMinutes;
  late LinkedStat? _linkedStat;

  // Recurrence
  late RecurrenceType _recurrenceType;
  late int _weeklyWeekday; // 0=Mon..6=Sun
  late List<int> _monthlyDays;

  // Group assignment
  String? _selectedGroupId;

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
    _recurrenceType = q?.recurrenceType ?? RecurrenceType.daily;
    _weeklyWeekday = q?.weeklyWeekday ?? DateTime.now().weekday - 1;
    _monthlyDays = q != null ? List.from(q.monthlyDays) : [];
    _selectedGroupId = q?.routineId;
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
              const SizedBox(height: 14),
              Text(
                isEditing ? 'Edit Quest' : 'New Quest',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 20),

              // ── TITLE ──────────────────────────────────────────────────────
              _SectionCard(
                label: 'TITLE',
                child: TextFormField(
                  controller: _titleCtrl,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Morning Run',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    errorStyle:
                        TextStyle(color: AppColors.danger, fontSize: 11),
                  ),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 15),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Quest title is required'
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // ── SCHEDULE: Time + Reminder (side by side) ───────────────────
              _SectionCard(
                label: 'SCHEDULE',
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Time'),
                            _TimePicker(
                              time: _time,
                              onChanged: (t) => setState(() => _time = t),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Reminder'),
                            Expanded(
                              child: _ReminderDropdown(
                                value: _reminderMinutes,
                                onChanged: (v) =>
                                    setState(() => _reminderMinutes = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── RECURRENCE ─────────────────────────────────────────────────
              _SectionCard(
                label: 'RECURRENCE',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecurrenceTypePicker(
                      selected: _recurrenceType,
                      onChanged: (t) => setState(() {
                        _recurrenceType = t;
                        if (t != RecurrenceType.daily) _isOneTime = false;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _buildRecurrenceSubPicker(),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── CHARACTER ──────────────────────────────────────────────────
              _SectionCard(
                label: 'TRAINS ATTRIBUTE',
                child: _StatPicker(
                  selected: _linkedStat,
                  onChanged: (s) => setState(() => _linkedStat = s),
                ),
              ),
              const SizedBox(height: 12),

              // ── DETAILS ────────────────────────────────────────────────────
              _SectionCard(
                label: 'NOTES  (optional)',
                tooltip:
                    'Habit cue = when/where you do it.\nMinimum version = the lowest effort that still counts.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _anchorCtrl,
                      decoration: const InputDecoration(
                        hintText:
                            'Habit cue — e.g., After my morning coffee...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                    ),
                    const Divider(height: 20, color: Color(0xFF2C3340)),
                    TextFormField(
                      controller: _minVersionCtrl,
                      decoration: const InputDecoration(
                        hintText:
                            'Minimum version — e.g., at least 5 push-ups',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── GROUP (optional) ────────────────────────────────────────────
              _GroupPicker(
                groups: widget.presenter.routines,
                selectedGroupId: _selectedGroupId,
                onChanged: (id) => setState(() => _selectedGroupId = id),
                onCreateGroup: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RoutineEditorView(
                        presenter: widget.presenter),
                  ));
                  // Refresh so new group appears in the list
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 28),

              // ── SAVE BUTTON ────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
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
      ),
    );
  }

  // ─── Recurrence sub-picker ─────────────────────────────────────────────────

  Widget _buildRecurrenceSubPicker() {
    switch (_recurrenceType) {
      case RecurrenceType.daily:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: _isOneTime ? 0.4 : 1.0,
              child: _DayPicker(
                days: _days,
                enabled: !_isOneTime,
                onChanged: (d) => setState(() => _days = d),
              ),
            ),
            const SizedBox(height: 12),
            _OneTimeTile(
              value: _isOneTime,
              onChanged: (v) => setState(() {
                _isOneTime = v;
                if (v) _days = List.filled(7, false);
              }),
            ),
          ],
        );

      case RecurrenceType.weekly:
      case RecurrenceType.biweekly:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FieldLabel('Day of week'),
            const SizedBox(height: 8),
            _WeekdayPicker(
              selected: _weeklyWeekday,
              onChanged: (d) => setState(() => _weeklyWeekday = d),
            ),
            if (_recurrenceType == RecurrenceType.biweekly) ...[
              const SizedBox(height: 10),
              const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 13, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Fires every other week starting from today.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case RecurrenceType.monthly:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _FieldLabel('Day(s) of month'),
                const Spacer(),
                Text(
                  'Pick 1 (monthly) or 2 (twice/month)',
                  style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MonthDayPicker(
              selected: _monthlyDays,
              onChanged: (days) => setState(() => _monthlyDays = days),
            ),
          ],
        );
    }
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Recurrence-specific validation
    if (_recurrenceType == RecurrenceType.monthly && _monthlyDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.gold, size: 18),
            SizedBox(width: 10),
            Text('Pick at least one day of the month.',
                style: TextStyle(color: AppColors.textPrimary)),
          ]),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final title = _titleCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final existing = widget.quest;

    final today = DateTime.now().toIso8601String().split('T')[0];
    final anchorDate =
        existing?.recurrenceAnchorDate ?? today;

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
        recurrenceType: _recurrenceType,
        weeklyWeekday: _weeklyWeekday,
        monthlyDays: _monthlyDays,
        recurrenceAnchorDate: anchorDate,
      ));
      await widget.presenter.assignQuestToGroup(existing.id, _selectedGroupId);
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
        recurrenceType: _recurrenceType,
        weeklyWeekday: _weeklyWeekday,
        monthlyDays: _monthlyDays,
        recurrenceAnchorDate: anchorDate,
      ));
      await widget.presenter.assignQuestToGroup(id, _selectedGroupId);
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
              existing != null ? 'Quest updated.' : '⚔️ Quest "$title" added!',
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

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;
  final String? tooltip;

  const _SectionCard({required this.label, required this.child, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (tooltip != null) ...[
              const SizedBox(width: 5),
              Tooltip(
                message: tooltip!,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.neutral.withValues(alpha: 0.3)),
                ),
                textStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.neutral.withValues(alpha: 0.18), width: 1),
          ),
          child: child,
        ),
      ],
    );
  }
}

// ─── Small label ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Recurrence type picker ───────────────────────────────────────────────────

class _RecurrenceTypePicker extends StatelessWidget {
  final RecurrenceType selected;
  final ValueChanged<RecurrenceType> onChanged;

  const _RecurrenceTypePicker(
      {required this.selected, required this.onChanged});

  static const _labels = {
    RecurrenceType.daily: 'Daily',
    RecurrenceType.weekly: 'Weekly',
    RecurrenceType.biweekly: 'Bi-weekly',
    RecurrenceType.monthly: 'Monthly',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: RecurrenceType.values.map((type) {
        final isSelected = type == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.neutral.withValues(alpha: 0.4),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                _labels[type]!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Weekday picker (single select) ──────────────────────────────────────────

class _WeekdayPicker extends StatelessWidget {
  final int selected; // 0=Mon..6=Sun
  final ValueChanged<int> onChanged;

  const _WeekdayPicker({required this.selected, required this.onChanged});

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final isSelected = i == selected;
        return InkWell(
          onTap: () => onChanged(i),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.transparent,
              border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.neutral),
              shape: BoxShape.circle,
            ),
            child: Text(
              _labels[i],
              style: TextStyle(
                color: isSelected ? AppColors.background : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Month-day picker ─────────────────────────────────────────────────────────

class _MonthDayPicker extends StatelessWidget {
  final List<int> selected; // 1–31 day numbers
  final ValueChanged<List<int>> onChanged;

  const _MonthDayPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(31, (i) {
        final day = i + 1;
        final isSelected = selected.contains(day);
        return GestureDetector(
          onTap: () {
            final updated = List<int>.from(selected);
            if (isSelected) {
              updated.remove(day);
            } else if (updated.length < 2) {
              updated.add(day);
              updated.sort();
            }
            onChanged(updated);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.neutral.withValues(alpha: 0.4),
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$day',
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── One-time toggle ──────────────────────────────────────────────────────────

class _OneTimeTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OneTimeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: const Text('One-time Quest',
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      subtitle: const Text('Deleted after completion',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      value: value,
      onChanged: onChanged,
    );
  }
}

// ─── Time picker ──────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          border:
              Border.all(color: AppColors.neutral.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(time.format(context),
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
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

// ─── Reminder dropdown ────────────────────────────────────────────────────────

class _ReminderDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _ReminderDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 13),
          items: const [
            DropdownMenuItem(value: null, child: Text('None')),
            DropdownMenuItem(value: 5, child: Text('5 min')),
            DropdownMenuItem(value: 30, child: Text('30 min')),
            DropdownMenuItem(value: 60, child: Text('1 hour')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Stat picker ──────────────────────────────────────────────────────────────

class _StatPicker extends StatelessWidget {
  final LinkedStat? selected;
  final ValueChanged<LinkedStat?> onChanged;

  const _StatPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(null),
          ...LinkedStat.values.map(_chip),
        ],
      ),
    );
  }

  Widget _chip(LinkedStat? stat) {
    final isSelected = selected == stat;
    final color = stat != null ? linkedStatColor(stat) : AppColors.neutral;
    final label = stat != null ? linkedStatLabel(stat) : 'None';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stat != null) ...[
              Icon(linkedStatIcon(stat),
                  size: 13, color: isSelected ? AppColors.background : color),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: isSelected
                        ? AppColors.background
                        : AppColors.textSecondary,
                    fontSize: 12)),
          ],
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: Colors.transparent,
        side: BorderSide(
            color:
                isSelected ? color : AppColors.neutral.withValues(alpha: 0.4)),
        onSelected: (_) => onChanged(stat),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
    );
  }
}

// ─── Day picker (daily recurrence) ────────────────────────────────────────────

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
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
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
              labels[i],
              style: TextStyle(
                color: isSelected ? AppColors.background : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }
}

//  Group picker ─

class _GroupPicker extends StatelessWidget {
  final List<HabitRoutine> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onCreateGroup;

  const _GroupPicker({
    required this.groups,
    required this.selectedGroupId,
    required this.onChanged,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      label: 'GROUP  (optional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "No group" option — always first
          _GroupOption(
            label: 'No group',
            subtitle: 'Standalone quest',
            isSelected: selectedGroupId == null,
            color: AppColors.neutral,
            onTap: () => onChanged(null),
          ),

          if (groups.isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'No groups yet. Create one to organise quests together.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ] else ...[
            const SizedBox(height: 8),
            ...groups.map((g) {
              final color =
                  Color(int.parse(g.colorHex.replaceFirst('#', '0xFF')));
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GroupOption(
                  label: g.name,
                  subtitle:
                      '${g.questIds.length} quest${g.questIds.length != 1 ? "s" : ""}',
                  isSelected: selectedGroupId == g.id,
                  color: color,
                  onTap: () => onChanged(g.id),
                ),
              );
            }),
          ],

          // + New Group button
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onCreateGroup,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline,
                    size: 15, color: AppColors.accent),
                SizedBox(width: 6),
                Text(
                  'New Group',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _GroupOption({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : AppColors.background.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color
                : AppColors.neutral.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: isSelected ? color : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      )),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
