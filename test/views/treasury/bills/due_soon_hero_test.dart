import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/treasury/bills/due_soon_hero.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders the bill, due label, amount and mark-paid action',
      (tester) async {
    var markPaid = 0;
    var edit = 0;
    await tester.pumpWidget(host(DueSoonHero(
      billName: 'Meralco',
      amount: 3200,
      dueLabel: 'Due in 3 days',
      subtitle: 'Electricity · due Jun 28',
      overdue: false,
      onMarkPaid: () => markPaid++,
      onEdit: () => edit++,
    )));

    expect(find.text('Meralco'), findsOneWidget);
    // Due label is uppercased in the card.
    expect(find.text('DUE IN 3 DAYS'), findsOneWidget);
    expect(find.text('Electricity · due Jun 28'), findsOneWidget);
    expect(find.text('Mark paid'), findsOneWidget);

    await tester.tap(find.text('Mark paid'));
    await tester.pump();
    expect(markPaid, 1);

    await tester.tap(find.byTooltip('Edit bill'));
    await tester.pump();
    expect(edit, 1);
  });

  testWidgets('overdue state uses the error color and error icon',
      (tester) async {
    await tester.pumpWidget(host(const DueSoonHero(
      billName: 'Rent',
      amount: 15000,
      dueLabel: 'Overdue by 2 days',
      subtitle: 'Housing · due Jun 1',
      overdue: true,
      onMarkPaid: _noop,
      onEdit: _noop,
    )));

    expect(find.text('OVERDUE BY 2 DAYS'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });
}

void _noop() {}
