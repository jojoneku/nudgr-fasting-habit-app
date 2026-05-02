import 'package:flutter/material.dart';
import '../../../../utils/app_spacing.dart';

/// M3 ListTile wrapper with consistent padding and optional swipe-to-delete.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.deleteConfirmLabel = 'Delete',
    this.dense = false,
    this.selected = false,
    this.insetGrouped = false,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Future<bool> Function()? onDelete;
  final String deleteConfirmLabel;
  final bool dense;
  final bool selected;
  final bool insetGrouped;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tile = ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle != null
          ? DefaultTextStyle.merge(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              child: subtitle!,
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
      dense: dense,
      selected: selected,
      contentPadding: insetGrouped
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs)
          : contentPadding,
    );

    if (onDelete != null) {
      return Dismissible(
        key: key ?? UniqueKey(),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          color: theme.colorScheme.error,
          child: Icon(Icons.delete_outline,
              color: theme.colorScheme.onError),
        ),
        confirmDismiss: (_) => onDelete!(),
        child: tile,
      );
    }

    return tile;
  }
}
