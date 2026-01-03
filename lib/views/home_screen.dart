import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../presenters/fasting_presenter.dart';
import '../models/quest.dart';
import '../app_colors.dart';
import 'tabs/timer_tab.dart';
import 'tabs/quests_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FastingPresenter _presenter = FastingPresenter();
  int _selectedIndex = 0;
  bool _isEditingQuests = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presenter.loadState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      TimerTab(presenter: _presenter),
      QuestsTab(
        presenter: _presenter,
        onAddQuest: _addQuest,
        onEditQuest: _editQuest,
        isEditing: _isEditingQuests,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: true,
        actions: [
          if (_selectedIndex == 1) ...[
            IconButton(
              icon: Icon(_isEditingQuests ? Icons.check : MdiIcons.swordCross),
              onPressed: () =>
                  setState(() => _isEditingQuests = !_isEditingQuests),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addQuest,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Settings'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading:
                            const Icon(Icons.science, color: AppColors.primary),
                        title: const Text('Add Test Data'),
                        subtitle: const Text('Add sample fasting records'),
                        onTap: () {
                          Navigator.pop(context);
                          _presenter.addTestData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added test data!')),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading:
                            const Icon(Icons.notifications_active, color: AppColors.secondary),
                        title: const Text('Test Notification'),
                        subtitle: const Text('Check if notifications work'),
                        onTap: () async {
                          Navigator.pop(context);
                          await _presenter.testNotification();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Notification sent! Check status bar.')),
                            );
                          }
                        },
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.delete_forever,
                            color: AppColors.neutral),
                        title: const Text('Clear All Data'),
                        subtitle:
                            const Text('Delete all fasting history and quests'),
                        onTap: () async {
                          Navigator.pop(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirm Reset'),
                              content: const Text(
                                  'This will delete ALL your data including fasting history and quests. This cannot be undone!'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: AppColors.neutral),
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await _presenter.clearAllData();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('All data cleared successfully')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer),
              label: 'Fasting'),
          NavigationDestination(
              icon: Icon(MdiIcons.swordCross),
              selectedIcon: Icon(MdiIcons.swordCross),
              label: 'Quests'),
        ],
      ),
    );
  }

  void _addQuest() => _showQuestDialog();

  void _editQuest(Quest quest) => _showQuestDialog(quest: quest);

  Future<void> _showQuestDialog({Quest? quest}) async {
    final isEditing = quest != null;
    String? title = quest?.title;
    TimeOfDay time = quest != null
        ? TimeOfDay(hour: quest.hour, minute: quest.minute)
        : const TimeOfDay(hour: 8, minute: 0);
    List<bool> days =
        quest != null ? List.from(quest.days) : List.filled(7, true);
    const dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    bool submitted = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        TextEditingController controller = TextEditingController(text: title);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isEditing ? "Edit Quest" : "New Quest"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Title"),
                    TextField(
                      controller: controller,
                      decoration:
                          const InputDecoration(hintText: "e.g., Jogging, Meds"),
                      autofocus: true,
                      onChanged: (val) => title = val,
                    ),
                    const SizedBox(height: 20),
                    const Text("Time"),
                    InkWell(
                      onTap: () async {
                        TimeOfDay tempTime = time;
                        await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text("Select Time"),
                              content: SizedBox(
                                width: double.maxFinite,
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
                                    backgroundColor: AppColors.surface,
                                    mode: CupertinoDatePickerMode.time,
                                    initialDateTime:
                                        DateTime(2024, 1, 1, time.hour, time.minute),
                                    onDateTimeChanged: (DateTime newDateTime) {
                                      tempTime = TimeOfDay.fromDateTime(newDateTime);
                                    },
                                    use24hFormat:
                                        MediaQuery.of(context).alwaysUse24HourFormat,
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      time = tempTime;
                                    });
                                    Navigator.pop(context);
                                  },
                                  child: const Text("OK"),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.neutral),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(time.format(context),
                                style: const TextStyle(fontSize: 16)),
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
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.neutral),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                dayLabels[index].substring(0, 1),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary,
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

    final safeTitle = title;
    if (!submitted || safeTitle == null || safeTitle.isEmpty) return;

    if (quest != null) {
      final index = _presenter.quests.indexOf(quest);
      if (index != -1) {
        await _presenter.updateQuest(
            index, safeTitle, time.hour, time.minute, days);
      }
    } else {
      await _presenter.addQuest(safeTitle, time.hour, time.minute, days);
    }
  }
}
