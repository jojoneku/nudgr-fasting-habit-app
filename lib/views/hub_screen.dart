import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import 'activity/activity_permission_screen.dart';
import 'activity/activity_screen.dart';
import 'nutrition/log_meal_sheet.dart';
import 'nutrition/nutrition_screen.dart';
import 'quests/quests_tab.dart';
import 'settings_screen.dart';
import 'tabs/timer_tab.dart';
import 'treasury/treasury_module_view.dart';
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

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fabCtrl;
  bool _isFabOpen = false;

  @override
  void initState() {
    super.initState();
    _fabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    super.dispose();
  }

  void _toggleFab() {
    setState(() {
      _isFabOpen = !_isFabOpen;
      _isFabOpen ? _fabCtrl.forward() : _fabCtrl.reverse();
    });
  }

  void _closeFab() {
    if (!_isFabOpen) return;
    setState(() {
      _isFabOpen = false;
      _fabCtrl.reverse();
    });
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _ExpandableFab(
        controller: _fabCtrl,
        isOpen: _isFabOpen,
        onToggle: _toggleFab,
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _fabCtrl,
        builder: (ctx, _) {
          final color = Color.lerp(
            theme.colorScheme.surfaceContainerHigh,
            theme.colorScheme.primary,
            _fabCtrl.value,
          )!;
          return BottomAppBar(
            color: color,
            elevation: 0,
            height: 56,
            padding: EdgeInsets.zero,
            child: const SizedBox.shrink(),
          );
        },
      ),
      body: Stack(
        children: [
          RefreshIndicator(
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
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
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
          // Tap-outside scrim, only while the FAB fan is open.
          AnimatedBuilder(
            animation: _fabCtrl,
            builder: (_, __) {
              final v = _fabCtrl.value;
              if (v == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isFabOpen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeFab,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.28 * v),
                    ),
                  ),
                ),
              );
            },
          ),
          // Fan items live in the body Stack (not inside the FAB) so taps
          // outside the FAB's tiny hit-test box still register. Rendered above
          // the scrim so taps reach the items first.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_isFabOpen,
              child: Center(
                child: _FanLayer(
                  controller: _fabCtrl,
                  onClose: _closeFab,
                  onNutrition: widget.nutritionPresenter != null
                      ? () => _pushNutritionScreen(context)
                      : null,
                  onActivity: widget.activityPresenter != null
                      ? () => _pushActivityScreen(context)
                      : null,
                  onFinance: widget.treasuryPresenter != null
                      ? () => _pushTreasuryScreen(context)
                      : null,
                  onQuests: () => _pushQuestsTab(context),
                  onFasting: () => _pushTimerTab(context),
                ),
              ),
            ),
          ),
        ],
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

// ── Expandable feature FAB ────────────────────────────────────────────────────
//
// Center-docked FAB that fans its items out in a half-arc above when tapped.
// The FAB and the BottomAppBar share the same animation: grey when closed,
// primary blue when open.

class _ExpandableFab extends StatelessWidget {
  const _ExpandableFab({
    required this.controller,
    required this.isOpen,
    required this.onToggle,
  });

  final AnimationController controller;
  final bool isOpen;
  final VoidCallback onToggle;

