import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/views/treasury/bills/coming_up_timeline.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders each row and marks an inflow with a +', (tester) async {
    final items = [
      ComingUpItem(
        kind: ComingUpKind.bill,
        name: 'Internet · PLDT',
        amount: 2099,
        isInflow: false,
        date: DateTime(2026, 7, 1),
        dateLabel: 'Jul 1 · 6 days',
        source: Object(),
      ),
      ComingUpItem(
        kind: ComingUpKind.receivable,
        name: 'Refund · Lazada',
        amount: 1240,
        isInflow: true,
        date: DateTime(2026, 7, 3),
        dateLabel: 'Jul 3 · incoming',
        source: Object(),
      ),
    ];

    await tester.pumpWidget(host(ComingUpTimeline(items: items)));

    expect(find.text('Internet · PLDT'), findsOneWidget);
    expect(find.text('Refund · Lazada'), findsOneWidget);
    // The receivable amount is prefixed with a +.
    expect(find.textContaining('+'), findsWidgets);
  });

  testWidgets('tapping a row reports the item', (tester) async {
    ComingUpItem? tapped;
    final item = ComingUpItem(
      kind: ComingUpKind.bill,
      name: 'Spotify',
      amount: 149,
      isInflow: false,
      date: DateTime(2026, 7, 5),
      dateLabel: 'Jul 5 · 10 days',
      source: Object(),
    );

    await tester.pumpWidget(host(
      ComingUpTimeline(items: [item], onTap: (i) => tapped = i),
    ));

    await tester.tap(find.text('Spotify'));
    await tester.pump();
    expect(tapped, same(item));
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(host(const ComingUpTimeline(items: [])));
    expect(find.byType(InkWell), findsNothing);
  });
}
