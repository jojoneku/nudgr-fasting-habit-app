import 'package:flutter/material.dart';

/// SnackBar helper — success, error, action, and plain variants.
///
/// All variants share one floating, rounded, single-at-a-time presentation so
/// toasts read consistently across the app. Pass [duration] to override the
/// default 4s dwell (e.g. a shorter confirmation or a longer actionable error).
class AppToast {
  static void show(BuildContext context, String message, {Duration? duration}) {
    _show(context, message: message, duration: duration);
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      color: Theme.of(context).colorScheme.tertiary,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      color: Theme.of(context).colorScheme.error,
      duration: duration,
    );
  }

  static void action(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    IconData? icon,
    Color? color,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      icon: icon,
      color: color,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? color,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = cs.surfaceContainerHigh;
    final bg = color != null
        ? Color.alphaBlend(color.withValues(alpha: 0.15), base)
        : base;
    final fg = color ?? cs.onSurface;

    final messenger = ScaffoldMessenger.of(context);
    // Replace any in-flight snackbar instead of queueing — repeated deletes
    // shouldn't pile up.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bg,
        elevation: 0,
        duration: duration ?? const Duration(seconds: 4),
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
