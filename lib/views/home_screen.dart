import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_coach_context.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/ai_coach_presenter.dart';
import '../presenters/bills_receivables_presenter.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/quest_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../services/auth_service.dart';
import '../services/food_db_service.dart';
import '../services/health_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../app_colors.dart';
import 'hub_screen.dart';
import 'stats_view.dart';
import 'widgets/ai_chat_sheet.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final LocalStorageService _storage;
  late final StatsPresenter _statsPresenter;
  late final FastingPresenter _fastingPresenter;
  late final QuestPresenter _questPresenter;
  late final FoodDbService _foodDb;
  late final OnDeviceAiCoachService _onDeviceAi;
  late final HealthService _healthService;
  late final ActivityPresenter _activityPresenter;
  late final TreasuryDashboardPresenter _treasuryPresenter;
  late final LedgerPresenter _ledgerPresenter;
  late final BillsReceivablesPresenter _billsPresenter;
  late final BudgetPresenter _budgetPresenter;
  late final TreasuryHistoryPresenter _historyPresenter;
  late final InstallmentPresenter _installmentPresenter;
  late final AiCoachPresenter _aiCoachPresenter;
  late final AuthPresenter _authPresenter;
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  SyncQueue? _syncQueue;
  NutritionPresenter? _nutritionPresenter;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _storage = LocalStorageService();
    _syncQueue = SyncQueue();
    _statsPresenter = StatsPresenter(_storage);
    _fastingPresenter = FastingPresenter(
      statsPresenter: _statsPresenter,
      storage: _storage,
    );
    _questPresenter = QuestPresenter(
      storage: _storage,
      stats: _statsPresenter,
    );
    _foodDb = FoodDbService();
    _onDeviceAi = OnDeviceAiCoachService();
    _healthService = HealthService();
    _activityPresenter = ActivityPresenter(
      statsPresenter: _statsPresenter,
      healthService: _healthService,
      storage: _storage,
    );
    _treasuryPresenter = TreasuryDashboardPresenter(_storage);
    _ledgerPresenter = LedgerPresenter(_storage, _statsPresenter);
    _billsPresenter =
        BillsReceivablesPresenter(_storage, _ledgerPresenter, _statsPresenter);
    _budgetPresenter = BudgetPresenter(_storage, _statsPresenter);
    _historyPresenter = TreasuryHistoryPresenter(_storage);
    _installmentPresenter =
        InstallmentPresenter(_storage, _ledgerPresenter, _statsPresenter);
    _nutritionPresenter = NutritionPresenter(
      statsPresenter: _statsPresenter,
      fastingPresenter: _fastingPresenter,
      storage: _storage,
      foodDb: _foodDb,
      aiCoach: _onDeviceAi,
    );
    _aiCoachPresenter = AiCoachPresenter(
      stats: _statsPresenter,
      fasting: _fastingPresenter,
      nutrition: _nutritionPresenter,
      service: _onDeviceAi,
    );
    _authPresenter = AuthPresenter(
      AuthService.instance,
      onFirstSignIn: (userId) => _initSync(userId),
    );
    WidgetsBinding.instance.addObserver(this);
    // Run heavy I/O after the first frame so the widget tree renders first.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _foodDb.init(); // copy asset → documents dir if needed
      await _onDeviceAi.init(); // silently loads Qwen if already installed
      _nutritionPresenter?.initAi(); // notifies UI when AI state changes
      await _syncQueue!.load(); // restore persisted queue before auth
      await AuthService.instance.init(); // init Supabase + restore session
      _authPresenter.init();
      // If already signed in from cached session, init sync immediately
      if (_authPresenter.isSignedIn && _authPresenter.userId != null) {
        _initSync(_authPresenter.userId!);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fastingPresenter.dispose();
    _statsPresenter.dispose();
    _questPresenter.dispose();
    _nutritionPresenter?.dispose();
    _activityPresenter.dispose();
    _treasuryPresenter.dispose();
    _ledgerPresenter.dispose();
    _billsPresenter.dispose();
    _budgetPresenter.dispose();
    _historyPresenter.dispose();
    _installmentPresenter.dispose();
    _aiCoachPresenter.dispose();
    _authPresenter.dispose();
    _syncService?.dispose();
    _syncPresenter?.dispose();
    super.dispose();
  }

  void _initSync(String userId) {
    if (_syncService != null) return;
    _syncService = SyncService(
      supabase: Supabase.instance.client,
      storage: _storage,
      queue: _syncQueue!,
      userId: userId,
    );
    _syncPresenter = SyncPresenter(_syncService!, _authPresenter);
    _storage.setSyncQueue(_syncQueue!);
    _storage.onRemoteDataApplied = _reloadAll;
    _syncService!.init();
    _syncService!.pullAll();
    if (mounted) setState(() {});
  }

  void _reloadAll() {
    _fastingPresenter.loadState();
    _questPresenter.reload();
    _nutritionPresenter?.loadState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fastingPresenter.loadState();
      _syncService?.pushPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HubScreen(
        fastingPresenter: _fastingPresenter,
        statsPresenter: _statsPresenter,
        questPresenter: _questPresenter,
        nutritionPresenter: _nutritionPresenter,
        activityPresenter: _activityPresenter,
        aiCoachPresenter: _aiCoachPresenter,
        treasuryPresenter: _treasuryPresenter,
        ledgerPresenter: _ledgerPresenter,
        billsPresenter: _billsPresenter,
        budgetPresenter: _budgetPresenter,
        historyPresenter: _historyPresenter,
        installmentPresenter: _installmentPresenter,
      ),
      StatsView(
        presenter: _statsPresenter,
        fastingPresenter: _fastingPresenter,
        authPresenter: _authPresenter,
        syncPresenter: _syncPresenter,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: screens[_selectedIndex],
      floatingActionButton: _AiCoachFab(
        presenter: _aiCoachPresenter,
        entryPoint: _selectedIndex == 1
            ? AiCoachEntryPoint.stats
            : AiCoachEntryPoint.general,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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

class _AiCoachFab extends StatefulWidget {
  final AiCoachPresenter presenter;
  final AiCoachEntryPoint entryPoint;

  const _AiCoachFab({required this.presenter, required this.entryPoint});

  @override
  State<_AiCoachFab> createState() => _AiCoachFabState();
}

class _AiCoachFabState extends State<_AiCoachFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          AiChatSheet.show(context,
              presenter: widget.presenter, entryPoint: widget.entryPoint);
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const Center(
              child: Icon(Icons.psychology_outlined,
                  color: AppColors.primary, size: 24),
            ),
          ),
        ),
      );
}
