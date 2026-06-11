import 'package:flutter/material.dart';
import '../design/web_breakpoints.dart';

/// Lays KPI tiles in **balanced, full rows** — never leaving a single card
/// "hanging" alone on the last row (Plan 050 polish).
///
/// Column count is derived from the available width, then nudged down so the
/// item count never leaves a remainder of exactly 1 (e.g. 4 tiles become 2×2
/// instead of 3+1; 5 become 3+2 instead of 4+1). Every tile is equal width
/// (rows use `Expanded`), and partial last rows are padded with invisible
/// spacers so tile widths stay uniform across rows.
class WebStatGrid extends StatelessWidget {
  final List<Widget> tiles;
  final double minTileWidth;
  final double spacing;

  const WebStatGrid({
    super.key,
    required this.tiles,
    this.minTileWidth = 240,
    this.spacing = WebInsets.lg,
  });

  @override
  Widget build(BuildContext context) {
    final n = tiles.length;
    if (n == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var cols = ((width + spacing) / (minTileWidth + spacing)).floor();
        cols = cols.clamp(1, n);
        // Avoid a lone trailing card: never leave a remainder of exactly 1.
        while (cols > 1 && n % cols == 1) {
          cols--;
        }

        final rows = <Widget>[];
        for (var start = 0; start < n; start += cols) {
          final end = (start + cols).clamp(0, n);
          final rowTiles = tiles.sublist(start, end);
          final children = <Widget>[];
          for (var i = 0; i < cols; i++) {
            if (i > 0) children.add(SizedBox(width: spacing));
            children.add(
              Expanded(
                child:
                    i < rowTiles.length ? rowTiles[i] : const SizedBox.shrink(),
              ),
            );
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}
