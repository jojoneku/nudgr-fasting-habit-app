import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

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
      return const Center(child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text("No fasts recorded yet."),
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: presenter.history.length,
      itemBuilder: (context, index) {
        final log = presenter.history[index];
        final fastStart = log.fastStart;
        final fastEnd = log.fastEnd;
        final fastDuration = log.fastDuration;

        final eatingDuration = log.eatingDuration;
        double eatingDurVal = eatingDuration ?? (24.0 - fastDuration);
        if (eatingDurVal < 0) eatingDurVal = 0;

        final note = log.note;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            elevation: 0,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.surface.withValues(alpha: 0.5), width: 1),
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
                    // Header: Icon + Ratio
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${log.goalDuration}:${24 - log.goalDuration}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (note != null && note.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.note, size: 16, color: AppColors.textSecondary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Duration
                    Text(
                      '${fastDuration.toStringAsFixed(1)} Hours',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      '${eatingDurVal.toStringAsFixed(1)} Hours Eating',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Start / End Times
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Start',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MMM d, h:mm a').format(fastStart),
                                style: const TextStyle(
                                  color: AppColors.textPrimary, 
                                  fontSize: 14, 
                                  fontWeight: FontWeight.w600
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: AppColors.textSecondary.withValues(alpha: 0.2),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'End',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MMM d, h:mm a').format(fastEnd),
                                style: const TextStyle(
                                  color: AppColors.textPrimary, 
                                  fontSize: 14, 
                                  fontWeight: FontWeight.w600
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      },
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
                    const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red)),
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
                      const Text('Fast Start', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      const Text('Fast End', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        const Text('Eating End', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    final newFastDuration = newFastEnd.difference(newFastStart).inSeconds / 3600;
                    final newEatingDuration = newEatingEnd != null
                        ? newEatingEnd!.difference(newFastEnd).inSeconds / 3600
                        : null;

                    // Replace the entry with a new FastingLog object
                    presenter.updateLog(index, FastingLog(
                      fastStart: newFastStart,
                      fastEnd: newFastEnd,
                      fastDuration: newFastDuration,
                      success: newFastDuration >= presenter.fastingGoalHours,
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
      presenter.updateLog(index, FastingLog(
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (confirm == true) {
      presenter.deleteLog(index);
    }
  }
}
