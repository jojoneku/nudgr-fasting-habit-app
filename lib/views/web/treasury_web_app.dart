import 'dart:async';

import 'package:flutter/material.dart';
import '../../utils/app_scroll_behavior.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:intermittent_fasting/views/widgets/system/system.dart';
import '../../presenters/ai_coach_presenter.dart';
import '../../presenters/auth_presenter.dart';
import '../../presenters/bills_receivables_presenter.dart';
import '../../presenters/budget_presenter.dart';
import '../../presenters/grocery_cart_presenter.dart';
import '../../presenters/installment_presenter.dart';
import '../../presenters/ledger_presenter.dart';
import '../../presenters/stats_presenter.dart';
import '../../presenters/sync_presenter.dart';
import '../../presenters/treasury_dashboard_presenter.dart';
import '../../presenters/treasury_history_presenter.dart';
import '../../presenters/treasury_month_scope.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_ai_coach_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/null_ai_coach_service.dart';
import '../../services/realtime_sync_service.dart';
import '../../services/snapshot_service.dart';
import '../../services/sync_queue.dart';
import '../../services/sync_service.dart';
import '../treasury/dashboard/goals_savings_screen.dart';
import '../treasury/grocery/grocery_cart_view.dart';
import '../treasury/treasury_module_view.dart';
import 'design/web_theme.dart';
import 'dev/preview_seed.dart';
import 'pages/bills/web_bills_page.dart';
import 'pages/budget/web_budget_page.dart';
import 'pages/dashboard/web_dashboard_page.dart';
import 'pages/history/web_history_page.dart';
import 'pages/ledger/web_ledger_page.dart';
import 'pages/more/web_more_page.dart';
import 'pages/setup/web_setup_page.dart';
import 'web_login_view.dart';
import 'widgets/web_advisor_panel.dart';
import 'widgets/web_widgets.dart';

/// App-level theme mode for the web companion. Lifted out of the widget tree so
/// the shell's topbar toggle can flip light/dark without prop-threading through
/// the stateful composition root. Defaults to the dark Solo-Leveling identity.
final ValueNotifier<ThemeMode> webThemeMode = ValueNotifier(ThemeMode.dark);

/// Root of the Treasury web companion (Plan 042). Reuses the mobile dark/light
/// identity from [buildDarkTheme]/[buildLightTheme]; defaults to the dark
/// Solo-Leveling theme on web, toggleable from the shell topbar.
class TreasuryWebApp extends StatelessWidget {
  const TreasuryWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: webThemeMode,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Treasury',
        scrollBehavior: const AppScrollBehavior(),
        theme: buildWebLightTheme(),
        darkTheme: buildWebDarkTheme(),
        themeMode: mode,
        home: const TreasuryWebShell(),
      ),
    );
  }
}

/// Composition root for web: builds the auth/storage/sync stack and the seven
/// treasury presenters, then mirrors the mobile [AppShell]'s
/// init/teardown/reload sync lifecycle — minus the widget-bridge, health,
/// food-db, gemma, and nutrition wiring that web doesn't have. Shows the web
/// login when signed out, the treasury module when signed in.
class TreasuryWebShell extends StatefulWidget {
  const TreasuryWebShell({super.key});

  @override
  State<TreasuryWebShell> createState() => _TreasuryWebShellState();
}

