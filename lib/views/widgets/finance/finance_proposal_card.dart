import 'package:flutter/material.dart';

import '../../../presenters/finance_tool_executor.dart';

/// The confirm card for a change Nudgy proposed.
///
/// Nothing has been written when this renders. The proposal exists only as a
/// description until the user presses Add, which is the whole safety property
/// of the tool-calling agent — see [FinanceProposalHost].
class FinanceProposalCard extends StatefulWidget {
  const FinanceProposalCard({
    super.key,
    required this.host,
    required this.action,
  });

  final FinanceProposalHost host;
  final PendingFinanceAction action;

  @override
  State<FinanceProposalCard> createState() => _FinanceProposalCardState();
}

class _FinanceProposalCardState extends State<FinanceProposalCard> {
  /// Recurrence scope. Starts narrow, always: widening it writes into months
  /// the user is not looking at, and a default that does that silently is how
  /// a chat agent quietly rearranges a year of someone's budget.
  bool _applyToFuture = false;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    await widget.host.confirm(applyToFuture: _applyToFuture);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final action = widget.action;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'NUDGY SUGGESTS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          action.title,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final row in action.details)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    row.label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (action.isRecurring) ...[
          const SizedBox(height: 6),
          _ScopeChoice(
            applyToFuture: _applyToFuture,
            onChanged: _busy
                ? null
                : (value) => setState(() => _applyToFuture = value),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : widget.host.decline,
              child: const Text('Not now'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _busy ? null : _confirm,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Add it'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The recurrence-scope control.
///
/// Rendered as two explicit choices rather than a checkbox, because the
/// consequence of the wider one has to be readable at a glance: it writes into
/// months the user is not currently looking at.
class _ScopeChoice extends StatelessWidget {
  const _ScopeChoice({required this.applyToFuture, required this.onChanged});

  final bool applyToFuture;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Apply to',
          style:
              theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ScopeOption(
              label: 'This month',
              selected: !applyToFuture,
              onTap: onChanged == null ? null : () => onChanged!(false),
            ),
            _ScopeOption(
              label: 'Every month ahead',
              selected: applyToFuture,
              onTap: onChanged == null ? null : () => onChanged!(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          // 44px minimum touch target (CLAUDE.md #4).
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
