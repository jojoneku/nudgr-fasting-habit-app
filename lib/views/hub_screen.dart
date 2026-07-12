import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/quest.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/ai_coach_presenter.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/bills_receivables_presenter.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/grocery_cart_presenter.dart';
import '../presenters/hub_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/onboarding_presenter.dart';
import '../presenters/quest_presenter.dart';
import '../presenters/settings_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/sync_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../presenters/update_presenter.dart';
import '../services/local_storage_service.dart';
import '../services/widget_bridge_service.dart';
import 'activity/activity_permission_screen.dart';
import 'activity/activity_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'quests/quests_tab.dart';
import 'settings_screen.dart';
import 'stats_view.dart';
import 'tabs/timer_tab.dart';
import 'treasury/ledger/add_transaction_sheet.dart';
import 'treasury/treasury_module_view.dart';
import 'widgets/finance/ledger_chat_panel.dart';
import 'widgets/hub/activity_hub_card.dart';
import 'widgets/hub/fasting_hub_card.dart';
import 'widgets/hub/hub_coach_line.dart';
import 'widgets/hub/hub_rings_hero.dart';
import 'widgets/hub/hub_streak_pill.dart';
import 'widgets/hub/nutrition_hub_card.dart';
import 'widgets/hub/quests_hub_card.dart';
import 'widgets/hub/stats_hub_card.dart';
import 'widgets/hub/treasury_hub_card.dart';
import 'widgets/hub/weight_body_hub_card.dart';
import 'nutrition/measurement_log_screen.dart';
import 'nutrition/weight_log_screen.dart';
import 'widgets/system/overlays/app_bottom_sheet.dart';
import 'widgets/system/overlays/app_toast.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/quick_log_router.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({
    super.key,
    required this.hubPresenter,
    required this.fastingPresenter,
    required this.statsPresenter,
    required this.questPresenter,
    this.nutritionPresenter,
    this.activityPresenter,
    this.aiCoachPresenter,
    this.treasuryPresenter,
    this.ledgerPresenter,
    this.billsPresenter,
    this.budgetPresenter,
    this.historyPresenter,
    this.installmentPresenter,
    this.groceryCartPresenter,
    this.authPresenter,
    this.syncPresenter,
    required this.settingsPresenter,
    this.updatePresenter,
    this.deepLinkRoute,
    this.localStorage,
    this.onboardingPresenter,
  });

  final HubPresenter hubPresenter;
  final FastingPresenter fastingPresenter;
  final StatsPresenter statsPresenter;
  final QuestPresenter questPresenter;
  final NutritionPresenter? nutritionPresenter;
  final ActivityPresenter? activityPresenter;
  final AiCoachPresenter? aiCoachPresenter;
  final TreasuryDashboardPresenter? treasuryPresenter;
  final LedgerPresenter? ledgerPresenter;
  final BillsReceivablesPresenter? billsPresenter;
  final BudgetPresenter? budgetPresenter;
  final TreasuryHistoryPresenter? historyPresenter;
  final InstallmentPresenter? installmentPresenter;
  final GroceryCartPresenter? groceryCartPresenter;
  final AuthPresenter? authPresenter;
  final SyncPresenter? syncPresenter;
  final SettingsPresenter settingsPresenter;
  final UpdatePresenter? updatePresenter;
  final OnboardingPresenter? onboardingPresenter;

  /// Set by [AppShell] when a home-screen widget is tapped; the hub consumes it
  /// and navigates to the matching screen.
  final ValueNotifier<WidgetRoute?>? deepLinkRoute;

  /// Concrete storage, forwarded to Settings for the cloud-backup restore flow.
  final LocalStorageService? localStorage;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  @override
  void initState() {
    super.initState();
    widget.deepLinkRoute?.addListener(_handleDeepLink);
    // A deep-link may already be pending from a cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleDeepLink());
  }

  @override
  void dispose() {
    widget.deepLinkRoute?.removeListener(_handleDeepLink);
    super.dispose();
  }

  /// Navigates to the screen a tapped home-screen widget points to.
  void _handleDeepLink() {
    final notifier = widget.deepLinkRoute;
    final route = notifier?.value;
    if (route == null || !mounted) return;
    notifier!.value = null; // consume so it fires once
    switch (route) {
      case WidgetRoute.fasting:
        _pushTimerTab(context);
        break;
      case WidgetRoute.foodLog:
        _pushNutritionScreen(context);
        break;
      case WidgetRoute.expenseAdd:
        _pushTreasuryScreen(context);
        break;
      case WidgetRoute.weightLog:
        _pushWeightLogScreen(context);
        break;
      case WidgetRoute.quests:
        _pushQuestsTab(context);
        break;
    }
  }

  String _firstName() {
    // userDisplayName / userEmail reach into Supabase.instance, which throws
    // an assertion if accessed before AppShell's post-frame init runs (e.g.
    // on the very first build after a hot restart). Treat any failure here
    // as "not yet known" — the ListenableBuilder will rebuild once auth is
    // ready and resolve the real name.
    try {
      final name = widget.authPresenter?.userDisplayName;
      if (name != null && name.isNotEmpty) return name.split(' ').first;
      final email = widget.authPresenter?.userEmail ?? '';
      if (email.contains('@')) {
        final part = email.split('@').first.split('.').first;
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      }
    } catch (_) {
      // Supabase not yet initialized — fall through.
    }
    return 'Champion';
  }

  String _getGreeting() {
    final greetings = [
      'Hi',
      'Hello',
      'Hey',
      'Good day',
      'Welcome',
      'Greetings'
    ];
    final dayOfYear =
        DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return greetings[dayOfYear % greetings.length];
  }

  String _getTitleText() {
    return '${_getGreeting()}, ${_firstName()}';
  }

  String _todayLabel() {
    return DateFormat('EEEE, MMMM d').format(DateTime.now());
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.fastingPresenter.loadState(),
      widget.questPresenter.reload(),
      if (widget.activityPresenter != null)
        widget.activityPresenter!.loadState(),
      if (widget.nutritionPresenter != null)
        widget.nutritionPresenter!.loadState(),
    ]);
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_getTitleText(), style: AppTextStyles.headlineMedium),
          ),
          const SizedBox(height: 2),
          Text(
            _todayLabel(),
            style: AppTextStyles.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget header = _buildHeader(context);
    // Re-render whenever auth resolves so "Champion" updates to the real name.
    if (widget.authPresenter != null) {
      header = ListenableBuilder(
        listenable: widget.authPresenter!,
        builder: (ctx, _) => _buildHeader(ctx),
      );
    }

    // The docked quick-log bar needs both the ledger and nutrition pipelines;
    // omit it when either is unavailable (e.g. in widget tests).
    final ledger = widget.ledgerPresenter;
    final nutrition = widget.nutritionPresenter;
    final quickLogBar = (ledger != null && nutrition != null)
        ? _QuickLogBar(ledger: ledger, nutrition: nutrition)
        : null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: quickLogBar,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 76,
              collapsedHeight: 76,
              titleSpacing: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: theme.scaffoldBackgroundColor,
              title: header,
              actions: [
                HubStreakPill(nutrition: widget.nutritionPresenter),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _pushSettings(context),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
            // Fixed leading content above the reorderable card stack: the
            // three-ring hero + the adaptive coaching line. Not reorderable.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    HubRingsHero(
                      fasting: widget.fastingPresenter,
                      nutrition: widget.nutritionPresenter,
                      activity: widget.activityPresenter,
                      settings: widget.settingsPresenter,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    HubCoachLine(
                      aiCoach: widget.aiCoachPresenter,
                      nutrition: widget.nutritionPresenter,
                      treasury: widget.treasuryPresenter,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              sliver: ListenableBuilder(
                listenable: widget.hubPresenter,
                builder: (ctx, _) => SliverReorderableList(
                  itemCount: widget.hubPresenter.cardOrder.length,
                  onReorder: (old, neo) {
                    HapticFeedback.mediumImpact();
                    widget.hubPresenter.reorderCards(old, neo);
                  },
                  proxyDecorator: (child, index, animation) => Stack(
                    children: [
                      child,
                      // Border only over the card — stops before the 8px spacing.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: AppSpacing.sm,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  itemBuilder: (ctx, i) {
                    final type = widget.hubPresenter.cardOrder[i];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(type),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildCard(type, ctx),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(HubCardType type, BuildContext context) {
    return switch (type) {
      HubCardType.fasting => FastingHubCard(
          fasting: widget.fastingPresenter,
          onNavigate: () => _pushTimerTab(context),
          onStartFast: widget.fastingPresenter.startFast,
          onEndFast: () => _endFast(context),
        ),
      HubCardType.nutrition => widget.nutritionPresenter != null
          ? NutritionHubCard(
              nutrition: widget.nutritionPresenter!,
              onNavigate: () => _pushNutritionScreen(context),
              onLogMeal: () => _pushNutritionScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.quests => QuestsHubCard(
          quests: widget.questPresenter,
          onNavigate: () => _pushQuestsTab(context),
          onCompleteQuest: (quest) => _markQuestDone(context, quest),
        ),
      HubCardType.activity => widget.activityPresenter != null
          ? ActivityHubCard(
              activity: widget.activityPresenter!,
              onNavigate: () => _pushActivityScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.treasury => widget.treasuryPresenter != null
          ? TreasuryHubCard(
              treasury: widget.treasuryPresenter!,
              ledger: widget.ledgerPresenter,
              bills: widget.billsPresenter,
              onNavigate: () => _pushTreasuryScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.stats => widget.authPresenter != null
          ? StatsHubCard(
              stats: widget.statsPresenter,
              onNavigate: () => _pushStatsScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.weightLog => widget.nutritionPresenter != null
          ? WeightBodyHubCard(
              nutrition: widget.nutritionPresenter!,
              onOpenBody: () => _pushBodyMeasurementScreen(context),
              onOpenWeight: () => _pushWeightLogScreen(context),
            )
          : const SizedBox.shrink(),
      // Body is folded into the Weight slot (2-up tile); not a standalone card.
      HubCardType.bodyMeasurements => const SizedBox.shrink(),
    };
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _pushTimerTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Fasting')),
          body: TimerTab(presenter: widget.fastingPresenter),
        ),
      ),
    );
  }

  void _pushNutritionScreen(BuildContext context) {
    final n = widget.nutritionPresenter;
    if (n == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NutritionScreen(
            presenter: n, aiCoachPresenter: widget.aiCoachPresenter),
      ),
    );
  }

  void _pushWeightLogScreen(BuildContext context) {
    final n = widget.nutritionPresenter;
    if (n == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WeightLogScreen(presenter: n)),
    );
  }

  void _pushBodyMeasurementScreen(BuildContext context) {
    final n = widget.nutritionPresenter;
    if (n == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MeasurementLogScreen(presenter: n)),
    );
  }

  void _pushQuestsTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => QuestsTab(presenter: widget.questPresenter)),
    );
  }

  void _pushActivityScreen(BuildContext context) {
    final ap = widget.activityPresenter;
    if (ap == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ap.isHealthConnectAvailable && !ap.hasHealthPermission
            ? ActivityPermissionScreen(presenter: ap)
            : ActivityScreen(presenter: ap),
      ),
    );
  }

  void _pushTreasuryScreen(BuildContext context) {
    final dash = widget.treasuryPresenter;
    final ledger = widget.ledgerPresenter;
    final bills = widget.billsPresenter;
    final budget = widget.budgetPresenter;
    final history = widget.historyPresenter;
    final installments = widget.installmentPresenter;
    final groceryCart = widget.groceryCartPresenter;
    if (dash == null ||
        ledger == null ||
        bills == null ||
        budget == null ||
        history == null ||
        installments == null ||
        groceryCart == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TreasuryModuleView(
          dashPresenter: dash,
          ledgerPresenter: ledger,
          billsPresenter: bills,
          budgetPresenter: budget,
          historyPresenter: history,
          installmentPresenter: installments,
          groceryCartPresenter: groceryCart,
        ),
      ),
    );
  }

  void _pushStatsScreen(BuildContext context) {
    final auth = widget.authPresenter;
    if (auth == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: StatsView(
            presenter: widget.statsPresenter,
            fastingPresenter: widget.fastingPresenter,
            authPresenter: auth,
            settingsPresenter: widget.settingsPresenter,
            syncPresenter: widget.syncPresenter,
            aiCoachPresenter: widget.aiCoachPresenter,
          ),
        ),
      ),
    );
  }

  void _pushSettings(BuildContext context) {
    final auth = widget.authPresenter;
    if (auth == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          fastingPresenter: widget.fastingPresenter,
          authPresenter: auth,
          settingsPresenter: widget.settingsPresenter,
          syncPresenter: widget.syncPresenter,
          nutritionPresenter: widget.nutritionPresenter,
          statsPresenter: widget.statsPresenter,
          aiCoachPresenter: widget.aiCoachPresenter,
          updatePresenter: widget.updatePresenter,
          localStorage: widget.localStorage,
          onboardingPresenter: widget.onboardingPresenter,
        ),
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────────

  Future<void> _endFast(BuildContext context) async {
    final (xp, _) = await widget.fastingPresenter.stopFast();
    if (context.mounted) {
      AppToast.success(
          context, xp > 0 ? 'Fast complete! +$xp XP' : 'Fast ended');
    }
  }

  Future<void> _markQuestDone(BuildContext context, Quest quest) async {
    final (xp, isCrit) = await widget.questPresenter.completeQuest(quest.id);
    if (context.mounted) {
      final label = isCrit ? 'Critical! +$xp XP' : '+$xp XP';
      AppToast.success(context, '${quest.title} done · $label');
    }
  }
}

