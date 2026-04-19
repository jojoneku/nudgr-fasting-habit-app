import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../models/fasting_phase.dart';
import '../../presenters/fasting_presenter.dart';
import '../../models/fasting_log.dart';
import '../../app_colors.dart';

class HistoryList extends StatefulWidget {
  final FastingPresenter presenter;

  const HistoryList({super.key, required this.presenter});

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  FastingPresenter get presenter => widget.presenter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, child) {
        return _buildHistoryView();
      },
    );
  }

  Widget _buildHistoryView() {
    if (presenter.history.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("No fasts recorded yet."),
      ));
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildStatsBanner(),
              const SizedBox(height: 16),
              _buildWeekHeatmap(),
              const SizedBox(height: 8),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final log = presenter.history[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildHistoryCard(log, index),
                );
              },
              childCount: presenter.history.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatTile(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.danger,
            label: 'STREAK',
            value: '${presenter.currentStreak}d',
          ),
          _buildStatDivider(),
          _buildStatTile(
            icon: Icons.bolt,
            iconColor: AppColors.gold,
            label: 'BEST',
            value: '${presenter.longestStreak}d',
          ),
          _buildStatDivider(),
          _buildStatTile(
            icon: Icons.timer_outlined,
            iconColor: AppColors.secondary,
            label: 'TOTAL',
            value: '${presenter.totalHoursFasted.toStringAsFixed(0)}h',
          ),
          _buildStatDivider(),
          _buildStatTile(
            icon: Icons.verified_rounded,
            iconColor: AppColors.success,
            label: 'SUCCESS',
            value: '${presenter.successRate.toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildStatDivider() => const SizedBox(width: 8);

  Widget _buildWeekHeatmap() {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final day = DateUtils.dateOnly(now.subtract(Duration(days: 6 - i)));
          final fasts = presenter.fastsOnDay(day);
          final hasSuccess = fasts.any((f) => f.success);
          final hasAny = fasts.isNotEmpty;
          final isToday = day == DateUtils.dateOnly(now);
          final label = DateFormat('E').format(day).substring(0, 1);

          Color circleColor;
          if (hasSuccess) {
            circleColor = AppColors.secondary;
          } else if (hasAny) {
            circleColor = AppColors.gold;
          } else {
            circleColor = AppColors.surface;
          }

          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                    border: isToday
                        ? Border.all(color: AppColors.textSecondary, width: 1.5)
                        : null,
                  ),
                  child: hasAny
                      ? Center(
                          child: Icon(
                            hasSuccess
                                ? Icons.check_rounded
                                : Icons.remove_rounded,
                            color: AppColors.background,
                            size: 16,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isToday
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildHistoryCard(FastingLog log, int index) {
    final fastDuration = log.fastDuration;
    final eatingDuration = log.eatingDuration;
    double eatingDurVal = eatingDuration ?? (24.0 - fastDuration);
    if (eatingDurVal < 0) eatingDurVal = 0;
    final note = log.note;
    final goalHours = log.goalDuration.toDouble();
    final progress = (fastDuration / goalHours).clamp(0.0, 1.0);
    final isOvertime = fastDuration > goalHours;
    final highestPhase =
        FastingPhase.fromElapsedSeconds((fastDuration * 3600).round());
    final xpEarned = log.success
        ? (50 + (fastDuration * 10)).round()
        : (fastDuration * 5).round();

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: (log.success ? AppColors.secondary : AppColors.danger)
                .withValues(alpha: 0.15),
            width: 1),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showHistoryContextMenu(context, index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    log.success ? Icons.bolt : Icons.bolt_outlined,
                    color: log.success
                        ? AppColors.secondary
                        : AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${log.goalDuration}:${log.goalDuration >= 36 ? 0 : 24 - log.goalDuration}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Phase badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: highestPhase.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      highestPhase.label.toUpperCase(),
                      style: TextStyle(
                        color: highestPhase.color,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // XP earned
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$xpEarned XP',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.note_rounded,
                        size: 14, color: AppColors.textSecondary),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Duration
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${fastDuration.toStringAsFixed(1)}h',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'of ${goalHours.toStringAsFixed(0)}h goal',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (isOvertime) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '⚡ OVERTIME',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Progress bar
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: AppColors.neutral.withValues(alpha: 0.15),
                  color: log.success ? AppColors.secondary : AppColors.danger,
                ),
              ),
              const SizedBox(height: 12),

              // Start / End Times
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM d, h:mm a').format(log.fastStart),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: AppColors.textSecondary.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'End',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM d, h:mm a').format(log.fastEnd),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Note
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.format_quote_rounded,
                          color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showHistoryContextMenu(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.pop(context);
                        _editHistoryTimes(index);
                      },
                    ),
                    const Text('Edit Times', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.note_add),
                      onPressed: () {
                        Navigator.pop(context);
                        _editHistoryNote(index);
                      },
                    ),
                    const Text('Add Note', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteHistoryItem(index);
                      },
                    ),
                    const Text('Delete',
                        style: TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editHistoryTimes(int index) async {
    final log = presenter.history[index];
    DateTime newFastStart = log.fastStart;
    DateTime newFastEnd = log.fastEnd;
    DateTime? newEatingEnd = log.eatingEnd;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Times'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Fast Start',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
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
                            mode: CupertinoDatePickerMode.dateAndTime,
                            initialDateTime: newFastStart,
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (DateTime value) {
                              setState(() {
                                newFastStart = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      const Text('Fast End',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
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
                            mode: CupertinoDatePickerMode.dateAndTime,
                            initialDateTime: newFastEnd,
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (DateTime value) {
                              setState(() {
                                newFastEnd = value;
                              });
                            },
                          ),
                        ),
                      ),
                      if (newEatingEnd != null) ...[
                        const Divider(height: 32),
                        const Text('Eating End',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
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
                              mode: CupertinoDatePickerMode.dateAndTime,
                              initialDateTime: newEatingEnd ?? DateTime.now(),
                              maximumDate: DateTime.now(),
                              onDateTimeChanged: (DateTime value) {
                                setState(() {
                                  newEatingEnd = value;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
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
                    final newFastDuration =
                        newFastEnd.difference(newFastStart).inSeconds / 3600;
                    final newEatingDuration = newEatingEnd != null
                        ? newEatingEnd!.difference(newFastEnd).inSeconds / 3600
                        : null;

                    // Replace the entry with a new FastingLog object
                    presenter.updateLog(
                        index,
                        FastingLog(
                          fastStart: newFastStart,
                          fastEnd: newFastEnd,
                          fastDuration: newFastDuration,
                          success:
                              newFastDuration >= presenter.fastingGoalHours,
                          eatingStart: newFastEnd,
                          eatingEnd: newEatingEnd,
                          eatingDuration: newEatingDuration,
                          note: log.note,
                          goalDuration: log.goalDuration,
                        ));
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
  }

  Future<void> _editHistoryNote(int index) async {
    final currentNote = presenter.history[index].note ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentNote);
        return AlertDialog(
          title: const Text('Add Note'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter your note...',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final log = presenter.history[index];
      presenter.updateLog(
          index,
          FastingLog(
            fastStart: log.fastStart,
            fastEnd: log.fastEnd,
            fastDuration: log.fastDuration,
            success: log.success,
            eatingStart: log.eatingStart,
            eatingEnd: log.eatingEnd,
            eatingDuration: log.eatingDuration,
            note: result.isEmpty ? null : result,
            goalDuration: log.goalDuration,
          ));
    }
  }

  Future<void> _deleteHistoryItem(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record"),
        content: const Text("Are you sure you want to delete this record?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (confirm == true) {
      presenter.deleteLog(index);
    }
  }
}
