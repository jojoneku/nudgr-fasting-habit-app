import 'package:flutter/material.dart';

/// SnackBar helper — success, error, action, and plain variants.
class AppToast {
  static void show(BuildContext context, String message) {
    _show(context, message: message);
  }

  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      color: Theme.of(context).colorScheme.tertiary,
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      color: Theme.of(context).colorScheme.error,
    );
  }

  static void action(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    _show(context,
        message: message, actionLabel: actionLabel, onAction: onAction);
  }

  static void _show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? color,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = cs.surfaceContainerHigh;
    final bg = color != null
        ? Color.alphaBlend(color.withValues(alpha: 0.15), base)
        : base;
    final fg = color ?? cs.onSurface;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: (color ?? cs.outline).withValues(alpha: 0.25),
          ),
        ),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fg),
              ),
            ),
          ],
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }
}
