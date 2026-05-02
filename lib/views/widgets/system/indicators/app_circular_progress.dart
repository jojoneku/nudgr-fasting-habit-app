import 'package:flutter/material.dart';

/// Circular progress indicator with optional centered child.
class AppCircularProgress extends StatelessWidget {
  const AppCircularProgress({
    super.key,
    required this.value,
    this.centerChild,
    this.size = 40,
    this.strokeWidth = 3,
    this.color,
    this.backgroundColor,
  });

  /// Pass -1 or null for indeterminate.
  final double value;
  final Widget? centerChild;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIndeterminate = value < 0;

    Widget indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: isIndeterminate ? null : value.clamp(0.0, 1.0),
        strokeWidth: strokeWidth,
        color: color ?? theme.colorScheme.primary,
        backgroundColor:
            backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
      ),
    );

    if (centerChild != null) {
      indicator = Stack(
        alignment: Alignment.center,
        children: [indicator, centerChild!],
      );
    }

    return indicator;
  }
}
