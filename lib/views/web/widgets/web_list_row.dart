import 'package:flutter/material.dart';

import '../design/web_breakpoints.dart';
import '../design/web_constants.dart';

/// The 36 px rounded tile at the left of a [WebListRow] — an icon or a
/// two-letter initial on a domain color.
class WebRowTile extends StatelessWidget {
  final Color color;
  final Widget child;
  final double size;

  const WebRowTile({
    super.key,
    required this.color,
    required this.child,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconTheme.merge(
        data: const IconThemeData(size: 18, color: Colors.white),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A 12 px-padded list row: tile, title (14/700) with an optional badge,
/// subtitle (11.5 muted), right-aligned trailing figure, then row actions
/// (a `WebRowMenu`, a Mark paid button). Rows separate with an
/// `outlineVariant` hairline; the last row passes `divider: false`.
///
/// This is the row of the Bills tabs, the Setup account groups and the
/// Dashboard account list.
class WebListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final Widget? trailing;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool selected;
  final bool divider;

  const WebListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.badge,
    this.trailing,
    this.actions = const [],
    this.onTap,
    this.selected = false,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kWebHitTarget),
          padding: const EdgeInsets.all(WebInsets.md),
          decoration: divider
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant),
                  ),
                )
              : null,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: WebInsets.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: WebInsets.sm),
                          badge!,
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: WebInsets.md),
                trailing!,
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(width: WebInsets.xs),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
