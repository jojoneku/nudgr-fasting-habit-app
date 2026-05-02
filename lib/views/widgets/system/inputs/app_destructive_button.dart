import 'package:flutter/material.dart';

/// Full-width destructive FilledButton using colorScheme.error.
class AppDestructiveButton extends StatelessWidget {
  const AppDestructiveButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
    this.isLoading = false,
    this.fullWidth = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final bool isLoading;
  final bool fullWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onError,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                Icon(leading, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.error,
        foregroundColor: theme.colorScheme.onError,
        minimumSize: Size(fullWidth ? double.infinity : 0, height),
        fixedSize: Size.fromHeight(height),
      ),
      child: child,
    );
  }
}
