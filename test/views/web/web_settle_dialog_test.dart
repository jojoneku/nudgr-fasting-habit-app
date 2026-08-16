import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_settle_dialog.dart';

/// The one settle dialog behind every desktop "mark paid / received / funded"
/// action.
///
/// What it exists to guarantee: the settled amount and date are the user's, not
/// the entry's. Every one of those flows used to post the scheduled amount dated
/// today, so a partial payment, an overpayment, or reconciling last month could
/// only be done on the phone. These tests pin the values that actually reach the
/// presenter.
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
  /// Returns a one-element holder so a test can read the captured result after
  /// the dialog closes.
  Future<List<WebSettleResult>> openDialog(
    WidgetTester tester, {
    required double initialAmount,
    List<FinancialAccount> accounts = const [],
    String? initialAccountId,
    bool requiresAccount = false,
    bool showLedgerToggle = false,
    WebSettleDestination? destination,
    Future<void> Function(WebSettleResult)? onSubmit,
  }) async {
    final captured = <WebSettleResult>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildWebDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWebSettleDialog(
              context,
              title: 'Mark paid',
              summary: 'Records the payment.',
              confirmLabel: 'Mark paid',
              initialAmount: initialAmount,
              accounts: accounts,
              initialAccountId: initialAccountId,
              requiresAccount: requiresAccount,
              showLedgerToggle: showLedgerToggle,
              destination: destination,
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

  Finder amountField() => find.byType(TextFormField);

  /// The destination picker is the second dropdown (the funding account is the
  /// first). Tapping the widget rather than its hint text keeps the tap landing
  /// on the control itself.
  Finder destinationDropdown() =>
      find.byType(DropdownButtonFormField<String>).last;

  group('amount', () {
    testWidgets('defaults to the scheduled amount', (tester) async {
      await openDialog(tester, initialAmount: 2500, accounts: [bpi]);

      expect(find.text('2500.00'), findsOneWidget);
      // The scheduled figure is named, so a deliberate partial is
      // distinguishable from a typo.
      expect(find.textContaining('Scheduled:'), findsOneWidget);
    });

    testWidgets('a partial payment reaches onSubmit, not the scheduled amount',
        (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '1000');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured, hasLength(1));
      expect(captured.single.amount, 1000);
      expect(captured.single.scheduledAmount, 2500);
      expect(captured.single.isPartial, isTrue);
      expect(captured.single.isOverpayment, isFalse);
    });

    testWidgets('an overpayment is allowed', (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '3000');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.amount, 3000);
      expect(captured.single.isOverpayment, isTrue);
    });

    testWidgets('zero and non-numeric amounts are rejected', (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();
      expect(captured, isEmpty);
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(amountField(), 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();
      expect(captured, isEmpty);
    });

    testWidgets('a thousands separator is accepted', (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 2500, accounts: [bpi]);

      await tester.enterText(amountField(), '1,250.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.amount, 1250.50);
    });
  });

  group('date', () {
    testWidgets('defaults to today and is carried through', (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 100, accounts: [bpi]);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(captured.single.date.year, today.year);
      expect(captured.single.date.month, today.month);
      expect(captured.single.date.day, today.day);
    });

    testWidgets('back-dating a settle is possible', (tester) async {
      final captured =
          await openDialog(tester, initialAmount: 100, accounts: [bpi]);

      // Open the picker, step back one month, take the 15th.
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

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
        initialAmount: 100,
        accounts: [bpi, gcash],
        initialAccountId: 'a_gcash',
        requiresAccount: true,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.accountId, 'a_gcash');
    });

    testWidgets('a preselection that is not on offer falls back to the first',
        (tester) async {
      // Guards the dropdown assert: a value absent from its items throws.
      final captured = await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi, gcash],
        initialAccountId: 'a_deleted',
        requiresAccount: true,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.accountId, 'a_bpi');
    });

    testWidgets('submit is blocked when an account is required but none exist',
        (tester) async {
      await openDialog(
        tester,
        initialAmount: 100,
        accounts: const [],
        requiresAccount: true,
      );

      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark paid'));
      expect(button.onPressed, isNull);
    });
  });

  group('already in ledger', () {
    testWidgets('drops the account and clears recordInLedger', (tester) async {
      final captured = await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi],
        requiresAccount: true,
        showLedgerToggle: true,
      );

      expect(find.text('BPI · ₱5,000.00'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      // The picker is gone — nothing is being recorded, so nothing is debited.
      expect(find.text('BPI · ₱5,000.00'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.recordInLedger, isFalse);
      expect(captured.single.accountId, isNull);
    });

    testWidgets('with no accounts at all, the toggle still lets it through',
        (tester) async {
      final captured = await openDialog(
        tester,
        initialAmount: 100,
        accounts: const [],
        requiresAccount: true,
        showLedgerToggle: true,
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.recordInLedger, isFalse);
    });
  });

  group('set-aside destination', () {
    testWidgets('submit waits until a destination is chosen', (tester) async {
      await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi],
        requiresAccount: true,
        destination: WebSettleDestination(
          options: [savings],
          label: 'Set aside into',
        ),
      );

      // Nothing on file — where the money goes must be answered first.
      final blocked = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark paid'));
      expect(blocked.onPressed, isNull);

      await tester.tap(destinationDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Savings').last);
      await tester.pumpAndSettle();

      final unblocked = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark paid'));
      expect(unblocked.onPressed, isNotNull);
    });

    testWidgets('"spend it" is a real answer, not an unanswered question',
        (tester) async {
      final captured = await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi],
        requiresAccount: true,
        destination: WebSettleDestination(
          options: [savings],
          label: 'Set aside into',
        ),
      );

      await tester.tap(destinationDropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spend it (no transfer)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      // Chosen, and chosen as null — a plain outflow rather than a transfer.
      expect(captured, hasLength(1));
      expect(captured.single.destinationId, isNull);
    });

    testWidgets('a stored destination preselects and submits straight through',
        (tester) async {
      final captured = await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi],
        requiresAccount: true,
        destination: WebSettleDestination(
          options: [savings],
          label: 'Set aside into',
          initialId: 'a_savings',
          initiallyChosen: true,
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      expect(captured.single.destinationId, 'a_savings');
    });

    testWidgets('a destination that is also the funding account is dropped',
        (tester) async {
      // Money can't move into the account it just left, so the preselection is
      // discarded and the question reopens rather than submitting an invalid
      // transfer.
      await openDialog(
        tester,
        initialAmount: 100,
        accounts: [bpi],
        requiresAccount: true,
        destination: WebSettleDestination(
          options: [bpi],
          label: 'Set aside into',
          initialId: 'a_bpi',
          initiallyChosen: true,
        ),
      );

      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark paid'));
      expect(button.onPressed, isNull);
    });
  });

  group('failure', () {
    testWidgets('a failed write keeps the dialog open with values intact',
        (tester) async {
      final captured = await openDialog(
        tester,
        initialAmount: 2500,
        accounts: [bpi],
        requiresAccount: true,
        onSubmit: (_) async => throw StateError('ledger refused'),
      );

      await tester.enterText(amountField(), '1000');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid'));
      await tester.pumpAndSettle();

      // It was attempted, it failed, and the entry is not silently settled —
      // the dialog is still up with the typed amount ready to retry.
      expect(captured, hasLength(1));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });
  });
}
