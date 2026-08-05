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

  testWidgets('done state offers Undo in place of the check when it can be '
      'reversed', (tester) async {
    var undone = 0;
    await tester.pumpWidget(host(ObligationCard(
      icon: Icons.bolt_outlined,
      iconColor: Colors.orange,
      name: 'Meralco',
      amount: 3200,
      dateLabel: 'due Jun 28',
      actionLabel: 'Pay',
      done: true,
      onUndo: () => undone++,
    )));

    // A mis-tapped "Paid" is recoverable from the row it happened on.
    expect(find.text('Pay'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, 1);
  });

  testWidgets('long-press menu carries the undo entry under its own label',
      (tester) async {
    var undone = 0;
    await tester.pumpWidget(host(ObligationCard(
      icon: Icons.bolt_outlined,
      iconColor: Colors.orange,
      name: 'Meralco',
      amount: 3200,
      dateLabel: 'due Jun 28',
      actionLabel: 'Pay',
      done: true,
      onUndo: () => undone++,
      undoLabel: 'Mark unpaid',
      onEdit: () {},
    )));

    await tester.longPress(find.text('Meralco'));
    await tester.pumpAndSettle();
    expect(find.text('Mark unpaid'), findsOneWidget);

    await tester.tap(find.text('Mark unpaid'));
    await tester.pumpAndSettle();
    expect(undone, 1);
  });

  testWidgets('renders the type badge, note, and progress bar', (tester) async {
    await tester.pumpWidget(host(ObligationCard(
      icon: Icons.credit_score_outlined,
      iconColor: Colors.purple,
      name: 'MacBook',
      amount: 5000,
      dateLabel: 'payment 3/12',
      badgeLabel: 'INSTALL',
      note: 'BPI Credit Card',
      progress: 0.25,
      actionLabel: 'Pay',
      onAction: () {},
    )));

    expect(find.text('MacBook'), findsOneWidget);
    expect(find.text('INSTALL'), findsOneWidget);
    expect(find.text('BPI Credit Card'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);
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
