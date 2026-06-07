import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/ai_coach_presenter.dart';
import '../presenters/bills_receivables_presenter.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/grocery_cart_presenter.dart';
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
import '../services/widget_bridge_service.dart';
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
  late final AuthService _authService;
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
  late final GroceryCartPresenter _groceryCartPresenter;
  late final AiCoachPresenter _aiCoachPresenter;
  late final AuthPresenter _authPresenter;
  late HubPresenter _hubPresenter;
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  SyncQueue? _syncQueue;
  NutritionPresenter? _nutritionPresenter;
  String? _currentUserId;
  WidgetBridgeService? _widgetBridge;
  final ValueNotifier<WidgetRoute?> _deepLinkRoute = ValueNotifier(null);
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
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
      tokenProvider: () => _authService.currentAccessToken,
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
    _groceryCartPresenter =
        GroceryCartPresenter(_storage, ledger: _ledgerPresenter);
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
      _authService,
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
      await _authService.init(); // init Supabase + restore session
      _authPresenter.init();
      if (_authPresenter.isSignedIn && _authPresenter.userId != null) {
        await _initSync(_authPresenter.userId!);
      } else if (mounted) {
        // New/unauthenticated session — show welcome screen.
        // onFirstSignIn callback handles sync init if user signs in.
        await LoginView.show(context, _authPresenter);
      }

      // Home-screen widget deep-links: a tap on a glance widget routes the app
      // to the matching screen (both while running and from a cold start).
      _widgetClickSub = HomeWidget.widgetClicked.listen((uri) {
        final route = WidgetBridgeService.parseLaunchUri(uri);
        if (route != null) _deepLinkRoute.value = route;
      });
      try {
        final launchUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
        final route = WidgetBridgeService.parseLaunchUri(launchUri);
        if (route != null) _deepLinkRoute.value = route;
      } catch (_) {}
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
    _groceryCartPresenter.dispose();
    _aiCoachPresenter.dispose();
    _authPresenter.dispose();
    _hubPresenter.dispose();
    _syncService?.dispose();
    _syncPresenter?.dispose();
    _widgetBridge?.detach();
    _widgetClickSub?.cancel();
    _deepLinkRoute.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _cloudAi.enabled = widget.settingsPresenter.useCloudAi;
  }

  Future<void> _initSync(String userId) async {
    if (_syncService != null) {
      if (_currentUserId == userId) return; // already running for this user
      await _tearDownSync(); // different user signed in — tear down first
    }
    _currentUserId = userId;
    // Await migration so scoped keys are populated before presenters reload.
    await _storage.setUserId(userId);
    // Reload all presenters from the now-correct scoped namespace.
    // This covers the startup race where constructors read bare keys before
    // the user namespace was known, as well as user-switch scenarios.
    _reloadAll();

    // Wire the home-screen widget bridge to the now-scoped presenters. Persist
    // the user id so the inline-action background isolate can re-scope storage.
    await _storage.saveWidgetLastUserId(userId);
    _widgetBridge ??= WidgetBridgeService(
      storage: _storage,
      fasting: _fastingPresenter,
      ledger: _ledgerPresenter,
      quests: _questPresenter,
      nutrition: _nutritionPresenter,
    );
    _widgetBridge!.attach();
    await _widgetBridge!.drainPendingActions();
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

  Future<void> _tearDownSync() async {
    final userId = _currentUserId;
    _currentUserId = null;

    // Flush unsynced local changes to the cloud BEFORE wiping local data, so a
    // sign-out can never destroy un-uploaded records (e.g. weight/body logs).
    // If the push can't fully complete (offline / error), we KEEP local data
    // intact — it stays under the user's own `u/$id/` scope (invisible to any
    // other user) and re-syncs on the next launch — rather than being lost.
    final svc = _syncService;
    var flushed = true;
    if (userId != null && svc != null) {
      try {
        await svc.pushPending();
      } catch (_) {}
      flushed = (_syncQueue?.pendingCount ?? 0) == 0;
    }

    _storage.onDirty = null;
    _storage.onRemoteDataApplied = null;
    svc?.dispose();
    _syncPresenter?.dispose();
    _syncService = null;
    _syncPresenter = null;

    // Only wipe once everything is safely uploaded. Skipping the wipe when a
    // flush didn't complete is safe: user-scoping keeps a later signed-in user
    // from ever seeing this data.
    if (userId != null && flushed) {
      _storage.clearUserData();
      _syncQueue?.clearAll();
    }

    // Clear the home-screen widgets so a second account on a shared device never
    // sees the signed-out user's data.
    _widgetBridge?.detach();
    await _widgetBridge?.clearForSignOut();

    if (mounted) setState(() {});
  }

  void _reloadAll() {
    _statsPresenter.loadStats();
    _fastingPresenter.loadState();
    _questPresenter.reload();
    _activityPresenter.loadState();
    _nutritionPresenter?.loadState();
    _ledgerPresenter.load();
    _treasuryPresenter.load();
    _budgetPresenter.load();
    _billsPresenter.load();
    _historyPresenter.load();
    _installmentPresenter.load();
    _groceryCartPresenter.load();
    // Refresh the home-screen widgets after a (re)load — e.g. once cloud data
    // has been pulled in.
    _widgetBridge?.pushSnapshot();
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
      // Apply any widget-tap actions queued while the app was backgrounded,
      // then refresh the widgets.
      _widgetBridge?.drainPendingActions();
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
          groceryCartPresenter: _groceryCartPresenter,
          authPresenter: _authPresenter,
          syncPresenter: _syncPresenter,
          settingsPresenter: widget.settingsPresenter,
          updatePresenter: widget.updatePresenter,
          deepLinkRoute: _deepLinkRoute,
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
