import 'package:flutter/material.dart';

/// Full-width M3 OutlinedButton with loading state.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
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
              color: theme.colorScheme.primary,
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

    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(fullWidth ? double.infinity : 0, height),
        fixedSize: Size.fromHeight(height),
      ),
      child: child,
    );
  }
}
