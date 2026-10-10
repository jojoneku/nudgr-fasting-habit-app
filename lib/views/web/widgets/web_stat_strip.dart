import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app_colors.dart';
import '../../../utils/app_radii.dart';
import '../design/web_breakpoints.dart';
import '../design/web_constants.dart';
import 'web_number.dart';

/// Tone of a [WebStat] value — a theme color, never a hardcoded one.
enum WebStatTone { neutral, success, warning, danger, info }

/// One figure of a [WebStatStrip]: a small label, a 20/800 value and an
/// optional caption under it.
class WebStat {
  final String label;
  final String value;
  final String? caption;
  final WebStatTone tone;

  /// Stable key for parity tests.
  final Key? key;

  const WebStat({
    required this.label,
    required this.value,
    this.caption,
    this.tone = WebStatTone.neutral,
    this.key,
  });
}

/// An even row of stat cells — the one KPI strip for History (5), Setup (4),
/// Bills' side column and the Dashboard outlook. Replaces the four hand-rolled
/// grids the pre-v2 pages carried.
///
/// Every cell is the same width. The strip wraps only when a cell would drop
/// under [minItemWidth], and when it wraps it never leaves one orphan on the
/// last row: a five-stat strip is 5 across, or 3 + 2, never 4 + 1 (see
/// [columnsFor]).
///
/// [onCard] renders the cells as wells on the page background (inside a
/// card, as History does); the default renders them as small cards on the
/// page (as Setup does).
class WebStatStrip extends StatelessWidget {
  final List<WebStat> items;
  final double minItemWidth;
  final double gap;
  final bool onCard;

  const WebStatStrip({
    super.key,
    required this.items,
    this.minItemWidth = kWebTabletMinColumn,
    this.gap = WebInsets.md,
    this.onCard = false,
  });

  /// Columns for [count] cells in [width]: as many as fit at [minItemWidth],
  /// capped at [count], minus one when that would strand a single cell on
  /// the last row.
  static int columnsFor({
    required int count,
    required double width,
    double minItemWidth = kWebTabletMinColumn,
    double gap = WebInsets.md,
  }) {
    if (count <= 0) return 0;
    final fit = ((width + gap) / (minItemWidth + gap)).floor();
    var columns = math.max(1, math.min(count, fit));
    if (columns > 1 && count % columns == 1) columns -= 1;
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = columnsFor(
          count: items.length,
          width: width,
          minItemWidth: minItemWidth,
          gap: gap,
        );
        final itemWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: WebStatCell(key: item.key, stat: item, onCard: onCard),
              ),
          ],
        );
      },
    );
  }
}

/// One cell of a [WebStatStrip]. Public so a page can place a single stat in
/// a side column with the same look.
class WebStatCell extends StatelessWidget {
  final WebStat stat;
  final bool onCard;

  const WebStatCell({super.key, required this.stat, this.onCard = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final warning = context.appColors.bills;
    final valueColor = switch (stat.tone) {
      WebStatTone.neutral => cs.onSurface,
      WebStatTone.success => cs.tertiary,
      WebStatTone.warning => warning,
      WebStatTone.danger => cs.error,
      WebStatTone.info => cs.primary,
    };
    final small = theme.textTheme.bodySmall?.copyWith(
      color: context.appColors.textMuted,
      fontSize: 11.5,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: onCard ? theme.scaffoldBackgroundColor : cs.surfaceContainerLow,
        borderRadius: AppRadii.mdBorder,
        border: onCard
            ? null
            : Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: WebInsets.xs),
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: webNumericStyle(
              theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
              color: valueColor,
            ),
          ),
          if (stat.caption != null) ...[
            const SizedBox(height: WebInsets.xs),
            Text(
              stat.caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
          ],
        ],
      ),
    );
  }
}
