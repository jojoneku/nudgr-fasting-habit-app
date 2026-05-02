import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/ai_coach_presenter.dart';
import '../presenters/auth_presenter.dart';
import '../presenters/bills_receivables_presenter.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
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
import 'activity/activity_permission_screen.dart';
import 'activity/activity_screen.dart';
import 'nutrition/log_meal_sheet.dart';
import 'nutrition/nutrition_screen.dart';
import 'quests/quests_tab.dart';
import 'stats_view.dart';
import 'tabs/timer_tab.dart';
import 'treasury/ledger/add_transaction_sheet.dart';
import 'treasury/treasury_module_view.dart';
import 'widgets/hub/activity_hub_card.dart';
import 'widgets/hub/fasting_hub_card.dart';
import 'widgets/hub/nutrition_hub_card.dart';
import 'widgets/hub/quests_hub_card.dart';
import 'widgets/hub/treasury_hub_card.dart';
import 'widgets/system/overlays/app_bottom_sheet.dart';
import 'widgets/system/overlays/app_toast.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';

class HubScreen extends StatelessWidget {
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
    this.authPresenter,
    this.syncPresenter,
    required this.settingsPresenter,
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
  final AuthPresenter? authPresenter;
  final SyncPresenter? syncPresenter;
  final SettingsPresenter settingsPresenter;

  String _firstName() {
    final name = authPresenter?.userDisplayName;
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    final email = authPresenter?.userEmail ?? '';
    if (email.contains('@')) {
      final part = email.split('@').first.split('.').first;
      return part[0].toUpperCase() + part.substring(1).toLowerCase();
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
      fastingPresenter.loadState(),
      questPresenter.reload(),
      if (activityPresenter != null) activityPresenter!.loadState(),
      if (nutritionPresenter != null) nutritionPresenter!.loadState(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 88% opacity so content is faintly visible through the pinned header.
    final stickyBg = theme.colorScheme.surface.withValues(alpha: 0.88);

    Widget nameTitle = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(_getTitleText(), style: AppTextStyles.headlineMedium),
    );
    // Re-render whenever auth resolves so "Champion" updates to the real name.
    if (authPresenter != null) {
      nameTitle = ListenableBuilder(
        listenable: authPresenter!,
        builder: (_, __) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_getTitleText(), style: AppTextStyles.headlineMedium),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: _ExpandableFab(
        onNutrition: nutritionPresenter != null
            ? () => _pushNutritionScreen(context)
            : null,
        onActivity: activityPresenter != null
            ? () => _pushActivityScreen(context)
            : null,
        onFinance: treasuryPresenter != null
            ? () => _pushTreasuryScreen(context)
            : null,
        onQuests: () => _pushQuestsTab(context),
        onFasting: () => _pushTimerTab(context),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 64,
              collapsedHeight: 64,
              titleSpacing: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: stickyBg,
              title: nameTitle,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _todayLabel(),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              sliver: ListenableBuilder(
                listenable: hubPresenter,
                builder: (ctx, _) => SliverReorderableList(
                  itemCount: hubPresenter.cardOrder.length,
                  onReorder: (old, neo) {
                    HapticFeedback.mediumImpact();
                    hubPresenter.reorderCards(old, neo);
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
                    final type = hubPresenter.cardOrder[i];
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
          fasting: fastingPresenter,
          onNavigate: () => _pushTimerTab(context),
          onStartFast: fastingPresenter.startFast,
          onEndFast: () => _endFast(context),
        ),
      HubCardType.nutrition => nutritionPresenter != null
          ? NutritionHubCard(
              nutrition: nutritionPresenter!,
              onNavigate: () => _pushNutritionScreen(context),
              onLogMeal: () => _showLogMealSheet(context),
            )
          : const SizedBox.shrink(),
      HubCardType.quests => QuestsHubCard(
          quests: questPresenter,
          onNavigate: () => _pushQuestsTab(context),
          onMarkComplete: () => _markNextQuestDone(context),
        ),
      HubCardType.activity => activityPresenter != null
          ? ActivityHubCard(
              activity: activityPresenter!,
              onNavigate: () => _pushActivityScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.treasury => treasuryPresenter != null
          ? TreasuryHubCard(
              treasury: treasuryPresenter!,
              onNavigate: () => _pushTreasuryScreen(context),
            )
          : const SizedBox.shrink(),
      HubCardType.stats => const SizedBox.shrink(),
    };
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _pushTimerTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Fasting')),
          body: TimerTab(presenter: fastingPresenter),
        ),
      ),
    );
  }

  void _pushNutritionScreen(BuildContext context) {
    final n = nutritionPresenter;
    if (n == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NutritionScreen(presenter: n, aiCoachPresenter: aiCoachPresenter),
      ),
    );
  }

  void _pushQuestsTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuestsTab(presenter: questPresenter)),
    );
  }

  void _pushActivityScreen(BuildContext context) {
    final ap = activityPresenter;
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
    final dash = treasuryPresenter;
    final ledger = ledgerPresenter;
    final bills = billsPresenter;
    final budget = budgetPresenter;
    final history = historyPresenter;
    final installments = installmentPresenter;
    if (dash == null ||
        ledger == null ||
        bills == null ||
        budget == null ||
        history == null ||
        installments == null) return;
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
        ),
      ),
    );
  }

  void _pushStatsView(BuildContext context) {
    final auth = authPresenter;
    if (auth == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: StatsView(
            presenter: statsPresenter,
            fastingPresenter: fastingPresenter,
            authPresenter: auth,
            syncPresenter: syncPresenter,
            settingsPresenter: settingsPresenter,
          ),
        ),
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────────

  Future<void> _endFast(BuildContext context) async {
    final (xp, _) = await fastingPresenter.stopFast();
    if (context.mounted) {
      AppToast.success(
          context, xp > 0 ? 'Fast complete! +$xp XP' : 'Fast ended');
    }
  }

  void _showLogMealSheet(BuildContext context) {
    final n = nutritionPresenter;
    if (n == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogMealSheet(presenter: n),
    );
  }

  Future<void> _markNextQuestDone(BuildContext context) async {
    final quest = questPresenter.nextUrgentQuest;
    if (quest == null) return;
    final (xp, isCrit) = await questPresenter.completeQuest(quest.id);
    if (context.mounted) {
      final label = isCrit ? 'Critical! +$xp XP' : '+$xp XP';
      AppToast.success(context, '${quest.title} done · $label');
    }
  }

  void _showAddTransactionSheet(BuildContext context) {
    final ledger = ledgerPresenter;
    if (ledger == null) return;
    AppBottomSheet.show(
      context: context,
      title: 'Log Expense',
      body: AddTransactionSheet(presenter: ledger),
    );
  }
}

