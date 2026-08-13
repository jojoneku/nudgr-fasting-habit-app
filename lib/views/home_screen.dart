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
import '../presenters/insights_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/quest_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/food_db_service.dart';
import '../services/health_service.dart';
import '../services/cloud_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/snapshot_service.dart';
import '../services/remote_secrets_service.dart';
import '../services/sync_service.dart';
import '../services/sync_queue.dart';
import '../services/widget_bridge_service.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/onboarding_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../presenters/hub_presenter.dart';
import '../presenters/update_presenter.dart';
import 'auth/login_view.dart';
import 'hub_screen.dart';
import 'onboarding/onboarding_flow.dart';
import 'widgets/system/system.dart';
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
  late final BackupService _backup;
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
  late final InsightsPresenter _insightsPresenter;
  late final AuthPresenter _authPresenter;
  late final OnboardingPresenter _onboardingPresenter;
  late HubPresenter _hubPresenter;
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  SyncQueue? _syncQueue;
  SnapshotService? _snapshots;
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
    _backup = BackupService();
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
    _ledgerPresenter = LedgerPresenter(
      _storage,
      _statsPresenter,
      ai: _onDeviceAi,
      cloudAi: _cloudAi,
    );
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
      treasury: _treasuryPresenter,
      budget: _budgetPresenter,
      installments: _installmentPresenter,
      ledger: _ledgerPresenter,
      storage: _storage,
      cloudFallback: _cloudAi,
    );
    _insightsPresenter = InsightsPresenter(
      storage: _storage,
      fasting: _fastingPresenter,
      stats: _statsPresenter,
      quests: _questPresenter,
      nutrition: _nutritionPresenter,
      treasury: _treasuryPresenter,
      budget: _budgetPresenter,
      activity: _activityPresenter,
      onDeviceAi: _onDeviceAi,
      cloudAi: _cloudAi,
    );
    _authPresenter = AuthPresenter(
      _authService,
      onFirstSignIn: (userId) => _initSync(userId),
      onSignOut: _tearDownSync,
    );
    _hubPresenter = HubPresenter(
      storage: _storage,
      fasting: _fastingPresenter,
      quests: _questPresenter,
      treasury: _treasuryPresenter,
    );
    _onboardingPresenter = OnboardingPresenter(
      storage: _storage,
      nutrition: _nutritionPresenter!,
      fasting: _fastingPresenter,
      quests: _questPresenter,
      notifications: NotificationService(),
      auth: _authPresenter,
    );
    WidgetsBinding.instance.addObserver(this);
    // Run heavy I/O after the first frame so the widget tree renders first.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _foodDb.init(); // copy asset → documents dir if needed
      await _onDeviceAi.init(); // silently loads Qwen if already installed
      _nutritionPresenter?.initAi(); // notifies UI when AI state changes
      await _insightsPresenter.init(); // load persisted insights/baseline
      unawaited(_insightsPresenter
          .generateDailyBriefIfDue()); // once-per-day, off the build path

      await _syncQueue!.load(); // restore persisted queue before auth
      await _authService.init(); // init Supabase + restore session
      _authPresenter.init();
      final onboarded = await _storage.loadOnboardingComplete();
      if (_authPresenter.isSignedIn && _authPresenter.userId != null) {
        await _initSync(_authPresenter.userId!);
        // Users already signed in predate the onboarding gate — mark them
        // complete so the Awakening flow never appears for them.
        if (!onboarded) await _storage.saveOnboardingComplete(true);
      } else if (mounted) {
        // Guest / signed-out. Awaken only genuine new users: the gate is unset
        // AND there is no pre-existing local profile (an upgrading guest already
        // has one and must not be forced through onboarding). The flow owns the
        // sign-in step; onFirstSignIn handles sync init if the user signs in.
        final hasLocalProfile = (await _storage.loadTdeeProfile()) != null;
        if (!onboarded && !hasLocalProfile) {
          await OnboardingFlow.show(context, _onboardingPresenter);
        } else {
          if (!onboarded) await _storage.saveOnboardingComplete(true);
          if (mounted) await LoginView.show(context, _authPresenter);
        }
        // Guest finish (skip / complete / "log in later"): still wire the
        // home-screen widgets so they reflect local data — sign-in only adds
        // cloud sync. If the user signed in during the flow, onFirstSignIn
        // already ran _initSync (which reloads + wires), so skip it here.
        if (mounted && !_authPresenter.isSignedIn) {
          await _reloadAll();
          await _setupWidgetBridge();
        }
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
    _insightsPresenter.dispose();
    _authPresenter.dispose();
    _onboardingPresenter.dispose();
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

    // Restore-on-empty (Plan 053 Phase 0.5): if this device has no local data
    // for the user but an on-device backup.json exists, seed local from it
    // BEFORE reloading/syncing. The restore writes raw prefs (no dirty mark, no
    // sync-timestamp bump), so a newer cloud row still wins on the pull below.
    if (!await _storage.hasUserData()) {
      final backup = await _backup.readBackup(userId);
      if (backup != null && backup.isNotEmpty) {
        await _storage.importUserData(backup);
        debugPrint(
            'AppShell: restored ${backup.length} keys from local backup');
      }
    }

    // Reload all presenters from the now-correct scoped namespace.
    // This covers the startup race where constructors read bare keys before
    // the user namespace was known, as well as user-switch scenarios.
    // Awaited so the widget-bridge push below sees loaded data, not defaults.
    await _reloadAll();

    // Wire the home-screen widget bridge to the now-scoped presenters. Persist
    // the user id so the inline-action background isolate can re-scope storage.
    await _storage.saveWidgetLastUserId(userId);
    await _setupWidgetBridge();
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
      // Durable backup: write a daily immutable cloud snapshot (Plan 053 Phase
      // 3.5). Fire-and-forget — it's 24h-throttled and never throws. Inert until
      // the `backups` migration is applied.
      _snapshots = SnapshotService(
        supabase: Supabase.instance.client,
        storage: _storage,
        userId: userId,
      );
      unawaited(_snapshots!.writeSnapshotIfDue());
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
        AppToast.action(
          context,
          message: 'Sync failed: $e',
          actionLabel: 'Retry',
          onAction: () => _initSync(userId),
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 8),
        );
      }
    }
  }

  Future<void> _tearDownSync() async {
    final userId = _currentUserId;
    _currentUserId = null;

    // Best-effort flush of unsynced changes to the cloud before detaching.
    final svc = _syncService;
    if (userId != null && svc != null) {
      try {
        await svc.pushPending();
      } catch (_) {}
    }

    _storage.onDirty = null;
    _storage.onRemoteDataApplied = null;
    svc?.dispose();
    _syncPresenter?.dispose();
    _syncService = null;
    _syncPresenter = null;

    // Sign-out is NON-DESTRUCTIVE (Plan 053): we DETACH the user namespace
    // instead of wiping it. The data stays under the user's own `u/$id/` scope
    // (invisible to any other account via key-scoping) and is restored on the
    // next sign-in, so a stale or empty cloud row can never wipe local
    // progress — the failure mode behind three rounds of data loss.
    _storage.detachUser();
    _syncQueue?.clearAll();

    // Cancel scheduled OS notifications so a signed-out user never receives
    // ghost quest/weight/bills/fasting reminders. These live in the OS alarm
    // manager, not app storage, so detaching/wiping data never cleared them.
    await NotificationService().cancelAll();

    // Clear the home-screen widgets so a second account on a shared device never
    // sees the signed-out user's data.
    _widgetBridge?.detach();
    await _widgetBridge?.clearForSignOut();

    if (mounted) setState(() {});
  }

  /// Creates (once), attaches, and does the authoritative initial push of the
  /// home-screen widget bridge. Safe to call from both the signed-in and guest
  /// ("Log in later") paths — [WidgetBridgeService.attach] is idempotent.
  Future<void> _setupWidgetBridge() async {
    _widgetBridge ??= WidgetBridgeService(
      storage: _storage,
      fasting: _fastingPresenter,
      ledger: _ledgerPresenter,
      quests: _questPresenter,
      nutrition: _nutritionPresenter,
    );
    _widgetBridge!.attach();
    // A quest notification "Mark as Done" tap enqueues onto the same pending-
    // actions queue; when the tap lands while the app is alive, apply it right
    // away instead of waiting for the next resume.
    NotificationService.onQuestActionDrain =
        () => _widgetBridge?.drainPendingActions();
    await _widgetBridge!.drainPendingActions();
  }

  Future<void> _reloadAll() async {
    // Await the loads so callers (and the home-screen widget push below) see
    // loaded data, not the presenters' empty construction-time defaults. Each
    // load is isolated so one failure can't abort the others or sync setup.
    final loads = <Future<void>>[
      _statsPresenter.loadStats(),
      _fastingPresenter.loadState(),
      _questPresenter.reload(),
      _activityPresenter.loadState(),
      if (_nutritionPresenter != null) _nutritionPresenter!.loadState(),
      _ledgerPresenter.load(),
      _treasuryPresenter.load(),
      _budgetPresenter.load(),
      _billsPresenter.load(),
      _historyPresenter.load(),
      _installmentPresenter.load(),
      _groceryCartPresenter.load(),
    ];
    await Future.wait(loads.map((f) async {
      try {
        await f;
      } catch (e) {
        debugPrint('AppShell._reloadAll: presenter load failed: $e');
      }
    }));
    // Steps/distance: loadState above only rehydrates the cached log, which is
    // why the Hub's Activity card sat at stale/zero steps until the Activity
    // screen was opened. Now that availability/permission are resolved, pull
    // today's live figures from Health Connect (no-op when unavailable/denied)
    // so the Hub — and the home-screen widget snapshot below — are current.
    try {
      await _activityPresenter.syncFromHealthConnect();
    } catch (e) {
      debugPrint('AppShell._reloadAll: activity sync failed: $e');
    }
    // Refresh the home-screen widgets after a (re)load — e.g. once cloud data
    // has been pulled in.
    _widgetBridge?.pushSnapshot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _ledgerPresenter.notifyAppPaused();
      _writeLocalBackup();
    }
    if (state == AppLifecycleState.resumed) {
      _ledgerPresenter.notifyAppResumed();
      _fastingPresenter.loadState();
      // Pull today's steps/distance from Health Connect on every resume so the
      // Hub's Activity card stays current after the user walks — previously it
      // only refreshed when the Activity screen itself was opened. recheck-
      // Permissions re-verifies the grant, then syncs today (no-op if denied).
      _activityPresenter.recheckPermissions();
      // One ordered cycle: pull THEN push, so a stale queued edit can never
      // overwrite a newer record written on another device (see
      // docs/sync_conflict_resolution_spec.md).
      unawaited(
          _syncService?.syncCycle(staleness: const Duration(minutes: 5)) ??
              Future.value());
      // Re-scan the Insight Engine on resume: refresh is hash-gated (near-zero
      // cost when nothing changed) and the brief is once-per-day. Both fire and
      // forget — neither throws.
      _insightsPresenter.refresh();
      _insightsPresenter.generateDailyBriefIfDue();
      // Apply any widget-tap actions queued while the app was backgrounded,
      // then refresh the widgets.
      _widgetBridge?.drainPendingActions();
    }
  }

  /// Writes an on-device backup of all local user data (Plan 053 Phase 0.5).
  /// Fire-and-forget on app pause — [BackupService] never throws and no-ops on
  /// web. The backup survives sign-out/detach and is the source for the
  /// restore-on-empty path in [_initSync].
  Future<void> _writeLocalBackup() async {
    final userId = _currentUserId;
    if (userId == null) return;
    final data = await _storage.exportUserData();
    await _backup.writeBackup(userId, data);
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
          insightsPresenter: _insightsPresenter,
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
          localStorage: _storage,
          onboardingPresenter: _onboardingPresenter,
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
