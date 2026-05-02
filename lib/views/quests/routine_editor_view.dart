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
import 'widgets/quest_mission_tile.dart' show linkedStatColor, linkedStatIcon;

class RoutineEditorView extends StatefulWidget {
  const RoutineEditorView(
      {super.key, required this.presenter, this.routine});

  final QuestPresenter presenter;
  final HabitRoutine? routine;

  @override
  State<RoutineEditorView> createState() => _RoutineEditorViewState();
}

class _RoutineEditorViewState extends State<RoutineEditorView> {
  final _nameCtrl = TextEditingController();
  String? _nameError;

  late TimeOfDay _time;
  late List<String> _selectedQuestIds;
  String _selectedColor = '#29B6F6';

  bool _isLoading = false;

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
    _nameCtrl.text = r?.name ?? '';
    _time = r != null
        ? TimeOfDay(hour: r.scheduledHour, minute: r.scheduledMinute)
        : const TimeOfDay(hour: 7, minute: 0);
    _selectedQuestIds = r != null ? List.from(r.questIds) : [];
    _selectedColor = r?.colorHex ?? '#29B6F6';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.routine != null;

  @override
  Widget build(BuildContext context) {
    final allQuests = widget.presenter.quests;

    return AppPageScaffold(
      title: _isEditing ? 'Edit Group' : 'New Quest Group',
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _save,
          child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
      padding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
        children: [
          // ── Name ───────────────────────────────────────────────────────────
          AppSection(
            title: 'Group name',
            child: AppTextField(
              controller: _nameCtrl,
              hint: 'e.g., Morning Ritual',
              autofocus: !_isEditing,
              errorText: _nameError,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.mdGenerous),

          // ── Suggested start time ────────────────────────────────────────────
          AppSection(
            title: 'Suggested start time',
            child: _TimeTile(
              time: _time,
              onChanged: (t) => setState(() => _time = t),
            ),
          ),
          const SizedBox(height: AppSpacing.mdGenerous),

          // ── Color ──────────────────────────────────────────────────────────
          AppSection(
            title: 'Color',
            child: _ColorPicker(
              colors: _colorOptions,
              selected: _selectedColor,
              onChanged: (c) => setState(() => _selectedColor = c),
            ),
          ),
          const SizedBox(height: AppSpacing.mdGenerous),

          // ── Quest selection ────────────────────────────────────────────────
          AppSection(
            title: 'Quests in this group',
            child: allQuests.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text(
                      'No quests available. Add quests first.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: allQuests
                        .map((q) => _QuestPickerTile(
                              quest: q,
                              isSelected: _selectedQuestIds
                                  .contains(q.id.toString()),
                              onToggle: (selected) => setState(() {
                                final id = q.id.toString();
                                if (selected) {
                                  _selectedQuestIds.add(id);
                                } else {
                                  _selectedQuestIds.remove(id);
                                }
                              }),
                            ))
                        .toList(),
                  ),
          ),

          if (_selectedQuestIds.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Quests execute in the order selected above.',
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // ── Save button ───────────────────────────────────────────────────
          AppPrimaryButton(
            label: _isEditing ? 'Save Changes' : 'Create Group',
            isLoading: _isLoading,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Group name is required');
      return;
    }

    setState(() => _isLoading = true);
    final existing = widget.routine;

    if (existing != null) {
      await widget.presenter.updateRoutine(existing.copyWith(
        name: name,
        colorHex: _selectedColor,
        questIds: _selectedQuestIds,
        scheduledHour: _time.hour,
        scheduledMinute: _time.minute,
      ));
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      await widget.presenter.addRoutine(HabitRoutine(
        id: id,
        name: name,
        icon: 'lightning-bolt',
        colorHex: _selectedColor,
        questIds: _selectedQuestIds,
        scheduledHour: _time.hour,
        scheduledMinute: _time.minute,
      ));
    }

    if (!mounted) return;
    AppToast.success(
        context, existing != null ? 'Group updated.' : 'Group "$name" created!');
    Navigator.of(context).pop();
  }
}

// ─── Time tile ────────────────────────────────────────────────────────────────

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.time, required this.onChanged});

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 12, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(time.format(context), style: AppTextStyles.bodyLarge),
            Icon(Icons.access_time,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
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
        title: const Text('Start time'),
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

// ─── Color picker ─────────────────────────────────────────────────────────────

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: colors.map((hex) {
        final color = Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
        final isSelected = hex == selected;
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: AppMotion.micro,
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Quest picker tile ────────────────────────────────────────────────────────

class _QuestPickerTile extends StatelessWidget {
  const _QuestPickerTile({
    required this.quest,
    required this.isSelected,
    required this.onToggle,
  });

  final Quest quest;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final statColor = quest.linkedStat != null
        ? linkedStatColor(quest.linkedStat!)
        : AppColors.neutral;
    return AppListTile(
      leading: Icon(
        quest.linkedStat != null
            ? linkedStatIcon(quest.linkedStat!)
            : Icons.circle,
        color: statColor,
        size: 20,
      ),
      title: Text(quest.title),
      subtitle: Text(
        TimeOfDay(hour: quest.hour, minute: quest.minute).format(context),
      ),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (v) => onToggle(v ?? false),
        activeColor: AppColors.primary,
      ),
      onTap: () => onToggle(!isSelected),
    );
  }
}
