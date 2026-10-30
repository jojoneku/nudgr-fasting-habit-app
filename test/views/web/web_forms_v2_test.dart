import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/category_icon_catalog.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/treasury/bills/installment_review_panel.dart';
import 'package:intermittent_fasting/views/treasury/bills/statement_breakdown_sheet.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_bills_forms_v2.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_statement_breakdown_dialog.dart';
import 'package:intermittent_fasting/views/web/pages/budget/web_manage_groups_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/pages/budget/web_new_category_dialog.dart';
import 'package:intermittent_fasting/views/web/pages/dashboard/web_account_inventory_dialog.dart';
import 'package:intermittent_fasting/views/web/pages/goals/web_goals_page.dart';
import 'package:intermittent_fasting/views/web/pages/history/web_month_detail_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/pages/ledger/web_transaction_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/pages/setup/web_account_form_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_receipt_drop.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// Phase 10 forms pass: one smoke test per v2 dialog against the preview
/// seed — it opens on the kit, a required field is flagged rather than saved,
/// Enter in a single-line field submits a valid form, and Esc closes it.
///
/// Plus the kit contract the dialogs lean on: `WebDialog.onSubmit` reaches
/// every single-line `WebInput` that has no submit of its own, skips the
/// `TextInputAction.next` fields and the multiline notes, the first field
/// takes focus on open, and the dialog is announced by its title.
void main() {
  late LocalStorageService storage;
  late MockStatsPresenter stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = LocalStorageService();
    await storage.setUserId(PreviewSeed.userId);
    await PreviewSeed.seedInto(storage);
    stats = MockStatsPresenter();
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  /// The ledger on the real clock — its load never settles on the fake one.
  Future<LedgerPresenter> ledger(WidgetTester tester) async {
    late LedgerPresenter p;
    await tester.runAsync(() async {
      p = LedgerPresenter(storage, stats);
      while (p.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    return p;
  }

  Future<(BillsReceivablesPresenter, InstallmentPresenter)> billsAndPlans(
      WidgetTester tester) async {
    late BillsReceivablesPresenter bills;
    late InstallmentPresenter plans;
    await tester.runAsync(() async {
      final l = LedgerPresenter(storage, stats);
      bills = BillsReceivablesPresenter(storage, l, stats);
      plans = InstallmentPresenter(storage, l, stats);
      await bills.load();
      await plans.load();
      while (l.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    return (bills, plans);
  }

  Future<TreasuryDashboardPresenter> dashboard(WidgetTester tester) async {
    late TreasuryDashboardPresenter dash;
    await tester.runAsync(() async {
      dash = TreasuryDashboardPresenter(storage);
      await dash.load();
    });
    return dash;
  }

  const openKey = Key('open');

  /// A host page with one button that runs [open] with a page context, then
  /// taps it so the dialog is up when the test continues.
  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open, {
    Widget? page,
  }) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildWebDarkTheme(),
      home: Scaffold(
        body: page ??
            Builder(
              builder: (context) => Center(
                child: FilledButton(
                  key: openKey,
                  onPressed: () => open(context),
                  child: const Text('open'),
                ),
              ),
            ),
      ),
    ));
    await tester.pumpAndSettle();
    if (page == null) {
      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
    }
  }

  /// Enter in the focused field, as the platform delivers it.
  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> esc(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> focus(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Finder dialog() => find.byType(WebDialog);

  group('WebDialog keyboard contract', () {
    testWidgets(
        'Enter in a plain field submits; a .next field and the notes do '
        'not; the first field has focus; the title is the semantics label',
        (tester) async {
      var submits = 0;
      final name = TextEditingController();
      final notes = TextEditingController();
      final nextField = TextEditingController();
      addTearDown(() {
        name.dispose();
        notes.dispose();
        nextField.dispose();
      });
      await pumpHost(
        tester,
        (context) => showWebDialog<void>(
          context,
          builder: (_) => WebDialog(
            title: 'Keyboard check',
            onSubmit: () => submits++,
            body: Column(
              children: [
                WebField(
                  label: 'Name',
                  child: WebInput(
                    key: const Key('name'),
                    controller: name,
                    autofocus: true,
                  ),
                ),
                WebField(
                  label: 'Next',
                  child: WebInput(
                    key: const Key('next'),
                    controller: nextField,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                WebField(
                  label: 'Notes',
                  child: WebInput.multiline(
                    key: const Key('notes'),
                    controller: notes,
                  ),
                ),
              ],
            ),
            primary: FilledButton(onPressed: () {}, child: const Text('Save')),
          ),
        ),
      );

      // Focus landed on the first field without a tap.
      final nameField = tester.widget<EditableText>(find.descendant(
          of: find.byKey(const Key('name')),
          matching: find.byType(EditableText)));
      expect(nameField.focusNode.hasFocus, isTrue);
      expect(
        find.bySemanticsLabel(RegExp('Keyboard check')),
        findsWidgets,
      );

      await enter(tester);
      expect(submits, 1);

      await focus(tester, const Key('next'));
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(submits, 1, reason: 'a .next field hands Enter on, not down');

      await focus(tester, const Key('notes'));
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pumpAndSettle();
      expect(submits, 1, reason: 'Enter in the notes is a newline');

      await esc(tester);
      expect(dialog(), findsNothing);
    });

    testWidgets('a null onSubmit means Enter does nothing', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await pumpHost(
        tester,
        (context) => showWebDialog<void>(
          context,
          builder: (_) => WebDialog(
            title: 'Disabled',
            body: WebInput(controller: c, autofocus: true),
            primary: const FilledButton(onPressed: null, child: Text('Save')),
          ),
        ),
      );
      await enter(tester);
      expect(dialog(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await esc(tester);
      expect(dialog(), findsNothing);
    });
  });

  group('Ledger', () {
    testWidgets('Add / Edit transaction', (tester) async {
      final l = await ledger(tester);
      await pumpHost(tester,
          (context) => showWebTransactionDialogV2(context, presenter: l));
      expect(find.byType(WebTransactionDialogV2), findsOneWidget);
      expect(find.text('Add transaction'), findsWidgets);

      // The amount has focus; Enter on a blank form flags it, nothing saves.
      final before = l.allTransactions.length;
      await enter(tester);
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.byType(WebTransactionDialogV2), findsOneWidget);
      expect(l.allTransactions.length, before);
      await esc(tester);
      expect(find.byType(WebTransactionDialogV2), findsNothing);

      // A seeded expense is a valid form: Enter in the amount saves it.
      final existing = l.allTransactions.firstWhere((t) =>
          t.type == TransactionType.outflow && t.transferGroupId == null);
      await pumpHost(
        tester,
        (context) => showWebTransactionDialogV2(
          context,
          presenter: l,
          existing: existing,
        ),
      );
      expect(find.text('Edit transaction'), findsWidgets);
      await tester.enterText(find.byKey(WebKeys.ledgerDialogAmount), '123.45');
      await enter(tester);
      await tester.pumpAndSettle();
      expect(find.byType(WebTransactionDialogV2), findsNothing);
      expect(
        l.allTransactions.firstWhere((t) => t.id == existing.id).amount,
        123.45,
      );
    });

    testWidgets('Scan a receipt', (tester) async {
      final l = await ledger(tester);
      await pumpHost(
          tester, (context) => showWebReceiptDialog(context, ledger: l));
      expect(find.text('Scan a receipt'), findsOneWidget);
      expect(find.byKey(WebKeys.ledgerReceiptDropZone), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(WebKeys.ledgerReceiptScan))
            .onPressed,
        isNull,
        reason: 'nothing to scan until a photo is staged',
      );
      await esc(tester);
      expect(dialog(), findsNothing);
    });
  });

  group('Bills', () {
    testWidgets('Add / Edit bill', (tester) async {
      final (bills, _) = await billsAndPlans(tester);
      await pumpHost(
          tester, (context) => showWebBillDialog(context, presenter: bills));
      expect(find.text('Add bill'), findsWidgets);
      expect(find.text('Something you pay on a date.'), findsOneWidget);

      final before = bills.bills.length;
      // The name field takes focus; its Enter moves on (.next), so the blank
      // form is submitted from the primary and flags the name.
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(bills.bills.length, before);
      await esc(tester);
      expect(dialog(), findsNothing);

      final existing = bills.bills.first;
      await pumpHost(
        tester,
        (context) =>
            showWebBillDialog(context, presenter: bills, existing: existing),
      );
      expect(find.text('Edit bill'), findsWidgets);
      // Enter in the last single-line field (the payment note, under More
      // options) submits the valid form.
      await tester.ensureVisible(find.byKey(WebKeys.billsDialogMoreOptions));
      await tester.tap(find.byKey(WebKeys.billsDialogMoreOptions));
      await tester.pumpAndSettle();
      await focus(tester, WebKeys.billsFormNote);
      await enter(tester);
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
      expect(bills.bills.length, before);
    });

    testWidgets('Add / Edit receivable', (tester) async {
      final (bills, _) = await billsAndPlans(tester);
      await pumpHost(tester,
          (context) => showWebReceivableDialog(context, presenter: bills));
      expect(find.text('Add receivable'), findsWidgets);
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);

      final existing = bills.allReceivables.first;
      await pumpHost(
        tester,
        (context) => showWebReceivableDialog(context,
            presenter: bills, existing: existing),
      );
      expect(find.text('Edit receivable'), findsWidgets);
      await focus(tester, WebKeys.billsFormAmount);
      await enter(tester);
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
    });

    testWidgets('Add / Edit set-aside', (tester) async {
      final (bills, _) = await billsAndPlans(tester);
      await pumpHost(tester,
          (context) => showWebSetAsideDialog(context, presenter: bills));
      expect(find.text('Add set-aside'), findsWidgets);
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);

      final existing = bills.allBudgetedExpenses.first;
      await pumpHost(
        tester,
        (context) => showWebSetAsideDialog(context,
            presenter: bills, existing: existing),
      );
      expect(find.text('Edit set-aside'), findsWidgets);
      await focus(tester, WebKeys.billsFormAmount);
      await enter(tester);
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
    });

    testWidgets('Add / Edit installment', (tester) async {
      final (_, plans) = await billsAndPlans(tester);
      await pumpHost(tester,
          (context) => showWebInstallmentDialog(context, presenter: plans));
      expect(find.text('Add installment'), findsWidgets);
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);

      final existing = plans.allInstallments.first;
      await pumpHost(
        tester,
        (context) => showWebInstallmentDialog(context,
            presenter: plans, existing: existing),
      );
      expect(find.text('Edit installment'), findsWidgets);
      await tester.ensureVisible(find.byKey(WebKeys.billsDialogMoreOptions));
      await tester.tap(find.byKey(WebKeys.billsDialogMoreOptions));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(WebKeys.billsFormNote));
      await focus(tester, WebKeys.billsFormNote);
      await enter(tester);
      await tester.pumpAndSettle();
      // Enter opens the review page; nothing is saved until it is confirmed.
      expect(find.byKey(InstallmentReviewKeys.panel), findsOneWidget);
      expect(dialog(), findsOneWidget);
      await tester.tap(find.byKey(InstallmentReviewKeys.confirm));
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
    });

    testWidgets('Installment paying for someone: review, back, confirm',
        (tester) async {
      final (bills, plans) = await billsAndPlans(tester);
      final before = plans.allInstallments.length;
      await pumpHost(
        tester,
        (context) => showWebInstallmentDialog(context,
            presenter: plans, receivables: bills),
      );
      await tester.enterText(
          find.byKey(WebKeys.billsFormName), 'Xiaomi Redmi Note 15');
      await tester.enterText(find.byKey(WebKeys.billsFormTotal), '12000');
      await tester.ensureVisible(find.byKey(WebKeys.billsFormPaidFor));
      await tester.tap(find.byKey(WebKeys.billsFormPaidFor));
      await tester.pumpAndSettle();

      // The person is required while the toggle is on.
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.text('Who is it for?'), findsWidgets);
      expect(find.byKey(InstallmentReviewKeys.panel), findsNothing);

      await tester.enterText(find.byKey(WebKeys.billsFormPaidForName), 'Papa');
      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      expect(find.byKey(InstallmentReviewKeys.panel), findsOneWidget);
      expect(find.text('Receivables from Papa'), findsOneWidget);
      expect(find.text('12 new'), findsOneWidget);
      expect(plans.allInstallments.length, before);

      // Back keeps what was typed.
      await tester.tap(find.byKey(InstallmentReviewKeys.back));
      await tester.pumpAndSettle();
      expect(find.byKey(InstallmentReviewKeys.panel), findsNothing);
      expect(find.text('Xiaomi Redmi Note 15'), findsOneWidget);
      expect(plans.allInstallments.length, before);

      await tester.tap(find.byKey(WebKeys.billsDialogSubmit));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(InstallmentReviewKeys.confirm));
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
      final saved = plans.allInstallments
          .firstWhere((p) => p.name == 'Xiaomi Redmi Note 15');
      expect(saved.paidForName, 'Papa');
    });

    testWidgets('Settle (mark paid)', (tester) async {
      final l = await ledger(tester);
      final payers = l.accounts.where((a) => a.isLiquid).toList();
      SettleResult? result;
      Future<void> open(BuildContext context) async {
        result = await showWebSettleDialog(
          context,
          kind: SettleKind.bill,
          targets: const [
            SettleTarget(id: 'b1', name: 'Electricity', amount: 1600),
          ],
          accounts: payers,
        );
      }

      await pumpHost(tester, open);
      expect(find.text('Mark Electricity paid'), findsOneWidget);
      // Blank the amount: Enter flags it instead of settling.
      await tester.enterText(find.byKey(WebKeys.billsSettleAmount), '');
      await enter(tester);
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(dialog(), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
      expect(result, isNull);

      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
      await enter(tester);
      expect(dialog(), findsNothing);
      expect(result?.amount, 1600);
    });

    testWidgets('Recurring scope', (tester) async {
      Object? scope;
      Future<void> open(BuildContext context) async {
        scope = await showWebRecurringScopeDialog(
          context,
          title: 'Delete Internet',
          subtitle: 'This bill repeats every month.',
          month: toMonthKey(DateTime.now()),
          noun: 'bill',
        );
      }

      await pumpHost(tester, open);
      expect(find.text('Only this month'), findsOneWidget);
      expect(find.text('This and future months'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
      expect(scope, isNull);

      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.billsScopeConfirm));
      await tester.pumpAndSettle();
      expect(scope, isNotNull);
    });

    testWidgets('Undo settlement', (tester) async {
      Object? choice;
      Future<void> open(BuildContext context) async {
        choice = await showWebUndoSettlementDialog(
          context,
          title: 'Undo payment?',
          name: 'Electricity',
          entryLabel: 'bill',
          hasLedgerEntry: true,
          ledgerEffect: '₱1,600.00 goes back into GCASH.',
        );
      }

      await pumpHost(tester, open);
      expect(find.text('Undo payment?'), findsOneWidget);
      expect(find.byKey(WebKeys.billsUndoRemoveTransaction), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
      expect(choice, isNull);

      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.billsUndoConfirm));
      await tester.pumpAndSettle();
      expect(choice, isNotNull);
    });

    testWidgets('Statement items: wide kit dialog, Pay now, item opens Edit',
        (tester) async {
      final (bills, _) = await billsAndPlans(tester);
      final statement =
          bills.bills.firstWhere((b) => bills.statementCard(b) != null);
      var paid = 0;
      await pumpHost(
        tester,
        (context) => showWebStatementBreakdownDialog(
          context,
          presenter: bills,
          bill: statement.copyWith(isPaid: false),
          onPayNow: () async => paid++,
        ),
      );
      expect(find.byType(WebStatementBreakdownDialog), findsOneWidget);
      expect(tester.widget<WebDialog>(dialog()).width, kWebDialogWideWidth);
      expect(find.byKey(WebKeys.billsStatementClose), findsOneWidget);
      expect(find.byKey(WebKeys.billsStatementPayNow), findsOneWidget);
      expect(find.text('Unpaid amount'), findsOneWidget);

      // An item opens the v2 transaction dialog on that record.
      final row = find.byType(StatementLineRow).first;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(WebTransactionDialogV2), findsOneWidget);
      await esc(tester);
      expect(find.byType(WebTransactionDialogV2), findsNothing);
      expect(find.byType(WebStatementBreakdownDialog), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.billsStatementPayNow));
      await tester.pumpAndSettle();
      expect(find.byType(WebStatementBreakdownDialog), findsNothing);
      expect(paid, 1);

      // A paid statement offers Close only.
      await pumpHost(
        tester,
        (context) => showWebStatementBreakdownDialog(
          context,
          presenter: bills,
          bill: statement,
          onPayNow: () async => paid++,
        ),
      );
      expect(find.byKey(WebKeys.billsStatementPayNow), findsNothing);
      await tester.tap(find.byKey(WebKeys.billsStatementClose));
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
    });
  });

  group('Budget and History', () {
    testWidgets('New category', (tester) async {
      final l = await ledger(tester);
      Object? created;
      Future<void> open(BuildContext context) async {
        created =
            await showWebNewCategoryDialog(context, existing: l.categories);
      }

      await pumpHost(tester, open);
      expect(find.text('New expense category'), findsOneWidget);
      await enter(tester);
      expect(find.text('Give the category a name.'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
      expect(created, isNull);

      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(WebKeys.budgetNewCategoryName), 'Pet care');
      await enter(tester);
      expect(dialog(), findsNothing);
      expect(created, isNotNull);
    });

    testWidgets('Manage groups and Rename group', (tester) async {
      late BudgetPresenter budget;
      await tester.runAsync(() async {
        budget =
            BudgetPresenter(storage, stats, null, MockNotificationService());
        await budget.load();
      });
      await pumpHost(tester,
          (context) => showWebManageGroupsDialogV2(context, presenter: budget));
      expect(find.text('Budget groups'), findsOneWidget);
      expect(find.byKey(WebKeys.budgetGroupsRename), findsWidgets);

      await tester.tap(find.byKey(WebKeys.budgetGroupsRename).first);
      await tester.pumpAndSettle();
      expect(find.text('Rename group'), findsOneWidget);
      // A blank name is not a rename: Enter keeps the prompt open.
      await tester.enterText(find.byKey(WebKeys.budgetGroupsRenameField), '');
      await enter(tester);
      expect(find.text('Rename group'), findsOneWidget);
      await tester.enterText(
          find.byKey(WebKeys.budgetGroupsRenameField), 'Trips');
      await enter(tester);
      expect(find.text('Rename group'), findsNothing);
      expect(budget.groups.any((g) => g.name == 'Trips'), isTrue);

      await esc(tester);
      expect(dialog(), findsNothing);
    });

    testWidgets('Month detail', (tester) async {
      late TreasuryHistoryPresenter history;
      await tester.runAsync(() async {
        history = TreasuryHistoryPresenter(storage);
        await history.load();
      });
      final s = history.summaries.first;
      await pumpHost(
        tester,
        (context) => showWebMonthDetailDialogV2(
          context,
          summary: s,
          categories: history.categories,
        ),
      );
      expect(find.byType(WebMonthDetailDialogV2), findsOneWidget);
      expect(tester.widget<WebDialog>(dialog()).width, kWebDialogWideWidth);
      expect(find.byKey(WebKeys.historyMonthDetailClose), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
    });
  });

  group('Setup, accounts and goals', () {
    testWidgets('Add / Edit account', (tester) async {
      final dash = await dashboard(tester);
      await pumpHost(
          tester, (context) => WebAccountFormDialogV2.show(context, dash));
      expect(find.text('Add account'), findsWidgets);
      final before = dash.accounts.length;
      await tester.tap(find.byKey(WebKeys.setupFormSave));
      await tester.pumpAndSettle();
      expect(find.text('Enter account name'), findsOneWidget);
      expect(dash.accounts.length, before);
      await esc(tester);
      expect(dialog(), findsNothing);

      final existing = dash.accounts.firstWhere((a) => a.isLiquid);
      await pumpHost(
        tester,
        (context) =>
            WebAccountFormDialogV2.show(context, dash, existing: existing),
      );
      expect(find.text('Save'), findsWidgets);
      // The balance is the form's last single-line field: Enter there saves.
      await focus(tester, WebKeys.setupFormBalance);
      await enter(tester);
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
      expect(dash.accounts.length, before);
    });

    testWidgets('Account inventory', (tester) async {
      final dash = await dashboard(tester);
      await pumpHost(
          tester,
          (context) =>
              WebAccountInventoryDialog.show(context, presenter: dash));
      expect(find.text('All accounts'), findsOneWidget);
      expect(tester.widget<WebDialog>(dialog()).width, kWebDialogWideWidth);
      await tester.tap(find.byKey(WebKeys.dashboardAccountInventoryClose));
      await tester.pumpAndSettle();
      expect(dialog(), findsNothing);
    });

    testWidgets('Choose an icon', (tester) async {
      await pumpHost(
        tester,
        (context) => showWebCategoryIconPicker(
          context,
          current: kAutoCategoryIconKey,
        ),
      );
      expect(find.text('Choose an icon'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      await esc(tester);
      expect(dialog(), findsNothing);
    });

    testWidgets('Add goal and Start again, from the Goals page',
        (tester) async {
      final dash = await dashboard(tester);
      await pumpHost(
        tester,
        (_) async {},
        page: WebGoalsPage(
          presenter: dash,
          onOpenBudget: () {},
          onOpenSetup: () {},
          onSetMonthlyAmount: (_) {},
        ),
      );
      final before = dash.activeGoalAccounts.length;

      await tester.tap(find.byKey(WebKeys.goalsAddGoal));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.goalsAddGoalDialog), findsOneWidget);
      // The target is the last single-line field: Enter there submits, and
      // the blank form is flagged.
      await focus(tester, WebKeys.goalsAddGoalTarget);
      await enter(tester);
      expect(find.text('Give the goal a name'), findsOneWidget);
      expect(find.text('Enter a target above ₱0'), findsOneWidget);
      await esc(tester);
      expect(find.byKey(WebKeys.goalsAddGoalDialog), findsNothing);

      await tester.tap(find.byKey(WebKeys.goalsAddGoal));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(WebKeys.goalsAddGoalName), 'Laptop Fund');
      await tester.enterText(find.byKey(WebKeys.goalsAddGoalTarget), '45000');
      await enter(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.goalsAddGoalDialog), findsNothing);
      expect(dash.activeGoalAccounts.length, before + 1);

      // Start again: from a card's ⋯ menu; the target is prefilled, so
      // Enter in it (the one field) restarts the goal.
      await tester.tap(find.byKey(WebKeys.goalsCardMenu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.goalsCardStartAgain));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.goalsStartAgainDialog), findsOneWidget);
      await esc(tester);
      expect(find.byKey(WebKeys.goalsStartAgainDialog), findsNothing);

      await tester.tap(find.byKey(WebKeys.goalsCardMenu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.goalsCardStartAgain));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(WebKeys.goalsStartAgainTarget), '9000');
      await enter(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.goalsStartAgainDialog), findsNothing);
    });
  });

  group('Confirm', () {
    testWidgets('showWebConfirm resolves false on Esc, true on confirm',
        (tester) async {
      bool? answer;
      Future<void> open(BuildContext context) async {
        answer = await showWebConfirm(
          context,
          title: 'Delete GoTyme?',
          message: 'It has no transactions and a ₱0 balance.',
        );
      }

      await pumpHost(tester, open);
      expect(find.text('Delete GoTyme?'), findsOneWidget);
      await esc(tester);
      expect(answer, isFalse);
      await tester.tap(find.byKey(openKey));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });
}
