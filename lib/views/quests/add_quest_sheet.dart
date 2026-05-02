import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../models/habit_routine.dart';
import '../../models/quest.dart';
import '../../presenters/quest_presenter.dart';
import '../../utils/app_motion.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../widgets/system/system.dart';
import 'routine_editor_view.dart';
import 'widgets/quest_mission_tile.dart'
    show linkedStatColor, linkedStatIcon, linkedStatLabel;

class AddQuestSheet extends StatefulWidget {
  const AddQuestSheet({super.key, required this.presenter, this.quest});

  final QuestPresenter presenter;
  final Quest? quest;

  @override
  State<AddQuestSheet> createState() => _AddQuestSheetState();
}

class _AddQuestSheetState extends State<AddQuestSheet> {
  final _titleCtrl = TextEditingController();
  final _anchorCtrl = TextEditingController();
  final _minVersionCtrl = TextEditingController();
  String? _titleError;

  late TimeOfDay _time;
  late List<bool> _days;
  late bool _isOneTime;
  late int? _reminderMinutes;
  late LinkedStat? _linkedStat;
  late RecurrenceType _recurrenceType;
  late int _weeklyWeekday;
  late List<int> _monthlyDays;
  String? _selectedGroupId;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final q = widget.quest;
    _titleCtrl.text = q?.title ?? '';
    _anchorCtrl.text = q?.anchorNote ?? '';
    _minVersionCtrl.text = q?.minimumVersion ?? '';
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

