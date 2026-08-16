import 'package:flutter/material.dart';
import '../../../../utils/app_radii.dart';
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
    this.cardColor,
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

  /// Fills the row as its own card — a rounded surface with the house hairline
  /// and a gap to the next row — instead of letting it sit transparent on the
  /// page. Pass `colorScheme.surfaceContainerLow` for the standard
  /// lighter-grey-on-screen card; null keeps the flat, backgroundless row.
  ///
  /// A [Material] rather than a plain box: it is what the tile's ink splash
  /// paints on, and an opaque box would swallow the tap feedback. It also sits
  /// *inside* the swipe-to-delete [Dismissible], so a dismissed row collapses
  /// card and gap together rather than leaving an empty shell behind.
  final Color? cardColor;

  /// Vertical gap to the next card. Only applied when [cardColor] is set.
  static const double _cardGap = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget tile = ListTile(
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

    if (cardColor != null) {
      tile = Padding(
        padding: const EdgeInsets.only(bottom: _cardGap),
        child: Material(
          color: cardColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.lgBorder,
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: tile,
        ),
      );
    }

    if (onDelete != null) {
      return Dismissible(
        key: key ?? UniqueKey(),
        direction: DismissDirection.endToStart,
        background: Padding(
          // Match the card's own gap so the reveal stops at the card's edge
          // instead of bleeding into the next row's space.
          padding: cardColor != null
              ? const EdgeInsets.only(bottom: _cardGap)
              : EdgeInsets.zero,
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.error,
              borderRadius: cardColor != null ? AppRadii.lgBorder : null,
            ),
            child: Icon(Icons.delete_outline, color: theme.colorScheme.onError),
          ),
        ),
        confirmDismiss: (_) => onDelete!(),
        child: tile,
      );
    }

    return tile;
  }
}