class _TreasuryWebShellState extends State<TreasuryWebShell>
    with WidgetsBindingObserver {
  late final AuthService _authService;
  late final LocalStorageService _storage;
  late final SyncQueue _syncQueue;
  late final StatsPresenter _statsPresenter;
  late final LedgerPresenter _ledgerPresenter;
  late final TreasuryDashboardPresenter _treasuryPresenter;
  late final BudgetPresenter _budgetPresenter;
  late final BillsReceivablesPresenter _billsPresenter;
  late final TreasuryHistoryPresenter _historyPresenter;
  late final InstallmentPresenter _installmentPresenter;
  late final GroceryCartPresenter _groceryCartPresenter;
  late final AuthPresenter _authPresenter;
  late final AiCoachPresenter _advisorPresenter;

  /// One "month being read" for Ledger / Bills / Budget / Installments, so
  /// paging one destination back to June doesn't leave the others in the
  /// current month with nothing on screen saying so.
  final TreasuryMonthScope _monthScope = TreasuryMonthScope();
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  RealtimeSyncService? _realtime;
  SnapshotService? _snapshots;
  String? _currentUserId;
  bool _booting = true;

  /// True once the local preview-seed path has loaded — bypasses the auth gate
  /// so the dashboard renders without a Supabase session. Dev-only; see
  /// [previewSeedEnabled].
  bool _previewMode = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _storage = LocalStorageService();
    _syncQueue = SyncQueue();
    _statsPresenter = StatsPresenter(_storage);
    // No on-device model on web. The ledger's natural-language Quick Add uses
    // the rule-based parser first, then Bedrock (Claude Haiku) via the cloud
    // service for anything ambiguous — on by default (no Cloud AI toggle), it
    // just needs the user signed in + AI_COACH_ENDPOINT compiled into the build.
    final cloudAi = CloudAiCoachService(
      tokenProvider: () => _authService.currentAccessToken,
    );
    // Opt the cloud tier in explicitly. `enabled` gates
    // `CloudAiCoachService.isAvailable` and defaults to false, and on mobile it
    // is driven by the Settings "Cloud AI" switch (home_screen.dart) — a screen
    // web does not have. Left unset, a signed-in web user with a working
    // endpoint still saw "Money Mentor is unavailable", because the advisor
    // gates on `isAvailable` while Quick Add gates on transport readiness alone
    // (hence the ledger parser worked and hid the problem). Web has no
    // on-device tier and no toggle to honour, so the cloud tier is the only
    // tier and is on by definition.
    cloudAi.enabled = true;
    _ledgerPresenter = LedgerPresenter(
      _storage,
      _statsPresenter,
      cloudAi: cloudAi,
      monthScope: _monthScope,
    );
    _treasuryPresenter = TreasuryDashboardPresenter(_storage, _ledgerPresenter);
    _budgetPresenter = BudgetPresenter(
      _storage,
      _statsPresenter,
      _ledgerPresenter,
      null,
      _monthScope,
    );
    _billsPresenter = BillsReceivablesPresenter(
      _storage,
      _ledgerPresenter,
      _statsPresenter,
      dashboard: _treasuryPresenter,
      budget: _budgetPresenter,
      monthScope: _monthScope,
    );
    // Budgets are owned by the budget presenter but mirrored by the dashboard;
    // without this an allocation edited on the Budget page left the dashboard's
    // Budget Overview and month-end projection showing pre-edit numbers.
    _budgetPresenter.onBudgetsChanged = _treasuryPresenter.reloadBudgets;
    _historyPresenter = TreasuryHistoryPresenter(_storage);
    _installmentPresenter = InstallmentPresenter(
      _storage,
      _ledgerPresenter,
      _statsPresenter,
      monthScope: _monthScope,
    );
    _groceryCartPresenter =
        GroceryCartPresenter(_storage, ledger: _ledgerPresenter);
    // Money Mentor. `fasting` and `nutrition` are omitted: both are optional,
    // and constructing them here would init NotificationService / the sqflite
    // food DB — neither of which has a web implementation. The advisor entry
    // point reads neither.
    //
    // `service:` is an explicit NullAiCoachService so the presenter does NOT
    // fall into its on-device init path (which would construct the Gemma
    // service); the cloud tier is supplied as the fallback and is the only tier
    // web ever uses.
    _advisorPresenter = AiCoachPresenter(
      stats: _statsPresenter,
      service: NullAiCoachService(),
      cloudFallback: cloudAi,
      treasury: _treasuryPresenter,
      budget: _budgetPresenter,
      installments: _installmentPresenter,
      ledger: _ledgerPresenter,
      storage: _storage,
    );
    _authPresenter = AuthPresenter(
      _authService,
      onFirstSignIn: (userId) => _initSync(userId),
      onSignOut: _tearDownSync,
    );

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Local preview-seed mode (dev only): seed a demo treasury into local
      // storage and render the dashboard directly. No Supabase, no auth, no
      // SyncService is ever constructed — nothing leaves the browser.
      if (previewSeedEnabled) {
        await _storage.setUserId(PreviewSeed.userId);
        await PreviewSeed.seedInto(_storage);
        await _reloadAll();
        if (mounted) {
          setState(() {
            _previewMode = true;
            _booting = false;
          });
        }
        return;
      }
      await _syncQueue.load(); // restore persisted queue before auth
      await _authService.init(); // init Supabase + restore session
      _authPresenter.init();
      if (_authPresenter.isSignedIn && _authPresenter.userId != null) {
        await _initSync(_authPresenter.userId!);
      }
      if (mounted) setState(() => _booting = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsPresenter.dispose();
    _ledgerPresenter.dispose();
    _treasuryPresenter.dispose();
    _budgetPresenter.dispose();
    _billsPresenter.dispose();
    _historyPresenter.dispose();
    _installmentPresenter.dispose();
    _groceryCartPresenter.dispose();
    _advisorPresenter.dispose();
    _authPresenter.dispose();
    _monthScope.dispose();
    unawaited(_realtime?.dispose() ?? Future.value());
    _syncService?.dispose();
    _syncPresenter?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On web this fires on tab visibility changes — mirror the mobile resume
    // path so a tab refocus pulls any edits made on the phone meanwhile and
    // flushes anything queued locally.
    if (state == AppLifecycleState.resumed) {
      // One ordered cycle: pull THEN push. This used to fire both unawaited,
      // push first, so refocusing a tab that had an edit queued uploaded that
      // stale copy over whatever the phone had written since — and every device
      // then pulled the stale value back down.
      //
      // Tighten the staleness window on web (Plan 053 Phase 3.3): the 5-minute
      // default meant refocusing the tab within 5 min of the last pull showed
      // stale data (e.g. an edit just made on the phone). 30s makes a refocus
      // reliably reflect recent cross-device changes without hammering the API.
      unawaited(
          _syncService?.syncCycle(staleness: const Duration(seconds: 30)) ??
              Future.value());
    }
  }

  Future<void> _initSync(String userId) async {
    if (_syncService != null) {
      if (_currentUserId == userId) return; // already running for this user
      await _tearDownSync(); // different user signed in — tear down first
    }
    _currentUserId = userId;
    // Await migration so scoped keys are populated before presenters reload.
    await _storage.setUserId(userId);
    await _reloadAll();
    try {
      await _syncQueue.load(userId: userId);
      _syncService = SyncService(
        supabase: Supabase.instance.client,
        storage: _storage,
        queue: _syncQueue,
        userId: userId,
      );
      _syncPresenter = SyncPresenter(_syncService!, _authPresenter);
      _storage.setSyncQueue(_syncQueue);
      _storage.onRemoteDataApplied = _reloadAll;
      _storage.onDirty = _syncService!.schedulePush;
      await _syncService!.init();
      // Pull cloud data first so a fresh browser never overwrites cloud data.
      await _syncService!.pullAll();
      // Push local → cloud in the BACKGROUND so boot isn't blocked on it. With
      // a large finance backlog this was firing hundreds of serial upserts and
      // stalling the first paint for minutes. The queue is durable — whatever
      // doesn't flush now goes out on the next push. Chained so the two pushes
      // don't race on the _isSyncing guard.
      unawaited(
        _syncService!.pushPending().then((_) => _syncService?.pushAll()),
      );
      // Durable backup on web too (Plan 053 Phase 3.5): write a daily immutable
      // cloud snapshot. Fire-and-forget — 24h-throttled, never throws, inert
      // until the `backups` migration is applied.
      _snapshots = SnapshotService(
        supabase: Supabase.instance.client,
        storage: _storage,
        userId: userId,
      );
      unawaited(_snapshots!.writeSnapshotIfDue());
      // Realtime: sync within seconds of another device writing, instead of
      // waiting for the next resume. Best-effort — if the publication migration
      // isn't applied or the socket can't open, no events arrive and the
      // existing boot/resume/manual triggers carry on unchanged.
      _realtime = RealtimeSyncService(
        supabase: Supabase.instance.client,
        userId: userId,
        onRemoteChange: () => _syncService?.syncCycle() ?? Future.value(),
      )..connect();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('TreasuryWebShell: _initSync failed for $userId: $e');
      _storage.onDirty = null;
      _storage.onRemoteDataApplied = null;
      unawaited(_realtime?.dispose() ?? Future.value());
      _realtime = null;
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
    // Close the channel before the namespace detaches, so no realtime event can
    // fire a cycle for the user who just signed out.
    await _realtime?.dispose();
    _realtime = null;
    svc?.dispose();
    _syncPresenter?.dispose();
    _syncService = null;
    _syncPresenter = null;

    // Sign-out is NON-DESTRUCTIVE (Plan 053): detach the user namespace rather
    // than wiping it, so an empty/stale cloud row can never wipe local data.
    // Data stays under the user's own `u/$id/` scope and restores next sign-in.
    _storage.detachUser();
    _syncQueue.clearAll();

    if (mounted) setState(() {});
  }

  Future<void> _reloadAll() async {
    final loads = <Future<void>>[
      _statsPresenter.loadStats(),
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
        debugPrint('TreasuryWebShell._reloadAll: presenter load failed: $e');
      }
    }));

    // Seed the legacy Jan–May history ONCE, strictly after every presenter has
    // finished loading + persisting monthly summaries — running it inside
    // dashboard.load() raced TreasuryHistoryPresenter over the same storage key
    // (last writer wins, dropping the backfill). Then reload history so its
    // page reflects the seeded months immediately.
    try {
      await _treasuryPresenter.backfillHistoricalSummariesOnce();
      await _historyPresenter.load();
    } catch (e) {
      debugPrint('TreasuryWebShell._reloadAll: history backfill failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ListenableBuilder(
      listenable: _authPresenter,
      builder: (context, _) {
        if (!_previewMode && !_authPresenter.isSignedIn) {
          return WebLoginView(presenter: _authPresenter);
        }
        return _TreasuryWebHome(
          syncPresenter: _syncPresenter,
          dashPresenter: _treasuryPresenter,
          ledgerPresenter: _ledgerPresenter,
          billsPresenter: _billsPresenter,
          budgetPresenter: _budgetPresenter,
          historyPresenter: _historyPresenter,
          installmentPresenter: _installmentPresenter,
          groceryCartPresenter: _groceryCartPresenter,
          authPresenter: _authPresenter,
          advisorPresenter: _advisorPresenter,
        );
      },
    );
  }
}

