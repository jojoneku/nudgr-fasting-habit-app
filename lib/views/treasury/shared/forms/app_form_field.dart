import 'package:flutter/material.dart';

/// Labeled field wrapper for the Nudgr Treasury form kit: an UPPERCASE,
/// letter-tracked, muted label above [child] (the input), with an optional
/// [hint] line below and an optional [trailing] widget on the label row.
///
/// The wrapped input should render *without* its own label so this is the only
/// label shown. Theme-aware — reads only `Theme.of(context)` tokens.
class AppFormField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  final Widget? trailing;

  const AppFormField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style:
                theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
