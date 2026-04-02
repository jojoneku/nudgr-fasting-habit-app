import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../app_colors.dart';
import '../../models/activity_log.dart';
import '../../presenters/activity_presenter.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRAINING GROUNDS',
          style: TextStyle(letterSpacing: 2.0, fontSize: 14),
        ),
        centerTitle: true,
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
      ),
      body: ListenableBuilder(
        listenable: widget.presenter,
        builder: (context, _) {
          final p = widget.presenter;
          return SafeArea(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                if (p.hasHealthPermission) {
                  await p.syncFromHealthConnect();
                } else {
                  await p.recheckPermissions();
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroSection(animation: _ringAnimation, presenter: p),
                    const SizedBox(height: 16),
                    _MetricCardsRow(presenter: p),
                    const SizedBox(height: 20),
                    _WeeklyChart(presenter: p),
                    const SizedBox(height: 20),
                    _CalendarSection(presenter: p),
                  ],
                ),
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
    final p = presenter;
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 180,
          height: 180,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) => CustomPaint(
              painter: _RingPainter(
                progress: animation.value,
                ringColor: p.isGoalMet ? AppColors.success : AppColors.gold,
                trackColor: AppColors.surface,
                distanceProgress: p.distanceProgress,
                distanceColor: p.isDistanceGoalMet ? AppColors.success : AppColors.accent,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.isGoalMet)
                      const Icon(Icons.emoji_events, color: AppColors.success, size: 18),
                    Text(
                      _numFmt.format(p.todaySteps),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: p.isGoalMet ? AppColors.success : AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    const Text(
                      'STEPS',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          p.isGoalMet
              ? 'Daily goal crushed!'
              : '${_numFmt.format(p.goals.dailyStepGoal - p.todaySteps > 0 ? p.goals.dailyStepGoal - p.todaySteps : 0)} steps to goal',
          style: TextStyle(
            color: p.isGoalMet ? AppColors.success : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: p.isGoalMet ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (!p.hasHealthPermission) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showManualEntry(context, p),
            child: const Text(
              'Enter manually',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Metric Cards Row ─────────────────────────────────────────────────────────

class _MetricCardsRow extends StatelessWidget {
  final ActivityPresenter presenter;

  const _MetricCardsRow({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final log = presenter.todayLog;
    final goalSteps = presenter.goals.dailyStepGoal;
    final progress = (presenter.todaySteps / goalSteps).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        _MetricCard(
          icon: Icons.directions_walk,
          iconColor: AppColors.success,
          label: 'GOAL',
          value: '${(progress * 100).round()}%',
          sub: '${_numFmt.format(goalSteps)} steps',
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: MdiIcons.fire,
          iconColor: const Color(0xFFFF6D00),
          label: 'CALORIES',
          value: presenter.caloriesBurned(log) != null
              ? _numFmt.format(presenter.caloriesBurned(log)!.round())
              : '—',
          sub: presenter.todayCaloriesLabel,
        ),
        const SizedBox(width: 10),
        _MetricCard(
          icon: MdiIcons.mapMarkerDistance,
          iconColor: AppColors.accent,
          label: 'DISTANCE',
          value: log.distanceMeters != null
              ? (log.distanceMeters! / 1000).toStringAsFixed(1)
              : '—',
          sub: log.distanceMeters != null ? 'km today' : 'no data',
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;

  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Weekly Bar Chart ─────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  final ActivityPresenter presenter;

  const _WeeklyChart({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final logs = presenter.weeklyLogs;
    final maxSteps = presenter.weeklyMaxSteps;
    final goalSteps = presenter.goals.dailyStepGoal;
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    const barAreaHeight = 56.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'WEEKLY ACTIVITY',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                '${_compactNum(logs.fold(0, (s, l) => s + l.steps))} this week',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: logs.map((log) {
              final isToday = log.date == todayKey;
              final ratio = maxSteps > 0 ? log.steps / maxSteps : 0.0;
              final barColor = log.goalMet
                  ? AppColors.success
                  : log.steps > 0
                      ? AppColors.gold
                      : Colors.white.withValues(alpha: 0.08);
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
                      // Bar area — fixed height so labels align
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
                                bottom: math.max(4, ratio * barAreaHeight) + 3,
                                child: Text(
                                  _compactNum(log.steps),
                                  style: TextStyle(
                                    color: isToday ? AppColors.textPrimary : AppColors.textSecondary,
                                    fontSize: 9,
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
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
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
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
                              ? AppColors.accent
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
              const Text('Goal met', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              const SizedBox(width: 12),
              _legendDot(AppColors.gold),
              const SizedBox(width: 4),
              const Text('Active', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              const Spacer(),
              Text(
                'Goal ${_numFmt.format(goalSteps)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
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

    // Connected & synced — subtle green dot, tap does nothing (pull to refresh)
    if (p.hasHealthPermission) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: 'Health Connect active',
          child: Icon(Icons.favorite, color: AppColors.success.withValues(alpha: 0.8), size: 18),
        ),
      );
    }

    // Connecting spinner
    if (p.isConnecting) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    // Not connected — amber chip
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
                style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Manual Entry (accessible from hero section long-press or tap) ────────────

void _showManualEntry(BuildContext context, ActivityPresenter p) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ManualEntrySheet(presenter: p),
  );
}

// ─── Calendar Section (main screen) ──────────────────────────────────────────

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
    final p = widget.presenter;
    final today = DateTime.now();
    final month = DateTime(today.year, today.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final todayKey = DateFormat('yyyy-MM-dd').format(today);
    final historyByDate = p.historyByDate;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('MMMM yyyy').format(month).toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              if (p.isBackfilling) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: () => _openFullList(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Full History →',
                  style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // DOW headers
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map((d) => Expanded(
              child: Center(
                child: Text(d, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Grid — compact cells with mini ring progress
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
              final hasDist = !isFuture && log != null && log.distanceMeters != null && log.distanceMeters! > 0;
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
                      : AppColors.textSecondary;

              return GestureDetector(
                onTap: hasData
                    ? () => setState(() => _selected = isSelected ? null : log)
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
                                  ? AppColors.textSecondary.withValues(alpha: 0.25)
                                  : hasData
                                      ? labelColor
                                      : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: hasData || isToday ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSteps ? _compactSteps(log.steps) : hasDist ? _compactDist(log.distanceMeters!) : '',
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
          // Selected day inline detail
          if (_selected != null) ...[
            const SizedBox(height: 12),
            _DayDetail(log: _selected!, goalSteps: p.goals.dailyStepGoal, calories: p.caloriesBurned(_selected!)),
          ],
          // Legend
          const SizedBox(height: 10),
          Row(
            children: [
              _calLegend(AppColors.success, 'Steps goal'),
              const SizedBox(width: 12),
              _calLegend(AppColors.gold, 'Active'),
              const SizedBox(width: 12),
              _calLegend(AppColors.accent, 'Distance'),
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

  Widget _calLegend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      );

  void _openFullList(BuildContext context) {
    final p = widget.presenter;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (context, _) {
        final p = widget.presenter;
        final sources = p.stepSources;
        final currentSource = p.preferredStepsSourceId;

        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Daily Goals',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _stepsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Steps',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _distCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 5.0',
                ),
              ),
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'STEP DATA SOURCE',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pick one source to prevent double-counting.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 8),
                ...sources.map((s) {
                  final isSelected = currentSource == s.sourceId;
                  return GestureDetector(
                    onTap: () => p.setPreferredStepsSource(
                        isSelected ? null : s.sourceId),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.12)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? AppColors.accent : AppColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.sourceName,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  s.sourceId,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
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
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Today's Steps",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Steps taken today',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final steps = int.tryParse(_ctrl.text);
    if (steps == null || steps < 0) return;
    widget.presenter.setManualSteps(steps);
    Navigator.pop(context);
  }
}

// ─── Full History Sheet (year calendar view) ─────────────────────────────────

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
    // All 12 months of current year, January first
    final months = List.generate(12, (i) => DateTime(today.year, i + 1));

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Handle + title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'ACTIVITY HISTORY',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${history.length} days tracked',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: months.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
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
      ),
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
    final month = widget.month;
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final todayKey = DateFormat('yyyy-MM-dd').format(widget.today);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(month).toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // DOW headers
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
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
              final hasDist = !isFuture && log != null && log.distanceMeters != null && log.distanceMeters! > 0;
              final hasData = hasSteps || hasDist;
              final stepsProgress = hasSteps && widget.goalSteps > 0
                  ? (log.steps / widget.goalSteps).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              final ringColor = !hasSteps
                  ? Colors.transparent
                  : log.goalMet
                      ? AppColors.success
                      : AppColors.gold;
              final distProgress = hasDist && widget.goalDistanceMeters > 0
                  ? (log.distanceMeters! / widget.goalDistanceMeters).clamp(0.0, 1.0).toDouble()
                  : 0.0;
              final distColor = hasDist && widget.goalDistanceMeters > 0
                  ? AppColors.accent
                  : Colors.transparent;
              final labelColor = ringColor != Colors.transparent
                  ? ringColor
                  : distColor != Colors.transparent
                      ? distColor
                      : AppColors.textSecondary;

              return GestureDetector(
                onTap: hasData
                    ? () => setState(() => _selected = isSelected ? null : log)
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
                                  ? AppColors.textSecondary.withValues(alpha: 0.25)
                                  : hasData
                                      ? labelColor
                                      : AppColors.textSecondary,
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
                      hasSteps ? _compactSteps(log.steps) : hasDist ? _compactDist(log.distanceMeters!) : '',
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

  double? _selectedCalories(ActivityLog log) => log.activeCalories ?? log.totalCalories;
}

class _DayDetail extends StatelessWidget {
  final ActivityLog log;
  final int goalSteps;
  final double? calories;

  const _DayDetail({required this.log, required this.goalSteps, this.calories});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(log.date);
    final accentColor = log.goalMet ? AppColors.success : AppColors.gold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(date),
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(Icons.directions_walk, '${_numFmt.format(log.steps)} steps', accentColor),
              if (calories != null) ...[
                const SizedBox(width: 8),
                _chip(MdiIcons.fire, '${calories!.round()} kcal', const Color(0xFFFF6D00)),
              ],
              if (log.distanceMeters != null) ...[
                const SizedBox(width: 8),
                _chip(MdiIcons.mapMarkerDistance, '${(log.distanceMeters! / 1000).toStringAsFixed(1)} km', AppColors.accent),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: goalSteps > 0 ? (log.steps / goalSteps).clamp(0.0, 1.0).toDouble() : 0,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
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
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
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
    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );
    // Progress arc
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

    // Outer ring — steps
    _drawRing(canvas, center, outerRadius, outerStroke, progress, ringColor);
    // Inner ring — distance
    _drawRing(canvas, center, innerRadius, innerStroke, distanceProgress, distanceRingColor);
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
    // Track
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
      _drawRing(canvas, center, innerRadius, innerStroke, distanceProgress, distanceColor);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.distanceProgress != distanceProgress;
}