/// Responsive Treasury home: the desktop [WebShell] (sidebar + redesigned web
/// pages) at ≥ 840 dp, falling back to the mobile [TreasuryModuleView] (bottom
/// tabs) below that — free mobile-web parity (Plan 050).
class _TreasuryWebHome extends StatefulWidget {
  final TreasuryDashboardPresenter dashPresenter;
  final LedgerPresenter ledgerPresenter;
  final BillsReceivablesPresenter billsPresenter;
  final BudgetPresenter budgetPresenter;
  final TreasuryHistoryPresenter historyPresenter;
  final InstallmentPresenter installmentPresenter;
  final GroceryCartPresenter groceryCartPresenter;
  final AuthPresenter authPresenter;
  final AiCoachPresenter advisorPresenter;

  /// Null until the sync stack is up (or when it failed) — the dashboard's
  /// status pill reports that instead of claiming everything is synced.
  final SyncPresenter? syncPresenter;

  const _TreasuryWebHome({
    required this.syncPresenter,
    required this.dashPresenter,
    required this.ledgerPresenter,
    required this.billsPresenter,
    required this.budgetPresenter,
    required this.historyPresenter,
    required this.installmentPresenter,
    required this.groceryCartPresenter,
    required this.authPresenter,
    required this.advisorPresenter,
  });

