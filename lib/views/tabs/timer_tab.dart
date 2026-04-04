import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../presenters/fasting_presenter.dart';
import '../../app_colors.dart';
import '../../utils/date_utils.dart' as date_utils;
import '../widgets/partial_ring_painter.dart';
import 'history_tab.dart';

class TimerTab extends StatefulWidget {
  final FastingPresenter presenter;

  const TimerTab({super.key, required this.presenter});

  @override
  State<TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<TimerTab> {
  FastingPresenter get presenter => widget.presenter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, child) {
        return _buildTimerView();
      },
    );
  }

  Widget _buildTimerView() {
    double progress = 0.0;
    int targetSeconds = 1;
    String statusLabel = "Ready?";
    int eatingHours = 24 - presenter.fastingGoalHours;
    if (eatingHours < 0) eatingHours = 0;
    final bool hasEatingWindow = eatingHours > 0;
    int eatingRemainingSeconds = 0;
    double eatingElapsedPercent = 0;

    if (presenter.isFasting) {
      targetSeconds = presenter.fastingGoalHours * 3600;
      progress = (presenter.elapsedSeconds / targetSeconds);
      statusLabel = "Fasting Time";
    } else if (presenter.eatingStartTime != null) {
      final int eatingTargetSeconds = hasEatingWindow ? eatingHours * 3600 : 1;
      targetSeconds = eatingTargetSeconds;
      if (hasEatingWindow) {
        eatingRemainingSeconds = eatingTargetSeconds - presenter.elapsedSeconds;
        if (eatingRemainingSeconds < 0) eatingRemainingSeconds = 0;
        progress = eatingTargetSeconds > 0
            ? (eatingRemainingSeconds / eatingTargetSeconds)
            : 0;
        eatingElapsedPercent = eatingTargetSeconds > 0
            ? (presenter.elapsedSeconds / eatingTargetSeconds)
            : 0;
        if (eatingElapsedPercent < 0) eatingElapsedPercent = 0;
        if (eatingElapsedPercent > 1) eatingElapsedPercent = 1;
      } else {
        eatingRemainingSeconds = 0;
        progress = 0;
        eatingElapsedPercent = 0;
      }
      statusLabel =
          hasEatingWindow ? "Eating Window Left" : "Eating Window Disabled";
    }
    if (progress > 1.0) progress = 1.0;

    final theme = Theme.of(context);
    const Color fastingAccent = AppColors.secondary;
    const Color eatingAccent = AppColors.primary;
    final bool showEatingProgress =
        presenter.eatingStartTime != null && hasEatingWindow;
    final bool showProgressLabel = presenter.isFasting || showEatingProgress;
    final String timerDisplay = presenter.isFasting
        ? _formatTime(presenter.elapsedSeconds)
        : (presenter.eatingStartTime != null
            ? (hasEatingWindow
                ? _formatTime(eatingRemainingSeconds)
                : '00:00:00')
            : "${presenter.fastingGoalHours}:00:00");
    double displayProgress =
        (presenter.isFasting || presenter.eatingStartTime != null)
            ? progress
            : 0.0;
    displayProgress = math.max(0.0, math.min(1.0, displayProgress));

    final bool reverseProgress =
        !presenter.isFasting && presenter.eatingStartTime != null;

    final timerCore = Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 280,
          child: CustomPaint(
            painter: PartialRingPainter(
              progress: displayProgress,
              trackColor: AppColors.neutral.withValues(alpha: 0.2),
              progressColor: presenter.isFasting
                  ? fastingAccent
                  : (presenter.eatingStartTime != null
                      ? eatingAccent
                      : AppColors.neutral),
              strokeWidth: 20,
              reverse: reverseProgress,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(statusLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              timerDisplay,
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            if (showProgressLabel)
              Text(
                presenter.isFasting
                    ? "${(progress * 100).toInt()}%"
                    : "${(eatingElapsedPercent * 100).toInt()}% elapsed",
                style: theme.textTheme.titleLarge?.copyWith(
                  color: presenter.isFasting ? fastingAccent : eatingAccent,
                ),
              ),
          ],
        )
      ],
    );

    Widget? leftPanel;
    Widget? rightPanel;

    if (presenter.isFasting && presenter.startTime != null) {
      final start = presenter.startTime!;
      leftPanel = _buildTimerInfoPanel(
        title: 'Started',
        value: _format12Hour(start),
        accentColor: fastingAccent,
        onEdit: _editCurrentFastingTime,
      );
      rightPanel = _buildTimerInfoPanel(
        title: 'Goal End',
        value: date_utils.formatTimeWithDay(
            start.add(Duration(hours: presenter.fastingGoalHours)), start),
        accentColor: fastingAccent,
      );
    } else if (presenter.eatingStartTime != null) {
      final eatingStart = presenter.eatingStartTime!;
      leftPanel = _buildTimerInfoPanel(
        title: 'Window Start',
        value: _format12Hour(eatingStart),
        accentColor: eatingAccent,
        onEdit: _editCurrentEatingTime,
      );
      rightPanel = _buildTimerInfoPanel(
        title: 'Window End',
        value: date_utils.formatTimeWithDay(
            eatingStart.add(Duration(hours: 24 - presenter.fastingGoalHours)),
            eatingStart),
        accentColor: eatingAccent,
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!presenter.isFasting)
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: ToggleButtons(
                  isSelected: [16, 18, 20, 24]
                      .map((e) => e == presenter.fastingGoalHours)
                      .toList(),
                  onPressed: (int index) {
                    presenter.updateFastingGoal([16, 18, 20, 24][index]);
                  },
                  borderRadius: BorderRadius.circular(10),
                  children: const [
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("16:8")),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("18:6")),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("20:4")),
                    Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text("OMAD")),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32)),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  color: theme.colorScheme.surface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: timerCore,
                      ),
                      if (leftPanel != null || rightPanel != null) ...[
                        const SizedBox(height: 16),
                        IntrinsicHeight(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (leftPanel != null) Expanded(child: leftPanel),
                              if (rightPanel != null)
                                Expanded(child: rightPanel),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: (presenter.isFasting
                                      ? fastingAccent
                                      : (presenter.eatingStartTime != null
                                          ? eatingAccent
                                          : theme.colorScheme.primary))
                                  .withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: FilledButton(
                          onPressed: _toggleFast,
                          style: FilledButton.styleFrom(
                            backgroundColor: presenter.isFasting
                                ? fastingAccent
                                : (presenter.eatingStartTime != null
                                    ? eatingAccent
                                    : theme.colorScheme.primary),
                          ),
                          child: Text(
                            presenter.isFasting ? "END FAST" : "START FAST",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (presenter.eatingStartTime != null &&
                          !presenter.isFasting &&
                          hasEatingWindow) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _skipEatingWindow,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                            ),
                            child: const Text("Skip / Pause Today"),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _buildHistorySummary(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerInfoPanel({
    required String title,
    required String value,
    Color? accentColor,
    VoidCallback? onEdit,
  }) {
    final color = accentColor ?? AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onEdit,
                child: Icon(Icons.edit, size: 16, color: color),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _toggleFast() {
    if (presenter.isFasting) {
      _showStopFastDialog();
    } else {
      presenter.startFast();
    }
  }

  Future<void> _showStopFastDialog() async {
    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Fast?"),
        content: const Text("Are you sure you want to end your fast now?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("End Fast")),
        ],
      ),
    );

    if (shouldStop == true) {
      final (xp, hpChange) = await presenter.stopFast();
      if (mounted) {
        if (hpChange < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Fast Failed. +$xp XP\nPenalty: $hpChange HP"),
              backgroundColor: AppColors.danger,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Fast Complete! +$xp XP\nRecovered: +$hpChange HP"),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _skipEatingWindow() async {
    await presenter.skipEatingWindow();
  }

  Future<void> _editCurrentFastingTime() async {
    if (presenter.startTime == null) return;
    DateTime tempStartTime = presenter.startTime!;
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Start Time'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 200,
                    width: double.maxFinite,
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
                        mode: CupertinoDatePickerMode.dateAndTime,
                        initialDateTime: tempStartTime,
                        maximumDate: DateTime.now(),
                        onDateTimeChanged: (DateTime value) {
                          setState(() {
                            tempStartTime = value;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            presenter.updateStartTime(tempStartTime);
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editCurrentEatingTime() async {
    if (presenter.eatingStartTime == null) return;
    DateTime tempStartTime = presenter.eatingStartTime!;
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Window Start'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 200,
                    width: double.maxFinite,
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
                        mode: CupertinoDatePickerMode.dateAndTime,
                        initialDateTime: tempStartTime,
                        maximumDate: DateTime.now(),
                        onDateTimeChanged: (DateTime value) {
                          setState(() {
                            tempStartTime = value;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            presenter.updateEatingStartTime(tempStartTime);
                            Navigator.pop(context);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _format12Hour(DateTime dateTime) {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:${dateTime.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildHistorySummary(ThemeData theme) {
    if (presenter.history.isEmpty) return const SizedBox.shrink();

    final lastLog = presenter.history.first;
    final duration = lastLog.fastDuration;
    final isSuccess = lastLog.success;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "LAST FAST",
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text("History")),
                        body: HistoryList(presenter: presenter),
                      ),
                    ),
                  );
                },
                child: const Text("Show All"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.neutral.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isSuccess ? AppColors.primary : AppColors.error)
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSuccess ? Icons.check : Icons.close,
                    color: isSuccess ? AppColors.primary : AppColors.error,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${duration.toStringAsFixed(1)} Hours",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        DateFormat('MMM d, h:mm a').format(lastLog.fastStart),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
