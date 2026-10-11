import 'package:flutter/material.dart';

import '../../../utils/app_radii.dart';
import '../design/web_constants.dart';

/// One entry of a [WebRowMenu].
class WebMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool destructive;

  /// Stable key for parity tests.
  final Key? key;

  const WebMenuItem(
    this.label, {
    required this.onTap,
    this.icon,
    this.destructive = false,
    this.key,
  });
}

/// The row ⋯ button: always visible (not hover-only), a 44 px hit area, and a
/// popup menu of [items] with destructive entries in `colorScheme.error`.
///
/// Replaces the hover-only delete icons the pre-v2 tables used, which were
/// unreachable on a touch screen and invisible until the pointer found them.
class WebRowMenu extends StatelessWidget {
  final List<WebMenuItem> items;
  final String tooltip;

  const WebRowMenu({
    super.key,
    required this.items,
    this.tooltip = 'More actions',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopupMenuButton<int>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      color: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.mdBorder,
        side: BorderSide(color: cs.outline),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
      style: IconButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        hoverColor: cs.surfaceContainerHigh,
        minimumSize: const Size(kWebHitTarget, kWebHitTarget),
        maximumSize: const Size(kWebHitTarget, kWebHitTarget),
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
      ),
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            key: items[i].key,
            value: i,
            height: 40,
            child: _MenuRow(item: items[i]),
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final WebMenuItem item;

  const _MenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = item.destructive ? cs.error : cs.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.icon != null) ...[
          Icon(item.icon, size: 16, color: fg),
          const SizedBox(width: 10),
        ],
        // Flexible + ellipsis: a long label shortens instead of overflowing
        // the popup's 280 px maximum width.
        Flexible(
          child: Text(
            item.label,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fg,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
