import 'package:flutter/material.dart';

enum AppButtonVariant { filled, tonal }

/// Full-width M3 button with loading state — no layout jump on load.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leading,
    this.isLoading = false,
    this.fullWidth = true,
    this.height = 52,
    this.variant = AppButtonVariant.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final bool isLoading;
  final bool fullWidth;
  final double height;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(fullWidth ? double.infinity : 0, height)),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(height)),
    );

    Widget child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
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

    return switch (variant) {
      AppButtonVariant.filled => FilledButton(
          onPressed: isLoading ? null : onPressed,
          style: style,
          child: child,
        ),
      AppButtonVariant.tonal => FilledButton.tonal(
          onPressed: isLoading ? null : onPressed,
          style: style,
          child: child,
        ),
    };
  }
}
