import 'package:flutter/material.dart';

/// Small layout pieces shared by the Bills tab bodies: group labels, a titled
/// section, and the receivables Reorder toggle. Moved out of
/// `bills_receivables_view.dart` (Plan 071 Phase 6).

/// A plain bold label, e.g. "Due soon".
class BillsSectionLabel extends StatelessWidget {
  final String text;

  const BillsSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// A list section: an optional bold [title] with its [count], an optional
/// [trailing] control, then its cards — or [emptyMessage] when there are none.
class BillsSection extends StatelessWidget {
  final String? title;
  final int count;
  final String emptyMessage;
  final List<Widget> children;

  /// Optional control pinned to the right of the header row (e.g. the
  /// receivables Reorder toggle).
  final Widget? trailing;

  const BillsSection({
    super.key,
    this.title,
    this.count = 0,
    required this.emptyMessage,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final heading = title;
    final hasHeader = heading != null || trailing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Row(
              children: [
                if (heading != null) BillsSectionLabel(heading),
                if (heading != null && count > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
            child: Text(
              emptyMessage,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// Header control that puts the Receivables list into drag-to-rearrange mode.
/// While active it also offers "Auto", which throws the hand-set arrangement away
/// and returns the list to its expected-date order — shown only when there is an
/// arrangement to throw away.
class ReorderToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;
  final VoidCallback? onReset;

  const ReorderToggle({
    super.key,
    required this.active,
    required this.onToggle,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active && onReset != null)
          TextButton(
            onPressed: onReset,
            style: style.copyWith(
              foregroundColor: WidgetStatePropertyAll(cs.onSurfaceVariant),
            ),
            child: const Text('Auto'),
          ),
        TextButton.icon(
          onPressed: onToggle,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(cs.primary),
          ),
          icon: Icon(active ? Icons.check_rounded : Icons.swap_vert_rounded,
              size: 17),
          label: Text(active ? 'Done' : 'Reorder'),
        ),
      ],
    );
  }
}
