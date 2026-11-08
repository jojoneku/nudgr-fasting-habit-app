import 'package:flutter/material.dart';

/// A disclosure section: a tappable header ([title], optional [subtitle],
/// chevron) that shows or hides [child]. Used for optional form fields
/// ("More options", installments) so the primary action stays near the top
/// of a sheet on small phones.
///
/// Starts open when [initiallyOpen] is true. The caller passes true whenever a
/// field inside has a value or an error, so a filled or failing field is
/// never hidden. If [initiallyOpen] later flips from false to true (say a
/// validation error appears), the fold opens on its own. It never closes on
/// its own: once the user sees a field, it stays put.
///
/// The header is at least 48 px tall and the body animates in 200 ms. The fold
/// has no fill, only a hairline outline, so it reads the same on a page or
/// inside a sheet in light and dark mode.
class AppFold extends StatefulWidget {
  const AppFold({
    super.key,
    required this.title,
    this.subtitle,
    this.initiallyOpen = false,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final bool initiallyOpen;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 200);
  static const double minHeaderHeight = 48;

  @override
  State<AppFold> createState() => _AppFoldState();
}

class _AppFoldState extends State<AppFold> {
  late bool _open = widget.initiallyOpen;

  @override
  void didUpdateWidget(covariant AppFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyOpen && !oldWidget.initiallyOpen && !_open) {
      _open = true;
    }
  }

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subtitle = widget.subtitle;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              child: InkWell(
                onTap: _toggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppFold.minHeaderHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: AppFold.duration,
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 22,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: AppFold.duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: widget.child,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
