import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../presenters/fasting_presenter.dart';
import '../../app_colors.dart';

class HabitsTab extends StatefulWidget {
  final FastingPresenter presenter;

  const HabitsTab({super.key, required this.presenter});

  @override
  State<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends State<HabitsTab> {
  FastingPresenter get presenter => widget.presenter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, child) {
        return _buildHabitsView();
      },
    );
  }

  Widget _buildHabitsView() {
    if (presenter.reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notification_add_outlined, size: 64, color: AppColors.neutral),
            const SizedBox(height: 16),
            const Text("No habits yet."),
            TextButton(onPressed: _addReminder, child: const Text("Add your first habit"))
          ],
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: presenter.reminders.length,
        itemBuilder: (context, index) {
          final item = presenter.reminders[index];
          final timeStr = "${item.hour.toString().padLeft(2,'0')}:${item.minute.toString().padLeft(2,'0')}";

          // Generate Days Text string
          String daysText = "Daily";
          List<bool> days = item.days;
          if (days.every((d) => !d)) {
            daysText = "Never";
          } else if (!days.every((d) => d)) {
            const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
            daysText = "";
            for(int i=0; i<7; i++) {
              if (days[i]) daysText += "${labels[i]} ";
            }
          }

          return Dismissible(
            key: Key(item.id.toString()),
            background: Container(color: AppColors.primary, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
            onDismissed: (direction) => presenter.deleteHabit(index),
            child: ListTile(
              leading: Icon(
                item.isEnabled ? Icons.alarm_on : Icons.alarm_off,
                color: item.isEnabled ? AppColors.primary : AppColors.neutral,
              ),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("$timeStr • $daysText"),
              trailing: Switch(
                  value: item.isEnabled,
                  onChanged: (val) => presenter.toggleHabit(index, val)
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addReminder() async {
    String? title;
    TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);
    List<bool> days = List.filled(7, true);
    const dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    bool submitted = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        TextEditingController controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("New Habit"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Title"),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: "e.g., Jogging, Meds"),
                      autofocus: true,
                    ),
                    const SizedBox(height: 20),
                    const Text("Time"),
                    InkWell(
                      onTap: () async {
                        await showCupertinoModalPopup(
                          context: context,
                          builder: (BuildContext context) {
                            return Container(
                              height: 200,
                              color: Colors.white,
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.time,
                                initialDateTime: DateTime(2024, 1, 1, time.hour, time.minute),
                                onDateTimeChanged: (DateTime newDateTime) {
                                  setState(() {
                                    time = TimeOfDay.fromDateTime(newDateTime);
                                  });
                                },
                                use24hFormat: MediaQuery.of(context).alwaysUse24HourFormat,
                              ),
                            );
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                    ),
                    const SizedBox(height: 20),
                    const Text("Repeat on"),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final isSelected = days[index];
                        return Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: InkWell(
                            onTap: () {
                              setState(() => days[index] = !days[index]);
                            },
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : Colors.transparent,
                                border: Border.all(color: isSelected ? AppColors.primary : AppColors.neutral),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                dayLabels[index].substring(0, 1),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    title = controller.text.trim();
                    if (title == null || title!.isEmpty) {
                      return;
                    }
                    submitted = true;
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (!submitted || title == null || title!.isEmpty) return;

    await presenter.addHabit(title!, time.hour, time.minute, days);
  }
}
