import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/views/treasury/bills/batch_settle_sheet.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/widgets/web_batch_bar.dart';
import 'package:intermittent_fasting/views/web/widgets/web_batch_settle_dialog.dart';

/// Desktop batch settling: picking several rows and settling them in one go.
///
/// The web Bills page had no selection at all, so a month of bills had to be
/// settled one dialog at a time. These pin the two halves of the fix — the
/// selection controls, and the dialog that asks once for what the batch shares.
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

  Widget wrap(Widget child) => MaterialApp(
        theme: buildWebDarkTheme(),
        home: Scaffold(body: child),
      );

  Future<List<BatchSettleChoice?>> openDialog(
    WidgetTester tester, {
    required BatchSettleKind kind,
    int count = 3,
    double total = 3000,
    List<FinancialAccount> accounts = const [],
    List<FinancialAccount> destinations = const [],
    String? initialAccountId,
    int savedDestinationCount = 0,
  }) async {
    final captured = <BatchSettleChoice?>[];
    await tester.pumpWidget(wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final choice = await showWebBatchSettleDialog(
            context,
            kind: kind,
            count: count,
            total: total,
            accounts: accounts,
            destinations: destinations,
            initialAccountId: initialAccountId,
            savedDestinationCount: savedDestinationCount,
          );
          captured.add(choice);
        },
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return captured;
  }

  group('batch settle dialog', () {
    testWidgets('bills: asks once for the funding account and date',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.bills,
        accounts: [bpi, gcash],
        initialAccountId: 'a_gcash',
      );

      expect(find.text('Mark 3 bills paid'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark 3 paid'));
      await tester.pumpAndSettle();

      final choice = captured.single!;
      expect(choice.accountId, 'a_gcash');
      expect(choice.alreadyInLedger, isFalse);
      final today = DateTime.now();
      expect(choice.date.day, today.day);
      expect(choice.date.month, today.month);
    });

    testWidgets('bills: "already in ledger" drops the account', (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.bills,
        accounts: [bpi],
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark 3 paid'));
      await tester.pumpAndSettle();

      final choice = captured.single!;
      expect(choice.alreadyInLedger, isTrue);
      expect(choice.accountId, isNull);
    });

    testWidgets('installments ask for no account at all', (tester) async {
      // Each installment is charged to its own account, so there is nothing to
      // pick — offering a funding account here would be a lie.
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.installments,
        accounts: [bpi],
      );

      expect(find.text('Pay from'), findsNothing);
      // And no ledger opt-out either: the payment IS its transaction.
      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Pay 3'));
      await tester.pumpAndSettle();
      expect(captured.single!.accountId, isNull);
    });

    testWidgets('receivables offer a deposit account, not a funding one',
        (tester) async {
      await openDialog(
        tester,
        kind: BatchSettleKind.receivables,
        accounts: [bpi],
      );

      expect(find.text('Deposit into'), findsOneWidget);
      expect(find.text('Pay from'), findsNothing);
    });

    testWidgets('set-asides: confirm waits for a destination', (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.setAsides,
        accounts: [bpi],
        destinations: [savings],
      );

      // None of the three name a destination, so the shared one must be
      // answered before money moves.
      final blocked = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fund 3'));
      expect(blocked.onPressed, isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Savings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Fund 3'));
      await tester.pumpAndSettle();

      expect(captured.single!.toAccountId, 'a_savings');
      expect(captured.single!.useSavedDestinations, isTrue);
    });

    testWidgets(
        'set-asides: rows with their own destination need no shared answer',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.setAsides,
        accounts: [bpi],
        destinations: [savings],
        savedDestinationCount: 3,
      );

      // All three already know where they go, so nothing is left to ask and
      // Fund is live immediately.
      expect(find.text('3 of 3 have their own destination'), findsOneWidget);
      final button = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fund 3'));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Fund 3'));
      await tester.pumpAndSettle();
      expect(captured.single!.useSavedDestinations, isTrue);
    });

    testWidgets(
        'set-asides: overriding saved destinations reopens the question',
        (tester) async {
      await openDialog(
        tester,
        kind: BatchSettleKind.setAsides,
        accounts: [bpi],
        destinations: [savings],
        savedDestinationCount: 3,
      );

      // Unticking "each keeps its own" means all three now need the shared
      // destination, so Fund blocks again until it is chosen.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final blocked = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Fund 3'));
      expect(blocked.onPressed, isNull);
      expect(find.text('Set aside into'), findsOneWidget);
    });

    testWidgets('cancelling returns null', (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.bills,
        accounts: [bpi],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(captured.single, isNull);
    });

    testWidgets('with no account that covers the whole selection, it says so',
        (tester) async {
      final captured = await openDialog(
        tester,
        kind: BatchSettleKind.bills,
        accounts: const [],
      );

      expect(find.textContaining('No account can cover'), findsOneWidget);

      // It still goes through — the bills are flagged paid with no ledger
      // entry rather than the batch failing outright.
      await tester.tap(find.widgetWithText(FilledButton, 'Mark 3 paid'));
      await tester.pumpAndSettle();
      expect(captured.single!.accountId, isNull);
    });
  });

  group('batch bar', () {
    Widget bar({
      int selected = 3,
      int settleable = 2,
      int undoable = 1,
      bool enabled = true,
      VoidCallback? onSettle,
      VoidCallback? onUndo,
      VoidCallback? onDelete,
    }) =>
        wrap(WebBatchBar(
          settleVerb: 'Pay',
          selectedCount: selected,
          settleableCount: settleable,
          undoableCount: undoable,
          enabled: enabled,
          onSettle: onSettle ?? () {},
          onUndo: onUndo ?? () {},
          onDelete: onDelete ?? () {},
        ));

    testWidgets('counts what each action would actually touch', (tester) async {
      await tester.pumpWidget(bar());

      expect(find.text('3 selected'), findsOneWidget);
      expect(find.text('Pay 2'), findsOneWidget);
      expect(find.text('Undo 1'), findsOneWidget);
      expect(find.text('Delete 3'), findsOneWidget);
    });

    testWidgets('an action with nothing to act on is disabled, not hidden',
        (tester) async {
      await tester.pumpWidget(bar(settleable: 0, undoable: 0));

      // Visible so the bar doesn't reflow as the selection changes, but inert.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pay 0'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Undo 0'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('everything is inert while a batch is in flight',
        (tester) async {
      await tester.pumpWidget(bar(enabled: false));

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pay 2'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Delete 3'))
            .onPressed,
        isNull,
      );
    });
  });

  group('select control', () {
    Widget control({
      bool active = false,
      bool locked = false,
      int selected = 0,
      int total = 5,
      VoidCallback? onStart,
      VoidCallback? onToggleAll,
    }) =>
        wrap(WebBatchSelectControl(
          active: active,
          locked: locked,
          selectedCount: selected,
          totalCount: total,
          onStart: onStart ?? () {},
          onCancel: () {},
          onToggleAll: onToggleAll ?? () {},
        ));

    testWidgets('offers Select when idle', (tester) async {
      await tester.pumpWidget(control());
      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('is disabled while another section owns the selection',
        (tester) async {
      await tester.pumpWidget(control(locked: true));

      // Disabled rather than hidden: it explains why this section went quiet.
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Select'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('is disabled when the section has no rows', (tester) async {
      await tester.pumpWidget(control(total: 0));
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Select'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('shows the count and flips to Clear all when everything is in',
        (tester) async {
      await tester.pumpWidget(control(active: true, selected: 2, total: 5));
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

      await tester.pumpWidget(control(active: true, selected: 5, total: 5));
      expect(find.text('Clear all'), findsOneWidget);
    });
  });
}
