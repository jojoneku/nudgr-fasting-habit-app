import 'package:flutter/material.dart';

/// Renders [label] on its own line **above** [child] (per the Nudgr reference),
/// instead of Flutter's floating inline `labelText`. Wrap any bare field
/// (`TextField`/`TextFormField`) whose decoration would otherwise carry a
/// `labelText`. Matches [AppTextField]'s above-label styling so every form reads
/// consistently.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