  @override
  State<_TreasuryWebHome> createState() => _TreasuryWebHomeState();
}

class _TreasuryWebHomeState extends State<_TreasuryWebHome> {
  int _index = 0;

  /// Ledger table filters live here rather than inside the page, so leaving the
  /// Ledger destination and coming back doesn't quietly drop them.
  final WebLedgerFilters _ledgerFilters = WebLedgerFilters();

  @override
  void dispose() {
    _ledgerFilters.dispose();
    super.dispose();
  }

  // Destination order is deliberately IDENTICAL to the mobile module's tab
  // order (Dashboard · Ledger · Bills · Budget · History · Cart · Goals, then
  // the trailing settings-ish destination). That makes the index itself the
  // shared position, so crossing the desktop breakpoint mid-session keeps the
  // user on the page they were reading instead of resetting to Dashboard.
  static const _destinations = [
    WebDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    WebDestination(icon: Icons.list_alt_outlined, label: 'Ledger'),
    WebDestination(icon: Icons.receipt_long_outlined, label: 'Bills'),
    WebDestination(icon: Icons.pie_chart_outline, label: 'Budget'),
    WebDestination(icon: Icons.history_outlined, label: 'History'),
    WebDestination(icon: Icons.shopping_cart_outlined, label: 'Cart'),
    WebDestination(icon: Icons.savings_outlined, label: 'Goals'),
    WebDestination(icon: Icons.settings_outlined, label: 'Setup & Accounts'),
  ];

