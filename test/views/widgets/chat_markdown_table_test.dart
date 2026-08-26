import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/widgets/chat_markdown.dart';

/// Tables in a chat bubble.
///
/// The advisor's prompt used to forbid any structure beyond bullets, because the
/// renderer handled nothing else and the syntax leaked through as literal
/// characters. A comparison — budget vs actual, card vs card — is exactly what a
/// table is for, so it renders one now, and the prompt is allowed to ask for it.
void main() {
  Future<void> pump(WidgetTester tester, String markdown) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(width: 380, child: ChatMarkdown(markdown)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('a pipe table', () {
    const table = '''
| Category | Budget | Actual |
|---|---:|---:|
| Food | ₱6,000 | ₱5,240 |
| Transport | ₱2,000 | ₱2,310 |
''';

    testWidgets('renders as a table, not as pipes', (tester) async {
      await pump(tester, table);

      expect(find.byType(Table), findsOneWidget);
      // Every cell is its own widget, and no pipe survives into the text.
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('₱5,240'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.textContaining('|'), findsNothing);
      expect(find.textContaining('---'), findsNothing);
    });

    testWidgets('reads alignment off the delimiter row', (tester) async {
      await pump(tester, table);

      // `---:` means the money columns are right-aligned; the label column is
      // left. Getting this from the model matters — it is the only thing that
      // knows which columns hold numbers.
      // find.text matches the cell's own Text (it reads the rich span too),
      // so take the widget directly rather than hunting an ancestor.
      expect(
        tester.widget<Text>(find.text('Food')).textAlign,
        TextAlign.left,
      );
      expect(
        tester.widget<Text>(find.text('₱5,240')).textAlign,
        TextAlign.right,
      );
      // Centre too, so ':-:' is not silently read as left.
      expect(
        tester.widget<Text>(find.text('Budget')).textAlign,
        TextAlign.right,
      );
    });

    testWidgets('scrolls sideways rather than overflowing the bubble',
        (tester) async {
      await pump(
        tester,
        '| A | B | C | D | E | F |\n|---|---|---|---|---|---|\n'
        '| aaaaaaaaaa | bbbbbbbbbb | cccccccccc | dddddddddd '
        '| eeeeeeeeee | ffffffffff |\n',
      );

      expect(find.byType(Table), findsOneWidget);
      expect(tester.takeException(), isNull);
      final scroll = find.ancestor(
        of: find.byType(Table),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroll, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
    });

    testWidgets('surrounding prose still renders around it', (tester) async {
      await pump(tester, 'Here is the split:\n\n$table\nOverall you are fine.');

      expect(find.text('Here is the split:'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Overall you are fine.'), findsOneWidget);
    });

    testWidgets('a ragged row is padded, not dropped', (tester) async {
      await pump(
        tester,
        '| A | B | C |\n|---|---|---|\n| one | two |\n',
      );

      // Generated tables lose trailing cells. An empty box beats losing the row.
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inline emphasis inside a cell is still parsed',
        (tester) async {
      await pump(
        tester,
        '| Item | Note |\n|---|---|\n| Food | **over** budget |\n',
      );

      // The cell holds a rich span, so the asterisks must not survive.
      expect(find.textContaining('**'), findsNothing);
      expect(find.byType(Table), findsOneWidget);
    });
  });

  group('what must NOT become a table', () {
    testWidgets('prose containing a pipe stays prose', (tester) async {
      await pump(tester, 'Compare cash | credit and decide.');

      expect(find.byType(Table), findsNothing);
      expect(find.text('Compare cash | credit and decide.'), findsOneWidget);
    });

    testWidgets('a pipe row with no delimiter row stays prose', (tester) async {
      await pump(tester, '| Food | ₱5,240 |\n| Transport | ₱2,310 |');

      // Without the |---| row it is not a table, and guessing would turn any
      // two consecutive pipe-bearing sentences into one.
      expect(find.byType(Table), findsNothing);
    });

    testWidgets('a horizontal rule is still a rule, not a delimiter row',
        (tester) async {
      await pump(tester, 'Above\n\n---\n\nBelow');

      expect(find.byType(Table), findsNothing);
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  group('the existing subset still works', () {
    testWidgets('headings, bullets, quotes and emphasis', (tester) async {
      await pump(
        tester,
        '## Liquidity\n\n- **₱28,739** liquid\n- ₱1,200 held\n\n'
        '> Correction: that was last month.\n',
      );

      expect(find.text('Liquidity'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('**'), findsNothing);
      expect(find.byType(Table), findsNothing);
    });
  });
}
