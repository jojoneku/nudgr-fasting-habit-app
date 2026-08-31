import 'package:flutter/material.dart';
import 'package:intermittent_fasting/views/web/design/web_breakpoints.dart';

/// How a short final row — one holding fewer tiles than [WebTileFlow.columns] —
/// uses the space its missing columns would have occupied.
enum WebLastRowFit {
  /// Leave the empty columns empty. Tiles keep the exact width they'd have in a
  /// full row and stay aligned to the grid above. Correct when the tiles are
  /// peers of one another and column alignment is the point — a list of account
  /// cards reads as a grid, and a last card at double width reads as special.
  pad,

  /// Widen the row's tiles so they fill the width exactly. Correct for a fixed,
  /// small set of headline stats that should read as one band.
  fill,

  /// Widen the tiles, but no further than [WebTileFlow.maxStretch] times their
  /// natural width, then centre what's left. Correct for variable-length rows,
  /// where filling would blow a lone card up to banner width but padding would
  /// leave a lopsided hole on the right.
  capAndCentre,
}

/// A responsive row-major tile grid with an explicit policy for the short last
/// row (see [WebLastRowFit]).
///
/// Every Treasury web page laid out tiles by hand before this existed — the
/// dashboard through a private `_GridFlow`, the others through a `Wrap` sized
/// against a computed `tileWidth`. Four copies of the same arithmetic drifted
/// apart on exactly one point: what the short row does. Most of them silently
/// padded, so the History strip's fifth tile sat alone in a quarter of a row
/// and any odd number of budget groups or due-soon bills trailed a hole.
///
/// [columns] is still the caller's call — it depends on the tile's own legible
/// minimum width, which this widget can't know.
class WebTileFlow extends StatelessWidget {
  final int columns;

  /// Horizontal gap between tiles in a row.
  final double spacing;

  /// Vertical gap between rows. Defaults to [spacing].
  final double? runSpacing;

  final List<Widget> children;
  final WebLastRowFit lastRowFit;

  /// Ceiling on how far a short row's tiles may grow, as a multiple of their
  /// natural width. Only consulted for [WebLastRowFit.capAndCentre]. 1.5 lets a
  /// lone tile grow enough to look deliberate without becoming a banner.
  final double maxStretch;

  const WebTileFlow({
    super.key,
    required this.columns,
    required this.children,
    this.spacing = WebInsets.lg,
    this.runSpacing,
    this.lastRowFit = WebLastRowFit.pad,
    this.maxStretch = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cols = columns < 1 ? 1 : columns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // The width a tile has in a FULL row — the reference every short-row
        // policy is expressed against.
        final natural = (width - spacing * (cols - 1)) / cols;

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final end = i + cols;
          final slice = children.sublist(
              i, end > children.length ? children.length : end);
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: runSpacing ?? spacing));
          }
          rows.add(_buildRow(slice, natural: natural, width: width));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _buildRow(
    List<Widget> slice, {
    required double natural,
    required double width,
  }) {
    final short = slice.length < columns;

    // A full row — and a short row under [WebLastRowFit.fill] — divides the
    // width evenly, which Expanded does exactly and without rounding drift.
    if (!short || lastRowFit == WebLastRowFit.fill) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < slice.length; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(child: slice[c]),
            ],
          ],
        ),
      );
    }

    // Short row, padded: natural widths, left-aligned, empty columns left as
    // they are. Sized boxes rather than Expanded so the tiles stay on the grid.
    if (lastRowFit == WebLastRowFit.pad) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < slice.length; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              SizedBox(width: natural, child: slice[c]),
            ],
          ],
        ),
      );
    }

    // Short row, capped and centred.
    final n = slice.length;
    final stretched = (width - spacing * (n - 1)) / n;
    final capped = natural * maxStretch;
    final cell = stretched < capped ? stretched : capped;

    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var c = 0; c < n; c++) ...[
            if (c > 0) SizedBox(width: spacing),
            SizedBox(width: cell, child: slice[c]),
          ],
        ],
      ),
    );
  }
}
