import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../../services/auth_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/sync_queue.dart';
import '../../services/sync_service.dart';
import '../app_theme.dart';
import '../treasury/treasury_module_view.dart';
import 'pages/bills/web_bills_page.dart';
import 'pages/budget/web_budget_page.dart';
import 'pages/dashboard/web_dashboard_page.dart';
import 'pages/history/web_history_page.dart';
import 'pages/ledger/web_ledger_page.dart';
import 'pages/setup/web_setup_page.dart';
import 'web_login_view.dart';
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
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
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
  SyncService? _syncService;
  SyncPresenter? _syncPresenter;
  String? _currentUserId;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _storage = LocalStorageService();
    _syncQueue = SyncQueue();
    _statsPresenter = StatsPresenter(_storage);
    // No on-device AI on web — ledger NLP falls back to its rule-based parser.
    _ledgerPresenter = LedgerPresenter(_storage, _statsPresenter);
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
    _authPresenter = AuthPresenter(
      _authService,
      onFirstSignIn: (userId) => _initSync(userId),
      onSignOut: _tearDownSync,
    );

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
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
    _authPresenter.dispose();
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
      _syncService?.pushPending();
      _syncService?.pullIfStale();
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
      await _syncService!.pushPending();
      await _syncService!.pushAll();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('TreasuryWebShell: _initSync failed for $userId: $e');
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
            content: const Text('Sync failed. Tap retry to refresh.'),
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
    // sign-out can never destroy un-uploaded records. If the flush can't
    // complete, KEEP local data (it stays under the user's own scope and
    // re-syncs next launch).
    final svc = _syncService;
    var flushed = true;
    if (userId != null && svc != null) {
      try {
        await svc.pushPending();
      } catch (_) {}
      flushed = (_syncQueue.pendingCount) == 0;
    }

    _storage.onDirty = null;
    _storage.onRemoteDataApplied = null;
    svc?.dispose();
    _syncPresenter?.dispose();
    _syncService = null;
    _syncPresenter = null;

    if (userId != null && flushed) {
      _storage.clearUserData();
      _syncQueue.clearAll();
    }

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
        if (!_authPresenter.isSignedIn) {
          return WebLoginView(presenter: _authPresenter);
        }
        return _TreasuryWebHome(
          dashPresenter: _treasuryPresenter,
          ledgerPresenter: _ledgerPresenter,
          billsPresenter: _billsPresenter,
          budgetPresenter: _budgetPresenter,
          historyPresenter: _historyPresenter,
          installmentPresenter: _installmentPresenter,
          groceryCartPresenter: _groceryCartPresenter,
          authPresenter: _authPresenter,
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

  const _TreasuryWebHome({
    required this.dashPresenter,
    required this.ledgerPresenter,
    required this.billsPresenter,
    required this.budgetPresenter,
    required this.historyPresenter,
    required this.installmentPresenter,
    required this.groceryCartPresenter,
    required this.authPresenter,
  });

  @override
  State<_TreasuryWebHome> createState() => _TreasuryWebHomeState();
}

class _TreasuryWebHomeState extends State<_TreasuryWebHome> {
  int _index = 0;

  static const _destinations = [
    WebDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    WebDestination(icon: Icons.list_alt_outlined, label: 'Ledger'),
    WebDestination(icon: Icons.receipt_long_outlined, label: 'Bills'),
    WebDestination(icon: Icons.pie_chart_outline, label: 'Budget'),
    WebDestination(icon: Icons.history_outlined, label: 'History'),
    WebDestination(icon: Icons.settings_outlined, label: 'Setup & Accounts'),
  ];

  /// Reload the focused page's presenter so cross-page mutations show up
  /// without a refresh (mirrors TreasuryModuleView._onTabChanged).
  void _onSelect(int i) {
    setState(() => _index = i);
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
        widget.dashPresenter.load();
        widget.ledgerPresenter
            .load(); // categories live on the ledger presenter
    }
  }

  Widget _page(int i) {
    switch (i) {
      case 1:
        return WebLedgerPage(presenter: widget.ledgerPresenter);
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
        return WebSetupPage(
          presenter: widget.dashPresenter,
          ledgerPresenter: widget.ledgerPresenter,
        );
      case 0:
      default:
        return WebDashboardPage(presenter: widget.dashPresenter);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < WebBreakpoints.rail) {
          return TreasuryModuleView(
            dashPresenter: widget.dashPresenter,
            ledgerPresenter: widget.ledgerPresenter,
            billsPresenter: widget.billsPresenter,
            budgetPresenter: widget.budgetPresenter,
            historyPresenter: widget.historyPresenter,
            installmentPresenter: widget.installmentPresenter,
            groceryCartPresenter: widget.groceryCartPresenter,
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
          footer: _SignOutFooter(authPresenter: widget.authPresenter),
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
  const _SignOutFooter({required this.authPresenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final email = authPresenter.userEmail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