  // Wide bell-curve dimensions. Top half (above the bar) renders a Gaussian
  // bell; bottom half is rectangular and hidden inside the BottomAppBar.
  static const double _fabWidth = 120;
  static const double _fabHeight = 70;
  // Positive values push the FAB down on the y-axis (deeper into the bar,
  // less visible bump). Negative values lift it up.
  static const double _fabYOffset = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Transform.translate(
      offset: const Offset(0, _fabYOffset),
      child: SizedBox(
        width: _fabWidth,
        height: _fabHeight,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final t = controller.value;
            final bg = Color.lerp(
              theme.colorScheme.surfaceContainerHigh,
              theme.colorScheme.primary,
              t,
            )!;
            final fg = Color.lerp(
              theme.colorScheme.onSurface,
              theme.colorScheme.onPrimary,
              t,
            )!;
            return ClipPath(
              clipper: const _BellClipper(),
              child: Material(
                color: bg,
                elevation: 0,
                child: InkWell(
                  onTap: onToggle,
                  child: SizedBox(
                    width: _fabWidth,
                    height: _fabHeight,
                    // Icon sits in the top half, centered on the bell's peak.
                    child: Align(
                      alignment: const Alignment(0, -0.5),
                      child: Transform.rotate(
                        angle: t * (math.pi / 4),
                        child: Icon(Icons.add, size: 24, color: fg),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Renders the fan items as a layer in the body Stack so taps outside the
/// FAB's small hit-test box still register. Anchored at the bottom-center of
/// the body, with items radiating up from the bell's visual position.
class _FanLayer extends StatelessWidget {
  const _FanLayer({
    required this.controller,
    required this.onClose,
    required this.onNutrition,
    required this.onActivity,
    required this.onFinance,
    required this.onQuests,
    required this.onFasting,
  });

  final AnimationController controller;
  final VoidCallback onClose;
  final VoidCallback? onNutrition;
  final VoidCallback? onActivity;
  final VoidCallback? onFinance;
  final VoidCallback? onQuests;
  final VoidCallback? onFasting;

  static const double _layerWidth = 360;
  static const double _layerHeight = 220;
  static const double _fanRadius = 150;

  @override
  Widget build(BuildContext context) {
    final items = <_FabAction>[
      _FabAction('Fasting', Icons.timer_outlined, onFasting),
      _FabAction('Nutrition', Icons.restaurant_outlined, onNutrition),
      _FabAction('Quests', Icons.assignment_outlined, onQuests),
      _FabAction('Activity', Icons.directions_run_outlined, onActivity),
      _FabAction('Finance', Icons.account_balance_outlined, onFinance),
    ];

    return SizedBox(
      width: _layerWidth,
      height: _layerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < items.length; i++)
            _FanItem(
              controller: controller,
              angle: _angleFor(i, items.length),
              radius: _fanRadius,
              anchor: const Offset(_layerWidth / 2, _layerHeight),
              label: items[i].label,
              icon: items[i].icon,
              onTap: items[i].cb != null
                  ? () {
                      onClose();
                      items[i].cb!();
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  // Spread items across an arc above the FAB. 140° = upper-left, 40° =
  // upper-right (0° points right in math convention; we negate y for screen).
  double _angleFor(int i, int n) {
    if (n <= 1) return math.pi / 2;
    const startDeg = 140.0;
    const endDeg = 40.0;
    final t = i / (n - 1);
    final deg = startDeg + (endDeg - startDeg) * t;
    return deg * math.pi / 180;
  }
}

class _FabAction {
  const _FabAction(this.label, this.icon, this.cb);
  final String label;
  final IconData icon;
  final VoidCallback? cb;
}

class _FanItem extends StatelessWidget {
  const _FanItem({
    required this.controller,
    required this.angle,
    required this.radius,
    required this.anchor,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final AnimationController controller;
  final double angle; // radians
  final double radius;
  final Offset
      anchor; // (x, y) origin from which items radiate, in parent coords
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  static const double _itemSize = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final raw = controller.value;
        // Skip building entirely when fully closed so the label Text is not
        // in the tree (avoids duplicate matches with hub card titles).
        if (raw == 0) return const SizedBox.shrink();
        // easeOutBack gives a small overshoot so items "pop" into place.
        final t = Curves.easeOutBack.transform(raw);
        final dx = math.cos(angle) * radius * t;
        final dy = -math.sin(angle) * radius * t;
        final left = anchor.dx + dx;
        final top = anchor.dy + dy - _itemSize / 2;
        final opacity = raw.clamp(0.0, 1.0);
        return Positioned(
          left: left,
          top: top,
          child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: IgnorePointer(
              ignoring: raw < 0.4,
              child: Opacity(
                opacity: opacity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: theme.colorScheme.primaryContainer,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        onTap: onTap,
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: _itemSize,
                          height: _itemSize,
                          child: Icon(
                            icon,
                            size: 22,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Gaussian bell-curve clipper. Top half of the rect renders the bell; bottom
// half is rectangular and sits embedded in the BottomAppBar. Used by
// _ExpandableFab.
class _BellClipper extends CustomClipper<Path> {
  const _BellClipper();

  // Width of the bell relative to the rect: ~3.6 sigma per half-width keeps
  // the curve visually grounded by the time it reaches the rect edges.
  static const double _sigmaDivisor = 3.6;
  static const int _samples = 72;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final bumpHeight = h * 0.5;
    final sigma = w / _sigmaDivisor;
    final cx = w / 2;

    final path = Path()..moveTo(0, bumpHeight);
    for (int i = 0; i <= _samples; i++) {
      final t = i / _samples;
      final x = w * t;
      final dx = x - cx;
      final y =
          bumpHeight - bumpHeight * math.exp(-(dx * dx) / (2 * sigma * sigma));
      path.lineTo(x, y);
    }
    path
      ..lineTo(w, bumpHeight)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_BellClipper oldClipper) => false;
}
