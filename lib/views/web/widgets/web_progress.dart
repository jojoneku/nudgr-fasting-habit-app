import 'package:flutter/material.dart';
import '../design/web_breakpoints.dart';

/// A labeled progress meter: optional label + trailing text above a rounded
/// bar. Turns [danger] (error color) when over threshold. Shared across Budget,
/// Cart, and Dashboard (Plan 050 polish).
class WebProgressBar extends StatelessWidget {
  final double fraction;
  final String? label;
  final String? trailing;
  final bool danger;
  final double height;

  const WebProgressBar({
    super.key,
    required this.fraction,
    this.label,
    this.trailing,
    this.danger = false,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = danger ? cs.error : cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null || trailing != null) ...[
          Row(
            children: [
              if (label != null)
                Expanded(
                  child: Text(label!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
              if (trailing != null)
                Text(trailing!,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: danger ? cs.error : cs.onSurface,
                        fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: WebInsets.xs),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: height,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
