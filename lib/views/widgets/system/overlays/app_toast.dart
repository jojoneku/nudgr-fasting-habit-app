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
    _show(context, message: message, actionLabel: actionLabel, onAction: onAction);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color != null
            ? color.withValues(alpha: 0.12)
            : null,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: color ?? theme.colorScheme.onSurface, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color ?? theme.colorScheme.onSurface),
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
