import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../presenters/activity_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../app_colors.dart';
import 'activity/activity_permission_screen.dart';
import 'activity/activity_screen.dart';
import 'widgets/module_card.dart';
import 'tabs/timer_tab.dart';
import 'tabs/quests_tab.dart';
import 'nutrition/nutrition_screen.dart';

class HubScreen extends StatelessWidget {
  final FastingPresenter fastingPresenter;
  final StatsPresenter statsPresenter;
  final NutritionPresenter? nutritionPresenter;
  final ActivityPresenter? activityPresenter;

  /// Extra subtitle overrides: moduleId → subtitle string getter.
  /// Populated by AppShell as new modules (Activity, Treasury) are added.
  final Map<String, String Function()> moduleSubtitleGetters;

  /// Optional onTap overrides per module. If absent, defaults are used.
  final Map<String, VoidCallback> moduleOnTapOverrides;

  const HubScreen({
    super.key,
    required this.fastingPresenter,
    required this.statsPresenter,
    this.nutritionPresenter,
    this.activityPresenter,
    this.moduleSubtitleGetters = const {},
    this.moduleOnTapOverrides = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        fastingPresenter,
        statsPresenter,
        if (nutritionPresenter != null) nutritionPresenter!,
        if (activityPresenter != null) activityPresenter!,
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
    final fastingSubtitle = moduleSubtitleGetters['fasting']
            ?.call() ??
        (fastingPresenter.isFasting ? 'Fasting now' : 'Not fasting');

    final questsSubtitle = moduleSubtitleGetters['quests']?.call() ??
        _questsSummary();

    return [
      ModuleCard(
        title: 'Fasting',
        rpgName: 'DISCIPLINE PROTOCOL',
        icon: Icons.timer,
        accentColor: AppColors.primary,
        subtitle: fastingSubtitle,
        onTap: moduleOnTapOverrides['fasting'] ??
            () => _pushTimerTab(context),
      ),
      ModuleCard(
        title: 'Quests',
        rpgName: 'QUEST BOARD',
        icon: MdiIcons.swordCross,
        accentColor: AppColors.secondary,
        subtitle: questsSubtitle,
        onTap: moduleOnTapOverrides['quests'] ??
            () => _pushQuestsTab(context),
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
        isLocked: true,
      ),
    ];
  }

  String _questsSummary() {
    final quests = fastingPresenter.quests;
    if (quests.isEmpty) return 'No quests';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayWeekday = now.weekday;
    final todaysQuests = quests
        .where((q) => q.isEnabled && q.days[todayWeekday - 1])
        .toList();
    if (todaysQuests.isEmpty) return 'None today';
    final done =
        todaysQuests.where((q) => q.isCompletedOn(today)).length;
    return '$done/${todaysQuests.length} done today';
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

  void _pushQuestsTab(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuestsTab(presenter: fastingPresenter),
      ),
    );
  }
}
