import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/treasury/shared/month_year_picker.dart';

void main() {
  testWidgets('shows the month label and picks a new month', (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            MonthYearPill(
              monthKey: '2026-06',
              onChanged: (m) => changed = m,
            ),
          ],
        ),
      ),
    ));

    expect(find.text('Jun 2026'), findsOneWidget);

    await tester.tap(find.text('Jun 2026'));
    await tester.pumpAndSettle();

    // The picker sheet exposes a month grid for the selected year.
    expect(find.text('Aug'), findsOneWidget);
    await tester.tap(find.text('Aug'));
    await tester.pumpAndSettle();

    expect(changed, '2026-08');
  });

  testWidgets('same month selection does not fire onChanged', (tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            MonthYearPill(
              monthKey: '2026-06',
              onChanged: (_) => fired++,
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.text('Jun 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();

    expect(fired, 0);
  });
}
