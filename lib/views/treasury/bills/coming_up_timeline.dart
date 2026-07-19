import 'package:flutter/material.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The unified "Coming up" timeline — a dot/line list of the presenter's
/// merged [ComingUpItem]s (bills, receivables, budgeted, installments). Renders
/// nothing when the list is empty. Dumb widget: it's fed the ready-made list and
/// routes taps back via [onTap].
class ComingUpTimeline extends StatelessWidget {
  final List<ComingUpItem> items;
  final void Function(ComingUpItem)? onTap;

  const ComingUpTimeline({super.key, required this.items, this.onTap});

  Color _dotColor(BuildContext context, ComingUpKind kind) {
    final c = context.appColors;
    return switch (kind) {
      ComingUpKind.bill => c.bills,
      ComingUpKind.receivable => c.success,
      ComingUpKind.budgeted => c.gold,
      ComingUpKind.installment => c.purple,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < items.length; i++)
          _TimelineRow(
            item: items[i],
            dotColor: _dotColor(context, items[i].kind),
            isLast: i == items.length - 1,
            onTap: onTap == null ? null : () => onTap!(items[i]),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final ComingUpItem item;
  final Color dotColor;
  final bool isLast;
  final VoidCallback? onTap;

  const _TimelineRow({
    required this.item,
    required this.dotColor,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amountColor =
        item.isInflow ? context.appColors.success : cs.onSurface;
    final amountText =
        '${item.isInflow ? '+' : ''}${formatPeso(item.amount)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  _Dot(color: dotColor, inflow: item.isInflow),
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: isLast ? 2 : 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            item.dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: item.isInflow
                                  ? context.appColors.success
                                      .withValues(alpha: 0.9)
                                  : cs.onSurfaceVariant,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      amountText,
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
}

/// The timeline node: a ringed dot, or a down-arrow for incoming money.
class _Dot extends StatelessWidget {
  final Color color;
  final bool inflow;

  const _Dot({required this.color, required this.inflow});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: inflow
          ? Icon(Icons.arrow_downward_rounded, size: 10, color: color)
          : Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
    );
  }
}