// ── Expandable feature FAB ────────────────────────────────────────────────────

class _ExpandableFab extends StatefulWidget {
  const _ExpandableFab({
    required this.onNutrition,
    required this.onActivity,
    required this.onFinance,
    required this.onQuests,
    required this.onFasting,
  });

  final VoidCallback? onNutrition;
  final VoidCallback? onActivity;
  final VoidCallback? onFinance;
  final VoidCallback? onQuests;
  final VoidCallback? onFasting;

  @override
  State<_ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<_ExpandableFab>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      _isOpen ? _ctrl.forward() : _ctrl.reverse();
    });
  }

  void _close() {
    if (!_isOpen) return;
    setState(() {
      _isOpen = false;
      _ctrl.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      (
        label: 'Nutrition',
        icon: Icons.restaurant_outlined,
        cb: widget.onNutrition
      ),
      (
        label: 'Activity',
        icon: Icons.directions_run_rounded,
        cb: widget.onActivity
      ),
      (
        label: 'Finance',
        icon: Icons.account_balance_wallet_outlined,
        cb: widget.onFinance
      ),
      (label: 'Quests', icon: Icons.flag_outlined, cb: widget.onQuests),
      (
        label: 'Fasting',
        icon: Icons.hourglass_empty_rounded,
        cb: widget.onFasting
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: _isOpen
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      _FabItem(
                        label: items[i].label,
                        icon: items[i].icon,
                        controller: _ctrl,
                        intervalStart: i * 0.07,
                        onTap: items[i].cb != null
                            ? () {
                                _close();
                                items[i].cb!();
                              }
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
        FloatingActionButton(
          heroTag: 'hub_feature_fab',
          onPressed: _toggle,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 3,
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.add, size: 26),
          ),
        ),
      ],
    );
  }
}

class _FabItem extends StatelessWidget {
  const _FabItem({
    required this.label,
    required this.icon,
    required this.controller,
    required this.intervalStart,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final AnimationController controller;
  final double intervalStart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(intervalStart, (intervalStart + 0.6).clamp(0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(anim),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: theme.colorScheme.primaryContainer,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
