import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

/// Single item in an [AppActionSheet].
class AppActionSheetItem<T> {
  const AppActionSheetItem({
    required this.label,
    required this.value,
    this.icon,
    this.isDestructive = false,
    this.isPrimary = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData? icon;
  final bool isDestructive;
  final bool isPrimary;
  final bool enabled;
}

/// HIG-style action sheet — list of discrete choices from the bottom.
/// Returns the selected value or null if dismissed.
class AppActionSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? message,
    required List<AppActionSheetItem<T>> actions,
    AppActionSheetItem<T>? cancel,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (ctx) => _AppActionSheetContent<T>(
        title: title,
        message: message,
        actions: actions,
        cancel: cancel,
      ),
    );
  }
}

class _AppActionSheetContent<T> extends StatelessWidget {
  const _AppActionSheetContent({
    this.title,
    this.message,
    required this.actions,
    this.cancel,
  });

  final String? title;
  final String? message;
  final List<AppActionSheetItem<T>> actions;
  final AppActionSheetItem<T>? cancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: AppRadii.smBorder,
          ),
        ),
        if (title != null || message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.mdGenerous),
            child: Column(
              children: [
                if (title != null)
                  Text(title!,
                      style: AppTextStyles.titleMedium,
                      textAlign: TextAlign.center),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message!,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        ...actions.map((item) => _ActionTile<T>(item: item)),
        Divider(
            height: AppSpacing.md,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        _ActionTile<T>(
          item: cancel ??
              AppActionSheetItem<T>(
                label: 'Cancel',
                value: null as T,
                enabled: true,
              ),
          isCancel: true,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _ActionTile<T> extends StatelessWidget {
  const _ActionTile({required this.item, this.isCancel = false});

  final AppActionSheetItem<T> item;
  final bool isCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.isDestructive
        ? theme.colorScheme.error
        : isCancel
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface;

    return ListTile(
      enabled: item.enabled,
      leading: item.icon != null ? Icon(item.icon, color: color) : null,
      title: Text(
        item.label,
        style: AppTextStyles.bodyLarge.copyWith(
          color: color,
          fontWeight:
              item.isPrimary ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: item.enabled
          ? () => Navigator.of(context).pop(item.value)
          : null,
    );
  }
}
