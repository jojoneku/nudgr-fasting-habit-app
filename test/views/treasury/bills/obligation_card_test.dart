import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/treasury/bills/obligation_card.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders the name and fires the Pay action', (tester) async {
    var paid = 0;
    await tester.pumpWidget(host(ObligationCard(
      icon: Icons.bolt_outlined,
      iconColor: Colors.orange,
      name: 'Meralco',
      amount: 3200,
      dateLabel: 'due Jun 28',
      actionLabel: 'Pay',
      onAction: () => paid++,
    )));

    expect(find.text('Meralco'), findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);

    await tester.tap(find.text('Pay'));
    await tester.pump();
    expect(paid, 1);
  });

  testWidgets('done state hides the action and shows a check', (tester) async {
    await tester.pumpWidget(host(const ObligationCard(
      icon: Icons.bolt_outlined,
      iconColor: Colors.orange,
      name: 'Meralco',
      amount: 3200,
      dateLabel: 'due Jun 28',
      actionLabel: 'Pay',
      done: true,
    )));

    expect(find.text('Pay'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('receivable shows a Receive action', (tester) async {
    var received = 0;
    await tester.pumpWidget(host(ObligationCard(
      icon: Icons.replay_rounded,
      iconColor: Colors.green,
      name: 'Refund · Lazada',
      amount: 1240,
      dateLabel: 'exp Jul 3',
      isInflow: true,
      actionLabel: 'Receive',
      onAction: () => received++,
    )));

    expect(find.text('Receive'), findsOneWidget);
    await tester.tap(find.text('Receive'));
    await tester.pump();
    expect(received, 1);
  });
}
