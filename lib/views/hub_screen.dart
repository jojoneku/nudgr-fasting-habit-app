import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/bills_receivables_presenter.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/quest_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../app_colors.dart';
import 'activity/activity_permission_screen.dart';
import 'activity/activity_screen.dart';
import 'widgets/module_card.dart';
import 'tabs/timer_tab.dart';
import 'quests/quests_tab.dart';
import 'nutrition/nutrition_screen.dart';
import 'treasury/treasury_module_view.dart';

class HubScreen extends StatelessWidget {
  final FastingPresenter fastingPresenter;
  final StatsPresenter statsPresenter;
  final QuestPresenter questPresenter;
  final NutritionPresenter? nutritionPresenter;
  final ActivityPresenter? activityPresenter;
  final TreasuryDashboardPresenter? treasuryPresenter;
  final LedgerPresenter? ledgerPresenter;
  final BillsReceivablesPresenter? billsPresenter;
  final BudgetPresenter? budgetPresenter;
  final TreasuryHistoryPresenter? historyPresenter;
  final InstallmentPresenter? installmentPresenter;

  /// Extra subtitle overrides: moduleId → subtitle string getter.
  final Map<String, String Function()> moduleSubtitleGetters;

  /// Optional onTap overrides per module.
  final Map<String, VoidCallback> moduleOnTapOverrides;

  const HubScreen({
    super.key,
    required this.fastingPresenter,
    required this.statsPresenter,
    required this.questPresenter,
    this.nutritionPresenter,
    this.activityPresenter,
    this.treasuryPresenter,
    this.ledgerPresenter,
    this.billsPresenter,
    this.budgetPresenter,
    this.historyPresenter,
    this.installmentPresenter,
    this.moduleSubtitleGetters = const {},
    this.moduleOnTapOverrides = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        fastingPresenter,
        statsPresenter,
        questPresenter,
        if (nutritionPresenter != null) nutritionPresenter!,
        if (activityPresenter != null) activityPresenter!,
        if (treasuryPresenter != null) treasuryPresenter!,
      ]),
      builder: (context, _) => _buildGrid(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final modules = _buildModuleDefinitions(context);

    return CustomScrollView(
      slivers: [
        const SliverAppBar(
          title: Text(
            'SYSTEM INTERFACE',
            style: TextStyle(letterSpacing: 3.0, fontSize: 14),
          ),
          centerTitle: true,
          pinned: false,
          floating: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => modules[index],
              childCount: modules.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildModuleDefinitions(BuildContext context) {
    final fastingSubtitle = moduleSubtitleGetters['fasting']?.call() ??
        (fastingPresenter.isFasting ? 'Fasting now' : 'Not fasting');

    final questsSubtitle =
        moduleSubtitleGetters['quests']?.call() ?? _questsSummary();

    return [
      ModuleCard(
        title: 'Fasting',
        rpgName: 'DISCIPLINE PROTOCOL',
        icon: Icons.timer,
        accentColor: AppColors.primary,
        subtitle: fastingSubtitle,
        onTap: moduleOnTapOverrides['fasting'] ?? () => _pushTimerTab(context),
      ),
      ModuleCard(
        title: 'Quests',
        rpgName: 'QUEST BOARD',
        icon: MdiIcons.swordCross,
        accentColor: AppColors.secondary,
        subtitle: questsSubtitle,
        onTap: moduleOnTapOverrides['quests'] ?? () => _pushQuestsTab(context),
      ),
      ModuleCard(
        title: 'Calories',
        rpgName: 'ALCHEMY LAB',
        icon: MdiIcons.flask,
        accentColor: AppColors.gold,
        isLocked: nutritionPresenter == null,
        subtitle: nutritionPresenter != null
            ? moduleSubtitleGetters['calories']?.call() ??
                nutritionPresenter!.hubSubtitle
            : null,
        onTap: moduleOnTapOverrides['calories'] ??
            (nutritionPresenter != null
                ? () => _pushNutritionScreen(context)
                : null),
      ),
      ModuleCard(
        title: 'Activity',
        rpgName: 'TRAINING GROUNDS',
        icon: MdiIcons.run,
        accentColor: AppColors.success,
        isLocked: activityPresenter == null,
        subtitle: activityPresenter != null
            ? moduleSubtitleGetters['activity']?.call() ??
                activityPresenter!.hubSubtitle
            : null,
        onTap: moduleOnTapOverrides['activity'] ??
            (activityPresenter != null
                ? () => _pushActivityScreen(context)
                : null),
      ),
      ModuleCard(
        title: 'Finance',
        rpgName: 'TREASURY',
        icon: MdiIcons.bank,
        accentColor: Colors.amber,
        isLocked: treasuryPresenter == null,
        subtitle: treasuryPresenter != null ? 'Track finances' : null,
        onTap: moduleOnTapOverrides['treasury'] ??
            (treasuryPresenter != null
                ? () => _pushTreasuryScreen(context)
                : null),
      ),
    ];
  }

  String _questsSummary() {
    final active = questPresenter.todayActiveQuests.length;
    final overdue = questPresenter.todayOverdueQuests.length;
    final completed = questPresenter.todayCompletedQuests.length;
    final total = active + overdue + completed;
    if (total == 0) return 'No missions today';
    return '$completed/$total done today';
  }

  void _pushTimerTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Discipline Protocol')),
          body: TimerTab(presenter: fastingPresenter),
        ),
      ),
    );
  }

  void _pushNutritionScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NutritionScreen(presenter: nutritionPresenter!),
      ),
    );
  }

  void _pushActivityScreen(BuildContext context) {
    final ap = activityPresenter!;
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

  void _pushQuestsTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestsTab(presenter: questPresenter),
      ),
    );
  }
}
