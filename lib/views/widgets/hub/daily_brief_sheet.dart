import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_colors.dart';
import '../../../models/insight.dart';
import '../../../presenters/insights_presenter.dart';
import '../../../utils/date_utils.dart';

/// "System Analysis" sheet: today's daily brief as a hero block plus the recent
/// event-triggered directives (nudges). Draggable bottom sheet mirroring the
/// AI chat sheet's conventions (rounded top, drag handle, theme-aware surface).
class DailyBriefSheet extends StatelessWidget {
  const DailyBriefSheet({super.key, required this.insights});

  final InsightsPresenter insights;

  /// Opens the sheet. Usage:
  /// ```dart
  /// DailyBriefSheet.show(context, insights: insightsPresenter);
  /// ```
  static Future<void> show(
    BuildContext context, {
    required InsightsPresenter insights,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DailyBriefSheet(insights: insights),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const _DragHandle(),
            const _SheetHeader(),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: ListenableBuilder(
                listenable: insights,
                builder: (context, _) {
                  final brief = insights.dailyBrief;
                  final nudges = insights.recent
                      .where((i) => i.kind == InsightKind.nudge)
                      .toList();

                  if (brief == null && nudges.isEmpty) {
                    return const _EmptyState();
                  }

                  return TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    tween: Tween(begin: 0, end: 1),
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: child,
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        if (brief != null) _BriefHero(brief: brief),
                        if (nudges.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const _SectionLabel('Recent Directives'),
                          const SizedBox(height: 4),
                          for (final n in nudges) _DirectiveRow(insight: n),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: cs.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Text(
            'System Analysis',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }
}

class _BriefHero extends StatelessWidget {
  const _BriefHero({required this.brief});

  final Insight brief;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dateLabel = DateFormat('EEEE, MMMM d').format(brief.createdAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Daily Brief',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                dateLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            brief.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _DirectiveRow extends StatelessWidget {
  const _DirectiveRow({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = context.appColors;

    final (tint, icon) = switch (insight.mood) {
      InsightMood.urgent => (cs.error, Icons.warning_amber_rounded),
      InsightMood.positive => (c.move, Icons.auto_awesome),
      InsightMood.neutral => (c.fast, Icons.tips_and_updates_outlined),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                insight.text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                relativeDayLabel(insight.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar_outlined, color: cs.onSurfaceVariant, size: 40),
            const SizedBox(height: 16),
            Text(
              'No analysis yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The System is observing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
