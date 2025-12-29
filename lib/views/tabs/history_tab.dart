import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../presenters/fasting_presenter.dart';
import '../../models/fasting_log.dart';
import '../../app_colors.dart';
import '../../utils/date_utils.dart' as date_utils;

class HistoryTab extends StatefulWidget {
  final FastingPresenter presenter;

  const HistoryTab({super.key, required this.presenter});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
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
      return const Center(child: Text("No fasts recorded yet."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: presenter.history.length,
      itemBuilder: (context, index) {
        final log = presenter.history[index];
        final fastStart = log.fastStart;
        final fastEnd = log.fastEnd;
        final fastDuration = log.fastDuration;
        final isSuccess = log.success;

        final eatingStart = log.eatingStart;
        final eatingEnd = log.eatingEnd;
        final eatingDuration = log.eatingDuration;
        final hasEatingData = eatingEnd != null && eatingDuration != null;
        final note = log.note;

        final fastStartDate = DateTime(fastStart.year, fastStart.month, fastStart.day);
        final fastEndDate = DateTime(fastEnd.year, fastEnd.month, fastEnd.day);
        final fastSpansMultipleDays = !date_utils.isSameDay(fastStartDate, fastEndDate);

        String dateHeader;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final tomorrow = today.add(const Duration(days: 1));

        if (date_utils.isSameDay(fastStartDate, today)) {
          dateHeader = "Today";
        } else if (date_utils.isSameDay(fastStartDate, yesterday)) {
          dateHeader = "Yesterday";
        } else if (date_utils.isSameDay(fastStartDate, tomorrow)) {
          dateHeader = "Tomorrow";
        } else {
          dateHeader = DateFormat('EEE, MMM d').format(fastStart);
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateHeader,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        if (isSuccess)
                          const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                          onPressed: () => _editHistoryTimes(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                          onPressed: () => _deleteHistoryItem(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                        ),
                      ],
                    )
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      "${fastDuration.toStringAsFixed(1)}h Fast",
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                    const Spacer(),
                    Text(
                      "${DateFormat('HH:mm').format(fastStart)} - ${DateFormat('HH:mm').format(fastEnd)}${fastSpansMultipleDays ? ' (+1)' : ''}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                if (hasEatingData) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.restaurant, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        "${eatingDuration!.toStringAsFixed(1)}h Eating",
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange),
                      ),
                      const Spacer(),
                      Text(
                        "${DateFormat('HH:mm').format(eatingStart)} - ${DateFormat('HH:mm').format(eatingEnd!)}",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.note, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(child: Text(note, style: const TextStyle(fontStyle: FontStyle.italic))),
                      ],
                    ),
                  ),
                ],
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
                      const Text('Fast Start', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
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
                      const Divider(height: 32),
                      const Text('Fast End', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 200,
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
                      if (newEatingEnd != null) ...[
                        const Divider(height: 32),
                        const Text('Eating End', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
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
                    final newFastDuration = newFastEnd.difference(newFastStart).inSeconds / 3600;
                    final newEatingDuration = newEatingEnd != null
                        ? newEatingEnd!.difference(newFastEnd).inSeconds / 3600
                        : null;

                    // Replace the entry with a new FastingLog object
                    presenter.history[index] = FastingLog(
                      fastStart: newFastStart,
                      fastEnd: newFastEnd,
                      fastDuration: newFastDuration,
                      success: newFastDuration >= presenter.fastingGoalHours,
                      eatingStart: newFastEnd,
                      eatingEnd: newEatingEnd,
                      eatingDuration: newEatingDuration,
                      note: log.note,
                    );
                    presenter.saveState();
                    presenter.notifyListeners();
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

  Future<void> _deleteHistoryItem(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record"),
        content: const Text("Are you sure you want to delete this record?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (confirm == true) {
      presenter.history.removeAt(index);
      presenter.saveState();
      presenter.notifyListeners();
    }
  }
}
