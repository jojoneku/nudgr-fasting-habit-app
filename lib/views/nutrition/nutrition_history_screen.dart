import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_colors.dart';
import '../../models/daily_nutrition_log.dart';
import '../../models/weight_entry.dart';
import '../../presenters/nutrition_presenter.dart';
import '../widgets/system/system.dart';
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
        if (history.isNotEmpty) ...[
          _SummaryRow(
            last7: _last7,
            goalCalories: goal,
            logStreak: presenter.logStreak,
          ),
          const SizedBox(height: 20),
          _CalorieTrendSection(
            days: _last14Chrono,
            goalCalories: goal,
            todayKey: _today,
          ),
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
        if (history.isNotEmpty)
          AppSection(
            title: 'Recent Days',
            child: Column(
              children: history
                  .take(14)
                  .map((log) => _DayCard(log: log, goalCalories: goal))
                  .toList(),
            ),
          )
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

// ─── Summary Row ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final List<DailyNutritionLog> last7;
  final int goalCalories;
  final int logStreak;
  const _SummaryRow({
    required this.last7,
    required this.goalCalories,
    required this.logStreak,
  });

  int get _avgCalories {
    if (last7.isEmpty) return 0;
    final total = last7.fold(0, (s, l) => s + l.totalCalories);
    return (total / last7.length).round();
  }

  int get _goalDays => goalCalories > 0
      ? last7.where((l) => l.totalCalories >= goalCalories).length
      : 0;

  @override
  Widget build(BuildContext context) {
    final n = last7.length;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.local_fire_department_outlined,
            value: NumberFormat('#,###').format(_avgCalories),
            unit: 'kcal',
            label: 'Daily avg',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.emoji_events_outlined,
            value: '$_goalDays/$n',
            unit: 'days',
            label: 'Goal met',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.whatshot_outlined,
            value: '$logStreak',
            unit: logStreak == 1 ? 'day' : 'days',
            label: 'Log streak',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = context.appColors.gold;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: gold),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              unit,
              style: theme.textTheme.labelSmall?.copyWith(
                color: gold,
                fontWeight: FontWeight.w600,
                fontSize: 10,
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
          ],
        ),
      ),
    );
  }
}

// ─── Calorie Trend ────────────────────────────────────────────────────────────

class _CalorieTrendSection extends StatelessWidget {
  final List<DailyNutritionLog> days; // chronological
  final int goalCalories;
  final String todayKey;
  const _CalorieTrendSection({
    required this.days,
    required this.goalCalories,
    required this.todayKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = context.appColors.gold;

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
                  barColor: gold,
                  errorColor: theme.colorScheme.error,
                  todayKey: todayKey,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Day labels
            Row(
              children: days.map((log) {
                final dt = DateTime.tryParse(log.date) ?? DateTime.now();
                final isToday = log.date == todayKey;
                return Expanded(
                  child: Text(
                    DateFormat('E').format(dt).substring(0, 1),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          isToday ? gold : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 10,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Legend
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendItem(color: gold, label: 'Goal met'),
                _LegendItem(
                    color: gold.withValues(alpha: 0.35), label: 'Under'),
                _LegendItem(color: theme.colorScheme.error, label: 'Over 120%'),
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
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
  final String todayKey;

  const _CalorieTrendPainter({
    required this.days,
    required this.goalCalories,
    required this.barColor,
    required this.errorColor,
    required this.todayKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final maxCal = math.max(
      goalCalories > 0 ? goalCalories * 1.25 : 1.0,
      days.fold(0.0, (m, d) => math.max(m, d.totalCalories.toDouble())),
    );
    if (maxCal == 0) return;

    final slotW = size.width / days.length;
    final barW = (slotW * 0.52).clamp(4.0, 28.0);

    // Goal line — dashed
    if (goalCalories > 0) {
      final goalY = size.height * (1 - goalCalories / maxCal);
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

    for (int i = 0; i < days.length; i++) {
      final cal = days[i].totalCalories.toDouble();
      if (cal <= 0) continue;

      final barH = (size.height * (cal / maxCal)).clamp(2.0, size.height);
      final centerX = slotW * i + slotW / 2;
      final left = centerX - barW / 2;
      final top = size.height - barH;

      final isGoalMet = goalCalories > 0 && cal >= goalCalories;
      final isOver = goalCalories > 0 && cal > goalCalories * 1.2;
      final isToday = days[i].date == todayKey;

      final color = isOver ? errorColor : barColor;
      final topAlpha = isGoalMet ? 0.95 : 0.32;
      final botAlpha = isGoalMet ? 0.25 : 0.08;

      final rect = Rect.fromLTWH(left, top, barW, barH);
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );

      // Gradient fill
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: topAlpha),
          color.withValues(alpha: botAlpha),
        ],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = shader);

      // Today: subtle bright outline
      if (isToday) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: 0.7)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }

      // Goal-met dot on top
      if (isGoalMet) {
        canvas.drawCircle(
          Offset(centerX, top - 4),
          2.5,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CalorieTrendPainter old) =>
      old.days != days ||
      old.goalCalories != goalCalories ||
      old.todayKey != todayKey;
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
    final gold = context.appColors.gold;
    final protein = _avgProtein;
    final carbs = _avgCarbs;
    final fat = _avgFat;
    final total = protein + carbs + fat;

    final proteinColor = theme.colorScheme.primary;
    final carbsColor = gold;
    final fatColor = theme.colorScheme.error;

    return AppSection(
      title: 'Macro Averages',
      hint: '${_withMacros.length}d avg',
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Proportional macro bar
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
            // Per-macro tiles
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
    final gold = context.appColors.gold;
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
                  // Latest weight + delta
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
                                    ? gold
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
                                  ? gold
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
                          color: gold,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Recent entries list
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

    // Area fill under line
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

    // Line
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

    // Dots — only first and last
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
    final gold = context.appColors.gold;
    final cal = log.totalCalories;
    final goalMet = goalCalories > 0 && cal >= goalCalories;
    final isOver = goalCalories > 0 && cal > goalCalories * 1.2;
    final ratio = goalCalories > 0 ? (cal / goalCalories).clamp(0.0, 1.5) : 0.0;
    final pct =
        goalCalories > 0 ? '${((cal / goalCalories) * 100).round()}%' : null;
    final entryCount = log.allEntries.length;

    final barColor = isOver
        ? theme.colorScheme.error
        : goalMet
            ? gold
            : gold.withValues(alpha: 0.35);

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
                        color: goalMet ? gold : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isOver)
                      AppBadge(
                          text: pct ?? 'Over', color: theme.colorScheme.error)
                    else if (goalMet)
                      AppBadge(text: 'Goal met', color: gold)
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
            // Calorie progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            // Macro pills — only if available
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
                    color: gold,
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
