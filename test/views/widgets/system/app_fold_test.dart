import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Holds [initiallyOpen] in state so a test can flip it after the first build.
class _Flipper extends StatefulWidget {
  const _Flipper();

  @override
  State<_Flipper> createState() => _FlipperState();
}

class _FlipperState extends State<_Flipper> {
  bool hasError = false;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextButton(
            onPressed: () => setState(() => hasError = true),
            child: const Text('fail'),
          ),
          AppFold(
            title: 'More options',
            initiallyOpen: hasError,
            child: const Text('inside'),
          ),
        ],
      );
}

void main() {
  testWidgets('closed by default, opens and closes on header tap',
      (tester) async {
    await tester.pumpWidget(_host(const AppFold(
      title: 'More options',
      subtitle: 'Note',
      child: Text('inside'),
    )));
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('inside'), findsNothing);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsNothing);
  });

  testWidgets('opens on its own with initiallyOpen: true', (tester) async {
    await tester.pumpWidget(_host(const AppFold(
      title: 'More options',
      initiallyOpen: true,
      child: Text('inside'),
    )));
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('re-opens when initiallyOpen flips to true later',
      (tester) async {
    await tester.pumpWidget(_host(const _Flipper()));
    expect(find.text('inside'), findsNothing);

    await tester.tap(find.text('fail'));
    await tester.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('header is a 44 px+ target in light and dark', (tester) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      await tester.pumpWidget(_host(
        const AppFold(title: 'More options', child: Text('inside')),
        theme: theme,
      ));
      final header = find.ancestor(
        of: find.text('More options'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(header).height, greaterThanOrEqualTo(44));
    }
  });
}
