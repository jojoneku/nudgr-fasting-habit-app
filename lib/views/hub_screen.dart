import 'package:flutter/material.dart';
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
import 'widgets/hub/stats_hub_card.dart';
import 'widgets/hub/treasury_hub_card.dart';
import 'widgets/system/overlays/app_toast.dart';
import 'widgets/system/foundation/app_page_scaffold.dart';
import '../utils/app_spacing.dart';

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
    return AppPageScaffold.large(
      title: 'Today',
      subtitle: _todayLabel(),
      onRefresh: _refresh,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          sliver: ListenableBuilder(
            listenable: hubPresenter,
            builder: (ctx, _) => SliverList(
              delegate: SliverChildListDelegate(
                hubPresenter.cardOrder
                    .map((type) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _buildCard(type, ctx),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
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
              onLogExpense: () => _showAddTransactionSheet(context),
            )
          : const SizedBox.shrink(),
      HubCardType.stats => StatsHubCard(
          stats: statsPresenter,
          onNavigate: () => _pushStatsView(context),
        ),
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
        builder: (_) => NutritionScreen(presenter: n, aiCoachPresenter: aiCoachPresenter),
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
    if (dash == null || ledger == null || bills == null || budget == null || history == null || installments == null) return;
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
          ),
        ),
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────────

  Future<void> _endFast(BuildContext context) async {
    final (xp, _) = await fastingPresenter.stopFast();
    if (context.mounted) {
      AppToast.success(context, xp > 0 ? 'Fast complete! +$xp XP' : 'Fast ended');
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTransactionSheet(presenter: ledger),
    );
  }
}
