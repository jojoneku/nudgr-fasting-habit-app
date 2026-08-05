import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/views/treasury/bills/undo_settlement_dialog.dart';

/// The undo confirmation. Its one real job is the ledger question: a mis-tap
/// means the money never moved (remove the transaction), while a payment filed
/// against the wrong row means it did (keep it). Getting the returned choice
/// wrong would silently corrupt an account balance.
void main() {
  testWidgets('defaults to removing the linked transaction', (tester) async {
    UndoSettlementChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo payment?',
              name: 'Meralco',
              entryLabel: 'bill',
              hasLedgerEntry: true,
              ledgerEffect: 'GCash gets it back.',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Also remove the ledger transaction'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(choice?.removeTransaction, isTrue);
  });

  testWidgets('honours unchecking — the transaction stays', (tester) async {
    UndoSettlementChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo payment?',
              name: 'Meralco',
              entryLabel: 'bill',
              hasLedgerEntry: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(choice?.removeTransaction, isFalse);
  });

  testWidgets('offers no choice when nothing is linked', (tester) async {
    UndoSettlementChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showUndoSettlementDialog(
              context: context,
              title: 'Undo payment?',
              name: 'Meralco',
              entryLabel: 'bill',
              hasLedgerEntry: false,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(choice?.removeTransaction, isFalse);
  });

  testWidgets('cancelling changes nothing', (tester) async {
    UndoSettlementChoice? choice;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showUndoSettlementDialog(
                context: context,
                title: 'Undo payment?',
                name: 'Meralco',
                entryLabel: 'bill',
                hasLedgerEntry: true,
              );
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(choice, isNull);
  });
}
