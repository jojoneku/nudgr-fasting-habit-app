import 'package:flutter/material.dart';
import '../design/web_breakpoints.dart';

/// A sidebar destination for [WebShell].
class WebDestination {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  const WebDestination(
      {required this.icon, this.selectedIcon, required this.label});
}

/// Desktop shell: a left [NavigationRail] (extended, labelled) with a brand
/// header and a footer slot (sync status / sign-out), plus a scrolling content
/// area constrained to [WebBreakpoints.content]. Theme-aware, both modes.
class WebShell extends StatelessWidget {
  final List<WebDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  /// Optional brand/title shown at the top of the rail.
  final Widget? header;

  /// Optional footer (e.g. sync status + sign-out button).
  final Widget? footer;

  const WebShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          Container(
            width: 248,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border(
                right:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(WebInsets.xl,
                          WebInsets.xl, WebInsets.xl, WebInsets.lg),
                      child: header!,
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: WebInsets.md),
                      child: Column(
                        children: [
                          for (var i = 0; i < destinations.length; i++)
                            _RailItem(
                              destination: destinations[i],
                              selected: i == selectedIndex,
                              onTap: () => onDestinationSelected(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.all(WebInsets.lg),
                      child: footer!,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              // Full-height, width-constrained content region. Pages own their
              // own scrolling and padding (tables and two-pane layouts need to
              // manage scroll themselves).
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: WebBreakpoints.content),
                  child: SizedBox.expand(child: body),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final WebDestination destination;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = widget.selected;
    final fg = selected ? cs.primary : cs.onSurfaceVariant;

    Color? bg;
    if (selected) {
      bg = cs.primary.withValues(alpha: 0.12);
    } else if (_hover) {
      bg = cs.onSurface.withValues(alpha: 0.05);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: WebInsets.md, vertical: WebInsets.md),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? (widget.destination.selectedIcon ??
                          widget.destination.icon)
                      : widget.destination.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: WebInsets.md),
                Text(
                  widget.destination.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
