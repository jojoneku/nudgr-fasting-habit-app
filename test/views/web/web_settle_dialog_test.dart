import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_dialog.dart';
import 'package:intermittent_fasting/views/web/widgets/web_settle_dialog.dart';

/// The one settle dialog behind every desktop "mark paid / received / funded /
/// pay the card" action (Plan 063 §5).
///
/// What it exists to guarantee: the settled amount and date are the user's,
/// not the entry's. Every one of those flows used to post the scheduled
/// amount dated today, so a partial payment, an overpayment, or reconciling
/// last month could only be done on the phone. These tests pin the values
/// that actually reach the presenter, and that each [SettleKind] asks only
/// for what its money movement needs.
void main() {
  FinancialAccount account(String id, String name, {double balance = 5000}) =>
      FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.bank,
        balance: balance,
        colorHex: '#2E90FA',
        icon: 'wallet',
      );

  final bpi = account('a_bpi', 'BPI');
  final gcash = account('a_gcash', 'GCash');
  final savings = account('a_savings', 'Savings');

  /// Pumps a button that opens the dialog, and captures what `onSubmit` sees.
  /// Returns a holder so a test can read the captured result after the
  /// dialog closes.
  Future<List<SettleResult>> openDialog(
    WidgetTester tester, {
    SettleKind kind = SettleKind.bill,
    double amount = 2500,
    List<SettleTarget>? targets,
    List<FinancialAccount> accounts = const [],
    String? initialAccountId,
    List<FinancialAccount> destinations = const [],
    String? accountId,
    String? destinationId,
    bool requiresAccount = true,
    Future<void> Function(SettleResult)? onSubmit,
  }) async {
    final captured = <SettleResult>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildWebDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWebSettleDialog(
              context,
              kind: kind,
              targets: targets ??
                  [
                    SettleTarget(
                      id: 't1',
                      name: 'Electricity',
                      amount: amount,
                      dateLabel: 'due Oct 16',
                      accountId: accountId,
                      destinationId: destinationId,
                    ),
                  ],
              accounts: accounts,
              initialAccountId: initialAccountId,
              destinations: destinations,
              requiresAccount: requiresAccount,
              onSubmit: (r) async {
                captured.add(r);
                if (onSubmit != null) await onSubmit(r);
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return captured;
  }

  Finder amountField() => find.byKey(WebKeys.billsSettleAmount);
  Finder confirm() => find.byKey(WebKeys.billsSettleConfirm);
  FilledButton confirmButton(WidgetTester tester) =>
      tester.widget<FilledButton>(confirm());

  /// The destination picker is the second dropdown (the funding account is
  /// the first). Tapping the widget rather than its hint text keeps the tap
  /// landing on the control itself.
  Finder destinationDropdown() =>
      find.byType(DropdownButtonFormField<String>).last;

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(confirm());
    await tester.pumpAndSettle();
  }

  group('amount', () {
    testWidgets('defaults to the scheduled amount and names it',
        (tester) async {
      await openDialog(tester, amount: 2500, accounts: [bpi]);

      expect(find.text('2500.00'), findsOneWidget);
      // The scheduled figure is named, so a deliberate partial is
      // distinguishable from a typo.
      expect(find.text('Scheduled ₱2,500.00 · due Oct 16'), findsOneWidget);
      expect(find.text('Mark Electricity paid'), findsOneWidget);
    });

    testWidgets('a partial payment reaches onSubmit, not the scheduled amount',
        (tester) async {
      final captured = await openDialog(tester, amount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '1000');
      await submit(tester);

      expect(captured, hasLength(1));
      expect(captured.single.amount, 1000);
      expect(captured.single.scheduledAmount, 2500);
      expect(captured.single.isPartial, isTrue);
      expect(captured.single.isOverpayment, isFalse);
      expect(captured.single.targetIds, ['t1']);
    });

    testWidgets('an overpayment is allowed on a bill', (tester) async {
      final captured = await openDialog(tester, amount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '3000');
      await submit(tester);

      expect(captured.single.amount, 3000);
      expect(captured.single.isOverpayment, isTrue);
    });

    testWidgets('zero and non-numeric amounts are rejected', (tester) async {
      final captured = await openDialog(tester, amount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '0');
      await submit(tester);
      expect(captured, isEmpty);
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(amountField(), 'abc');
      await submit(tester);
      expect(captured, isEmpty);
    });

    testWidgets('a thousands separator is accepted', (tester) async {
      final captured = await openDialog(tester, amount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '1,250.50');
      await submit(tester);

      expect(captured.single.amount, 1250.50);
    });
  });

  group('date', () {
    testWidgets('defaults to today and is carried through', (tester) async {
      final captured = await openDialog(tester, amount: 100, accounts: [bpi]);

      await submit(tester);

      final today = DateTime.now();
      expect(captured.single.date.year, today.year);
      expect(captured.single.date.month, today.month);
      expect(captured.single.date.day, today.day);
    });

    testWidgets('back-dating a settle is possible', (tester) async {
      final captured = await openDialog(tester, amount: 100, accounts: [bpi]);

      // Open the picker, step back one month, take the 15th.
      await tester.tap(find.byKey(WebKeys.billsSettleDate));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await submit(tester);

      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1);
      expect(captured.single.date.day, 15);
      expect(captured.single.date.month, lastMonth.month);
      expect(captured.single.date.year, lastMonth.year);
    });
  });

  group('funding account', () {
    testWidgets('defaults to the preselected account', (tester) async {
      final captured = await openDialog(
        tester,
        amount: 100,
        accounts: [bpi, gcash],
        initialAccountId: 'a_gcash',
      );

      await submit(tester);

      expect(captured.single.accountId, 'a_gcash');
    });

    testWidgets('falls back to the account on the row', (tester) async {
      final captured = await openDialog(
        tester,
        amount: 100,
        accounts: [bpi, gcash],
        accountId: 'a_gcash',
      );

      await submit(tester);

      expect(captured.single.accountId, 'a_gcash');
    });

    testWidgets('a preselection that is not on offer falls back to the first',
        (tester) async {
      // Guards the dropdown assert: a value absent from its items throws.
      final captured = await openDialog(
        tester,
        amount: 100,
        accounts: [bpi, gcash],
        initialAccountId: 'a_deleted',
      );

      await submit(tester);

      expect(captured.single.accountId, 'a_bpi');
    });

    testWidgets('the balance is shown beside each account', (tester) async {
      await openDialog(tester, amount: 100, accounts: [bpi]);

      expect(find.text('BPI · ₱5,000.00'), findsOneWidget);
      expect(find.text('PAY FROM'), findsOneWidget);
    });

    testWidgets('submit is blocked when an account is required but none exist',
        (tester) async {
      await openDialog(tester, amount: 100, accounts: const []);

      expect(confirmButton(tester).onPressed, isNull);
      expect(find.text('Add an account before settling.'), findsOneWidget);
    });

    testWidgets('a short balance is named in words but does not block',
        (tester) async {
      await openDialog(
        tester,
        amount: 1600,
        accounts: [account('a_low', 'GCASH', balance: 250)],
      );

      expect(find.textContaining('short by ₱1,350.00'), findsOneWidget);
      expect(find.textContaining('GCASH does not have enough'), findsOneWidget);
      // Informational: the user may be about to move money in first.
      expect(confirmButton(tester).onPressed, isNotNull);
    });
  });

  group('already in ledger', () {
    testWidgets('drops the account and clears recordInLedger', (tester) async {
      final captured = await openDialog(tester, amount: 100, accounts: [bpi]);

      expect(find.text('BPI · ₱5,000.00'), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.billsSettleAlreadyLogged));
      await tester.pumpAndSettle();

      // The picker is gone — nothing is being recorded, so nothing is debited.
      expect(find.text('BPI · ₱5,000.00'), findsNothing);

      await submit(tester);

      expect(captured.single.recordInLedger, isFalse);
      expect(captured.single.accountId, isNull);
    });

    testWidgets('with no accounts at all, the toggle still lets it through',
        (tester) async {
      final captured =
          await openDialog(tester, amount: 100, accounts: const []);

      await tester.tap(find.byKey(WebKeys.billsSettleAlreadyLogged));
      await tester.pumpAndSettle();
      await submit(tester);

      expect(captured.single.recordInLedger, isFalse);
    });
  });

  group('kinds', () {
    testWidgets('a receivable deposits, so it asks where and has no shortfall',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: SettleKind.receivable,
        amount: 9000,
        accounts: [account('a_low', 'GCASH', balance: 250)],
      );

      expect(find.text('Receive Electricity'), findsOneWidget);
      expect(find.text('DEPOSIT INTO'), findsOneWidget);
      expect(find.text('PAY FROM'), findsNothing);
      expect(find.textContaining('short by'), findsNothing);

      await submit(tester);
      expect(captured.single.accountId, 'a_low');
    });

    testWidgets('an installment rides on its own card: no account, no toggle',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: SettleKind.installment,
        amount: 2166,
        accounts: const [],
      );

      expect(find.byKey(WebKeys.billsSettleAccount), findsNothing);
      expect(find.byKey(WebKeys.billsSettleAlreadyLogged), findsNothing);
      expect(find.text('Monthly ₱2,166.00 · charged to its own card'),
          findsOneWidget);
      expect(confirmButton(tester).onPressed, isNotNull);

      await submit(tester);
      expect(captured.single.amount, 2166);
      expect(captured.single.accountId, isNull);
    });

    testWidgets('a card payment cannot exceed what is owed', (tester) async {
      final captured = await openDialog(
        tester,
        kind: SettleKind.cardPayment,
        amount: 2500,
        accounts: [bpi],
      );

      expect(find.text('Pay Electricity'), findsOneWidget);
      expect(find.textContaining('You owe ₱2,500.00'), findsOneWidget);
      // A card payment is a transfer, so there is no ledger opt-out.
      expect(find.byKey(WebKeys.billsSettleAlreadyLogged), findsNothing);

      await tester.enterText(amountField(), '3000');
      await submit(tester);
      expect(captured, isEmpty);
      expect(find.text('More than the ₱2,500.00 owed'), findsOneWidget);

      await tester.enterText(amountField(), '1000');
      await submit(tester);
      expect(captured.single.amount, 1000);
      expect(captured.single.accountId, 'a_bpi');
    });
  });

  group('set-aside destination', () {
    testWidgets('submit waits until a destination is chosen', (tester) async {
      await openDialog(
        tester,
        kind: SettleKind.setAside,
        amount: 100,
        accounts: [bpi],
        destinations: [savings],
      );

      expect(find.text('Fund Electricity'), findsOneWidget);
      expect(find.text('SET ASIDE INTO'), findsOneWidget);
      // Nothing on file — where the money goes must be answered first.
      expect(confirmButton(tester).onPressed, isNull);

      await tester.tap(destinationDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Savings').last);
      await tester.pumpAndSettle();

      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('"spend it" is a real answer, not an unanswered question',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: SettleKind.setAside,
        amount: 100,
        accounts: [bpi],
        destinations: [savings],
      );

      await tester.tap(destinationDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spend it (no transfer)').last);
      await tester.pumpAndSettle();

      await submit(tester);

      // Chosen, and chosen as null — a plain outflow rather than a transfer.
      expect(captured, hasLength(1));
      expect(captured.single.destinationId, isNull);
    });

    testWidgets('a stored destination preselects and submits straight through',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: SettleKind.setAside,
        amount: 100,
        accounts: [bpi],
        destinations: [savings],
        destinationId: 'a_savings',
      );

      await submit(tester);

      expect(captured.single.destinationId, 'a_savings');
    });

    testWidgets('a destination that is also the funding account is dropped',
        (tester) async {
      // Money can't move into the account it just left, so the preselection
      // is discarded and the question reopens rather than submitting an
      // invalid transfer.
      await openDialog(
        tester,
        kind: SettleKind.setAside,
        amount: 100,
        accounts: [bpi],
        destinations: [bpi],
        destinationId: 'a_bpi',
      );

      expect(confirmButton(tester).onPressed, isNull);
    });
  });

  group('batch', () {
    final two = [
      const SettleTarget(
          id: 'b1', name: 'Electricity', amount: 1600, dateLabel: 'Oct 16'),
      const SettleTarget(id: 'b2', name: 'Insurance Premium', amount: 786),
    ];

    testWidgets(
        'lists the rows, asks once, and settles each for its own amount',
        (tester) async {
      final captured = await openDialog(
        tester,
        targets: two,
        accounts: [bpi, gcash],
        initialAccountId: 'a_gcash',
      );

      expect(find.text('Pay 2 bills'), findsOneWidget);
      expect(find.textContaining('₱2,386.00 total'), findsOneWidget);
      expect(find.text('Electricity'), findsOneWidget);
      expect(find.text('Insurance Premium'), findsOneWidget);
      expect(find.text('Oct 16'), findsOneWidget);
      // No editable amount: a batch is "these all happened", not an edit.
      expect(amountField(), findsNothing);
      expect(find.text('Mark 2 paid'), findsOneWidget);

      await submit(tester);

      final r = captured.single;
      expect(r.amount, 2386);
      expect(r.accountId, 'a_gcash');
      expect(r.targetIds, ['b1', 'b2']);
      expect(r.toBatchChoice().alreadyInLedger, isFalse);
    });

    testWidgets('batch set-asides keep saved destinations unless told not to',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWebSettleDialog(
                context,
                kind: SettleKind.setAside,
                targets: two,
                accounts: [bpi],
                destinations: [savings],
                savedDestinationCount: 2,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Both already know where they go, so nothing is left to ask.
      expect(find.text('2 of 2 have their own destination'), findsOneWidget);
      expect(find.text('SET ASIDE INTO'), findsNothing);
      expect(confirmButton(tester).onPressed, isNotNull);

      // Overriding them reopens the shared question, which blocks Fund.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('SET ASIDE INTO'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });
  });

  group('failure', () {
    testWidgets('a failed write keeps the dialog open with values intact',
        (tester) async {
      final captured = await openDialog(
        tester,
        amount: 2500,
        accounts: [bpi],
        onSubmit: (_) async => throw StateError('ledger refused'),
      );

      await tester.enterText(amountField(), '1000');
      await submit(tester);

      // It was attempted, it failed, and the entry is not silently settled —
      // the dialog is still up with the typed amount ready to retry.
      expect(captured, hasLength(1));
      expect(find.byType(WebDialog), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('cancelling returns null', (tester) async {
      final captured = await openDialog(tester, amount: 100, accounts: [bpi]);

      await tester.tap(find.byKey(WebKeys.billsSettleCancel));
      await tester.pumpAndSettle();

      expect(captured, isEmpty);
      expect(find.byType(WebDialog), findsNothing);
    });
  });
}
