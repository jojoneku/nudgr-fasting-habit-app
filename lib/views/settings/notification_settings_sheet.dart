import 'package:flutter/material.dart';
import '../../models/notification_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';

/// Opens the notification preferences sheet as a modal bottom sheet.
///
/// [onMasterReenabled] runs after the master switch is turned back on, so the
/// caller can re-arm alarms the sheet can't reach (fasting/eating timers).
Future<void> showNotificationSettingsSheet(
  BuildContext context, {
  required StorageService storage,
  required NotificationService notifications,
  Future<void> Function()? onMasterReenabled,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NotificationSettingsSheet(
      storage: storage,
      notifications: notifications,
      onMasterReenabled: onMasterReenabled,
    ),
  );
}

class _NotificationSettingsSheet extends StatefulWidget {
  final StorageService storage;
  final NotificationService notifications;
  final Future<void> Function()? onMasterReenabled;

  const _NotificationSettingsSheet({
    required this.storage,
    required this.notifications,
    this.onMasterReenabled,
  });

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  NotificationPreferences _prefs = NotificationPreferences.defaults();
  bool _loading = true;

  /// Android-level state, loaded async. null = still checking.
  bool? _systemBlocked;
  bool? _exactAlarmsOff;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadSystemStatus();
  }

  Future<void> _loadPrefs() async {
    final prefs = await widget.storage.loadNotificationPreferences();
    if (mounted)
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
  }

  Future<void> _loadSystemStatus() async {
    final enabled = await widget.notifications.areNotificationsEnabled();
    final exact = await widget.notifications.canScheduleExactAlarms();
    if (mounted) {
      setState(() {
        _systemBlocked = !enabled;
        _exactAlarmsOff = !exact;
      });
    }
  }

  Future<void> _updatePrefs(NotificationPreferences newPrefs) async {
    setState(() => _prefs = newPrefs);
    await widget.storage.saveNotificationPreferences(newPrefs);
  }

  // ── Toggle helpers ──────────────────────────────────────────────────────────

  Future<void> _toggleMaster(bool v) async {
    await _updatePrefs(_prefs.copyWith(masterEnabled: v));
    // setMasterEnabled(false) also cancels everything already scheduled.
    await widget.notifications.setMasterEnabled(v);
    if (!v) return;

    // Re-enabled: re-request permissions and re-arm what we know about. Quest
    // and credit-due reminders re-arm on their presenters' next load.
    await widget.notifications.requestPermissions();
    if (_prefs.weightReminderEnabled) {
      await widget.notifications
          .scheduleWeightReminder(_prefs.weightReminderTime);
    }
    if (_prefs.billsReminderEnabled) {
      await widget.notifications
          .scheduleBillsReminder(_prefs.billsReminderDayOfMonth);
    }
    await widget.onMasterReenabled?.call();
    await _loadSystemStatus();
  }

  Future<void> _toggleLevelUp(bool v) async {
    await _updatePrefs(_prefs.copyWith(levelUpEnabled: v));
  }

  Future<void> _toggleRankPromotion(bool v) async {
    await _updatePrefs(_prefs.copyWith(rankPromotionEnabled: v));
  }

  Future<void> _toggleWeightReminder(bool v) async {
    await _updatePrefs(_prefs.copyWith(weightReminderEnabled: v));
    if (v) {
      await widget.notifications
          .scheduleWeightReminder(_prefs.weightReminderTime);
    } else {
      await widget.notifications.cancelWeightReminder();
    }
  }

  Future<void> _pickWeightReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _prefs.weightReminderTime,
    );
    if (picked == null || !mounted) return;
    await _updatePrefs(_prefs.copyWith(weightReminderTime: picked));
    if (_prefs.weightReminderEnabled) {
      await widget.notifications.scheduleWeightReminder(picked);
    }
  }

  Future<void> _toggleCalorieGoal(bool v) async {
    await _updatePrefs(_prefs.copyWith(calorieGoalEnabled: v));
  }

  Future<void> _toggleQuestNotifications(bool v) async {
    await _updatePrefs(_prefs.copyWith(questNotificationsEnabled: v));
  }

  Future<void> _toggleStreakAtRisk(bool v) async {
    await _updatePrefs(_prefs.copyWith(streakAtRiskEnabled: v));
  }

  Future<void> _toggleBillsReminder(bool v) async {
    await _updatePrefs(_prefs.copyWith(billsReminderEnabled: v));
    if (v) {
      await widget.notifications
          .scheduleBillsReminder(_prefs.billsReminderDayOfMonth);
    } else {
      await widget.notifications.cancelBillsReminder();
    }
  }

  Future<void> _setBillsDayOfMonth(int day) async {
    final clamped = day.clamp(1, 28);
    await _updatePrefs(_prefs.copyWith(billsReminderDayOfMonth: clamped));
    if (_prefs.billsReminderEnabled) {
      await widget.notifications.scheduleBillsReminder(clamped);
    }
  }

  Future<void> _toggleBudgetWarning(bool v) async {
    await _updatePrefs(_prefs.copyWith(budgetWarningEnabled: v));
  }

  Future<void> _setBudgetWarningPercent(int pct) async {
    await _updatePrefs(_prefs.copyWith(budgetWarningPercent: pct));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(maxHeight: screenHeight * 0.92),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Notification Preferences',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── System status ───────────────────────────────────────
                    if (_systemBlocked == true) ...[
                      _SystemBlockedBanner(
                        onOpenSettings: () async {
                          await widget.notifications
                              .openSystemNotificationSettings();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Master switch ───────────────────────────────────────
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow notifications'),
                      subtitle:
                          const Text('Master switch for all app notifications'),
                      value: _prefs.masterEnabled,
                      onChanged: _toggleMaster,
                    ),
                    if (_prefs.masterEnabled &&
                        _systemBlocked == false &&
                        _exactAlarmsOff == true)
                      _ExactAlarmWarning(
                        onAllow: () async {
                          await widget.notifications.requestPermissions();
                          await _loadSystemStatus();
                        },
                      ),
                    const SizedBox(height: 16),

                    if (_prefs.masterEnabled) ...[
                      // ── Character Achievements ──────────────────────────────
                      const _SectionHeader(label: 'Character Achievements'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Level-up notifications'),
                        subtitle: const Text('Alert when you gain a level'),
                        value: _prefs.levelUpEnabled,
                        onChanged: _toggleLevelUp,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Rank promotion notifications'),
                        subtitle:
                            const Text('Alert when you advance to a new rank'),
                        value: _prefs.rankPromotionEnabled,
                        onChanged: _toggleRankPromotion,
                      ),
                      const SizedBox(height: 16),

                      // ── Quests ──────────────────────────────────────────────
                      const _SectionHeader(label: 'Quests'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Quest reminders'),
                        subtitle:
                            const Text('Scheduled alerts for active quests'),
                        value: _prefs.questNotificationsEnabled,
                        onChanged: _toggleQuestNotifications,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Streak-at-risk alerts'),
                        subtitle: const Text(
                            'Alert when an overdue quest could break your streak'),
                        value: _prefs.streakAtRiskEnabled,
                        onChanged: _toggleStreakAtRisk,
                      ),
                      const SizedBox(height: 16),

                      // ── Nutrition ───────────────────────────────────────────
                      const _SectionHeader(label: 'Nutrition'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Weight log reminder'),
                        subtitle:
                            const Text('Daily reminder to log your weight'),
                        value: _prefs.weightReminderEnabled,
                        onChanged: _toggleWeightReminder,
                      ),
                      if (_prefs.weightReminderEnabled)
                        ListTile(
                          contentPadding: const EdgeInsets.only(left: 16),
                          leading: const Icon(Icons.access_time_outlined),
                          title: const Text('Reminder time'),
                          subtitle: Text(
                            _prefs.weightReminderTime.format(context),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: _pickWeightReminderTime,
                          minTileHeight: 48,
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Calorie goal alert'),
                        subtitle: const Text(
                            'Notify when daily calorie goal is reached'),
                        value: _prefs.calorieGoalEnabled,
                        onChanged: _toggleCalorieGoal,
                      ),
                      const SizedBox(height: 16),

                      // ── Finance ─────────────────────────────────────────────
                      const _SectionHeader(label: 'Finance'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Monthly bills reminder'),
                        subtitle: const Text(
                            'Remind you to check unpaid bills each month'),
                        value: _prefs.billsReminderEnabled,
                        onChanged: _toggleBillsReminder,
                      ),
                      if (_prefs.billsReminderEnabled)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 8),
                          child: _DayOfMonthSelector(
                            day: _prefs.billsReminderDayOfMonth,
                            onChanged: _setBillsDayOfMonth,
                          ),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Budget warnings'),
                        subtitle: const Text(
                            'Alert when spending nears the budget limit'),
                        value: _prefs.budgetWarningEnabled,
                        onChanged: _toggleBudgetWarning,
                      ),
                      if (_prefs.budgetWarningEnabled)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 8),
                          child: _BudgetWarningSlider(
                            percent: _prefs.budgetWarningPercent,
                            onChanged: _setBudgetWarningPercent,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Internal widgets ─────────────────────────────────────────────────────────

/// Shown when Android has notifications blocked/denied for the app — the
/// in-app prompt can no longer appear, so deep-link to system settings.
class _SystemBlockedBanner extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _SystemBlockedBanner({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_outlined,
                  size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notifications are blocked by Android',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Nothing the app sends will appear until you allow notifications '
            'for Nudgr in system settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpenSettings,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              child: const Text('Open system settings'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the "Alarms & reminders" special access is off — scheduled
/// timers/reminders may fire late or not at all.
class _ExactAlarmWarning extends StatelessWidget {
  final VoidCallback onAllow;
  const _ExactAlarmWarning({required this.onAllow});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.alarm_off_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Exact alarms are off — timers may fire late',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(onPressed: onAllow, child: const Text('Allow')),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Day-of-month picker with +/- buttons (1–28).
class _DayOfMonthSelector extends StatelessWidget {
  final int day;
  final ValueChanged<int> onChanged;

  const _DayOfMonthSelector({required this.day, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Remind on day', style: theme.textTheme.bodyMedium),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.remove),
            onPressed: day > 1 ? () => onChanged(day - 1) : null,
            padding: EdgeInsets.zero,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$day',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.add),
            onPressed: day < 28 ? () => onChanged(day + 1) : null,
            padding: EdgeInsets.zero,
          ),
        ),
        Text('of month', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Warn-at-percent slider (50–95, step 5).
class _BudgetWarningSlider extends StatelessWidget {
  final int percent;
  final ValueChanged<int> onChanged;

  const _BudgetWarningSlider({required this.percent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Warn at $percent% of limit',
          style: theme.textTheme.bodyMedium,
        ),
        Slider(
          value: percent.toDouble(),
          min: 50,
          max: 95,
          divisions: 9, // (95-50)/5 = 9
          label: '$percent%',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
