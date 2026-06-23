import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intermittent_fasting/utils/app_radii.dart';
import '../design/web_breakpoints.dart';

/// One selectable option in a [WebSearchableDropdown].
///
/// [dotColor] renders an 8px rounded swatch before the [label] (used for
/// account/category color coding). Pass `null` for no dot.
class WebDropdownEntry<T> {
  final T value;
  final String label;
  final Color? dotColor;

  const WebDropdownEntry({
    required this.value,
    required this.label,
    this.dotColor,
  });
}

/// A type-to-filter dropdown for the Treasury web companion.
///
/// Renders like the plain Material dropdowns it replaces (a tappable field
/// showing the selected entry's dot + label, or [hintText]), but on tap opens
/// an anchored overlay with an autofocused search box and a height-capped,
/// scrollable list. Filtering is token-AND substring: the query is split on
/// whitespace and every token must appear in the label (case-insensitive).
///
/// Theme-aware only — all colors come from [Theme.of] so it works in both the
/// dark (Solo Leveling) and light modes.
class WebSearchableDropdown<T> extends StatefulWidget {
  final T? value;
  final List<WebDropdownEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final String? hintText;
  final double? width;
  final bool isDense;

  const WebSearchableDropdown({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.hintText,
    this.width,
    this.isDense = false,
  });

  @override
  State<WebSearchableDropdown<T>> createState() =>
      _WebSearchableDropdownState<T>();
}

class _WebSearchableDropdownState<T> extends State<WebSearchableDropdown<T>> {
  final _overlayController = OverlayPortalController();
  final _link = LayerLink();
  final _searchController = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onKey);

  String _query = '';

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  WebDropdownEntry<T>? get _selected {
    for (final e in widget.entries) {
      if (e.value == widget.value) return e;
    }
    return null;
  }

  List<WebDropdownEntry<T>> get _filtered {
    final tokens = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return widget.entries;
    return widget.entries.where((e) {
      final label = e.label.toLowerCase();
      return tokens.every(label.contains);
    }).toList();
  }

  void _open() {
    _searchController.clear();
    _query = '';
    _overlayController.show();
    // Autofocus once the overlay is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _close() {
    if (_overlayController.isShowing) _overlayController.hide();
  }

  void _select(T value) {
    widget.onChanged(value);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final field = CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: _buildOverlay,
        child: _buildField(context),
      ),
    );
    if (widget.width != null) {
      return SizedBox(width: widget.width, child: field);
    }
    return field;
  }

  Widget _buildField(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selected;
    final textStyle =
        widget.isDense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _overlayController.isShowing ? _close() : _open(),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isDense ? WebInsets.sm : WebInsets.md,
            vertical: widget.isDense ? WebInsets.xs : WebInsets.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border:
                widget.isDense ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              if (selected?.dotColor != null) ...[
                _Dot(color: selected!.dotColor!),
                const SizedBox(width: WebInsets.sm),
              ],
              Expanded(
                child: Text(
                  selected?.label ?? widget.hintText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: selected == null
                      ? textStyle?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6))
                      : textStyle,
                ),
              ),
              Icon(Icons.expand_more_rounded,
                  size: widget.isDense ? 16 : 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Full-screen barrier closes the overlay on an outside tap.
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 200,
                maxWidth: widget.width ?? 320,
              ),
              child: Material(
                color: cs.surfaceContainerHigh,
                elevation: 8,
                borderRadius: BorderRadius.circular(AppRadii.md),
                shadowColor: cs.shadow.withValues(alpha: 0.18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSearchField(theme, cs),
                      _buildList(theme, cs),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(WebInsets.sm),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        autofocus: true,
        style: theme.textTheme.bodyMedium,
        textInputAction: TextInputAction.done,
        onChanged: (v) => setState(() => _query = v),
        onSubmitted: (_) {
          final hits = _filtered;
          if (hits.isNotEmpty) _select(hits.first.value);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText ?? 'Search…',
          prefixIcon:
              Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: WebInsets.sm, vertical: WebInsets.sm),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, ColorScheme cs) {
    final hits = _filtered;
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WebInsets.md, vertical: WebInsets.lg),
        child: Text(
          'No matches',
          style:
              theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: WebInsets.xs),
        itemCount: hits.length,
        itemBuilder: (context, i) {
          final entry = hits[i];
          final isSelected = entry.value == widget.value;
          return InkWell(
            onTap: () => _select(entry.value),
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(
                  horizontal: WebInsets.md, vertical: WebInsets.sm),
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              child: Row(
                children: [
                  if (entry.dotColor != null) ...[
                    _Dot(color: entry.dotColor!),
                    const SizedBox(width: WebInsets.sm),
                  ],
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected ? cs.primary : null,
                        fontWeight: isSelected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_rounded, size: 16, color: cs.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
