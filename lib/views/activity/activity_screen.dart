import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/activity_log.dart';
import '../../presenters/activity_presenter.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../widgets/system/system.dart';

final _numFmt = NumberFormat('#,###');
final _dayFmt = DateFormat('E'); // Mon, Tue…

class ActivityScreen extends StatefulWidget {
  final ActivityPresenter presenter;

  const ActivityScreen({super.key, required this.presenter});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _ringController;
  late Animation<double> _ringAnimation;
  double _lastProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ringAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
    widget.presenter.addListener(_onPresenterUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateRingTo(widget.presenter.stepProgress);
      if (widget.presenter.hasHealthPermission) {
        widget.presenter.syncFromHealthConnect();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.presenter.recheckPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.presenter.removeListener(_onPresenterUpdate);
    _ringController.dispose();
    super.dispose();
  }

  void _onPresenterUpdate() {
    _animateRingTo(widget.presenter.stepProgress);
  }

  void _animateRingTo(double target) {
    _ringAnimation = Tween<double>(
      begin: _lastProgress,
      end: target.clamp(0, 1.5),
    ).animate(CurvedAnimation(parent: _ringController, curve: Curves.easeOut));
    _lastProgress = target.clamp(0, 1.5);
    _ringController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Training Grounds',
      actions: [
        ListenableBuilder(
          listenable: widget.presenter,
          builder: (context, _) => _HcStatusChip(presenter: widget.presenter),
        ),
        ListenableBuilder(
          listenable: widget.presenter,
          builder: (context, _) => IconButton(
            icon: const Icon(Icons.sync_outlined),
            tooltip: 'Re-sync history',
            onPressed: widget.presenter.isBackfilling
                ? null
                : () => widget.presenter.clearAndRebackfill(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.tune_outlined),
          onPressed: () => _showGoalSheet(context),
          tooltip: 'Set goals',
        ),
      ],
      padding: EdgeInsets.zero,
      body: ListenableBuilder(
        listenable: widget.presenter,
        builder: (context, _) {
          final p = widget.presenter;
          return RefreshIndicator(
            onRefresh: () async {
              if (p.hasHealthPermission) {
                await p.syncFromHealthConnect();
              } else {
                await p.recheckPermissions();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroSection(animation: _ringAnimation, presenter: p),
                  const SizedBox(height: AppSpacing.md),
                  _MetricPillsRow(presenter: p),
                  const SizedBox(height: AppSpacing.mdGenerous),
                  _WeeklyChart(presenter: p),
                  const SizedBox(height: AppSpacing.mdGenerous),
                  _CalendarSection(presenter: p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showGoalSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GoalSheet(presenter: widget.presenter),
    );
  }
}

// ─── Hero Section ─────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final Animation<double> animation;
  final ActivityPresenter presenter;

  const _HeroSection({required this.animation, required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = presenter;
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 180,
          height: 180,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _RingPainter(
                progress: animation.value,
                ringColor: p.isGoalMet ? AppColors.success : AppColors.gold,
                trackColor: theme.colorScheme.surfaceContainerLow,
                distanceProgress: p.distanceProgress,
                distanceColor:
                    p.isDistanceGoalMet ? AppColors.success : AppColors.accent,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.isGoalMet)
                      const Icon(Icons.emoji_events,
                          color: AppColors.success, size: 18),
                    Text(
                      _numFmt.format(p.todaySteps),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: p.isGoalMet
                            ? AppColors.success
                            : theme.colorScheme.onSurface,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'steps',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          p.isGoalMet
              ? 'Daily goal crushed!'
              : '${_numFmt.format(p.goals.dailyStepGoal - p.todaySteps > 0 ? p.goals.dailyStepGoal - p.todaySteps : 0)} steps to goal',
          style: TextStyle(
            color: p.isGoalMet
                ? AppColors.success
                : theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: p.isGoalMet ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (!p.hasHealthPermission) ...[
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () => _showManualEntry(context, p),
            child: Text(
              'Enter manually',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Metric Pills Row ─────────────────────────────────────────────────────────

class _MetricPillsRow extends StatelessWidget {
  final ActivityPresenter presenter;

  const _MetricPillsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final log = presenter.todayLog;
    final goalSteps = presenter.goals.dailyStepGoal;
    final progress =
        (presenter.todaySteps / goalSteps).clamp(0.0, 1.0).toDouble();
    final cals = presenter.caloriesBurned(log);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        AppStatPill(
          icon: Icons.directions_walk,
          label: 'Goal',
          value: '${(progress * 100).round()}%',
          color: presenter.isGoalMet
              ? AppStatColor.success
              : AppStatColor.neutral,
        ),
        if (cals != null)
          AppStatPill(
            icon: MdiIcons.fire,
            label: 'Cal',
            value: '${_numFmt.format(cals.round())} kcal',
            color: AppStatColor.warning,
          ),
        if (log.distanceMeters != null)
          AppStatPill(
            icon: MdiIcons.mapMarkerDistance,
            label: 'Dist',
            value: '${(log.distanceMeters! / 1000).toStringAsFixed(1)} km',
            color: AppStatColor.primary,
          ),
      ],
    );
  }
}

// ─── Weekly Bar Chart ─────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  final ActivityPresenter presenter;

  const _WeeklyChart({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = presenter.weeklyLogs;
    final maxSteps = presenter.weeklyMaxSteps;
    final goalSteps = presenter.goals.dailyStepGoal;
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    const barAreaHeight = 56.0;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Weekly activity',
                style: AppTextStyles.labelMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${_compactNum(logs.fold(0, (s, l) => s + l.steps))} this week',
                style: AppTextStyles.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: logs.map((log) {
              final isToday = log.date == todayKey;
              final ratio = maxSteps > 0 ? log.steps / maxSteps : 0.0;
              final barColor = log.goalMet
                  ? AppColors.success
                  : log.steps > 0
                      ? AppColors.gold
                      : theme.colorScheme.surfaceContainerHighest;
              final dayLabel = _dayFmt
                  .format(DateTime.parse(log.date))
                  .substring(0, 2)
                  .toUpperCase();

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: barAreaHeight,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              width: double.infinity,
                              height: math.max(4, ratio * barAreaHeight),
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            if (log.steps > 0)
                              Positioned(
                                bottom:
                                    math.max(4, ratio * barAreaHeight) + 3,
                                child: Text(
                                  _compactNum(log.steps),
                                  style: TextStyle(
                                    color: isToday
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurfaceVariant,
                                    fontSize: 9,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dayLabel,
                        style: TextStyle(
                          color: isToday
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isToday
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendDot(AppColors.success),
              const SizedBox(width: 4),
              Text(
                'Goal met',
                style: AppTextStyles.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              _legendDot(AppColors.gold),
              const SizedBox(width: 4),
              Text(
                'Active',
                style: AppTextStyles.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Goal ${_numFmt.format(goalSteps)}',
                style: AppTextStyles.labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );

  String _compactNum(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}

// ─── HC Status Chip (AppBar) ──────────────────────────────────────────────────

class _HcStatusChip extends StatelessWidget {
  final ActivityPresenter presenter;

  const _HcStatusChip({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final p = presenter;

    if (p.hasHealthPermission) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: 'Health Connect active',
          child: Icon(Icons.favorite,
              color: AppColors.success.withValues(alpha: 0.8), size: 18),
        ),
      );
    }

    if (p.isConnecting) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    final label = p.healthPermissionDenied ? 'Open HC' : 'Connect';
    final onTap = p.healthPermissionDenied
        ? () => p.openHealthConnectSettings()
        : () => p.requestHealthPermission();

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync_outlined, color: AppColors.gold, size: 13),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Manual Entry ─────────────────────────────────────────────────────────────

void _showManualEntry(BuildContext context, ActivityPresenter p) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ManualEntrySheet(presenter: p),
  );
}

// ─── Calendar Section ─────────────────────────────────────────────────────────

class _CalendarSection extends StatefulWidget {
  final ActivityPresenter presenter;

  const _CalendarSection({required this.presenter});

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  ActivityLog? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.presenter;
    final today = DateTime.now();
    final month = DateTime(today.year, today.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final todayKey = DateFormat('yyyy-MM-dd').format(today);
    final historyByDate = p.historyByDate;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('MMMM yyyy').format(month),
                style: AppTextStyles.labelMedium.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (p.isBackfilling) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: () => _openFullList(context),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Full History →',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 46,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox.shrink();
              final day = index - firstWeekday + 1;
              final date = DateTime(month.year, month.month, day);
              final dateKey = DateFormat('yyyy-MM-dd').format(date);
              final isFuture = date.isAfter(today);
              final isToday = dateKey == todayKey;
              final log = historyByDate[dateKey];
              final isSelected = _selected?.date == dateKey;
              final goalSteps = p.goals.dailyStepGoal;
              final goalDist = p.goals.dailyDistanceGoalMeters;
              final hasSteps = !isFuture && log != null && log.steps > 0;
              final hasDist = !isFuture &&
                  log != null &&
                  log.distanceMeters != null &&
                  log.distanceMeters! > 0;
              final hasData = hasSteps || hasDist;
              final stepsProgress = hasSteps && goalSteps > 0
                  ? (log.steps / goalSteps).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              final ringColor = !hasSteps
                  ? Colors.transparent
                  : log.goalMet
                      ? AppColors.success
                      : AppColors.gold;
              final distProgress = hasDist && goalDist > 0
                  ? (log.distanceMeters! / goalDist).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              final distColor = hasDist && goalDist > 0
                  ? AppColors.accent
                  : Colors.transparent;
              final labelColor = ringColor != Colors.transparent
                  ? ringColor
                  : distColor != Colors.transparent
                      ? distColor
                      : theme.colorScheme.onSurfaceVariant;

              return GestureDetector(
                onTap: hasData
                    ? () =>
                        setState(() => _selected = isSelected ? null : log)
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CustomPaint(
                        painter: _MiniRingPainter(
                          progress: stepsProgress,
                          ringColor: ringColor,
                          distanceProgress: distProgress,
                          distanceRingColor: distColor,
                          isToday: isToday,
                          isSelected: isSelected,
                        ),
                        child: Center(
                          child: Text(
                            day.toString(),
                            style: TextStyle(
                              color: isFuture
                                  ? theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.25)
                                  : hasData
                                      ? labelColor
                                      : theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: hasData || isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSteps
                          ? _compactSteps(log.steps)
                          : hasDist
                              ? _compactDist(log.distanceMeters!)
                              : '',
                      style: TextStyle(
                        color: hasData
                            ? labelColor.withValues(alpha: 0.85)
                            : Colors.transparent,
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_selected != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DayDetail(
                log: _selected!,
                goalSteps: p.goals.dailyStepGoal,
                calories: p.caloriesBurned(_selected!)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _calLegend(AppColors.success, 'Steps goal', theme),
              const SizedBox(width: 12),
              _calLegend(AppColors.gold, 'Active', theme),
              const SizedBox(width: 12),
              _calLegend(AppColors.accent, 'Distance', theme),
            ],
          ),
        ],
      ),
    );
  }

  String _compactSteps(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _compactDist(double meters) {
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)}k';
  }

  Widget _calLegend(Color color, String label, ThemeData theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  void _openFullList(BuildContext context) {
    final p = widget.presenter;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FullHistorySheet(
        history: p.history,
        goalSteps: p.goals.dailyStepGoal,
        goalDistanceMeters: p.goals.dailyDistanceGoalMeters,
      ),
    );
  }
}

// ─── Goal Sheet ───────────────────────────────────────────────────────────────

class _GoalSheet extends StatefulWidget {
  final ActivityPresenter presenter;

  const _GoalSheet({required this.presenter});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late TextEditingController _stepsCtrl;
  late TextEditingController _distCtrl;

  @override
  void initState() {
    super.initState();
    final goals = widget.presenter.goals;
    _stepsCtrl = TextEditingController(text: goals.dailyStepGoal.toString());
    _distCtrl = TextEditingController(
      text: goals.dailyDistanceGoalMeters > 0
          ? (goals.dailyDistanceGoalMeters / 1000).toStringAsFixed(1)
          : '',
    );
    widget.presenter.loadStepSources();
  }

  @override
  void dispose() {
    _stepsCtrl.dispose();
    _distCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final p = widget.presenter;
        final sources = p.stepSources;
        final currentSource = p.preferredStepsSourceId;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Text('Daily goals', style: AppTextStyles.titleMedium),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _stepsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Steps'),
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _distCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Distance (km)',
                      hintText: 'e.g. 5.0',
                    ),
                  ),
                  if (sources.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Step data source',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick one source to prevent double-counting.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...sources.map((s) {
                      final isSelected = currentSource == s.sourceId;
                      return AppListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                        title: Text(
                          s.sourceName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(s.sourceId),
                        onTap: () => p.setPreferredStepsSource(
                            isSelected ? null : s.sourceId),
                      );
                    }),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppPrimaryButton(label: 'Save', onPressed: _save),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _save() {
    final steps = int.tryParse(_stepsCtrl.text);
    if (steps == null || steps <= 0) return;
    final distKm = double.tryParse(_distCtrl.text) ?? 0.0;
    widget.presenter.updateGoals(widget.presenter.goals.copyWith(
      dailyStepGoal: steps,
      dailyDistanceGoalMeters: distKm * 1000,
    ));
    Navigator.pop(context);
  }
}

// ─── Manual Entry Sheet ───────────────────────────────────────────────────────

class _ManualEntrySheet extends StatefulWidget {
  final ActivityPresenter presenter;

  const _ManualEntrySheet({required this.presenter});

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.presenter.todaySteps > 0
          ? widget.presenter.todaySteps.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          child: Text("Today's steps", style: AppTextStyles.titleMedium),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration:
                    const InputDecoration(labelText: 'Steps taken today'),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(label: 'Save', onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }

  void _save() {
    final steps = int.tryParse(_ctrl.text);
    if (steps == null || steps < 0) return;
    widget.presenter.setManualSteps(steps);
    Navigator.pop(context);
  }
}

// ─── Full History Sheet ───────────────────────────────────────────────────────

class _FullHistorySheet extends StatelessWidget {
  final List<ActivityLog> history;
  final int goalSteps;
  final double goalDistanceMeters;

  const _FullHistorySheet({
    required this.history,
    required this.goalSteps,
    required this.goalDistanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    final historyByDate = {for (final l in history) l.date: l};
    final today = DateTime.now();
    final months = List.generate(12, (i) => DateTime(today.year, i + 1));

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, controller) {
        final theme = Theme.of(ctx);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Text('Activity history',
                          style: AppTextStyles.titleMedium),
                      const Spacer(),
                      Text(
                        '${history.length} days tracked',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
                itemCount: months.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _MonthCalendarGrid(
                    month: months[i],
                    historyByDate: historyByDate,
                    goalSteps: goalSteps,
                    goalDistanceMeters: goalDistanceMeters,
                    today: today,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Month Calendar Grid ──────────────────────────────────────────────────────

class _MonthCalendarGrid extends StatefulWidget {
  final DateTime month;
  final Map<String, ActivityLog> historyByDate;
  final int goalSteps;
  final double goalDistanceMeters;
  final DateTime today;

  const _MonthCalendarGrid({
    required this.month,
    required this.historyByDate,
    required this.goalSteps,
    required this.goalDistanceMeters,
    required this.today,
  });

  @override
  State<_MonthCalendarGrid> createState() => _MonthCalendarGridState();
}

class _MonthCalendarGridState extends State<_MonthCalendarGrid> {
  ActivityLog? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = widget.month;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final todayKey = DateFormat('yyyy-MM-dd').format(widget.today);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 14, AppSpacing.md, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: AppTextStyles.labelMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 46,
            ),
            itemCount: firstWeekday + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox.shrink();
              final day = index - firstWeekday + 1;
              final date = DateTime(month.year, month.month, day);
              final dateKey = DateFormat('yyyy-MM-dd').format(date);
              final isFuture = date.isAfter(widget.today);
              final isToday = dateKey == todayKey;
              final log = widget.historyByDate[dateKey];
              final isSelected = _selected?.date == dateKey;
              final hasSteps = !isFuture && log != null && log.steps > 0;
              final hasDist = !isFuture &&
                  log != null &&
                  log.distanceMeters != null &&
                  log.distanceMeters! > 0;
              final hasData = hasSteps || hasDist;
              final stepsProgress = hasSteps && widget.goalSteps > 0
                  ? (log.steps / widget.goalSteps).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              final ringColor = !hasSteps
                  ? Colors.transparent
                  : log.goalMet
                      ? AppColors.success
                      : AppColors.gold;
              final distProgress =
                  hasDist && widget.goalDistanceMeters > 0
                      ? (log.distanceMeters! / widget.goalDistanceMeters)
                          .clamp(0.0, 1.0)
                          .toDouble()
                      : 0.0;
              final distColor = hasDist && widget.goalDistanceMeters > 0
                  ? AppColors.accent
                  : Colors.transparent;
              final labelColor = ringColor != Colors.transparent
                  ? ringColor
                  : distColor != Colors.transparent
                      ? distColor
                      : theme.colorScheme.onSurfaceVariant;

              return GestureDetector(
                onTap: hasData
                    ? () =>
                        setState(() => _selected = isSelected ? null : log)
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CustomPaint(
                        painter: _MiniRingPainter(
                          progress: stepsProgress,
                          ringColor: ringColor,
                          distanceProgress: distProgress,
                          distanceRingColor: distColor,
                          isToday: isToday,
                          isSelected: isSelected,
                        ),
                        child: Center(
                          child: Text(
                            day.toString(),
                            style: TextStyle(
                              color: isFuture
                                  ? theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.25)
                                  : hasData
                                      ? labelColor
                                      : theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: hasData || isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSteps
                          ? _compactSteps(log.steps)
                          : hasDist
                              ? _compactDist(log.distanceMeters!)
                              : '',
                      style: TextStyle(
                        color: hasData
                            ? labelColor.withValues(alpha: 0.85)
                            : Colors.transparent,
                        fontSize: 7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_selected != null) ...[
            const SizedBox(height: 10),
            _DayDetail(
              log: _selected!,
              goalSteps: widget.goalSteps,
              calories: _selectedCalories(_selected!),
            ),
          ],
        ],
      ),
    );
  }

  String _compactSteps(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _compactDist(double meters) {
    final km = meters / 1000;
    return '${km.toStringAsFixed(1)}k';
  }

  double? _selectedCalories(ActivityLog log) =>
      log.activeCalories ?? log.totalCalories;
}

class _DayDetail extends StatelessWidget {
  final ActivityLog log;
  final int goalSteps;
  final double? calories;

  const _DayDetail({required this.log, required this.goalSteps, this.calories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.parse(log.date);
    final accentColor = log.goalMet ? AppColors.success : AppColors.gold;
    return AppCard(
      variant: AppCardVariant.outlined,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(date),
            style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _chip(Icons.directions_walk,
                  '${_numFmt.format(log.steps)} steps', accentColor),
              if (calories != null) ...[
                const SizedBox(width: 8),
                _chip(MdiIcons.fire, '${calories!.round()} kcal',
                    const Color(0xFFFF6D00)),
              ],
              if (log.distanceMeters != null) ...[
                const SizedBox(width: 8),
                _chip(
                    MdiIcons.mapMarkerDistance,
                    '${(log.distanceMeters! / 1000).toStringAsFixed(1)} km',
                    AppColors.accent),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: goalSteps > 0
                  ? (log.steps / goalSteps).clamp(0.0, 1.0).toDouble()
                  : 0,
              minHeight: 4,
              backgroundColor:
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
}

// ─── Mini Ring Painter (calendar cells) ──────────────────────────────────────

class _MiniRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final double distanceProgress;
  final Color distanceRingColor;
  final bool isToday;
  final bool isSelected;

  const _MiniRingPainter({
    required this.progress,
    required this.ringColor,
    required this.distanceProgress,
    required this.distanceRingColor,
    required this.isToday,
    required this.isSelected,
  });

  void _drawRing(Canvas canvas, Offset center, double radius,
      double strokeWidth, double prog, Color color) {
    if (color == Colors.transparent) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
    if (prog > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        prog * 2 * math.pi,
        false,
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const outerStroke = 2.5;
    const innerStroke = 2.0;
    const gap = 1.5;
    final outerRadius = size.shortestSide / 2 - 2;
    final innerRadius = outerRadius - outerStroke - gap - innerStroke / 2;

    _drawRing(canvas, center, outerRadius, outerStroke, progress, ringColor);
    _drawRing(canvas, center, innerRadius, innerStroke, distanceProgress,
        distanceRingColor);
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.distanceProgress != distanceProgress ||
      old.distanceRingColor != distanceRingColor ||
      old.isToday != isToday ||
      old.isSelected != isSelected;
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;
  final double distanceProgress;
  final Color distanceColor;

  const _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    this.distanceProgress = 0.0,
    this.distanceColor = AppColors.accent,
  });

  void _drawRing(Canvas canvas, Offset center, double radius,
      double strokeWidth, double prog, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (prog <= 0) return;
    final sweep = (prog * 2 * math.pi).clamp(0.0, 2 * math.pi * 1.5);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const outerStroke = 10.0;
    const innerStroke = 8.0;
    const gap = 4.0;
    final outerRadius = (size.shortestSide / 2) - 12;
    final innerRadius = outerRadius - outerStroke / 2 - gap - innerStroke / 2;

    _drawRing(canvas, center, outerRadius, outerStroke, progress, ringColor);
    if (distanceProgress > 0 || true) {
      _drawRing(canvas, center, innerRadius, innerStroke, distanceProgress,
          distanceColor);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.distanceProgress != distanceProgress;
}
