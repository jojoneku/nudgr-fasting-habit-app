import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../presenters/ai_coach_presenter.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../../../utils/hub_coach.dart';

/// The Hub's adaptive coaching line: one sentence from the AI coach (cached or
/// fallback, never blocking) with a mood tint derived from current state.
class HubCoachLine extends StatefulWidget {
  const HubCoachLine({
    super.key,
    this.aiCoach,
    this.nutrition,
    this.treasury,
  });

  final AiCoachPresenter? aiCoach;
  final NutritionPresenter? nutrition;
  final TreasuryDashboardPresenter? treasury;

  @override
  State<HubCoachLine> createState() => _HubCoachLineState();
}

class _HubCoachLineState extends State<HubCoachLine> {
  static const _neutralFallback =
      'Small, consistent choices are how you level up.';

  @override
  void initState() {
    super.initState();
    // Generate off the build path — the line shows the cached/fallback text
    // immediately and updates when (if) generation completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.aiCoach?.refreshHubNudge();
    });
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      if (widget.aiCoach != null) widget.aiCoach!,
      if (widget.nutrition != null) widget.nutrition!,
      if (widget.treasury != null) widget.treasury!,
    ];
    if (listenables.isEmpty) return _line(context);
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _line(context),
    );
  }

  Widget _line(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = context.appColors;

    final n = widget.nutrition;
    final mood = resolveHubCoachMood(
      overGoal:
          n != null && n.todayCalories > 0 && n.todayCalories > n.effectiveGoal,
      billImminent: widget.treasury?.hasBillImminent == true,
      goalsMet: n?.isCalorieGoalMet == true,
    );

    final (tint, icon) = switch (mood) {
      HubCoachMood.urgent => (cs.error, Icons.warning_amber_rounded),
      HubCoachMood.positive => (c.move, Icons.auto_awesome),
      HubCoachMood.neutral => (c.fast, Icons.tips_and_updates_outlined),
    };

    final text = widget.aiCoach?.hubNudge ?? _neutralFallback;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
