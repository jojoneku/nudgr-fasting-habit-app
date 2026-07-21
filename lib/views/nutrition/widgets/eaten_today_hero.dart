import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../presenters/nutrition_presenter.dart';

/// "EATEN TODAY" hero card for the redesigned Nutrition screen (Nudgr redesign).
///
/// Restyles the former calorie/macro stat card into the reference's gradient
/// hero: big eaten kcal, calories-left-of-goal in the domain accent, a calorie
/// progress bar, and Protein/Carbs/Fat mini-bar columns. Data + behavior are
/// unchanged — tapping still opens the breakdown sheet via [onTap]. All colors
/// come from the theme; no hardcoded per-mode tokens.
class EatenTodayHero extends StatelessWidget {
  final NutritionPresenter presenter;
  final VoidCallback onTap;
  const EatenTodayHero({
    super.key,
    required this.presenter,
    required this.onTap,
  });

  static final _comma = NumberFormat.decimalPattern();

  @override
  Widget build(BuildContext context) {
    final p = presenter;
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final barColor = p.isOverGoal ? cs.error : accent;
    final left = p.remainingCalories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  cs.surfaceContainerHigh,
                  cs.surfaceContainerLow,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Eaten ───────────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EATEN TODAY',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _comma.format(p.todayCalories),
                                    style: TextStyle(
                                      color: cs.onSurface,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w800,
                                      height: 0.9,
                                      letterSpacing: -1.2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'kcal',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ── Left of goal ────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _comma.format(left),
                          style: TextStyle(
                            color: p.isOverGoal ? cs.error : accent,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          p.isOverGoal
                              ? 'over ${_comma.format(p.effectiveGoal)}'
                              : 'left of ${_comma.format(p.effectiveGoal)}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Calorie bar ─────────────────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: p.netCalorieProgress.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: 13),
                // ── Macros ──────────────────────────────────────────────────
                Row(
                  children: [
                    _MacroColumn(
                      label: 'Protein',
                      grams: p.todayProtein,
                      progress: p.proteinProgress,
                      color: accent,
                    ),
                    const SizedBox(width: 10),
                    _MacroColumn(
                      label: 'Carbs',
                      grams: p.todayCarbs,
                      progress: p.carbsProgress,
                      color: context.appColors.gold,
                    ),
                    const SizedBox(width: 10),
                    _MacroColumn(
                      label: 'Fat',
                      grams: p.todayFat,
                      progress: p.fatProgress,
                      color: cs.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroColumn extends StatelessWidget {
  final String label;
  final double grams;
  final double progress;
  final Color color;
  const _MacroColumn({
    required this.label,
    required this.grams,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '${grams.round()}',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'g',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
