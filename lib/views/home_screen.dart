import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../presenters/fasting_presenter.dart';
import '../app_colors.dart';
import 'tabs/timer_tab.dart';
import 'tabs/habits_tab.dart';
import 'tabs/history_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FastingPresenter _presenter = FastingPresenter();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      TimerTab(presenter: _presenter),
      HistoryTab(presenter: _presenter),
      HabitsTab(presenter: _presenter),
    ];

    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: true,
        actions: [
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
                        leading: const Icon(Icons.science, color: AppColors.primary),
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
                        leading: const Icon(Icons.delete_forever, color: AppColors.neutral),
                        title: const Text('Clear All Data'),
                        subtitle: const Text('Delete all fasting history and habits'),
                        onTap: () async {
                          Navigator.pop(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Confirm Reset'),
                              content: const Text('This will delete ALL your data including fasting history and habits. This cannot be undone!'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.neutral),
                                  child: const Text('Delete All'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await _presenter.clearHistory();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('All data cleared successfully')),
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
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer),
              label: 'Fasting'
          ),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'
          ),
          NavigationDestination(
              icon: Icon(Icons.check_circle_outline),
              selectedIcon: Icon(Icons.check_circle),
              label: 'Habits'
          ),
        ],
      ),
    );
  }
}