  static const int _setupIndex = 7;

  /// Reload the focused page's presenter so cross-page mutations show up
  /// without a refresh (mirrors TreasuryModuleView._onTabChanged).
  void _onSelect(int i) {
    setState(() => _index = i);
    _reloadFor(i);
  }

  void _reloadFor(int i) {
    switch (i) {
      case 0:
        widget.dashPresenter.load();
      case 1:
        widget.ledgerPresenter.load();
      case 2:
        widget.billsPresenter.load();
      case 3:
        widget.budgetPresenter.load();
      case 4:
        widget.historyPresenter.load();
      case 5:
        widget.groceryCartPresenter.load();
      case 6:
        // Goals & Savings figures come from the dashboard presenter.
        widget.dashPresenter.load();
      case _setupIndex:
        widget.dashPresenter.load();
        widget.ledgerPresenter
            .load(); // categories live on the ledger presenter
    }
  }

  Widget _page(int i) {
    switch (i) {
      case 1:
        return WebLedgerPage(
          presenter: widget.ledgerPresenter,
          filters: _ledgerFilters,
        );
      case 2:
        return WebBillsPage(
          presenter: widget.billsPresenter,
          installmentPresenter: widget.installmentPresenter,
        );
      case 3:
        return WebBudgetPage(presenter: widget.budgetPresenter);
      case 4:
        return WebHistoryPage(presenter: widget.historyPresenter);
      case 5:
        // The mobile cart view, mounted in the desktop shell. The web spec
        // lists Cart as an in-scope tab; it was reachable only below the
        // breakpoint, so maximizing the window made a whole feature — and the
        // trips behind ledger rows it had already written — disappear.
        return GroceryCartView(presenter: widget.groceryCartPresenter);
      case 6:
        return GoalsSavingsScreen(
          presenter: widget.dashPresenter,
          // The shell topbar already names the destination.
          showAppBar: false,
        );
      case _setupIndex:
        return WebSetupPage(
          presenter: widget.dashPresenter,
          ledgerPresenter: widget.ledgerPresenter,
        );
      case 0:
      default:
        return WebDashboardPage(
          presenter: widget.dashPresenter,
          billsPresenter: widget.billsPresenter,
          onManageAccounts: () => _onSelect(_setupIndex),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < WebBreakpoints.rail) {
          return TreasuryModuleView(
            syncPresenter: widget.syncPresenter,
            // Same index space as the rail — hand over the current position.
            initialTabIndex: _index,
            onTabChanged: (i) {
              if (i != _index) setState(() => _index = i);
            },
            dashPresenter: widget.dashPresenter,
            ledgerPresenter: widget.ledgerPresenter,
            billsPresenter: widget.billsPresenter,
            budgetPresenter: widget.budgetPresenter,
            historyPresenter: widget.historyPresenter,
            installmentPresenter: widget.installmentPresenter,
            groceryCartPresenter: widget.groceryCartPresenter,
            // Narrow web has no sidebar, so sign-out, the theme toggle and the
            // Money Mentor get a tab of their own. Occupies the same index as
            // the rail's trailing destination, keeping the mapping 1:1.
            extraTabs: [
              TreasuryModuleTab(
                icon: Icons.more_horiz,
                label: 'More',
                ownsHeader: true,
                page: ValueListenableBuilder<ThemeMode>(
                  valueListenable: webThemeMode,
                  builder: (context, mode, _) => WebMorePage(
                    authPresenter: widget.authPresenter,
                    advisorPresenter: widget.advisorPresenter,
                    isDark: mode == ThemeMode.dark,
                    onToggleTheme: () => webThemeMode.value =
                        mode == ThemeMode.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                  ),
                ),
              ),
            ],
          );
        }
        final theme = Theme.of(context);
        return WebShell(
          destinations: _destinations,
          selectedIndex: _index,
          onDestinationSelected: _onSelect,
          header: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: WebInsets.sm),
              Text('Treasury',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          footer: _SignOutFooter(
            authPresenter: widget.authPresenter,
            syncPresenter: widget.syncPresenter,
          ),
          topBar: Row(
            children: [
              Text(_destinations[_index].label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              const _ThemeToggle(),
            ],
          ),
          body: _page(_index),
          // Persistent across every destination, so a question about a bill can
          // be asked while the Bills table is still on screen.
          dock: WebAdvisorPanel(presenter: widget.advisorPresenter),
        );
      },
    );
  }
}

