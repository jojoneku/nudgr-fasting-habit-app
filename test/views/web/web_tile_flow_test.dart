import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/web/widgets/web_tile_flow.dart';

/// [WebTileFlow] replaced four hand-rolled copies of the same tile-grid maths
/// across the Treasury web pages. The copies all agreed on full rows and all
/// differed on the SHORT last row, which is where every visible bug lived: the
/// History strip's fifth stat sat alone in a quarter of a row, and an odd
/// number of budget groups or due-soon bills trailed a hole on the right.
///
/// These tests pin the geometry of each [WebLastRowFit] so a future change to
/// the widget can't quietly reintroduce a gap on any of its call sites.
void main() {
  // Narrower than the 800x600 default test surface, so the SizedBox below
  // isn't clamped by the incoming constraint. Every expectation is derived
  // from this, not hardcoded.
  const width = 720.0;
  const spacing = 16.0;

  /// Natural tile width in a FULL row of [columns] — the reference every
  /// short-row policy is expressed against.
  double naturalWidth(int columns) =>
      (width - spacing * (columns - 1)) / columns;

  Future<void> pump(
    WidgetTester tester, {
    required int columns,
    required int tileCount,
    required WebLastRowFit fit,
    double maxStretch = 1.5,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: WebTileFlow(
                columns: columns,
                spacing: spacing,
                lastRowFit: fit,
                maxStretch: maxStretch,
                children: [
                  for (var i = 0; i < tileCount; i++)
                    SizedBox(key: ValueKey('tile$i'), height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, int i) {
    final finder = find.byKey(ValueKey('tile$i'));
    return tester.getTopLeft(finder) & tester.getSize(finder);
  }

  group('full rows', () {
    testWidgets('divide the width evenly and span it edge to edge',
        (tester) async {
      await pump(
        tester,
        columns: 4,
        tileCount: 4,
        fit: WebLastRowFit.capAndCentre,
      );

      final natural = naturalWidth(4);
      for (var i = 0; i < 4; i++) {
        expect(rectOf(tester, i).width, closeTo(natural, 0.01));
      }
      expect(rectOf(tester, 0).left, closeTo(0, 0.01));
      expect(rectOf(tester, 3).right, closeTo(width, 0.01));
    });

    testWidgets('wrap row-major at the column count', (tester) async {
      await pump(
        tester,
        columns: 3,
        tileCount: 6,
        fit: WebLastRowFit.pad,
      );

      // Two exact rows: tile 3 starts a new row back at the left edge.
      expect(rectOf(tester, 3).left, closeTo(0, 0.01));
      expect(rectOf(tester, 3).top, greaterThan(rectOf(tester, 0).top));
      expect(rectOf(tester, 5).right, closeTo(width, 0.01));
    });
  });

  group('short last row', () {
    testWidgets('pad keeps the natural width and stays on the grid',
        (tester) async {
      await pump(
        tester,
        columns: 4,
        tileCount: 5,
        fit: WebLastRowFit.pad,
      );

      final last = rectOf(tester, 4);
      expect(last.width, closeTo(naturalWidth(4), 0.01));
      expect(last.left, closeTo(0, 0.01),
          reason: 'padded rows stay column-aligned with the grid above');
    });

    testWidgets('fill stretches the row to the full width', (tester) async {
      await pump(
        tester,
        columns: 4,
        tileCount: 3,
        fit: WebLastRowFit.fill,
      );

      // The dashboard position row: three tiles, four columns, no hole.
      final expected = (width - spacing * 2) / 3;
      for (var i = 0; i < 3; i++) {
        expect(rectOf(tester, i).width, closeTo(expected, 0.01));
      }
      expect(rectOf(tester, 0).left, closeTo(0, 0.01));
      expect(rectOf(tester, 2).right, closeTo(width, 0.01));
    });

    testWidgets('capAndCentre caps growth at maxStretch and centres',
        (tester) async {
      // The History strip: five stat tiles over four columns.
      await pump(
        tester,
        columns: 4,
        tileCount: 5,
        fit: WebLastRowFit.capAndCentre,
      );

      final natural = naturalWidth(4);
      final last = rectOf(tester, 4);

      expect(last.width, closeTo(natural * 1.5, 0.01),
          reason: 'a lone tile grows to the cap, not to the full row');
      expect(last.left, closeTo((width - last.width) / 2, 0.01),
          reason:
              'the leftover space is split evenly, not dumped on the right');
      expect(last.width, lessThan(width));
    });

    testWidgets('capAndCentre centres a two-up row under three columns',
        (tester) async {
      await pump(
        tester,
        columns: 3,
        tileCount: 5,
        fit: WebLastRowFit.capAndCentre,
      );

      final natural = naturalWidth(3);
      final a = rectOf(tester, 3);
      final b = rectOf(tester, 4);

      expect(a.width, closeTo(natural * 1.5, 0.01));
      expect(b.width, closeTo(natural * 1.5, 0.01));
      expect(a.left, closeTo(width - b.right, 0.01),
          reason: 'equal margins either side');
      expect(b.left - a.right, closeTo(spacing, 0.01));
    });

    testWidgets('capAndCentre never exceeds the available width',
        (tester) async {
      // maxStretch high enough that the cap would overflow the row: the
      // stretched width has to win, or the tile would be clipped.
      await pump(
        tester,
        columns: 2,
        tileCount: 3,
        fit: WebLastRowFit.capAndCentre,
        maxStretch: 10,
      );

      final last = rectOf(tester, 2);
      expect(last.width, closeTo(width, 0.01));
      expect(last.left, closeTo(0, 0.01));
    });
  });

  testWidgets('an empty child list renders nothing', (tester) async {
    await pump(
      tester,
      columns: 4,
      tileCount: 0,
      fit: WebLastRowFit.capAndCentre,
    );

    expect(find.byType(Row), findsNothing);
  });
}
