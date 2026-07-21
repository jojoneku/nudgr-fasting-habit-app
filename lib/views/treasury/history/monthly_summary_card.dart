import 'package:flutter/material.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// A monthly summary as a compact card (Nudgr history redesign,
/// `Nutrition Focus Treasury.dc.html` Frame 5). Closed months read as a single
/// row — month + inflow/outflow on the left, net + saved% on the right. The
/// live current month shows IN / OUT / SAVED tiles instead. The "LIVE" pill
/// lives in the section header, so it isn't repeated on the card.
class MonthlySummaryCard extends StatelessWidget {
  final MonthlySummary summary;
  final bool isLive;
  final VoidCallback? onTap;

  const MonthlySummaryCard({
    super.key,
    required this.summary,
    this.isLive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.filled,
      onTap: onTap,
      child: isLive ? _buildLive(context) : _buildClosed(context),
    );
  }

  // Closed month: month + inflow/outflow (left), net + saved% (right).
  Widget _buildClosed(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final netPositive = summary.netSavings >= 0;
    final netColor = netPositive ? cs.primary : cs.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                monthLabel(summary.month),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '+${formatPesoCompact(summary.totalInflow)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.tertiary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '−${formatPesoCompact(summary.totalOutflow)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.error, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${netPositive ? '+' : '−'}${formatPesoCompact(summary.netSavings.abs())}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: netColor, fontWeight: FontWeight.w800),
            ),
            if (summary.savingsRate != null) ...[
              const SizedBox(height: 2),
              Text(
                '${(summary.savingsRate! * 100).round()}% saved',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // Live current month: month + "in progress", then IN / OUT / SAVED tiles.
  Widget _buildLive(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final savedPct = summary.savingsRate != null
        ? '${(summary.savingsRate! * 100).round()}%'
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                monthLabel(summary.month),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              'in progress',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MiniTile(
                label: 'IN',
                value: formatPesoCompact(summary.totalInflow),
                color: cs.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniTile(
                label: 'OUT',
                value: formatPesoCompact(summary.totalOutflow),
                color: cs.error,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniTile(
                label: 'SAVED',
                value: savedPct,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One IN / OUT / SAVED tile inside the live current-month card.
class _MiniTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: BoxDecoration(
        // A soft tint of the metric's own color (not a near-black fill), so the
        // tiles read as light, colored chips on the card.
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
