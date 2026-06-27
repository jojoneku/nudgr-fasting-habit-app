import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/ai_coach_context.dart';
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
import 'nutrition/log_meal_sheet.dart';
import 'nutrition/nutrition_screen.dart';
import 'quests/quests_tab.dart';
import 'settings_screen.dart';
import 'tabs/timer_tab.dart';
import 'treasury/treasury_module_view.dart';
import 'widgets/ai_chat_sheet.dart';
import 'widgets/hub/activity_hub_card.dart';
import 'widgets/hub/body_measurement_hub_card.dart';
import 'widgets/hub/fasting_hub_card.dart';
import 'widgets/hub/nutrition_hub_card.dart';
import 'widgets/hub/quests_hub_card.dart';
import 'widgets/hub/treasury_hub_card.dart';
import 'widgets/hub/weight_hub_card.dart';
import 'nutrition/measurement_log_screen.dart';
import 'nutrition/weight_log_screen.dart';
import 'widgets/system/overlays/app_toast.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';

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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: widget.aiCoachPresenter != null
          ? _HomeChatBar(presenter: widget.aiCoachPresenter!)
          : null,
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
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _pushSettings(context),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
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
          onMarkComplete: () => _markNextQuestDone(context),
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
              onNavigate: () => _pushTreasuryScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.stats => const SizedBox.shrink(),
      HubCardType.weightLog => widget.nutritionPresenter != null
          ? WeightHubCard(
              nutrition: widget.nutritionPresenter!,
              onNavigate: () => _pushWeightLogScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.bodyMeasurements => widget.nutritionPresenter != null
          ? BodyMeasurementHubCard(
              nutrition: widget.nutritionPresenter!,
              onNavigate: () => _pushBodyMeasurementScreen(context),
            )
          : const SizedBox.shrink(),
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

  void _showLogMealSheet(BuildContext context) {
    final n = widget.nutritionPresenter;
    if (n == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogMealSheet(presenter: n),
    );
  }

  Future<void> _markNextQuestDone(BuildContext context) async {
    final quest = widget.questPresenter.nextUrgentQuest;
    if (quest == null) return;
    final (xp, isCrit) = await widget.questPresenter.completeQuest(quest.id);
    if (context.mounted) {
      final label = isCrit ? 'Critical! +$xp XP' : '+$xp XP';
      AppToast.success(context, '${quest.title} done · $label');
    }
  }
}

// ── Home chat bar ─────────────────────────────────────────────────────────────
//
// Persistent docked entry into the AI Coach, replacing the old expandable
// feature FAB. Typing here and sending opens the full [AiChatSheet] (general
// entry point) and forwards the message; tapping send while empty just opens
// the coach. Feature navigation now lives on the hub cards themselves.

class _HomeChatBar extends StatefulWidget {
  const _HomeChatBar({required this.presenter});

  final AiCoachPresenter presenter;

  @override
  State<_HomeChatBar> createState() => _HomeChatBarState();
}

class _HomeChatBarState extends State<_HomeChatBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _launch({String? text}) {
    final seed = (text ?? _ctrl.text).trim();
    _ctrl.clear();
    _focus.unfocus();
    AiChatSheet.show(
      context,
      presenter: widget.presenter,
      entryPoint: AiCoachEntryPoint.general,
      initialText: seed.isEmpty ? null : seed,
    );
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
            child: Row(
              children: [
                Icon(Icons.psychology_outlined, color: cs.primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    style: AppTextStyles.bodyMedium,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (t) => _launch(text: t),
                    decoration: InputDecoration(
                      hintText: 'Ask your coach…',
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
                    icon: const Icon(Icons.send_rounded),
                    color: cs.primary,
                    tooltip: 'Ask your coach',
                    onPressed: () => _launch(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
