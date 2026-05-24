import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/daily_nutrition_log.dart';
import '../../models/dashboard_status.dart';
import '../../models/weight_entry.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';
import 'measurement_log_screen.dart';
import 'weight_log_screen.dart';

class NutritionHistoryScreen extends StatelessWidget {
  final NutritionPresenter presenter;
  const NutritionHistoryScreen({super.key, required this.presenter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: presenter,
      builder: (context, _) => AppPageScaffold(
        title: 'History',
        padding: EdgeInsets.zero,
        body: _HistoryBody(presenter: presenter),
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _HistoryBody extends StatelessWidget {
  final NutritionPresenter presenter;
  const _HistoryBody({required this.presenter});

  static final _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  List<DailyNutritionLog> get _last14Chrono =>
      presenter.history.take(14).toList().reversed.toList();

  List<DailyNutritionLog> get _last7 => presenter.history.take(7).toList();

  bool get _hasAnyMacros => presenter.history.any((l) => l.hasMacros);

  @override
  Widget build(BuildContext context) {
    final history = presenter.history;
    final goal = presenter.effectiveGoal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _GoalStatusCard(presenter: presenter),
        const SizedBox(height: 20),
        if (history.isNotEmpty) ...[
          _SummaryRow(
            presenter: presenter,
            last7: _last7,
            goalCalories: goal,
            logStreak: presenter.logStreak,
          ),
          const SizedBox(height: 20),
          _CalorieTrendSection(
            days: _last14Chrono,
            goalCalories: goal,
            todayKey: _today,
            activeGoal: presenter.activeGoal,
          ),
          const SizedBox(height: 20),
          _GoalChecksSection(presenter: presenter),
          const SizedBox(height: 20),
        ],
        if (_hasAnyMacros) ...[
          _MacroAveragesSection(
            history: history,
            proteinGoal: presenter.proteinGoal,
            carbsGoal: presenter.carbsGoal,
            fatGoal: presenter.fatGoal,
          ),
          const SizedBox(height: 20),
        ],
        _WeightSection(presenter: presenter),
        const SizedBox(height: 20),
        _MeasurementSection(presenter: presenter),
        const SizedBox(height: 20),
        if (history.isNotEmpty)
          _RecentDaysSection(history: history, goalCalories: goal)
        else
          const AppEmptyState(
            icon: Icons.restaurant_outlined,
            title: 'No history yet',
            body: 'Log meals for 2+ days to see your progress',
          ),
      ],
    );
  }
}

// ─── Goal Status Card ─────────────────────────────────────────────────────────

class _GoalStatusCard extends StatefulWidget {
  final NutritionPresenter presenter;
  const _GoalStatusCard({required this.presenter});

  @override
  State<_GoalStatusCard> createState() => _GoalStatusCardState();
}

class _GoalStatusCardState extends State<_GoalStatusCard> {
  bool _chipVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _chipVisible = true);
    });
  }

  static const _gold = Color(0xFFFFD700);

  (IconData, Color) _chipStyle(BuildContext context, GoalStatusLabel label) {
    final cs = Theme.of(context).colorScheme;
    return switch (label) {
      GoalStatusLabel.onTrack => (Icons.check_circle_outline, cs.primary),
      GoalStatusLabel.tooHigh => (Icons.arrow_upward, cs.error),
      GoalStatusLabel.tooAggressive => (Icons.warning_amber_outlined, cs.error),
      GoalStatusLabel.notEnoughSurplus => (Icons.arrow_downward, cs.tertiary),
      GoalStatusLabel.lowProtein => (Icons.warning_amber_outlined, cs.tertiary),
      GoalStatusLabel.possibleRecomp => (Icons.auto_awesome_outlined, _gold),
      GoalStatusLabel.needsMoreData =>
        (Icons.hourglass_empty_outlined, cs.onSurfaceVariant),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final presenter = widget.presenter;
    final status = presenter.dashboardStatus;
    final goalLabel = presenter.goalLabel;
    final avg = presenter.sevenDayAvgCalories;
    final target = presenter.effectiveGoal;
    final isSimpleMode = presenter.activeGoal == null;

    final (chipIcon, chipColor) = _chipStyle(context, status.label);

    final delta = target > 0 ? avg - target : null;
    final deltaText = delta == null
        ? null
        : '${delta >= 0 ? '+' : ''}${NumberFormat('#,###').format(delta)} kcal vs target';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored left accent bar
              Container(width: 4, color: chipColor),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: goal label + status chip
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              goalLabel ?? 'Custom goal',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedOpacity(
                            opacity: _chipVisible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: chipColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(chipIcon, size: 12, color: chipColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    status.headline,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: chipColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Big average number
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            avg > 0
                                ? NumberFormat('#,###').format(avg)
                                : '—',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              height: 1,
                            ),
                          ),
                          if (avg > 0) ...[
                            const SizedBox(width: 5),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                'kcal',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '7-day average',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (deltaText != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          deltaText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: chipColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (isSimpleMode) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Set up Standard Mode to unlock goal tracking.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Summary Row ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final NutritionPresenter presenter;
  final List<DailyNutritionLog> last7;
  final int goalCalories;
  final int logStreak;

  const _SummaryRow({
    required this.presenter,
    required this.last7,
    required this.goalCalories,
    required this.logStreak,
  });

  String get _tile1Value {
    final avg = presenter.sevenDayAvgCalories;
    final target = goalCalories;
    if (target <= 0) return NumberFormat('#,###').format(avg);
    final delta = avg - target;
    final sign = delta > 0 ? '+' : '';
    return '$sign${NumberFormat('#,###').format(delta)} kcal';
  }

  String get _tile2Value {
    final rate = presenter.proteinHitRate7d;
    if (rate == null) return '—';
    final hits = (rate * math.min(last7.length, 7)).round();
    return '$hits/7 days';
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.local_fire_department_outlined,
              value: _tile1Value,
              label: presenter.primaryKpiLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.emoji_events_outlined,
              value: _tile2Value,
              label: presenter.secondaryKpiLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.whatshot_outlined,
              value: '$logStreak',
              label: 'Log streak',
              unit: logStreak == 1 ? 'day' : 'days',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? unit;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (unit != null && unit!.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                unit!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Calorie Trend ────────────────────────────────────────────────────────────

class _CalorieTrendSection extends StatelessWidget {
  final List<DailyNutritionLog> days;
  final int goalCalories;
  final String todayKey;
  final String? activeGoal;

  const _CalorieTrendSection({
    required this.days,
    required this.goalCalories,
    required this.todayKey,
    required this.activeGoal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AppSection(
      title: 'Calorie Trend',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 130,
              child: CustomPaint(
                size: const Size(double.infinity, 130),
                painter: _CalorieTrendPainter(
                  days: days,
                  goalCalories: goalCalories,
                  barColor: primary,
                  errorColor: theme.colorScheme.error,
                  tertiaryColor: theme.colorScheme.tertiary,
                  todayKey: todayKey,
                  activeGoal: activeGoal,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: days.map((log) {
                final dt = DateTime.tryParse(log.date) ?? DateTime.now();
                final isToday = log.date == todayKey;
                return Expanded(
                  child: Text(
                    DateFormat('E').format(dt).substring(0, 1),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday
                          ? primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 10,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendItem(color: primary, label: 'On track'),
                _LegendItem(
                  color: primary.withValues(alpha: 0.35),
                  label: 'Under',
                ),
                _LegendItem(
                  color: theme.colorScheme.error,
                  label: 'Over',
                ),
                if (goalCalories > 0)
                  _LegendItem(
                    color: primary.withValues(alpha: 0.10),
                    label: 'Target band',
                    isRect: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isRect;
  const _LegendItem({
    required this.color,
    required this.label,
    this.isRect = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isRect ? 14 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: isRect ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isRect ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _CalorieTrendPainter extends CustomPainter {
  final List<DailyNutritionLog> days;
  final int goalCalories;
  final Color barColor;
  final Color errorColor;
  final Color tertiaryColor;
  final String todayKey;
  final String? activeGoal;

  const _CalorieTrendPainter({
    required this.days,
    required this.goalCalories,
    required this.barColor,
    required this.errorColor,
    required this.tertiaryColor,
    required this.todayKey,
    required this.activeGoal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final maxCal = math.max(
      goalCalories > 0 ? goalCalories * 1.25 : 1.0,
      days.fold(0.0, (m, d) => math.max(m, d.totalCalories.toDouble())),
    );
    if (maxCal == 0) return;

    double toY(double cal) =>
        size.height * (1 - (cal.clamp(0, maxCal) / maxCal));

    // Target band (±100 kcal around goal)
    if (goalCalories > 0) {
      final bandTop = toY((goalCalories + 100).toDouble());
      final bandBot = toY((goalCalories - 100).toDouble());
      canvas.drawRect(
        Rect.fromLTRB(0, bandTop, size.width, bandBot),
        Paint()..color = barColor.withValues(alpha: 0.10),
      );
    }

    // Goal line — dashed
    if (goalCalories > 0) {
      final goalY = toY(goalCalories.toDouble());
      final dashPaint = Paint()
        ..color = barColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      double x = 0;
      const dashLen = 5.0;
      const gapLen = 5.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, goalY),
          Offset(math.min(x + dashLen, size.width), goalY),
          dashPaint,
        );
        x += dashLen + gapLen;
      }
    }

    final slotW = size.width / days.length;
    final barW = (slotW * 0.52).clamp(4.0, 28.0);

    for (int i = 0; i < days.length; i++) {
      final cal = days[i].totalCalories.toDouble();
      if (cal <= 0) continue;

      final barH = (size.height * (cal / maxCal)).clamp(2.0, size.height);
      final centerX = slotW * i + slotW / 2;
      final left = centerX - barW / 2;
      final top = size.height - barH;
      final isToday = days[i].date == todayKey;

      final color = _barColor(cal.round(), goalCalories);
      final inBand = goalCalories > 0 &&
          cal >= goalCalories - 100 &&
          cal <= goalCalories + 100;
      final topAlpha = inBand || (goalCalories > 0 && cal >= goalCalories)
          ? 0.95
          : 0.32;
      final botAlpha = inBand || (goalCalories > 0 && cal >= goalCalories)
          ? 0.25
          : 0.08;

      final rect = Rect.fromLTWH(left, top, barW, barH);
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );

      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: topAlpha),
          color.withValues(alpha: botAlpha),
        ],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = shader);

      if (isToday) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: 0.7)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }

      if (goalCalories > 0 && cal >= goalCalories) {
        canvas.drawCircle(
          Offset(centerX, top - 4),
          2.5,
          Paint()..color = color,
        );
      }
    }
  }

  Color _barColor(int cal, int target) {
    if (target <= 0) return barColor;
    switch (activeGoal) {
      case 'bulk':
        if (cal > target + 200) return errorColor;
        if (cal < target - 100) return tertiaryColor;
        return barColor;
      case 'maintain':
        if (cal > target + 100 || cal < target - 100) return errorColor;
        return barColor;
      case 'cut':
      case 'recomp':
      default:
        if (cal > target + 100) return errorColor;
        return barColor;
    }
  }

  @override
  bool shouldRepaint(_CalorieTrendPainter old) =>
      old.days != days ||
      old.goalCalories != goalCalories ||
      old.todayKey != todayKey ||
      old.activeGoal != activeGoal;
}

// ─── Goal Checks Section ──────────────────────────────────────────────────────

class _GoalChecksSection extends StatelessWidget {
  final NutritionPresenter presenter;
  const _GoalChecksSection({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phr = presenter.proteinHitRate7d;
    final consistency = presenter.loggingConsistency7d;
    final trendDir = presenter.weightTrendDirection;
    final goal = presenter.activeGoal;

    // Protein threshold by goal
    final proteinThreshold = switch (goal) {
      'cut' => 0.7,
      'bulk' => 0.6,
      'recomp' => 0.65,
      _ => 0.4,
    };
    final proteinOk = phr != null && phr >= proteinThreshold;

    // Weight trend icon + label
    final (trendIcon, trendColor, trendLabel) =
        _trendStyle(context, goal, trendDir);

    String proteinValue;
    if (phr == null) {
      proteinValue = 'No protein goal set';
    } else {
      final hits = (phr * 7).round();
      proteinValue = '$hits/7 days met';
    }

    final loggingHits = (consistency * 7).round();

    return AppSection(
      title: 'Goal Checks',
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _CheckRow(
                icon: phr == null
                    ? Icons.remove_circle_outline
                    : proteinOk
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                iconColor: phr == null
                    ? theme.colorScheme.onSurfaceVariant
                    : proteinOk
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                label: presenter.secondaryKpiLabel,
                value: proteinValue,
              ),
              _CheckRow(
                icon: consistency >= 5 / 7
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                iconColor: consistency >= 5 / 7
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                label: 'Logging streak',
                value: '$loggingHits/7 days logged',
              ),
              _CheckRow(
                icon: trendIcon,
                iconColor: trendColor,
                label: 'Weight trend',
                value: trendLabel,
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, Color, String) _trendStyle(
    BuildContext context,
    String? goal,
    WeightTrendDirection dir,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (dir == WeightTrendDirection.insufficient) {
      return (
        Icons.hourglass_empty_outlined,
        cs.onSurfaceVariant,
        'Not enough data — log weight in Weight Log',
      );
    }
    if (goal == 'recomp' && dir == WeightTrendDirection.stable) {
      return (
        Icons.check_circle,
        cs.primary,
        'Weight holding — protein compliance is the key metric',
      );
    }
    final label = switch ((goal, dir)) {
      ('cut', WeightTrendDirection.down) => 'Trending down ↓',
      ('cut', WeightTrendDirection.stable) => 'Weight stable',
      ('cut', WeightTrendDirection.up) => 'Trending up ↑',
      ('bulk', WeightTrendDirection.up) => 'Trending up ↑',
      ('bulk', WeightTrendDirection.stable) => 'Weight stable',
      ('bulk', WeightTrendDirection.down) => 'Trending down ↓',
      _ => 'Weight stable',
    };
    final icon = switch ((goal, dir)) {
      ('cut', WeightTrendDirection.down) => Icons.check_circle,
      ('cut', WeightTrendDirection.stable) => Icons.auto_awesome_outlined,
      ('cut', WeightTrendDirection.up) => Icons.error_outline,
      ('bulk', WeightTrendDirection.up) => Icons.check_circle,
      ('bulk', WeightTrendDirection.stable) => Icons.info_outline,
      ('bulk', WeightTrendDirection.down) => Icons.error_outline,
      _ => Icons.check_circle,
    };
    final color = switch ((goal, dir)) {
      ('cut', WeightTrendDirection.up) => cs.error,
      ('bulk', WeightTrendDirection.down) => cs.error,
      ('cut', WeightTrendDirection.stable) => cs.tertiary,
      ('bulk', WeightTrendDirection.stable) => cs.onSurfaceVariant,
      _ => cs.primary,
    };
    return (icon, color, label);
  }
}

class _CheckRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isLast;

  const _CheckRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, isLast ? 10 : 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recent Days (paginated + sortable) ──────────────────────────────────────

enum _DaySort { newest, oldest, calHigh, calLow }

class _RecentDaysSection extends StatefulWidget {
  final List<DailyNutritionLog> history;
  final int goalCalories;
  const _RecentDaysSection({
    required this.history,
    required this.goalCalories,
  });

  @override
  State<_RecentDaysSection> createState() => _RecentDaysSectionState();
}

class _RecentDaysSectionState extends State<_RecentDaysSection> {
  static const _pageSize = 7;
  int _shown = _pageSize;
  _DaySort _sort = _DaySort.newest;

  List<DailyNutritionLog> get _sorted {
    final list = List<DailyNutritionLog>.from(widget.history);
    switch (_sort) {
      case _DaySort.newest:
        list.sort((a, b) => b.date.compareTo(a.date));
      case _DaySort.oldest:
        list.sort((a, b) => a.date.compareTo(b.date));
      case _DaySort.calHigh:
        list.sort((a, b) => b.totalCalories.compareTo(a.totalCalories));
      case _DaySort.calLow:
        list.sort((a, b) => a.totalCalories.compareTo(b.totalCalories));
    }
    return list;
  }

  void _setSort(_DaySort s) => setState(() {
        _sort = s;
        _shown = _pageSize;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sorted = _sorted;
    final visible = sorted.take(_shown).toList();
    final hasMore = sorted.length > _shown;

    return AppSection(
      title: 'Recent Days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sort pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SortPill(
                  label: 'Newest',
                  selected: _sort == _DaySort.newest,
                  onTap: () => _setSort(_DaySort.newest),
                ),
                const SizedBox(width: 6),
                _SortPill(
                  label: 'Oldest',
                  selected: _sort == _DaySort.oldest,
                  onTap: () => _setSort(_DaySort.oldest),
                ),
                const SizedBox(width: 6),
                _SortPill(
                  label: 'Cal ↑',
                  selected: _sort == _DaySort.calHigh,
                  onTap: () => _setSort(_DaySort.calHigh),
                ),
                const SizedBox(width: 6),
                _SortPill(
                  label: 'Cal ↓',
                  selected: _sort == _DaySort.calLow,
                  onTap: () => _setSort(_DaySort.calLow),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...visible.map(
            (log) => _DayCard(log: log, goalCalories: widget.goalCalories),
          ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => setState(() => _shown += _pageSize),
                  child: Text(
                    'Show ${math.min(_pageSize, sorted.length - _shown)} more',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.15) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── Macro Averages ───────────────────────────────────────────────────────────

class _MacroAveragesSection extends StatelessWidget {
  final List<DailyNutritionLog> history;
  final int? proteinGoal;
  final int? carbsGoal;
  final int? fatGoal;

  const _MacroAveragesSection({
    required this.history,
    required this.proteinGoal,
    required this.carbsGoal,
    required this.fatGoal,
  });

  List<DailyNutritionLog> get _withMacros =>
      history.where((l) => l.hasMacros).toList();

  double get _avgProtein {
    final w = _withMacros;
    return w.isEmpty ? 0 : w.fold(0.0, (s, l) => s + l.totalProtein) / w.length;
  }

  double get _avgCarbs {
    final w = _withMacros;
    return w.isEmpty ? 0 : w.fold(0.0, (s, l) => s + l.totalCarbs) / w.length;
  }

  double get _avgFat {
    final w = _withMacros;
    return w.isEmpty ? 0 : w.fold(0.0, (s, l) => s + l.totalFat) / w.length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final protein = _avgProtein;
    final carbs = _avgCarbs;
    final fat = _avgFat;
    final total = protein + carbs + fat;

    final proteinColor = theme.colorScheme.primary;
    final carbsColor = theme.colorScheme.secondary;
    final fatColor = theme.colorScheme.error;

    return AppSection(
      title: 'Macro Averages',
      hint: '${_withMacros.length}d avg',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (protein * 100).round(),
                        child: Container(color: proteinColor),
                      ),
                      Flexible(
                        flex: (carbs * 100).round(),
                        child: Container(color: carbsColor),
                      ),
                      Flexible(
                        flex: (fat * 100).round(),
                        child: Container(color: fatColor),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: _MacroTile(
                    label: 'Protein',
                    grams: protein,
                    goalGrams: proteinGoal?.toDouble(),
                    color: proteinColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroTile(
                    label: 'Carbs',
                    grams: carbs,
                    goalGrams: carbsGoal?.toDouble(),
                    color: carbsColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroTile(
                    label: 'Fat',
                    grams: fat,
                    goalGrams: fatGoal?.toDouble(),
                    color: fatColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  final String label;
  final double grams;
  final double? goalGrams;
  final Color color;

  const _MacroTile({
    required this.label,
    required this.grams,
    required this.goalGrams,
    required this.color,
  });

  double get _progress => (goalGrams != null && goalGrams! > 0)
      ? (grams / goalGrams!).clamp(0.0, 1.0)
      : -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${grams.round()}g',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        if (progress >= 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'of ${goalGrams!.round()}g',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Weight Section ───────────────────────────────────────────────────────────

class _WeightSection extends StatelessWidget {
  final NutritionPresenter presenter;
  const _WeightSection({required this.presenter});

  List<WeightEntry> get _recent =>
      presenter.weightLog.reversed.take(7).toList().reversed.toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final recent = _recent;
    final delta = presenter.weightDelta;

    return AppSection(
      title: 'Weight',
      trailing: FilledButton.tonal(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeightLogScreen(presenter: presenter),
          ),
        ),
        child: const Text('View all'),
      ),
      child: recent.isEmpty
          ? AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Tap Log to start tracking your weight',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          : AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${recent.last.weightKg.toStringAsFixed(1)} kg',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (delta != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (delta < 0
                                    ? primary
                                    : theme.colorScheme.onSurfaceVariant)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: delta < 0
                                  ? primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (recent.length >= 2) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 72,
                      child: CustomPaint(
                        size: const Size(double.infinity, 72),
                        painter: _WeightTrendPainter(
                          entries: recent,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...recent.reversed.take(3).map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Text(
                                '${entry.weightKg.toStringAsFixed(1)} kg',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(entry.loggedAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => presenter.deleteWeight(entry.id),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}

// ─── Weight Trend Painter ─────────────────────────────────────────────────────

class _WeightTrendPainter extends CustomPainter {
  final List<WeightEntry> entries;
  final Color color;

  const _WeightTrendPainter({required this.entries, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;

    final weights = entries.map((e) => e.weightKg).toList();
    final minW = weights.reduce(math.min);
    final maxW = weights.reduce(math.max);
    final range = (maxW - minW).clamp(0.5, double.infinity);
    final pad = range * 0.3;
    final lo = minW - pad;
    final hi = maxW + pad;

    double toY(double kg) => size.height * (1 - (kg - lo) / (hi - lo));

    final points = List.generate(entries.length, (i) {
      final x = size.width * i / (entries.length - 1);
      return Offset(x, toY(entries[i].weightKg));
    });

    final areaPath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      areaPath.lineTo(points[i].dx, points[i].dy);
    }
    areaPath
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final dotPaint = Paint()..color = color;
    for (final pt in [points.first, points.last]) {
      canvas.drawCircle(pt, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WeightTrendPainter old) =>
      old.entries != entries || old.color != color;
}

// ─── Day Card ─────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final DailyNutritionLog log;
  final int goalCalories;

  static final _dateFmt = DateFormat('EEE, MMM d');
  static final _calFmt = NumberFormat('#,###');

  const _DayCard({required this.log, required this.goalCalories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final cal = log.totalCalories;
    final goalMet = goalCalories > 0 && cal >= goalCalories;
    final isOver = goalCalories > 0 && cal > goalCalories * 1.2;
    final ratio =
        goalCalories > 0 ? (cal / goalCalories).clamp(0.0, 1.5) : 0.0;
    final pct =
        goalCalories > 0 ? '${((cal / goalCalories) * 100).round()}%' : null;
    final entryCount = log.allEntries.length;

    final barColor = isOver
        ? theme.colorScheme.error
        : goalMet
            ? primary
            : primary.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateFmt.format(DateTime.parse(log.date)),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_calFmt.format(cal)} kcal',
                      style: TextStyle(
                        color: goalMet ? primary : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isOver)
                      AppBadge(
                          text: pct ?? 'Over', color: theme.colorScheme.error)
                    else if (goalMet)
                      AppBadge(text: 'Goal met', color: primary)
                    else
                      AppBadge(
                        text: pct ?? 'Logged',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            if (log.hasMacros) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  _MacroPill(
                    label: 'P',
                    grams: log.totalProtein.round(),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  _MacroPill(
                    label: 'C',
                    grams: log.totalCarbs.round(),
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  _MacroPill(
                    label: 'F',
                    grams: log.totalFat.round(),
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final int grams;
  final Color color;
  const _MacroPill(
      {required this.label, required this.grams, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label ${grams}g',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Measurement Section ──────────────────────────────────────────────────────

class _MeasurementSection extends StatelessWidget {
  final NutritionPresenter presenter;
  const _MeasurementSection({required this.presenter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final latest = presenter.latestMeasurement;
    final bf = presenter.estimatedBodyFatPercent;
    final trend = presenter.waistTrendDirection;

    return AppSection(
      title: 'Body Measurements',
      trailing: FilledButton.tonal(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeasurementLogScreen(presenter: presenter),
          ),
        ),
        child: const Text('View all'),
      ),
      child: latest == null
          ? AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Log a measurement to track body composition',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          : AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (latest.waistCm != null)
                        Text(
                          'Waist ${presenter.formatMeasurement(latest.waistCm!)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const Spacer(),
                      if (bf != null)
                        _MeasChip(
                          label: '~${bf.toStringAsFixed(0)} % BF',
                          color: primary,
                        ),
                    ],
                  ),
                  if (trend != MeasurementTrendDirection.insufficient) ...[
                    const SizedBox(height: 6),
                    _MeasChip(
                      label: _trendLabel(trend),
                      color: trend == MeasurementTrendDirection.down
                          ? primary
                          : trend == MeasurementTrendDirection.up
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Logged ${DateFormat('MMM d, yyyy').format(latest.loggedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _trendLabel(MeasurementTrendDirection d) => switch (d) {
        MeasurementTrendDirection.down => 'Waist trending down ↓',
        MeasurementTrendDirection.up => 'Waist trending up ↑',
        MeasurementTrendDirection.stable => 'Waist stable →',
        MeasurementTrendDirection.insufficient => '',
      };
}

class _MeasChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MeasChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
