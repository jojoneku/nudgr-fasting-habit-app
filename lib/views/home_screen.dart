import 'package:flutter/material.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../services/ai_estimation_service.dart';
import '../services/food_db_service.dart';
import '../services/storage_service.dart';
import '../app_colors.dart';
import 'hub_screen.dart';
import 'stats_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final StorageService _storage;
  late final StatsPresenter _statsPresenter;
  late final FastingPresenter _fastingPresenter;
  late final FoodDbService _foodDb;
  late final AiEstimationService _aiEstimation;
  NutritionPresenter? _nutritionPresenter;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _storage        = StorageService();
    _statsPresenter = StatsPresenter(_storage);
    _fastingPresenter = FastingPresenter(statsPresenter: _statsPresenter);
    _foodDb       = FoodDbService();
    _aiEstimation = AiEstimationService();
    _nutritionPresenter = NutritionPresenter(
      statsPresenter:   _statsPresenter,
      fastingPresenter: _fastingPresenter,
      storage:          _storage,
      foodDb:           _foodDb,
      aiEstimation:     _aiEstimation,
    );
    WidgetsBinding.instance.addObserver(this);
    // Run heavy I/O after the first frame so the widget tree renders first.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _foodDb.init();       // copy asset → documents dir if needed
      _aiEstimation.init();       // non-blocking — loads Gemma if installed
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fastingPresenter.dispose();
    _statsPresenter.dispose();
    _nutritionPresenter?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fastingPresenter.loadState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HubScreen(
        fastingPresenter: _fastingPresenter,
        statsPresenter: _statsPresenter,
        nutritionPresenter: _nutritionPresenter,
      ),
      StatsView(
        presenter: _statsPresenter,
        fastingPresenter: _fastingPresenter,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Character',
          ),
        ],
      ),
    );
  }
}

// Keep HomeScreen as an alias so fasting_app.dart compiles until updated.
typedef HomeScreen = AppShell;
