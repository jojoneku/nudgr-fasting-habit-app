import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/views/app_theme.dart';
import 'package:intermittent_fasting/views/treasury/shared/settle_sheet.dart';
import 'package:intermittent_fasting/views/widgets/system/system.dart';

/// Plan 071 Phase 5: the one mobile Settle sheet. It only collects input and
/// hands a [SettleResult] to the caller's own presenter call; these tests pin
/// what it hands over for each kind, and that a failed save keeps it open.
void main() {
  FinancialAccount account(
    String id,
    String name, {
    double balance = 20000,
    AccountCategory category = AccountCategory.bank,
  }) =>
      FinancialAccount(
        id: id,
        name: name,
        category: category,
        balance: balance,
        colorHex: '#FFFFFF',
        icon: 'wallet',
      );

  final bpi = account('bpi', 'BPI');
  final gcash = account('gcash', 'GCash', category: AccountCategory.ewallet);
  final maya = account('maya', 'Maya', category: AccountCategory.savings);

  /// Opens the sheet from a button and records what reached `onConfirm` and
  /// what `showSettleSheet` returned.
  Future<({List<SettleResult> confirmed, List<SettleResult?> returned})> open(
    WidgetTester tester, {
    required SettleKind kind,
    required List<SettleTarget> targets,
    List<FinancialAccount> payers = const [],
    List<FinancialAccount> destinations = const [],
    String? initialAccountId,
    Future<void> Function(SettleResult)? onConfirm,
    ThemeData? theme,
  }) async {
    final confirmed = <SettleResult>[];
    final returned = <SettleResult?>[];
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              returned.add(await showSettleSheet(
                ctx,
                kind: kind,
                targets: targets,
                payers: payers,
                destinations: destinations,
                initialAccountId: initialAccountId,
                onConfirm: onConfirm ??
                    (r) async {
                      confirmed.add(r);
                    },
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (confirmed: confirmed, returned: returned);
  }

  Finder amountField() => find.descendant(
        of: find.byKey(SettleSheetKeys.amount),
        matching: find.byType(EditableText),
      );

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(SettleSheetKeys.confirm));
    await tester.tap(find.byKey(SettleSheetKeys.confirm));
    await tester.pumpAndSettle();
  }

  bool confirmEnabled(WidgetTester tester) =>
      tester
          .widget<AppPrimaryButton>(find.byKey(SettleSheetKeys.confirm))
          .onPressed !=
      null;

  group('single mode, one test per kind', () {
    for (final (label, theme) in [
      ('dark', buildDarkTheme),
      ('light', buildLightTheme),
    ]) {
      testWidgets('bill: edited amount and picked account ($label)',
          (tester) async {
        final run = await open(
          tester,
          theme: theme(),
          kind: SettleKind.bill,
          targets: const [
            SettleTarget(
                id: 'b1', name: 'Meralco', amount: 500, accountId: 'bpi'),
          ],
          payers: [bpi, gcash],
        );

        expect(find.text('Mark Meralco paid'), findsOneWidget);
        await tester.enterText(amountField(), '420');
        await tester.tap(find.byKey(SettleSheetKeys.account));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GCash').last);
        await tester.pumpAndSettle();
        await confirm(tester);

        final r = run.confirmed.single;
        expect(r.amount, 420);
        expect(r.scheduledAmount, 500);
        expect(r.accountId, 'gcash');
        expect(r.recordInLedger, isTrue);
        expect(r.targetIds, ['b1']);
        expect(run.returned.single, same(r));
        expect(find.byType(SettleSheet), findsNothing);
      });
    }

    testWidgets('receivable: "Already added to ledger" sits under More options',
        (tester) async {
      final run = await open(
        tester,
        kind: SettleKind.receivable,
        targets: const [SettleTarget(id: 'r1', name: 'Salary', amount: 30000)],
        payers: [bpi],
      );

      expect(find.text('DEPOSIT INTO'), findsOneWidget);
      expect(find.byKey(SettleSheetKeys.alreadyLogged), findsNothing,
          reason: 'the toggle is folded away until asked for');
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettleSheetKeys.alreadyLogged));
      await tester.pumpAndSettle();
      // Nothing to deposit into when nothing is recorded.
      expect(find.byKey(SettleSheetKeys.account), findsNothing);

      await confirm(tester);
      final r = run.confirmed.single;
      expect(r.amount, 30000);
      expect(r.recordInLedger, isFalse);
      expect(r.accountId, isNull);
    });

    testWidgets('a collapsed More options fold still says the box is ticked',
        (tester) async {
      await open(
        tester,
        kind: SettleKind.bill,
        targets: const [SettleTarget(id: 'b1', name: 'Rent', amount: 15000)],
        payers: [bpi],
      );

      expect(find.text('Already added to ledger: off'), findsOneWidget);
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SettleSheetKeys.alreadyLogged));
      await tester.pumpAndSettle();

      // Collapse the fold again: the subtitle still names the state.
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      expect(find.byKey(SettleSheetKeys.alreadyLogged), findsNothing);
      expect(find.text('Already added to ledger: on, no new entry'),
          findsOneWidget);
      expect(find.text('Already added to ledger: off'), findsNothing);
    });

    testWidgets('set-aside: waits for a destination, then sends it',
        (tester) async {
      final run = await open(
        tester,
        kind: SettleKind.setAside,
        targets: const [
          SettleTarget(
              id: 's1', name: 'Travel Fund', amount: 5000, accountId: 'bpi'),
        ],
        payers: [bpi],
        destinations: [bpi, maya],
      );

      expect(find.text('Choose where it goes'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);
      expect(find.text('More options'), findsNothing,
          reason: 'a set-aside is the transfer, so there is no ledger toggle');

      await tester.tap(find.byKey(SettleSheetKeys.destination));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maya').last);
      await tester.pumpAndSettle();
      expect(confirmEnabled(tester), isTrue);

      await confirm(tester);
      final r = run.confirmed.single;
      expect(r.accountId, 'bpi');
      expect(r.destinationId, 'maya');
      expect(r.amount, 5000);
    });

    testWidgets('set-aside with no destination accounts just spends it',
        (tester) async {
      final run = await open(
        tester,
        kind: SettleKind.setAside,
        targets: const [SettleTarget(id: 's1', name: 'Gift', amount: 800)],
        payers: [bpi],
      );
      expect(find.byKey(SettleSheetKeys.destination), findsNothing);
      await confirm(tester);
      expect(run.confirmed.single.destinationId, isNull);
    });

    testWidgets('installment: no account, the typed amount', (tester) async {
      final run = await open(
        tester,
        kind: SettleKind.installment,
        targets: const [
          SettleTarget(id: 'i1', name: 'Laptop (3/12)', amount: 2166),
        ],
      );

      expect(find.text('Mark Laptop (3/12) paid'), findsOneWidget);
      expect(find.byKey(SettleSheetKeys.account), findsNothing);
      expect(find.text('More options'), findsNothing);
      await tester.enterText(amountField(), '2170');
      await confirm(tester);

      final r = run.confirmed.single;
      expect(r.amount, 2170);
      expect(r.accountId, isNull);
    });

    testWidgets('card payment: a partial payment from the picked account',
        (tester) async {
      final run = await open(
        tester,
        kind: SettleKind.cardPayment,
        targets: const [SettleTarget(id: 'cc', name: 'Rewards', amount: 2500)],
        payers: [bpi],
      );

      expect(find.text('Pay Rewards'), findsOneWidget);
      await tester.enterText(amountField(), '1000');
      await confirm(tester);

      final r = run.confirmed.single;
      expect(r.amount, 1000);
      expect(r.accountId, 'bpi');
      expect(r.isPartial, isTrue);
    });
  });

  testWidgets('batch mode lists each row and settles each for its own amount',
      (tester) async {
    final run = await open(
      tester,
      kind: SettleKind.bill,
      targets: const [
        SettleTarget(id: 'b1', name: 'Meralco', amount: 500),
        SettleTarget(id: 'b2', name: 'Maynilad', amount: 300),
      ],
      payers: [bpi],
    );

    expect(find.text('Pay 2 bills'), findsOneWidget);
    // No shared amount to edit: each row keeps its own.
    expect(find.byKey(SettleSheetKeys.amount), findsNothing);
    final rows = find.byKey(SettleSheetKeys.batchRows);
    expect(find.descendant(of: rows, matching: find.text('₱500.00')),
        findsOneWidget);
    expect(find.descendant(of: rows, matching: find.text('₱300.00')),
        findsOneWidget);

    await confirm(tester);
    final r = run.confirmed.single;
    expect(r.targetIds, ['b1', 'b2']);
    expect(r.amount, 800);
    expect(r.accountId, 'bpi');
  });

  testWidgets('a batch with no eligible account still settles, off-ledger',
      (tester) async {
    final run = await open(
      tester,
      kind: SettleKind.bill,
      targets: const [
        SettleTarget(id: 'b1', name: 'Meralco', amount: 500),
        SettleTarget(id: 'b2', name: 'Maynilad', amount: 300),
      ],
    );
    expect(find.textContaining('No account can cover'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
    await confirm(tester);
    expect(run.confirmed.single.accountId, isNull);
  });

  testWidgets('a short balance is named but does not block', (tester) async {
    final thin = account('thin', 'Wallet', balance: 300);
    final run = await open(
      tester,
      kind: SettleKind.bill,
      targets: const [SettleTarget(id: 'b1', name: 'Meralco', amount: 500)],
      payers: [thin],
    );

    expect(find.byKey(SettleSheetKeys.shortBalance), findsOneWidget);
    expect(find.textContaining('short by ₱200.00'), findsOneWidget);

    // Lowering the amount below the balance clears the note.
    await tester.enterText(amountField(), '250');
    await tester.pump();
    expect(find.byKey(SettleSheetKeys.shortBalance), findsNothing);

    await tester.enterText(amountField(), '500');
    await tester.pump();
    expect(confirmEnabled(tester), isTrue);
    await confirm(tester);
    expect(run.confirmed.single.amount, 500);
  });

  testWidgets('a card payment above what is owed is blocked', (tester) async {
    final run = await open(
      tester,
      kind: SettleKind.cardPayment,
      targets: const [SettleTarget(id: 'cc', name: 'Rewards', amount: 2500)],
      payers: [bpi],
    );

    await tester.enterText(amountField(), '3000');
    await confirm(tester);

    expect(run.confirmed, isEmpty);
    expect(find.text('More than the ₱2,500.00 owed'), findsOneWidget);
    expect(find.byType(SettleSheet), findsOneWidget);
  });

  testWidgets('a failed save shows an error and keeps the sheet open',
      (tester) async {
    final run = await open(
      tester,
      kind: SettleKind.bill,
      targets: const [SettleTarget(id: 'b1', name: 'Meralco', amount: 500)],
      payers: [bpi],
      onConfirm: (_) async => throw StateError('disk full'),
    );

    await tester.enterText(amountField(), '480');
    await confirm(tester);

    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(find.byType(SettleSheet), findsOneWidget);
    expect(run.returned, isEmpty, reason: 'the sheet did not close');
    // The typed value is still there to retry with.
    expect(find.text('480'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
  });
}
