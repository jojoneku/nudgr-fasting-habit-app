import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/widgets/chat_markdown.dart';

/// Collect the plain text of every [Text]/[Text.rich] the widget rendered.
List<String> _renderedStrings(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final t = e.widget as Text;
    if (t.data != null) {
      out.add(t.data!);
    } else if (t.textSpan != null) {
      out.add(t.textSpan!.toPlainText());
    }
  }
  return out;
}

Future<void> _pump(WidgetTester tester, String md) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ChatMarkdown(md)),
    ),
  );
}

void main() {
  group('ChatMarkdown', () {
    testWidgets('strips heading markers and keeps the label text',
        (tester) async {
      await _pump(tester, '## Alright');
      final texts = _renderedStrings(tester);
      expect(texts, contains('Alright'));
      // The raw '##' must not leak into any rendered string.
      expect(texts.every((t) => !t.contains('#')), isTrue);
    });

    testWidgets('renders bold without leaking asterisks', (tester) async {
      await _pump(tester, 'You spent **₱22,478** today');
      final joined = _renderedStrings(tester).join('\n');
      expect(joined, contains('You spent ₱22,478 today'));
      expect(joined.contains('*'), isFalse);
    });

    testWidgets('bullets render as • and drop the dash', (tester) async {
      await _pump(tester, '- First item\n- Second item');
      final texts = _renderedStrings(tester);
      expect(texts.where((t) => t.contains('•')).length, 2);
      final joined = texts.join('\n');
      expect(joined, contains('First item'));
      expect(joined, contains('Second item'));
    });

    testWidgets('horizontal rule renders a divider, not literal dashes',
        (tester) async {
      await _pump(tester, 'Above\n\n---\n\nBelow');
      expect(find.byType(Divider), findsOneWidget);
      final joined = _renderedStrings(tester).join('\n');
      expect(joined.contains('---'), isFalse);
      expect(joined, contains('Above'));
      expect(joined, contains('Below'));
    });

    testWidgets('plain text passes through unchanged', (tester) async {
      await _pump(tester, 'Just a normal sentence.');
      expect(_renderedStrings(tester).join(), contains('Just a normal sentence.'));
    });
  });
}
