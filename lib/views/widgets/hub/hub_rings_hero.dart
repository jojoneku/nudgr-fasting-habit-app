import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../presenters/activity_presenter.dart';
import '../../../presenters/fasting_presenter.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../presenters/settings_presenter.dart';
import '../../../utils/hub_hero_slots.dart';
import '../../../utils/hub_ring_data.dart';
import '../system/indicators/app_ring_progress.dart';
import 'macro_split_ring.dart';

/// The Hub's three-ring hero. Each slot resolves from the (persisted) hero
/// configuration — default Fast / Food / Move, with slot 1 defaulting to the
/// macro-split ring for users who have never fasted. Pulls from the Fasting,
/// Nutrition, and Activity presenters (Nutrition/Activity nullable-safe: a ring
/// with no source renders its idle track-only state).
class HubRingsHero extends StatelessWidget {
  const HubRingsHero({
    super.key,
    required this.fasting,
    this.nutrition,
    this.activity,
    this.settings,
    this.ringSize = 88,
    this.strokeWidth = 8,
  });

  final FastingPresenter fasting;
  final NutritionPresenter? nutrition;
  final ActivityPresenter? activity;
  final SettingsPresenter? settings;
  final double ringSize;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      fasting,
      if (nutrition != null) nutrition!,
      if (activity != null) activity!,
      if (settings != null) settings!,
    ];
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _buildHero(context),
    );
  }

  Widget _buildHero(BuildContext context) {
    final slots = resolveHeroSlots(
      configured: settings?.heroSlots,
      hasEverFasted: fasting.history.isNotEmpty,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final slot in slots) _slot(context, slot)],
      ),
    );
  }

  Widget _slot(BuildContext context, HubHeroSlot slot) {
    final c = context.appColors;
    final cs = Theme.of(context).colorScheme;

    switch (slot) {
      case HubHeroSlot.fast:
        return _HeroRing(
          data: HubRings.fast(
            isFasting: fasting.isFasting,
            elapsedSeconds: fasting.elapsedSeconds,
            targetSeconds: fasting.targetSeconds,
            isOvertime: fasting.isOvertime,
          ),
          arc: c.fast,
          track: c.fastTrack,
          size: ringSize,
          strokeWidth: strokeWidth,
        );
      case HubHeroSlot.food:
        final n = nutrition;
        final data = n == null
            ? HubRings.food(calories: 0, goal: 0)
            : HubRings.food(calories: n.todayCalories, goal: n.effectiveGoal);
        return _HeroRing(
          data: data,
          arc: data.isOver ? cs.error : c.food,
          track: data.isOver ? cs.error.withValues(alpha: 0.16) : c.foodTrack,
          size: ringSize,
          strokeWidth: strokeWidth,
        );
      case HubHeroSlot.move:
        final a = activity;
        final data = a == null
            ? HubRings.move(steps: 0, goal: 0)
            : HubRings.move(steps: a.todaySteps, goal: a.goals.dailyStepGoal);
        return _HeroRing(
          data: data,
          arc: c.move,
          track: c.moveTrack,
          size: ringSize,
          strokeWidth: strokeWidth,
        );
      case HubHeroSlot.macros:
        final n = nutrition;
        // Macro colors match the nutrition detail screen: protein=blue,
        // carbs=gold, fat=red.
        return MacroSplitRing(
          protein: n?.todayProtein ?? 0,
          carbs: n?.todayCarbs ?? 0,
          fat: n?.todayFat ?? 0,
          proteinColor: cs.primary,
          carbsColor: c.gold,
          fatColor: cs.error,
          trackColor: cs.surfaceContainerHighest,
          size: ringSize,
          strokeWidth: strokeWidth,
        );
    }
  }
}

class _HeroRing extends StatelessWidget {
  const _HeroRing({
    required this.data,
    required this.arc,
    required this.track,
    required this.size,
    required this.strokeWidth,
  });

  final HubRingData data;
  final Color arc;
  final Color track;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppRingProgress(
          value: data.value,
          size: size,
          strokeWidth: strokeWidth,
          gapFraction: 0,
          primaryColor: arc,
          trackColor: track,
          center: _center(theme, arc),
        ),
        const SizedBox(height: 6),
        Text(
          data.caption,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _center(ThemeData theme, Color arc) {
    if (data.isIdle) {
      return Icon(data.glyph, size: 24, color: arc.withValues(alpha: 0.55));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.centerValue ?? '',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, height: 1),
        ),
        if (data.centerLabel != null)
          Text(
            data.centerLabel!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
      ],
    );
  }
}
