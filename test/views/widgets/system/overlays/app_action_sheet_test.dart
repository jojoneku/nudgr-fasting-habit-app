import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/widgets/system/overlays/app_action_sheet.dart';

/// Pumps a screen with a single button that opens [AppActionSheet.show],
/// captures the popped result, and returns a tapper for the button.
Future<T?> _openSheet<T>(
  WidgetTester tester, {
  required List<AppActionSheetItem<T>> actions,
  AppActionSheetItem<T>? cancel,
}) async {
  T? result;
  var popped = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await AppActionSheet.show<T>(
                  context: context,
                  title: 'Pick one',
                  actions: actions,
                  cancel: cancel,
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Sanity: the callback hasn't returned until the sheet is dismissed.
  expect(popped, isFalse);
  return result;
}

void main() {
  group('AppActionSheet', () {
    // Regression: a non-nullable T (e.g. show<String>) with no explicit cancel
    // used to synthesize `value: null as T`, which threw at build time and left
    // a grey screen (the treasury budget month picker symptom).
    testWidgets('opens with a non-nullable T and no explicit cancel',
        (tester) async {
      await _openSheet<String>(
        tester,
        actions: const [
          AppActionSheetItem(label: 'Jun 2026', value: '2026-06'),
          AppActionSheetItem(label: 'May 2026', value: '2026-05'),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Pick one'), findsOneWidget);
      expect(find.text('Jun 2026'), findsOneWidget);
      // The default cancel row is present.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('tapping an action returns its value', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await AppActionSheet.show<String>(
                      context: context,
                      actions: const [
                        AppActionSheetItem(label: 'Jun 2026', value: '2026-06'),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jun 2026'));
      await tester.pumpAndSettle();

      expect(picked, '2026-06');
    });

    testWidgets('tapping the default cancel dismisses with null',
        (tester) async {
      String? picked = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await AppActionSheet.show<String>(
                      context: context,
                      actions: const [
                        AppActionSheetItem(label: 'Jun 2026', value: '2026-06'),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(picked, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