  bool get _isEditing => widget.quest != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Quest' : 'New Quest',
                    style: AppTextStyles.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Title ─────────────────────────────────────────────────
                  AppSection(
                    title: 'Title',
                    child: AppTextField(
                      controller: _titleCtrl,
                      hint: 'e.g., Morning run',
                      autofocus: !_isEditing,
                      errorText: _titleError,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_titleError != null) {
                          setState(() => _titleError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.mdGenerous),

                  // ── Schedule ──────────────────────────────────────────────
                  AppSection(
                    title: 'Schedule',
                    child: Row(
                      children: [
                        Expanded(
                          child: _TimePicker(
                            time: _time,
                            onChanged: (t) => setState(() => _time = t),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
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
                  const SizedBox(height: AppSpacing.mdGenerous),

                  // ── Recurrence ────────────────────────────────────────────
                  AppSection(
                    title: 'Recurrence',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSegmentedControl<RecurrenceType>(
                          segments: const [
                            (
                              value: RecurrenceType.daily,
                              label: 'Daily',
                              icon: null
                            ),
                            (
                              value: RecurrenceType.weekly,
                              label: 'Weekly',
                              icon: null
                            ),
                            (
                              value: RecurrenceType.biweekly,
                              label: 'Bi-weekly',
                              icon: null
                            ),
                            (
                              value: RecurrenceType.monthly,
                              label: 'Monthly',
                              icon: null
                            ),
                          ],
                          selected: _recurrenceType,
                          onChanged: (t) => setState(() {
                            _recurrenceType = t;
                            if (t != RecurrenceType.daily) _isOneTime = false;
                          }),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _buildRecurrenceSubPicker(),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.mdGenerous),

                  // ── Trains attribute ──────────────────────────────────────
                  AppSection(
                    title: 'Trains attribute',
                    child: _StatPicker(
                      selected: _linkedStat,
                      onChanged: (s) => setState(() => _linkedStat = s),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.mdGenerous),

                  // ── Notes ─────────────────────────────────────────────────
                  AppSection(
                    title: 'Notes',
                    hint: 'Optional habit cue and minimum version',
                    child: Column(
                      children: [
                        AppTextField(
                          controller: _anchorCtrl,
                          hint: 'Habit cue — e.g., After morning coffee...',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppTextField(
                          controller: _minVersionCtrl,
                          hint: 'Minimum version — e.g., at least 5 push-ups',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.mdGenerous),

                  // ── Group ─────────────────────────────────────────────────
                  _GroupPicker(
                    groups: widget.presenter.routines,
                    selectedGroupId: _selectedGroupId,
                    onChanged: (id) => setState(() => _selectedGroupId = id),
                    onCreateGroup: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            RoutineEditorView(presenter: widget.presenter),
                      ));
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Save button ───────────────────────────────────────────
                  AppPrimaryButton(
                    label: _isEditing ? 'Save Changes' : 'Add Quest',
                    isLoading: _isLoading,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
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
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title:
                  const Text('One-time quest', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Deleted after completion',
                  style: TextStyle(fontSize: 11)),
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
            Text('Day of week',
                style: AppTextStyles.labelMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: AppSpacing.sm),
            _WeekdayPicker(
              selected: _weeklyWeekday,
              onChanged: (d) => setState(() => _weeklyWeekday = d),
            ),
            if (_recurrenceType == RecurrenceType.biweekly) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fires every other week starting from today.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );

      case RecurrenceType.monthly:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Day(s) of month',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
                Text(
                  'Pick 1 (monthly) or 2 (twice/month)',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
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
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Quest title is required');
      return;
    }
    if (_recurrenceType == RecurrenceType.monthly && _monthlyDays.isEmpty) {
      AppToast.error(context, 'Pick at least one day of the month.');
      return;
    }

    setState(() => _isLoading = true);
    final existing = widget.quest;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final anchorDate = existing?.recurrenceAnchorDate ?? today;

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
    AppToast.success(
        context, existing != null ? 'Quest updated.' : 'Quest "$title" added!');
    Navigator.of(context).pop();
  }
}

// ─── Time picker ──────────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  const _TimePicker({required this.time, required this.onChanged});

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(time.format(context), style: AppTextStyles.bodyMedium),
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
        title: const Text('Select time'),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(ctx).brightness,
              textTheme: const CupertinoTextThemeData(
                dateTimePickerTextStyle: TextStyle(fontSize: 20),
              ),
            ),
            child: CupertinoDatePicker(
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

// ─── Reminder dropdown ────────────────────────────────────────────────────────

class _ReminderDropdown extends StatelessWidget {
  const _ReminderDropdown({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          style: AppTextStyles.bodyMedium
              .copyWith(color: theme.colorScheme.onSurface),
          items: const [
            DropdownMenuItem(value: null, child: Text('No reminder')),
            DropdownMenuItem(value: 5, child: Text('5 min before')),
            DropdownMenuItem(value: 30, child: Text('30 min before')),
            DropdownMenuItem(value: 60, child: Text('1 hour before')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Weekday picker (single select) ──────────────────────────────────────────

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final isSelected = i == selected;
        return InkWell(
          onTap: () => onChanged(i),
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: AppMotion.micro,
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  isSelected ? theme.colorScheme.primary : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              _labels[i],
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
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
  const _MonthDayPicker({required this.selected, required this.onChanged});

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            duration: AppMotion.micro,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.4),
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$day',
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Day picker (daily recurrence) ────────────────────────────────────────────

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.days,
    required this.enabled,
    required this.onChanged,
  });

  final List<bool> days;
  final bool enabled;
  final ValueChanged<List<bool>> onChanged;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child: AnimatedContainer(
            duration: AppMotion.micro,
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  isSelected ? theme.colorScheme.primary : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              _labels[i],
              style: TextStyle(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── Stat picker ──────────────────────────────────────────────────────────────

class _StatPicker extends StatelessWidget {
  const _StatPicker({required this.selected, required this.onChanged});

  final LinkedStat? selected;
  final ValueChanged<LinkedStat?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, null),
          ...LinkedStat.values.map((s) => _chip(context, s)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, LinkedStat? stat) {
    final isSelected = selected == stat;
    final color = stat != null ? linkedStatColor(stat) : AppColors.neutral;
    final label = stat != null ? linkedStatLabel(stat) : 'None';
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        selected: isSelected,
        selectedColor: color.withValues(alpha: 0.2),
        checkmarkColor: color,
        side: BorderSide(
            color:
                isSelected ? color : AppColors.neutral.withValues(alpha: 0.4)),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stat != null) ...[
              Icon(linkedStatIcon(stat),
                  size: 13,
                  color: isSelected ? color : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  color: isSelected ? color : AppColors.textSecondary,
                  fontSize: 12,
                )),
          ],
        ),
        onSelected: (_) => onChanged(stat),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
      ),
    );
  }
}

// ─── Group picker ─────────────────────────────────────────────────────────────

class _GroupPicker extends StatelessWidget {
  const _GroupPicker({
    required this.groups,
    required this.selectedGroupId,
    required this.onChanged,
    required this.onCreateGroup,
  });

  final List<HabitRoutine> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSection(
      title: 'Group',
      hint: 'Optional',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GroupOption(
            label: 'No group',
            subtitle: 'Standalone quest',
            isSelected: selectedGroupId == null,
            color: AppColors.neutral,
            onTap: () => onChanged(null),
          ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...groups.map((g) {
              final color =
                  Color(int.parse(g.colorHex.replaceFirst('#', '0xFF')));
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No groups yet.',
              style: AppTextStyles.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onCreateGroup,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('New Group'),
          ),
        ],
      ),
    );
  }
}

class _GroupOption extends StatelessWidget {
  const _GroupOption({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.micro,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
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
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: isSelected ? color : null,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                  Text(subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
