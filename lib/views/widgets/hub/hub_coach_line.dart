import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../models/insight.dart';
import '../../../presenters/insights_presenter.dart';
import '../../../presenters/nutrition_presenter.dart';
import '../../../presenters/treasury_dashboard_presenter.dart';
import '../../../utils/hub_coach.dart';
import 'daily_brief_sheet.dart';

/// The Hub's adaptive coaching line: the current System insight (nudge > daily
/// brief > neutral fallback, never blocking) with a mood tint derived from the
/// insight — or, before any insight exists, from current app state. Tapping the
/// line opens the Daily Brief sheet and clears the unread badge.
class HubCoachLine extends StatefulWidget {
  const HubCoachLine({
    super.key,
    this.insights,
    this.nutrition,
    this.treasury,
  });

  final InsightsPresenter? insights;
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
    // Kick the Insight Engine off the build path — the line shows the
    // cached/fallback text immediately and updates when generation completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final insights = widget.insights;
      if (insights == null) return;
      // Fire and forget — both are cheap (hash-gated / once-per-day) and never
      // throw.
      insights.refresh();
      insights.generateDailyBriefIfDue();
    });
  }

  void _openBrief() {
    final insights = widget.insights;
    if (insights == null) return;
    DailyBriefSheet.show(context, insights: insights);
    insights.markRead();
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      if (widget.insights != null) widget.insights!,
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

    final insights = widget.insights;
    final current = insights?.current;

    // Prefer the insight's own mood; fall back to state-derived mood when no
    // insight has been generated yet. (Switch mapping only — no logic here.)
    final HubCoachMood mood;
    if (current != null) {
      mood = switch (current.mood) {
        InsightMood.urgent => HubCoachMood.urgent,
        InsightMood.positive => HubCoachMood.positive,
        InsightMood.neutral => HubCoachMood.neutral,
      };
    } else {
      final n = widget.nutrition;
      mood = resolveHubCoachMood(
        overGoal: n != null &&
            n.todayCalories > 0 &&
            n.todayCalories > n.effectiveGoal,
        billImminent: widget.treasury?.hasBillImminent == true,
        goalsMet: n?.isCalorieGoalMet == true,
      );
    }

    final (tint, icon) = switch (mood) {
      HubCoachMood.urgent => (cs.error, Icons.warning_amber_rounded),
      HubCoachMood.positive => (c.move, Icons.auto_awesome),
      HubCoachMood.neutral => (c.fast, Icons.tips_and_updates_outlined),
    };

    final text = current?.text ?? _neutralFallback;
    final hasUnread = insights?.hasUnread == true;
    final tappable = insights != null;

    final content = Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 44),
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
          if (hasUnread) ...[
            const SizedBox(width: 10),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );

    if (!tappable) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openBrief,
        borderRadius: BorderRadius.circular(14),
        child: content,
      ),
    );
  }
}
