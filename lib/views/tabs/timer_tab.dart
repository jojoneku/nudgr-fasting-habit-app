import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/fasting_phase.dart';
import '../../presenters/fasting_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../../utils/date_utils.dart' as date_utils;
import '../widgets/fast_completion_modal.dart';
import '../widgets/protocol_card.dart';
import '../widgets/refeeding_warning_sheet.dart';
import '../widgets/system/system.dart';
import 'history_tab.dart';

// Quick-pick protocol hours shown in AppSegmentedControl.
const _kQuickHours = [16, 18, 20, 24];

class TimerTab extends StatefulWidget {
  final FastingPresenter presenter;
  const TimerTab({super.key, required this.presenter});

  @override
  State<TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<TimerTab> {
  FastingPresenter get presenter => widget.presenter;

  // ── Derived helpers (pure derivations, no state) ────────────────────────────

  bool get _isEatingWindow =>
      !presenter.isFasting && presenter.eatingStartTime != null;

  bool get _isExtendedFast => presenter.fastingGoalHours >= 36;

  int get _eatingWindowHours =>
      _isExtendedFast ? 0 : (24 - presenter.fastingGoalHours).clamp(0, 24);

  bool get _hasEatingWindow => _eatingWindowHours > 0;

  double get _ringProgress {
    if (presenter.isFasting) {
      return (presenter.elapsedSeconds / presenter.targetSeconds).clamp(0.0, 1.0);
    }
    if (_isEatingWindow && _hasEatingWindow) {
      final eatingTarget = _eatingWindowHours * 3600;
      final remaining = (eatingTarget - presenter.elapsedSeconds).clamp(0, eatingTarget);
      return eatingTarget > 0 ? remaining / eatingTarget : 0.0;
    }
    return 0.0;
  }

  bool get _ringReversed => _isEatingWindow;

  Color _ringColor(BuildContext context) {
    if (presenter.isFasting) {
      return presenter.isOvertime
          ? Theme.of(context).colorScheme.error
          : presenter.currentPhase.color;
    }
    if (_isEatingWindow) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.outlineVariant;
  }

  String get _timerString {
    if (presenter.isFasting) {
      return presenter.isOvertime
          ? '+${_formatHMS(presenter.overtimeSeconds)}'
          : _formatHMS(presenter.elapsedSeconds);
    }
    if (_isEatingWindow && _hasEatingWindow) {
      final rem = (_eatingWindowHours * 3600 - presenter.elapsedSeconds).clamp(0, _eatingWindowHours * 3600);
      return _formatHMS(rem);
    }
    return '${presenter.fastingGoalHours.toString().padLeft(2, '0')}:00:00';
  }

  String get _statusLabel {
    if (presenter.isFasting) {
      return presenter.isOvertime ? 'Overdrive' : 'Fasting';
    }
    if (_isEatingWindow) {
      return _hasEatingWindow ? 'Window remaining' : 'Eating window disabled';
    }
    return 'Ready to start';
  }

  String? get _progressLabel {
    if (presenter.isFasting) {
      return '${(_ringProgress * 100).toInt()}% of ${presenter.fastingGoalHours}h goal';
    }
    if (_isEatingWindow && _hasEatingWindow) {
      final elapsed = (presenter.elapsedSeconds / (_eatingWindowHours * 3600) * 100).clamp(0.0, 100.0);
      return '${elapsed.toInt()}% elapsed';
    }
    return null;
  }

  String get _primaryActionLabel {
    if (presenter.isFasting) return 'End fast';
    return 'Start fast';
  }

  bool get _showSkipButton =>
      _isEatingWindow && _hasEatingWindow && !presenter.isFasting;

  int get _quickSelected => _kQuickHours.contains(presenter.fastingGoalHours)
      ? presenter.fastingGoalHours
      : _kQuickHours.first;

  FastingProtocol? get _currentProtocol => FastingProtocol.all
      .where((p) => p.hours == presenter.fastingGoalHours)
      .firstOrNull;

  String _formatHMS(int totalSeconds) {
    final abs = totalSeconds.abs();
    final h = abs ~/ 3600;
    final m = (abs % 3600) ~/ 60;
    final s = abs % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _format12Hour(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _onPrimaryAction() {
    if (presenter.isFasting) {
      _showStopFastDialog();
    } else {
      presenter.startFast();
    }
  }

  Future<void> _showStopFastDialog() async {
    final isShort = presenter.elapsedSeconds < 600;
    final needsRefeeding = presenter.requiresRefeedingProtocol;

    if (isShort) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Discard session?'),
          content: const Text(
              "You've fasted less than 10 minutes. Discard with no penalty?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep fasting')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Discard')),
          ],
        ),
      );
      if (shouldDiscard == true && mounted) await presenter.discardFast();
      return;
    }

    if (needsRefeeding) {
      if (!mounted) return;
      final shouldEnd = await RefeedingWarningSheet.show(context, presenter.elapsedSeconds);
      if (shouldEnd && mounted) await _doEndFast();
      return;
    }

    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End fast?'),
        content: const Text('Are you sure you want to end your fast now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End fast')),
        ],
      ),
    );
    if (shouldStop == true && mounted) await _doEndFast();
  }

  Future<void> _doEndFast() async {
    final durationHours = presenter.elapsedSeconds / 3600.0;
    final streak = presenter.currentStreak;
    final (xp, hpChange) = await presenter.stopFast();
    if (!mounted) return;
    await FastCompletionModal.show(
      context,
      FastCompletionData(
        xpEarned: xp,
        hpChange: hpChange,
        durationHours: durationHours,
        wasSuccess: durationHours >= presenter.fastingGoalHours,
        currentStreak: streak + (durationHours >= presenter.fastingGoalHours ? 1 : 0),
      ),
      onDismiss: (note) async {
        if (note != null && presenter.history.isNotEmpty) {
          final log = presenter.history.first;
          log.note = note;
          await presenter.updateLog(0, log);
        }
      },
    );
  }

  void _showFullProtocolSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FullProtocolSheet(presenter: presenter),
    );
  }

  Future<void> _editStartTime() async {
    if (presenter.startTime == null) return;
    DateTime temp = presenter.startTime!;
    final saved = await _showDateTimePicker(
      context,
      title: 'Edit start time',
      initial: temp,
    );
    if (saved != null && mounted) presenter.updateStartTime(saved);
  }

  Future<void> _editEatingTime() async {
    if (presenter.eatingStartTime == null) return;
    final saved = await _showDateTimePicker(
      context,
      title: 'Edit window start',
      initial: presenter.eatingStartTime!,
    );
    if (saved != null && mounted) presenter.updateEatingStartTime(saved);
  }

  Future<DateTime?> _showDateTimePicker(
    BuildContext context, {
    required String title,
    required DateTime initial,
  }) async {
    DateTime temp = initial;
    return showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            height: 200,
            width: double.maxFinite,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Theme.of(context).brightness,
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: initial,
                maximumDate: DateTime.now(),
                onDateTimeChanged: (v) => setLocal(() => temp = v),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, temp),
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Protocol picker — only when idle
          if (!presenter.isFasting && !_isEatingWindow) ...[
            _buildProtocolSection(context),
            const SizedBox(height: AppSpacing.md),
          ],
          // Hero ring card
          _buildRingCard(context),
          const SizedBox(height: AppSpacing.md),
          // Stats strip
          _buildStatsStrip(context),
          // History
          if (presenter.history.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildHistorySection(context),
          ],
        ],
      ),
    );
  }

  Widget _buildProtocolSection(BuildContext context) {
    final proto = _currentProtocol;
    return AppSection(
      title: 'Protocol',
      trailing: TextButton.icon(
        icon: const Icon(Icons.tune_rounded, size: 16),
        label: const Text('More'),
        onPressed: () => _showFullProtocolSheet(context),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSegmentedControl<int>(
            selected: _quickSelected,
            segments: const [
              (value: 16, label: '16:8', icon: null),
              (value: 18, label: '18:6', icon: null),
              (value: 20, label: '20:4', icon: null),
              (value: 24, label: 'OMAD', icon: null),
            ],
            onChanged: (h) => presenter.updateFastingGoal(h),
          ),
          if (proto != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${proto.rpgName} · ${proto.benefit}',
              style: AppTextStyles.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRingCard(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = _ringColor(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.mdGenerous),
      child: Column(
        children: [
          // Ring
          AppRingProgress(
            value: _ringProgress,
            size: 220,
            strokeWidth: 16,
            glowOpacity: 0.10,
            primaryColor: ringColor,
            reversed: _ringReversed,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusLabel,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                AppNumberDisplay(
                  value: _timerString,
                  size: AppNumberSize.headline,
                  color: theme.colorScheme.onSurface,
                ),
                if (presenter.isFasting) ...[
                  const SizedBox(height: 4),
                  _buildPhaseLabel(context, presenter.currentPhase),
                ],
                if (_progressLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _progressLabel!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: ringColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Time info row
          if (presenter.isFasting && presenter.startTime != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildTimeInfoRow(
              leftTitle: 'Started',
              leftValue: _format12Hour(presenter.startTime!),
              leftOnEdit: _editStartTime,
              rightTitle: 'Goal end',
              rightValue: date_utils.formatTimeWithDay(
                  presenter.startTime!
                      .add(Duration(hours: presenter.fastingGoalHours)),
                  presenter.startTime!),
            ),
          ] else if (_isEatingWindow && presenter.eatingStartTime != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildTimeInfoRow(
              leftTitle: 'Window start',
              leftValue: _format12Hour(presenter.eatingStartTime!),
              leftOnEdit: _editEatingTime,
              rightTitle: 'Window end',
              rightValue: date_utils.formatTimeWithDay(
                  presenter.eatingStartTime!
                      .add(Duration(hours: _eatingWindowHours)),
                  presenter.eatingStartTime!),
            ),
          ],
          const SizedBox(height: AppSpacing.mdGenerous),
          // Primary action
          AppPrimaryButton(
            label: _primaryActionLabel,
            onPressed: _onPrimaryAction,
          ),
          if (_showSkipButton) ...[
            const SizedBox(height: AppSpacing.sm),
            AppSecondaryButton(
              label: 'Skip eating window',
              onPressed: presenter.skipEatingWindow,
              fullWidth: true,
              height: 44,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhaseLabel(BuildContext context, FastingPhase phase) {
    return AppStatPill(
      value: phase.label,
      color: AppStatColor.neutral,
      size: AppStatSize.small,
    );
  }

  Widget _buildTimeInfoRow({
    required String leftTitle,
    required String leftValue,
    VoidCallback? leftOnEdit,
    required String rightTitle,
    required String rightValue,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _TimeInfoTile(
            title: leftTitle,
            value: leftValue,
            onEdit: leftOnEdit,
            color: theme.colorScheme.primary,
          ),
        ),
        Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outlineVariant),
        Expanded(
          child: _TimeInfoTile(
            title: rightTitle,
            value: rightValue,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsStrip(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        AppStatPill(
          icon: Icons.local_fire_department_rounded,
          label: 'Streak',
          value: '${presenter.currentStreak}d',
          color: AppStatColor.warning,
        ),
        AppStatPill(
          icon: Icons.emoji_events_outlined,
          label: 'Best',
          value: '${presenter.longestStreak}d',
          color: AppStatColor.success,
        ),
        AppStatPill(
          icon: Icons.history_rounded,
          label: 'Fasts',
          value: '${presenter.history.length}',
          color: AppStatColor.neutral,
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context) {
    final theme = Theme.of(context);
    final lastLog = presenter.history.first;
    final isSuccess = lastLog.success;
    final h = lastLog.fastDuration.floor();
    final m = ((lastLog.fastDuration - h) * 60).round();
    final durationLabel = m > 0 ? '${h}h ${m}m' : '${h}h';

    return AppSection(
      title: 'Last fast',
      trailing: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('History')),
              body: HistoryList(presenter: presenter),
            ),
          ),
        ),
        child: const Text('Show all'),
      ),
      child: AppCard(
        variant: AppCardVariant.tonal,
        child: Row(
          children: [
            AppIconBadge(
              icon: isSuccess ? Icons.check_rounded : Icons.close_rounded,
              color: isSuccess
                  ? AppColors.success
                  : theme.colorScheme.error,
              size: 36,
              iconSize: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppNumberDisplay(
                    value: durationLabel,
                    size: AppNumberSize.title,
                    color: isSuccess
                        ? AppColors.success
                        : theme.colorScheme.onSurface,
                  ),
                  Text(
                    DateFormat('MMM d, h:mm a').format(lastLog.fastStart),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _TimeInfoTile ────────────────────────────────────────────────────────────

class _TimeInfoTile extends StatelessWidget {
  const _TimeInfoTile({
    required this.title,
    required this.value,
    required this.color,
    this.onEdit,
  });

  final String title;
  final String value;
  final Color color;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: AppTextStyles.labelSmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyles.labelLarge.copyWith(
                  color: color, fontWeight: FontWeight.w600),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onEdit,
                child: Icon(Icons.edit_outlined, size: 14, color: color),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ── _FullProtocolSheet ───────────────────────────────────────────────────────

class _FullProtocolSheet extends StatelessWidget {
  const _FullProtocolSheet({required this.presenter});
  final FastingPresenter presenter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                    child: Text('Choose protocol',
                        style: AppTextStyles.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              itemCount: FastingProtocol.all.length,
              itemBuilder: (context, i) {
                final p = FastingProtocol.all[i];
                return SizedBox(
                  width: 160,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ProtocolCard(
                      protocol: p,
                      isSelected: presenter.fastingGoalHours == p.hours,
                      onTap: () {
                        presenter.updateFastingGoal(p.hours);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
