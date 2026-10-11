import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_bills_forms_v2.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_bills_page_v2.dart';
import 'package:intermittent_fasting/views/web/pages/bills/web_statement_breakdown_dialog.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 Bills page (Plan 063, Phase 5) against the preview seed: one header
/// with one Add ▾ menu, a due-soon hero, ONE tabbed list whose counts are the
/// presenter's lists, a bill in exactly one tab, batch selection into the
/// unified Settle dialog, Pay now on a credit line into the same dialog, the
/// statement items link, and a side column whose figures are the presenter's
/// totals — at three widths, in both modes.
void main() {
  const widths = [1440.0, 1100.0, 760.0];
  const modes = [true, false];
  String mode(bool dark) => dark ? 'dark' : 'light';

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

  /// Builds the seeded presenter pair on the real clock — the ledger's async
  /// load never settles under the test binding's fake clock.
  Future<(BillsReceivablesPresenter, InstallmentPresenter)> seeded(
      WidgetTester tester) async {
    late BillsReceivablesPresenter bills;
    late InstallmentPresenter plans;
    await tester.runAsync(() async {
      final ledger = LedgerPresenter(storage, stats);
      bills = BillsReceivablesPresenter(storage, ledger, stats);
      plans = InstallmentPresenter(storage, ledger, stats);
      await bills.load();
      await plans.load();
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    return (bills, plans);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required BillsReceivablesPresenter bills,
    required InstallmentPresenter plans,
    double width = 1440,
    bool dark = true,
  }) async {
    // Tall enough that nothing needs scrolling into view before a tap.
    tester.view.physicalSize = Size(width, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebBillsPageV2(presenter: bills, installmentPresenter: plans),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String plural(int n, String one) => n == 1 ? one : '${one}s';

  /// Unpaid bills in the order the Upcoming tab lists them: the due-soon group
  /// first, each group by due day.
  List<Bill> upcomingOrder(BillsReceivablesPresenter bills) {
    final unpaid = [...bills.bills.where((b) => !b.isPaid)]
      ..sort((a, b) => a.dueDay.compareTo(b.dueDay));
    final soon = {for (final b in bills.imminentUnpaidBills) b.id};
    return [
      ...unpaid.where((b) => soon.contains(b.id)),
      ...unpaid.where((b) => !soon.contains(b.id)),
    ];
  }

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(WebDialog), matching: matching);

  Future<void> closeDialog(WidgetTester tester, Key cancel) async {
    await tester.tap(find.byKey(cancel));
    await tester.pumpAndSettle();
    expect(find.byType(WebDialog), findsNothing);
  }

  /// Every parity key the page attaches with seeded data.
  const parityKeys = <Key>[
    WebKeys.billsMonthStepper,
    WebKeys.billsAddMenu,
    BillsV2Keys.listCard,
    WebKeys.billsTabUpcoming,
    WebKeys.billsTabSetAsides,
    WebKeys.billsTabReceivables,
    WebKeys.billsTabInstallments,
    WebKeys.billsTabPaid,
    WebKeys.billsBatchSelect,
    WebKeys.billsCreditCards,
    WebKeys.billsThisMonth,
    WebKeys.billsByAccount,
    WebKeys.billsComingUp,
  ];

  group('parity', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets('header, keys and cards at $width px in ${mode(dark)}',
            (tester) async {
          final (bills, plans) = await seeded(tester);
          await pumpPage(tester,
              bills: bills, plans: plans, width: width, dark: dark);

          expect(find.text('Bills'), findsOneWidget);
          final total = bills.bills.length;
          final unpaid = bills.bills.where((b) => !b.isPaid).length;
          expect(
            find.text('${monthLabel(bills.selectedMonth)} · $total '
                '${plural(total, 'bill')}, $unpaid still due · '
                '${bills.pendingReceivables.length} to receive · '
                '${formatPeso(bills.totalBillsPending)} unpaid'),
            findsOneWidget,
          );
          expect(find.text('Add'), findsOneWidget);

          for (final key in parityKeys) {
            expect(find.byKey(key), findsOneWidget, reason: '$key');
          }
          // The hero shows only when something is due within the week.
          expect(
            find.byKey(WebKeys.billsHero),
            bills.imminentUnpaidBills.isEmpty ? findsNothing : findsOneWidget,
          );
          // One Pay now per credit line with a balance.
          final owing =
              bills.creditAccounts.where((c) => c.currentPayable > 0).length;
          expect(find.byKey(WebKeys.billsPayCard), findsNWidgets(owing));

          for (final title in [
            'Credit cards & lines',
            'This month',
            'By account',
            'Coming up',
          ]) {
            expect(find.text(title), findsOneWidget, reason: title);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('tabs', () {
    testWidgets('each count is the length of the presenter list behind it',
        (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);

      final expected = <Key, int>{
        WebKeys.billsTabUpcoming: bills.bills.where((b) => !b.isPaid).length,
        WebKeys.billsTabSetAsides: bills.budgetedExpenses.length,
        WebKeys.billsTabReceivables: bills.receivables.length,
        WebKeys.billsTabInstallments: plans.dueThisMonth.length,
        WebKeys.billsTabPaid: bills.bills.where((b) => b.isPaid).length,
      };
      for (final entry in expected.entries) {
        expect(
          find.descendant(
            of: find.byKey(entry.key),
            matching: find.text('${entry.value}'),
          ),
          findsOneWidget,
          reason: '${entry.key} → ${entry.value}',
        );
      }
      // The seed exercises every tab.
      expect(expected.values.every((n) => n > 0), isTrue);
    });

    testWidgets('a bill is in exactly one tab besides the hero',
        (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);

      Finder inList(String name) => find.descendant(
            of: find.byKey(BillsV2Keys.listCard),
            matching: find.text(name),
          );
      // Statement rows are titled after their card, so compare plain bills.
      final plain =
          bills.bills.where((b) => bills.statementCard(b) == null).toList();
      final unpaid = plain.where((b) => !b.isPaid).toList();
      final paid = plain.where((b) => b.isPaid).toList();
      expect(unpaid, isNotEmpty);
      expect(paid, isNotEmpty);

      // Upcoming: every unpaid bill once, no paid bill.
      for (final b in unpaid) {
        expect(inList(b.name), findsOneWidget, reason: b.name);
      }
      for (final b in paid) {
        expect(inList(b.name), findsNothing, reason: b.name);
      }

      await tester.tap(find.byKey(WebKeys.billsTabPaid));
      await tester.pumpAndSettle();

      // Paid: the reverse.
      for (final b in paid) {
        expect(inList(b.name), findsOneWidget, reason: b.name);
      }
      for (final b in unpaid) {
        expect(inList(b.name), findsNothing, reason: b.name);
      }
    });
  });

  group('Add ▾', () {
    testWidgets('opens the four forms', (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);

      final forms = <Key, String>{
        WebKeys.billsAddBill: 'Something you pay on a date.',
        WebKeys.billsAddReceivable: 'Money someone owes you.',
        WebKeys.billsAddSetAside:
            'A planned amount to move into a fund this month.',
        WebKeys.billsAddInstallment:
            'A purchase paid over several card statements.',
      };
      for (final entry in forms.entries) {
        await tester.tap(find.byKey(WebKeys.billsAddMenu));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(entry.key));
        await tester.pumpAndSettle();

        expect(find.byType(WebDialog), findsOneWidget, reason: '${entry.key}');
        expect(find.text(entry.value), findsOneWidget);

        await closeDialog(tester, WebKeys.billsDialogCancel);
      }
    });
  });

  group('settling', () {
    testWidgets('Select → Pay 2 opens the Settle dialog in batch mode',
        (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);
      final rows = upcomingOrder(bills);
      expect(rows.length, greaterThanOrEqualTo(2));

      await tester.tap(find.descendant(
        of: find.byKey(WebKeys.billsBatchSelect),
        matching: find.text('Select'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(BillsV2Keys.batchBar), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Pay 2'));
      await tester.pumpAndSettle();

      expect(find.text('Pay 2 bills'), findsOneWidget);
      // The two picked rows are listed; nothing is editable per row.
      expect(inDialog(find.text(rows[0].name)), findsOneWidget);
      expect(inDialog(find.text(rows[1].name)), findsOneWidget);
      expect(find.byKey(WebKeys.billsSettleAmount), findsNothing);
      expect(find.text('Mark 2 paid'), findsOneWidget);

      await closeDialog(tester, WebKeys.billsSettleCancel);
      // Cancelling keeps the selection.
      expect(find.byKey(BillsV2Keys.batchBar), findsOneWidget);
    });

    testWidgets('Mark paid on a row opens single mode prefilled',
        (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);
      final first = upcomingOrder(bills).first;

      await tester.tap(find.byKey(BillsV2Keys.rowSettle).first);
      await tester.pumpAndSettle();

      expect(find.text('Mark ${first.name} paid'), findsOneWidget);
      final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(WebKeys.billsSettleAmount),
        matching: find.byType(TextField),
      ));
      expect(field.controller!.text,
          bills.billAmountOwed(first).toStringAsFixed(2));
      expect(find.byKey(WebKeys.billsSettleAccount), findsOneWidget);
      expect(find.byKey(WebKeys.billsSettleAlreadyLogged), findsOneWidget);

      await closeDialog(tester, WebKeys.billsSettleCancel);
    });

    testWidgets('Pay now on a credit line opens the card-payment kind',
        (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);
      final card = bills.creditAccounts.firstWhere((c) => c.currentPayable > 0);

      await tester.tap(find.byKey(WebKeys.billsPayCard).first);
      await tester.pumpAndSettle();

      expect(find.text('Pay ${card.name}'), findsOneWidget);
      expect(
        find.textContaining('You owe ${formatPeso(card.currentPayable)}'),
        findsOneWidget,
      );
      // A card payment is a transfer: no ledger opt-out.
      expect(find.byKey(WebKeys.billsSettleAlreadyLogged), findsNothing);

      await closeDialog(tester, WebKeys.billsSettleCancel);
    });

    testWidgets('the statement items link opens the breakdown', (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);
      final statements =
          bills.bills.where((b) => bills.statementCard(b) != null).toList();
      expect(statements, isNotEmpty);
      expect(statements.every((b) => b.isPaid), isTrue,
          reason: 'the seed files its card statements as paid');

      await tester.tap(find.byKey(WebKeys.billsTabPaid));
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.billsRowStatementItems),
          findsNWidgets(statements.length));

      await tester.tap(find.byKey(WebKeys.billsRowStatementItems).first);
      await tester.pumpAndSettle();

      expect(find.byType(WebStatementBreakdownDialog), findsOneWidget);
    });
  });

  group('side column', () {
    testWidgets('This month carries the presenter totals', (tester) async {
      final (bills, plans) = await seeded(tester);
      await pumpPage(tester, bills: bills, plans: plans);

      final card = find.byKey(WebKeys.billsThisMonth);
      Finder inCard(String text) =>
          find.descendant(of: card, matching: find.text(text));

      final setAsides = bills.budgetedExpenses
          .where((e) => !e.isPaid)
          .fold(0.0, (s, e) => s + e.allocatedAmount);
      final expected = <String, String>{
        'Due this month': formatPeso(bills.totalBillsPending),
        'Paid': formatPeso(bills.totalBillsPaid),
        'Total this month': formatPeso(bills.totalBillsAmount),
        'To receive': '+${formatPeso(bills.totalReceivablesPending)}',
        'Set-asides to fund': formatPeso(setAsides),
        'Installments': formatPeso(plans.monthlyInstallmentLoad),
      };
      for (final entry in expected.entries) {
        expect(inCard(entry.key), findsOneWidget, reason: entry.key);
        // Two rows may legitimately share a figure, so at least one.
        expect(inCard(entry.value), findsWidgets,
            reason: '${entry.key} → ${entry.value}');
      }
      // The seed has money due, paid and owed, so the figures are non-zero.
      expect(bills.totalBillsPending, greaterThan(0));
      expect(bills.totalBillsPaid, greaterThan(0));
      expect(bills.totalReceivablesPending, greaterThan(0));
    });
  });
}
