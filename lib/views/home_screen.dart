import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import '../services/cloud_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/local_storage_service.dart';
import '../services/remote_secrets_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../presenters/hub_presenter.dart';
import '../presenters/update_presenter.dart';
import 'auth/login_view.dart';
import 'hub_screen.dart';
import 'widgets/update_prompt.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settingsPresenter,
    this.updatePresenter,
  });

  final SettingsPresenter settingsPresenter;
  final UpdatePresenter? updatePresenter;

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
  late final CloudAiCoachService _cloudAi;
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
  late HubPresenter _hubPresenter;
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  SyncQueue? _syncQueue;
  NutritionPresenter? _nutritionPresenter;
  String? _currentUserId;

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
    final remoteSecrets = RemoteSecretsService();
    _onDeviceAi = OnDeviceAiCoachService(
      tokenProvider: remoteSecrets.getHuggingFaceToken,
    );
    _cloudAi = CloudAiCoachService(
      tokenProvider: () => AuthService.instance.currentAccessToken,
    );
    _cloudAi.enabled = widget.settingsPresenter.useCloudAi;
    widget.settingsPresenter.addListener(_onSettingsChanged);
    _healthService = HealthService();
    _activityPresenter = ActivityPresenter(
      statsPresenter: _statsPresenter,
      healthService: _healthService,
      storage: _storage,
    );
    _ledgerPresenter =
        LedgerPresenter(_storage, _statsPresenter, ai: _onDeviceAi);
    _treasuryPresenter = TreasuryDashboardPresenter(_storage, _ledgerPresenter);
    _budgetPresenter =
        BudgetPresenter(_storage, _statsPresenter, _ledgerPresenter);
    _billsPresenter = BillsReceivablesPresenter(
      _storage,
      _ledgerPresenter,
      _statsPresenter,
      dashboard: _treasuryPresenter,
      budget: _budgetPresenter,
    );
    _historyPresenter = TreasuryHistoryPresenter(_storage);
    _installmentPresenter =
        InstallmentPresenter(_storage, _ledgerPresenter, _statsPresenter);
    _nutritionPresenter = NutritionPresenter(
      statsPresenter: _statsPresenter,
      fastingPresenter: _fastingPresenter,
      storage: _storage,
      foodDb: _foodDb,
      aiCoach: _onDeviceAi,
      cloudAi: _cloudAi,
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
      onSignOut: _tearDownSync,
    );
    _hubPresenter = HubPresenter(
      fasting: _fastingPresenter,
      quests: _questPresenter,
      treasury: _treasuryPresenter,
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
      if (_authPresenter.isSignedIn && _authPresenter.userId != null) {
        await _initSync(_authPresenter.userId!);
      } else if (mounted) {
        // New/unauthenticated session — show welcome screen.
        // onFirstSignIn callback handles sync init if user signs in.
        await LoginView.show(context, _authPresenter);
      }
    });
  }

  @override
  void dispose() {
    widget.settingsPresenter.removeListener(_onSettingsChanged);
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
    _hubPresenter.dispose();
    _syncService?.dispose();
    _syncPresenter?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _cloudAi.enabled = widget.settingsPresenter.useCloudAi;
  }

  Future<void> _initSync(String userId) async {
    if (_syncService != null) {
      if (_currentUserId == userId) return; // already running for this user
      _tearDownSync(); // different user signed in — tear down first
    }
    _currentUserId = userId;
    _storage.setUserId(userId);
    try {
      await _syncQueue!.load(userId: userId);
      _syncService = SyncService(
        supabase: Supabase.instance.client,
        storage: _storage,
        queue: _syncQueue!,
        userId: userId,
      );
      _syncPresenter = SyncPresenter(_syncService!, _authPresenter);
      _storage.setSyncQueue(_syncQueue!);
      _storage.onRemoteDataApplied = _reloadAll;
      _storage.onDirty = _syncService!.schedulePush;
      await _syncService!.init();
      // Pull cloud data first so a fresh install never overwrites cloud data.
      await _syncService!.pullAll();
      // Flush queued offline changes, then do the once-per-device initial push.
      await _syncService!.pushPending();
      await _syncService!.pushAll();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('AppShell: _initSync failed for $userId: $e');
      // Null out so a retry attempt can re-enter (skip the early-return guard).
      _storage.onDirty = null;
      _storage.onRemoteDataApplied = null;
      _syncService?.dispose();
      _syncPresenter?.dispose();
      _syncService = null;
      _syncPresenter = null;
      _currentUserId = null;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sync failed. Tap retry or pull to refresh.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _initSync(userId),
            ),
          ),
        );
      }
    }
  }

  void _tearDownSync() {
    final userId = _currentUserId;
    _currentUserId = null;
    _storage.onDirty = null;
    _storage.onRemoteDataApplied = null;
    _syncService?.dispose();
    _syncPresenter?.dispose();
    _syncService = null;
    _syncPresenter = null;
    // Wipe all user-scoped prefs and reset the in-memory sync queue so a
    // subsequent sign-in by a different user starts from a clean slate.
    if (userId != null) {
      _storage.clearUserData();
    }
    _syncQueue?.clearAll();
    if (mounted) setState(() {});
  }

  void _reloadAll() {
    _fastingPresenter.loadState();
    _questPresenter.reload();
    _activityPresenter.loadState();
    _nutritionPresenter?.loadState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _ledgerPresenter.notifyAppPaused();
    }
    if (state == AppLifecycleState.resumed) {
      _ledgerPresenter.notifyAppResumed();
      _fastingPresenter.loadState();
      _syncService?.pushPending();
      _syncService?.pullIfStale();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HubScreen(
          hubPresenter: _hubPresenter,
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
          authPresenter: _authPresenter,
          syncPresenter: _syncPresenter,
          settingsPresenter: widget.settingsPresenter,
          updatePresenter: widget.updatePresenter,
        ),
        if (widget.updatePresenter != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: UpdatePrompt(presenter: widget.updatePresenter!),
          ),
      ],
    );
  }
}

// Keep HomeScreen as an alias so fasting_app.dart compiles until updated.
typedef HomeScreen = AppShell;