// ── Quick-log bar ─────────────────────────────────────────────────────────────
//
// Persistent docked logger that replaces the old expandable feature FAB. One
// input feeds two existing pipelines: a [QuickLogRouter] heuristic sends money
// entries to [LedgerPresenter]'s chat (cloud→on-device→form) and food/exercise
// to [NutritionPresenter.parseChat] (cloud→on-device→rules). Finance shows the
// same inline confirm/clarify panel as the Finance hub card; nutrition commits
// directly and toasts. Feature navigation now lives on the hub cards.

class _QuickLogBar extends StatefulWidget {
  const _QuickLogBar({required this.ledger, required this.nutrition});

  final LedgerPresenter ledger;
  final NutritionPresenter nutrition;

  @override
  State<_QuickLogBar> createState() => _QuickLogBarState();
}

class _QuickLogBarState extends State<_QuickLogBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _lastToastSummary;

  LedgerPresenter get _ledger => widget.ledger;
  NutritionPresenter get _nutrition => widget.nutrition;

  @override
  void initState() {
    super.initState();
    _ledger.addListener(_onLedgerChange);
  }

  @override
  void dispose() {
    _ledger.removeListener(_onLedgerChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Mirrors the Finance hub card: surface the post-commit toast and, when the
  /// AI hands back to the form, open the prefilled sheet. Guarded on route
  /// currency so it doesn't fire while a module is pushed on top of the hub.
  void _onLedgerChange() {
    if (!mounted) return;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrent) return;

    final summary = _ledger.lastCommittedSummary;
    if (summary != null && summary != _lastToastSummary) {
      _lastToastSummary = summary;
      AppToast.success(context, summary);
      _ledger.clearLastCommittedSummary();
    }

    final prefill = _ledger.pendingFormPrefill;
    if (prefill != null) {
      _ledger.consumeFormPrefill();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFormSheet(prefill);
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      _ctrl.clear();
      final target = _routeFor(text);
      if (target == QuickLogTarget.finance) {
        // Mobile clarify flow — the inline panel drives confirm/clarify.
        await _ledger.sendChatInput(text);
      } else {
        // Count before/after so a silent no-op (e.g. the IF-sync eating-window
        // gate) doesn't toast a stale earlier entry.
        final before = _nutrition.chatMessages.length;
        await _nutrition.parseChat(text);
        _toastNutritionResult(before);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  QuickLogTarget _routeFor(String text) {
    // A reply mid-finance-clarify stays with the ledger — don't re-route a
    // bare answer like "BPI" or "yes" back through the heuristic.
    if (_ledger.chatState.phase == ChatPhase.clarifying) {
      return QuickLogTarget.finance;
    }
    final accountNames = {for (final a in _ledger.accounts) a.name};
    return QuickLogRouter.route(text, accountNames: accountNames);
  }

  /// Nutrition commits synchronously to the feed, so after [parseChat] resolves
  /// we either toast the just-logged entry or leave the error chip showing.
  void _toastNutritionResult(int beforeCount) {
    if (!mounted || _nutrition.chatParseError != null) return;
    final messages = _nutrition.chatMessages;
    if (messages.length <= beforeCount) return; // nothing was committed
    final summary = _nutritionSummary(messages.last);
    if (summary != null) AppToast.success(context, summary);
  }

  String? _nutritionSummary(ChatMessage m) {
    if (m.kind == ChatMessageKind.exercise) {
      final e = m.exerciseEntry;
      if (e == null) return null;
      return 'Logged ${e.name} · ${e.caloriesBurned} kcal burned';
    }
    if (m.foodItems.isEmpty) return null;
    final names = m.foodItems.map((f) => f.name).join(', ');
    final kcal = m.foodItems.fold<int>(0, (sum, f) => sum + f.calories);
    return 'Logged $names · $kcal kcal';
  }

  void _openFormSheet(ParsedTransaction prefill) {
    AppBottomSheet.show(
      context: context,
      title: 'Log Transaction',
      body: AddTransactionSheet(
        presenter: _ledger,
        prefill: prefill,
        initialDate: _ledger.selectedDate,
      ),
    );
  }

  String _hint() {
    if (_ledger.chatState.phase == ChatPhase.clarifying) return 'Reply…';
    return 'Log food or an expense…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      // As a Scaffold bottomNavigationBar, this isn't lifted above the keyboard
      // automatically — the body shrinks but the bar stays put and gets covered.
      // Pad by the keyboard inset so the input rides up with the keyboard and
      // stays visible. Zero when the keyboard is dismissed.
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: ListenableBuilder(
              listenable: Listenable.merge([_ledger, _nutrition]),
              builder: (context, _) {
                final busy = _sending ||
                    _nutrition.isChatParsing ||
                    _ledger.chatState.phase == ChatPhase.classifying;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildResponseArea(cs),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            enabled: !busy,
                            style: AppTextStyles.bodyMedium,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: _hint(),
                              hintStyle: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHigh,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.send_rounded),
                            color: cs.primary,
                            tooltip: 'Log',
                            onPressed: busy ? null : _send,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Finance chat state takes the panel when active (it needs confirm/clarify);
  /// otherwise a nutrition parse error gets a dismissible chip.
  Widget _buildResponseArea(ColorScheme cs) {
    final financeActive = _ledger.chatHardError != null ||
        _ledger.chatState.phase != ChatPhase.idle ||
        _ledger.chatState.lastStep != null;
    if (financeActive) return LedgerChatPanel(ledger: _ledger);

    final error = _nutrition.chatParseError;
    if (error != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: AppTextStyles.bodySmall.copyWith(color: cs.error),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: cs.onSurfaceVariant, size: 18),
              onPressed: _nutrition.clearChatParseError,
              tooltip: 'Dismiss',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }
    return const SizedBox(width: double.infinity);
  }
}