/// Sun/moon button in the shell topbar that flips [webThemeMode] — mirrors the
/// theme toggle in the reference design (see `light.png`).
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: webThemeMode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () =>
              webThemeMode.value = isDark ? ThemeMode.light : ThemeMode.dark,
        );
      },
    );
  }
}

class _SignOutFooter extends StatelessWidget {
  final AuthPresenter authPresenter;
  final SyncPresenter? syncPresenter;

  const _SignOutFooter({required this.authPresenter, this.syncPresenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = authPresenter.userEmail;
    final sync = syncPresenter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Real sync state, in the rail where the shell always shows it.
        if (sync != null)
          ListenableBuilder(
            listenable: sync,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(bottom: WebInsets.sm),
              child: Row(
                children: [
                  Icon(
                    sync.syncError != null
                        ? Icons.error_outline
                        : sync.pendingCount > 0
                            ? Icons.cloud_upload_outlined
                            : Icons.cloud_done_outlined,
                    size: 14,
                    color:
                        sync.syncError != null ? cs.error : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: WebInsets.sm),
                  Expanded(
                    child: Text(
                      sync.syncError != null ? 'Sync failed' : sync.statusLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: sync.syncError != null
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (email != null)
          Padding(
            padding: const EdgeInsets.only(bottom: WebInsets.sm),
            child: Text(email,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
          ),
        OutlinedButton.icon(
          onPressed: authPresenter.signOut,
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
