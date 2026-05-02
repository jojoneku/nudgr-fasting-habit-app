import 'package:flutter/material.dart';

/// Full-width M3 FilledButton with loading state — no layout jump on load.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
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
    Widget child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
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

    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(fullWidth ? double.infinity : 0, height),
        fixedSize: Size.fromHeight(height),
      ),
      child: child,
    );

    return button;
  }
}
