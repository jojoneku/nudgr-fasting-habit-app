import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/monthly_summary.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/services/local_storage_service.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/dev/preview_seed.dart';
import 'package:intermittent_fasting/views/web/pages/setup/web_account_form_dialog_v2.dart';
import 'package:intermittent_fasting/views/web/pages/setup/web_categories_table_v2.dart';
import 'package:intermittent_fasting/views/web/pages/setup/web_setup_page_v2.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_widgets.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

/// The v2 Setup & Accounts page (Plan 063, Phase 8) against the preview seed:
/// the header switch moves between the Accounts and Categories tabs with
/// counts, the stat strip carries the presenter totals, the single
/// "Credit / target" column is filled only on credit and goal rows (never a
/// "—"), the overdrawn seed account is flagged, and every row action opens
/// the dialog it should.
void main() {
  // 760 is the content width beside the Nudgy rail.
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
  Future<(TreasuryDashboardPresenter, LedgerPresenter)> seeded(
      WidgetTester tester) async {
    late TreasuryDashboardPresenter dash;
    late LedgerPresenter ledger;
    await tester.runAsync(() async {
      dash = TreasuryDashboardPresenter(storage);
      await dash.load();
      ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    return (dash, ledger);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required TreasuryDashboardPresenter presenter,
    required LedgerPresenter ledger,
    double width = 1440,
    bool dark = true,
  }) async {
    // Tall enough that nothing needs scrolling into view before a tap.
    tester.view.physicalSize = Size(width, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(
        body: WebSetupPageV2(presenter: presenter, ledgerPresenter: ledger),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Every parity key the Accounts tab attaches with seeded data.
  const parityKeys = <Key>[
    WebKeys.setupAddAccount,
    WebKeys.setupTabAccounts,
    WebKeys.setupTabCategories,
    WebKeys.setupStatStrip,
    WebKeys.setupAccountsTable,
    kSetupStatLiquidKey,
    kSetupStatSavingsKey,
    kSetupStatCreditOwedKey,
    kSetupStatCreditAvailableKey,
  ];

  group('parity', () {
    for (final dark in modes) {
      for (final width in widths) {
        testWidgets('header, keys and rows at $width px in ${mode(dark)}',
            (tester) async {
          final (dash, ledger) = await seeded(tester);
          await pumpPage(tester,
              presenter: dash, ledger: ledger, width: width, dark: dark);

          expect(find.text('Setup & Accounts'), findsOneWidget);
          expect(
            find.textContaining('${dash.activeAccountCount} accounts'),
            findsOneWidget,
          );
          for (final key in parityKeys) {
            expect(find.byKey(key), findsOneWidget, reason: '$key');
          }
          // Every active top-level account is a row.
          for (final a in [
            ...dash.liquidAccounts,
            ...dash.goalAccounts,
            ...dash.creditAccounts,
          ]) {
            expect(find.text(a.name), findsOneWidget, reason: a.name);
          }
          expect(find.text('Pagibig'), findsOneWidget,
              reason: 'the investment account has a group too');
          // One inline type switcher per non-credit row; one ⋯ per row.
          final rows = dash.activeAccountCount;
          expect(find.byKey(kSetupRowMenuKey), findsNWidgets(rows));
          expect(find.byKey(WebKeys.setupRowType),
              findsNWidgets(rows - dash.creditAccounts.length));
          expect(find.byKey(WebKeys.setupRowEdit), findsNWidgets(rows));
          // "+" only on liquid parents.
          expect(find.byKey(WebKeys.setupRowAddPocket),
              findsNWidgets(dash.liquidAccounts.length));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('tabs', () {
    testWidgets('switch between Accounts and Categories and show counts',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final accountsTab = find.byKey(WebKeys.setupTabAccounts);
      final categoriesTab = find.byKey(WebKeys.setupTabCategories);
      expect(
        find.descendant(
            of: accountsTab, matching: find.text('${dash.activeAccountCount}')),
        findsOneWidget,
      );
      final listed = webListedCategories(ledger);
      // The reserved transfer category is system-owned and not a row.
      expect(listed.length, ledger.categories.length - 1);
      expect(
        find.descendant(
            of: categoriesTab, matching: find.text('${listed.length}')),
        findsOneWidget,
      );
      expect(find.byKey(WebKeys.setupAccountsTable), findsOneWidget);
      expect(find.byKey(WebKeys.setupCategoriesTable), findsNothing);

      await tester.tap(categoriesTab);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.setupCategoriesTable), findsOneWidget);
      expect(find.byKey(WebKeys.setupAccountsTable), findsNothing);
      expect(find.byKey(WebKeys.setupStatStrip), findsNothing);
      expect(find.byKey(WebKeys.setupCategoryAddRow), findsOneWidget);
      for (final c in listed) {
        expect(find.text(c.name), findsOneWidget, reason: c.name);
      }
      expect(find.text('Transfer'), findsNothing);
      // The header stays: Add account is reachable from either tab.
      expect(find.byKey(WebKeys.setupAddAccount), findsOneWidget);

      await tester.tap(accountsTab);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.setupAccountsTable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('stat strip', () {
    testWidgets('values equal the presenter totals', (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      Finder inStat(Key key, String text) =>
          find.descendant(of: find.byKey(key), matching: find.text(text));

      expect(inStat(kSetupStatLiquidKey, formatPeso(dash.totalLiquidCash)),
          findsOneWidget);
      expect(
          inStat(kSetupStatSavingsKey, formatPeso(dash.totalSavingsAndGoals)),
          findsOneWidget);
      expect(inStat(kSetupStatCreditOwedKey, formatPeso(dash.totalCreditOwed)),
          findsOneWidget);
      expect(
          inStat(kSetupStatCreditAvailableKey,
              formatPeso(dash.totalCreditAvailable)),
          findsOneWidget);
      // The seed has an overdrawn liquid account; the caption names it.
      expect(find.textContaining('Maribank is overdrawn'), findsOneWidget);
    });
  });

  group('credit / target column', () {
    testWidgets('is filled only on credit and goal rows, never "—"',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final creditWithLimit =
          dash.creditAccounts.where((a) => a.creditLimit != null).length;
      final goalsWithTarget =
          dash.goalAccounts.where((a) => a.hasGoalTarget).length;
      expect(creditWithLimit, greaterThan(0));
      expect(goalsWithTarget, greaterThan(0));

      expect(find.byKey(kSetupRowMeterKey),
          findsNWidgets(creditWithLimit + goalsWithTarget));
      expect(find.text('—'), findsNothing,
          reason: 'liquid rows leave the column empty');

      // A credit row reads "available of limit"; a goal row "N% of target".
      final card = dash.creditAccounts.firstWhere((a) => a.totalDebt > 0);
      expect(find.textContaining('of ₱${_whole(card.creditLimit!)}'),
          findsWidgets);
      final goal = dash.goalAccounts.firstWhere((a) => a.balance > 0);
      expect(
        find.text(
            '${formatPercent(goal.goalProgress)} of ₱${_whole(goal.goalTarget!)}'),
        findsOneWidget,
      );
    });

    testWidgets('the overdrawn Maribank row shows the warning pill',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final maribank = dash.liquidAccounts.firstWhere((a) => a.balance < 0);
      expect(maribank.name, 'Maribank');
      expect(find.byKey(kSetupRowNeedsFixKey), findsOneWidget);
      expect(find.text('Needs a fix'), findsOneWidget);
      expect(
          find.text('−${formatPeso(maribank.balance.abs())}'), findsOneWidget);
      expect(
        find.text(
            'Overdrawn · the last transfer out was larger than the balance'),
        findsOneWidget,
      );
      final pill = tester.widget<WebBadge>(find.byKey(kSetupRowNeedsFixKey));
      expect(pill.tone, WebBadgeTone.warning);
    });
  });

  group('row actions', () {
    testWidgets('"+" on a parent opens the pocket / goal form', (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final parent = dash.liquidAccounts.first;
      await tester.tap(find.byKey(WebKeys.setupRowAddPocket).first);
      await tester.pumpAndSettle();

      expect(find.byType(WebAccountFormDialogV2), findsOneWidget);
      expect(find.text('Add pocket or goal'), findsOneWidget);
      expect(find.textContaining('Inside ${parent.name}'), findsOneWidget);
      // Pockets start as Savings; the picker is limited to pocket types.
      expect(find.text('Savings'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add pocket'), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormDelete), findsNothing);
    });

    testWidgets('Edit opens the form with Delete at the footer\'s left',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      await tester.tap(find.byKey(WebKeys.setupRowEdit).first);
      await tester.pumpAndSettle();

      expect(find.text('Edit account'), findsOneWidget);
      final name = tester.widget<WebInput>(find.byKey(WebKeys.setupFormName));
      expect(name.controller?.text, dash.liquidAccounts.first.name);
      final delete = tester.getTopLeft(find.byKey(WebKeys.setupFormDelete));
      final save = tester.getTopLeft(find.byKey(WebKeys.setupFormSave));
      expect(delete.dx, lessThan(save.dx));
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    });

    testWidgets('Delete in the ⋯ menu opens the confirm with the real rule',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final first = dash.liquidAccounts.first;
      await tester.tap(find.byKey(kSetupRowMenuKey).first);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.setupRowDelete), findsOneWidget);
      // Archive is a goal-only action; a liquid row's menu has none.
      expect(find.byKey(kSetupRowArchiveKey), findsNothing);

      await tester.tap(find.byKey(WebKeys.setupRowDelete));
      await tester.pumpAndSettle();
      expect(find.text('Delete ${first.name}?'), findsOneWidget);
      expect(find.text(webAccountDeleteMessage(first)), findsOneWidget);
      expect(find.textContaining('cannot be deleted'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete ${first.name}?'), findsNothing);
      expect(dash.accounts.any((a) => a.id == first.id), isTrue);
    });

    testWidgets('a goal row offers Archive', (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      final goal = dash.goalAccounts.first;
      final goalRow = find.byKey(ValueKey('web.setup.row.${goal.id}'));
      await tester.tap(
          find.descendant(of: goalRow, matching: find.byKey(kSetupRowMenuKey)));
      await tester.pumpAndSettle();
      expect(find.byKey(kSetupRowArchiveKey), findsOneWidget);

      await tester.tap(find.byKey(kSetupRowArchiveKey));
      await tester.pumpAndSettle();
      expect(find.text('Archive ${goal.name}?'), findsOneWidget);
    });
  });

  group('account form', () {
    testWidgets('Add account opens the form and a Type change swaps fields',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);

      await tester.tap(find.byKey(WebKeys.setupAddAccount));
      await tester.pumpAndSettle();

      expect(find.byType(WebAccountFormDialogV2), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormName), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormCategory), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormBalance), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormColor), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormIcon), findsOneWidget);
      expect(find.text('OPENING BALANCE'), findsOneWidget);
      expect(find.text('CREDIT LIMIT'), findsNothing);
      expect(find.byKey(WebKeys.setupFormCreditFold), findsNothing);
      expect(find.byKey(WebKeys.setupFormGoalTarget), findsNothing);

      // Bank → Credit Card: balance becomes "owed", the limit and the
      // statement & payment fold appear.
      await tester.tap(find.byKey(WebKeys.setupFormCategory));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();
      expect(find.text('CURRENT BALANCE OWED'), findsOneWidget);
      expect(find.text('CREDIT LIMIT'), findsOneWidget);
      expect(find.byKey(WebKeys.setupFormCreditFold), findsOneWidget);
      expect(find.text('Statement & payment'), findsOneWidget);
      expect(find.text('STATEMENT DAY'), findsOneWidget);
      expect(find.text('MINIMUM PAYMENT'), findsOneWidget);

      // Credit Card → Goal: the target replaces the limit, the fold goes.
      await tester.tap(find.byKey(WebKeys.setupFormCategory));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goal').last);
      await tester.pumpAndSettle();
      expect(find.byKey(WebKeys.setupFormGoalTarget), findsOneWidget);
      expect(find.text('TARGET'), findsOneWidget);
      expect(find.text('CREDIT LIMIT'), findsNothing);
      expect(find.byKey(WebKeys.setupFormCreditFold), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a blank name and a blank goal target are flagged, not saved',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);
      final before = dash.accounts.length;

      await tester.tap(find.byKey(WebKeys.setupAddAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.setupFormCategory));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goal').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(WebKeys.setupFormSave));
      await tester.pumpAndSettle();
      expect(find.text('Enter account name'), findsOneWidget);
      expect(find.text('Enter a goal target'), findsOneWidget);
      expect(find.byType(WebAccountFormDialogV2), findsOneWidget);
      expect(dash.accounts.length, before);
    });
  });

  group('categories', () {
    testWidgets('the add row adds a category', (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);
      await tester.tap(find.byKey(WebKeys.setupTabCategories));
      await tester.pumpAndSettle();

      final before = ledger.categories.length;
      final addRow = find.byKey(WebKeys.setupCategoryAddRow);
      await tester.enterText(
        find.descendant(
            of: addRow, matching: find.byKey(WebKeys.setupCategoryName)),
        'Vet bills',
      );
      await tester.pump();
      await tester.tap(find.byKey(WebKeys.setupCategoryAdd));
      await tester.pumpAndSettle();

      expect(ledger.categories.length, before + 1);
      expect(ledger.categories.any((c) => c.name == 'Vet bills'), isTrue);
      expect(find.text('Vet bills'), findsOneWidget);
      // The add row is cleared for the next one.
      final field = tester.widget<TextField>(find.descendant(
          of: addRow, matching: find.byKey(WebKeys.setupCategoryName)));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('a category row carries icon, type, color, exclude, delete',
        (tester) async {
      final (dash, ledger) = await seeded(tester);
      await pumpPage(tester, presenter: dash, ledger: ledger);
      await tester.tap(find.byKey(WebKeys.setupTabCategories));
      await tester.pumpAndSettle();

      final n = webListedCategories(ledger).length;
      expect(find.byKey(WebKeys.setupCategoryIcon), findsNWidgets(n));
      expect(find.byKey(WebKeys.setupCategoryExclude), findsNWidgets(n));
      expect(find.byKey(WebKeys.setupCategoryDelete), findsNWidgets(n));
      // Rows plus the add row.
      expect(find.byKey(WebKeys.setupCategoryType), findsNWidgets(n + 1));
      expect(find.byKey(WebKeys.setupCategoryColor), findsNWidgets(n + 1));

      await tester.tap(find.byKey(WebKeys.setupCategoryDelete).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete '), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
    });
  });

  group('empty state', () {
    testWidgets('offers "Add account" when there are no accounts',
        (tester) async {
      final empty = MockStorageService();
      when(empty.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(empty.loadAccounts()).thenAnswer((_) async => <FinancialAccount>[]);
      when(empty.loadTransactions())
          .thenAnswer((_) async => <TransactionRecord>[]);
      when(empty.loadBills()).thenAnswer((_) async => []);
      when(empty.loadReceivables()).thenAnswer((_) async => []);
      when(empty.loadBudgets()).thenAnswer((_) async => []);
      when(empty.loadBudgetedExpenses()).thenAnswer((_) async => []);
      when(empty.loadFinanceCategories()).thenAnswer((_) async => []);
      when(empty.loadBudgetGroups()).thenAnswer((_) async => []);
      when(empty.loadMonthlySummaries())
          .thenAnswer((_) async => <MonthlySummary>[]);
      when(empty.saveMonthlySummaries(any)).thenAnswer((_) async {});
      when(empty.saveAccounts(any)).thenAnswer((_) async {});
      final dash = TreasuryDashboardPresenter(empty);
      await dash.load();
      final (_, ledger) = await seeded(tester);

      await pumpPage(tester, presenter: dash, ledger: ledger);

      expect(find.text('No accounts yet'), findsOneWidget);
      expect(find.byKey(WebKeys.setupStatStrip), findsNothing);
      expect(find.byKey(WebKeys.setupAccountsTable), findsNothing);
      await tester.tap(find.byKey(kSetupEmptyAddAccountKey));
      await tester.pumpAndSettle();
      expect(find.byType(WebAccountFormDialogV2), findsOneWidget);
    });
  });
}

/// Whole-peso digits with thousands separators, as the meter labels show.
String _whole(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
