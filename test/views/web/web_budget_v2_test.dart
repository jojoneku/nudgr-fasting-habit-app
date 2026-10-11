import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/pages/budget/web_budget_page_v2.dart';
import 'package:intermittent_fasting/views/web/pages/budget/web_budget_shared.dart';
import 'package:intermittent_fasting/views/web/web_keys.dart';
import 'package:intermittent_fasting/views/web/widgets/web_charts.dart';

import '../../mocks.mocks.dart';

/// The v2 Budget page (Plan 063, Phase 6).
///
/// Pins what the canvas changed: rows sit under their group with a subtotal
/// that is the sum of its rows; the status pill is one line at 1280 and an
/// over row says "Over by ₱X" in the warning tone, not red alone; the donut
/// legend sums to the allocation; and every action of the pre-v2 page is
/// still reachable — editing Allocated, the draft row, "＋ New category…",
/// and Manage groups with its rename, delete and move-on-delete behaviour.
void main() {
  final month = toMonthKey(DateTime.now());
  const ess = BudgetGroupDef.idNonNegotiables;
  const vari = BudgetGroupDef.idVariableOptional;
  const sav = BudgetGroupDef.idSavings;

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late List<Budget> savedBudgets;
  late List<BudgetGroupDef> savedGroups;

  FinanceCategory category(String id, String name) => FinanceCategory(
        id: id,
        name: name,
        type: CategoryType.expense,
        icon: 'receipt',
        colorHex: '#F6685E',
      );

  FinancialAccount savings(String id, String name) => FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.savings,
        balance: 0,
        colorHex: '#46BD6B',
        icon: 'savings',
      );

  Budget budget(String id, String key, String group, double alloc) => Budget(
        id: id,
        categoryId: key,
        month: month,
        allocatedAmount: alloc,
        group: group,
        budgetType: BudgetType.monthly,
      );

  TransactionRecord spend(String id, String categoryId, double amount) =>
      TransactionRecord(
        id: id,
        date: DateTime.parse('$month-10'),
        accountId: 'cash',
        categoryId: categoryId,
        amount: amount,
        type: TransactionType.outflow,
        description: id,
        month: month,
      );

  TransactionRecord fund(String id, String accountId, double amount) =>
      TransactionRecord(
        id: id,
        date: DateTime.parse('$month-10'),
        accountId: accountId,
        categoryId: 'cat',
        amount: amount,
        type: TransactionType.inflow,
        description: id,
        month: month,
      );

  /// The seed every test starts from: two Essentials rows, two Variable rows
  /// (Fun is over by ₱76, Transport on track), one Savings row, one
  /// unbudgeted category (Health) and one unbudgeted savings account.
  final categories = [
    category('c_bills', 'Bills & Utilities'),
    category('c_house', 'Household'),
    category('c_trans', 'Transportation'),
    category('c_fun', 'Guilt-Free / Fun'),
    category('c_health', 'Health & Wellness'),
  ];
  final accounts = [
    savings('a_maya', 'Maya Savings'),
    savings('a_ef', 'Emergency Fund'),
    FinancialAccount(
      id: 'cash',
      name: 'Cash',
      category: AccountCategory.cash,
      balance: 0,
      colorHex: '#2E90FA',
      icon: 'cash',
    ),
  ];
  final budgets = [
    budget('b1', 'c_bills', ess, 10000),
    budget('b2', 'c_house', ess, 14000),
    budget('b3', 'c_trans', vari, 1000),
    budget('b4', 'c_fun', vari, 1500),
    budget('b5', 'a_maya', sav, 3000),
  ];
  final transactions = [
    spend('t1', 'c_bills', 2738),
    spend('t2', 'c_house', 7997),
    spend('t3', 'c_trans', 276),
    spend('t4', 'c_fun', 1576),
    fund('t5', 'a_maya', 3000),
  ];

  Future<BudgetPresenter> load({
    List<Budget>? budgetsOverride,
    List<TransactionRecord>? transactionsOverride,
  }) async {
    savedBudgets = [];
    savedGroups = [];
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets())
        .thenAnswer((_) async => budgetsOverride ?? budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
    when(storage.loadTransactions())
        .thenAnswer((_) async => transactionsOverride ?? transactions);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((inv) async {
      savedBudgets =
          List<Budget>.from(inv.positionalArguments.first as List<Budget>);
    });
    when(storage.saveBudgetGroups(any)).thenAnswer((inv) async {
      savedGroups = List<BudgetGroupDef>.from(
          inv.positionalArguments.first as List<BudgetGroupDef>);
    });
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    final p = BudgetPresenter(storage, stats, null, notifications);
    await p.load();
    return p;
  }

  Future<void> pump(
    WidgetTester tester,
    BudgetPresenter presenter, {
    bool dark = true,
    double width = 1280,
    double height = 1400,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: dark ? buildWebDarkTheme() : buildWebLightTheme(),
      home: Scaffold(body: WebBudgetPageV2(presenter: presenter)),
    ));
    await tester.pumpAndSettle();
  }

  Finder inGroup(String groupId, Finder matching) => find.descendant(
        of: find.byKey(WebBudgetKeys.group(groupId)),
        matching: matching,
      );

  Finder inRow(String id, Finder matching) => find.descendant(
      of: find.byKey(WebBudgetKeys.row(id)), matching: matching);

  group('layout', () {
    for (final dark in [true, false]) {
      testWidgets(
          'renders the header, hero pair and grouped table in '
          '${dark ? 'dark' : 'light'} mode', (tester) async {
        final p = await load();
        await pump(tester, p, dark: dark);

        expect(find.text('Budget'), findsOneWidget);
        expect(find.byKey(WebKeys.budgetMonthStepper), findsOneWidget);
        expect(find.byKey(WebKeys.budgetManageGroups), findsOneWidget);
        expect(find.byKey(WebKeys.budgetPaceRing), findsOneWidget);
        expect(find.byKey(WebKeys.budgetGroupDonut), findsOneWidget);
        expect(find.byKey(WebKeys.budgetTable), findsOneWidget);
        expect(find.byKey(WebBudgetKeys.draftRow), findsOneWidget);
        expect(find.byKey(WebBudgetKeys.emptyState), findsNothing);

        // Subtitle carries the count the dropped stat strip used to show.
        expect(
          find.textContaining('allocated across 5 categories in 3 groups'),
          findsOneWidget,
        );
        // The three groups each open with a header row.
        expect(find.byKey(WebBudgetKeys.group(ess)), findsOneWidget);
        expect(find.byKey(WebBudgetKeys.group(vari)), findsOneWidget);
        expect(find.byKey(WebBudgetKeys.group(sav)), findsOneWidget);
        // Every row carries its parity keys.
        expect(find.byKey(WebKeys.budgetRowAllocated), findsNWidgets(5));
        expect(find.byKey(WebKeys.budgetRowRemove), findsNWidgets(5));
        // Expense rows get the group dropdown; the savings row does not.
        expect(find.byKey(WebKeys.budgetRowGroup), findsNWidgets(4));
        // Draft row controls.
        for (final k in [
          WebKeys.budgetAddRowMode,
          WebKeys.budgetAddRowPicker,
          WebKeys.budgetAddRowNewCategory,
          WebKeys.budgetAddRowGroup,
          WebKeys.budgetAddRowAmount,
          WebKeys.budgetAddRowAdd,
        ]) {
          expect(find.byKey(k), findsOneWidget, reason: '$k');
        }
      });
    }

    testWidgets('an empty month shows the empty state with the draft row',
        (tester) async {
      final p =
          await load(budgetsOverride: const [], transactionsOverride: const []);
      await pump(tester, p);

      expect(find.byKey(WebBudgetKeys.emptyState), findsOneWidget);
      expect(find.text('No budget set for this month'), findsOneWidget);
      expect(
        find.text('Add a category below to start planning your allocations.'),
        findsOneWidget,
      );
      expect(find.byKey(WebKeys.budgetPaceRing), findsNothing);
      expect(find.byKey(WebBudgetKeys.draftRow), findsOneWidget);
      expect(find.byKey(WebKeys.budgetAddRowPicker), findsOneWidget);
    });
  });

  group('grouped table', () {
    testWidgets('group subtotals equal the sum of their rows', (tester) async {
      final p = await load();
      await pump(tester, p);

      // Essentials: 10,000 + 14,000 allocated; 2,738 + 7,997 spent.
      expect(inGroup(ess, find.text(formatPeso(24000))), findsOneWidget);
      expect(inGroup(ess, find.text(formatPeso(10735))), findsOneWidget);
      expect(
          inGroup(ess, find.text(formatPeso(24000 - 10735))), findsOneWidget);
      expect(inGroup(ess, find.text('ESSENTIALS · 2')), findsOneWidget);
      expect(inGroup(ess, find.text('45% used')), findsOneWidget);

      // Variable: 1,000 + 1,500 allocated; 276 + 1,576 spent.
      expect(inGroup(vari, find.text(formatPeso(2500))), findsOneWidget);
      expect(inGroup(vari, find.text(formatPeso(1852))), findsOneWidget);
      expect(inGroup(vari, find.text(formatPeso(648))), findsOneWidget);
      expect(inGroup(vari, find.text('74% used')), findsOneWidget);

      // Savings: funded in, and the group reads "funded".
      expect(inGroup(sav, find.text(formatPeso(3000))), findsOneWidget);
      expect(inGroup(sav, find.text('${formatPeso(3000)} in')), findsOneWidget);
      expect(inGroup(sav, find.text('funded')), findsOneWidget);

      // The subtotals agree with the presenter, not just with each other.
      expect(p.sectionAllocated(ess), 24000);
      expect(p.sectionSpent(ess), 10735);
    });

    testWidgets('status pills never wrap at 1280', (tester) async {
      final p = await load();
      await pump(tester, p);

      final pills = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('web.budget.status.'));
      expect(pills, findsNWidgets(5));

      for (final pill in pills.evaluate()) {
        final pillFinder = find.byWidget(pill.widget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: pillFinder, matching: find.byType(RichText)),
        );
        final textWidget = tester.widget<Text>(
          find.descendant(of: pillFinder, matching: find.byType(Text)),
        );
        expect(textWidget.softWrap, isFalse);
        // One line: the laid-out height is a single 11.5 px line, and the
        // text's natural width fits in the width it was given (not clipped).
        expect(paragraph.size.height, lessThan(20));
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: '"${textWidget.data}" was clipped',
        );
        // And the pill as rendered (after any scale-down) sits inside the
        // 150 px Status column's 126 px of content width.
        expect(tester.getRect(pillFinder).width, lessThanOrEqualTo(150 - 24));
      }
    });

    testWidgets('an over row says "Over by" in the warning tone, not red',
        (tester) async {
      final p = await load();
      await pump(tester, p);

      final theme = buildWebDarkTheme();
      final warning = theme.extension<AppThemeExtension>()!.bills;
      final error = theme.colorScheme.error;

      final pill = tester.widget<Text>(
        find.descendant(
          of: find.byKey(WebBudgetKeys.status('c_fun')),
          matching: find.byType(Text),
        ),
      );
      expect(pill.data, 'Over by ₱76');
      expect(pill.style?.color, warning);
      expect(pill.style?.color, isNot(error));

      // The Remaining cell says the same thing, in the same tone.
      final remaining =
          tester.widget<Text>(inRow('c_fun', find.text('₱76 over')));
      expect(remaining.style?.color, warning);

      // The other tones read as designed.
      expect(inRow('c_bills', find.text('On track')), findsOneWidget);
      expect(inRow('a_maya', find.text('Funded')), findsOneWidget);
      expect(inRow('a_maya', find.text('₱3,000 in · ₱0 out')), findsOneWidget);
      expect(find.text('Over'), findsNothing);
    });

    testWidgets('a row at the shared threshold reads Watch', (tester) async {
      // 800 of 1,000 is 80 % — past kBudgetWatchThreshold, under 100 %.
      final p = await load(transactionsOverride: [spend('t', 'c_trans', 800)]);
      await pump(tester, p);

      expect(kBudgetWatchThreshold, 0.75);
      expect(inRow('c_trans', find.text('Watch · 80%')), findsOneWidget);
    });

    testWidgets(
        'editing an Allocated cell calls the presenter like the old page',
        (tester) async {
      final p = await load();
      await pump(tester, p);

      final field = inRow('c_fun', find.byKey(WebKeys.budgetRowAllocated));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '2500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final b = p.budgetFor('c_fun')!;
      expect(b.allocatedAmount, 2500);
      expect(b.group, vari, reason: 'editing the amount keeps the group');
      expect(savedBudgets.any((x) => x.id == 'b4' && x.allocatedAmount == 2500),
          isTrue);
      // The row re-reads: no longer over.
      expect(find.text('Over by ₱76'), findsNothing);
      expect(inRow('c_fun', find.text('On track')), findsOneWidget);
    });

    testWidgets('the draft row adds a category', (tester) async {
      final p = await load();
      await pump(tester, p);

      await tester.tap(find.text('Choose a category…'));
      await tester.pumpAndSettle();
      // Only unbudgeted categories are offered.
      expect(find.text('Health & Wellness'), findsOneWidget);
      expect(find.text('Transportation'), findsOneWidget,
          reason: 'budgeted already — appears only as its table row');
      await tester.tap(find.text('Health & Wellness').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(WebKeys.budgetAddRowAmount), '1200');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebKeys.budgetAddRowAdd));
      await tester.pumpAndSettle();

      final b = p.budgetFor('c_health')!;
      expect(b.allocatedAmount, 1200);
      expect(b.group, vari);
      expect(find.byKey(WebBudgetKeys.row('c_health')), findsOneWidget);
      // The picker is back on its hint and the amount cleared.
      expect(find.text('Choose a category…'), findsOneWidget);
    });

    testWidgets(
        '"＋ New category…" opens the dialog and the new category '
        'becomes the picked value', (tester) async {
      final p = await load();
      await pump(tester, p);

      await tester.tap(find.text('Choose a category…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ New category…'));
      await tester.pumpAndSettle();

      expect(find.text('New expense category'), findsOneWidget);
      expect(find.byKey(WebBudgetKeys.newCategoryName), findsOneWidget);
      expect(find.byKey(WebBudgetKeys.newCategoryColor), findsOneWidget);
      expect(find.byKey(WebBudgetKeys.newCategoryIcon), findsOneWidget);
      expect(find.byKey(WebBudgetKeys.newCategoryExclude), findsOneWidget);
      // From the Budget the type is fixed: only an expense can be budgeted.
      expect(find.byKey(WebBudgetKeys.newCategoryType), findsNothing);

      // An empty name is refused, not silently created.
      await tester.tap(find.byKey(WebBudgetKeys.newCategoryCreate));
      await tester.pumpAndSettle();
      expect(find.text('New expense category'), findsOneWidget);
      expect(p.expenseCategories.length, 5);

      await tester.enterText(
          find.byKey(WebBudgetKeys.newCategoryName), 'Pet care');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WebBudgetKeys.newCategoryCreate));
      await tester.pumpAndSettle();

      expect(find.text('New expense category'), findsNothing);
      final created = p.expenseCategories.where((c) => c.name == 'Pet care');
      expect(created, hasLength(1));
      expect(created.first.type, CategoryType.expense);
      // The draft picker now shows the new category.
      expect(find.text('Pet care'), findsOneWidget);
      expect(find.text('Choose a category…'), findsNothing);

      // The header + button opens the same dialog.
      await tester.tap(find.byKey(WebKeys.budgetAddRowNewCategory));
      await tester.pumpAndSettle();
      expect(find.text('New expense category'), findsOneWidget);
      await tester.tap(find.byKey(WebBudgetKeys.newCategoryCancel));
      await tester.pumpAndSettle();
      expect(find.text('New expense category'), findsNothing);
    });

    testWidgets('remove asks first, then clears the row and toasts',
        (tester) async {
      final p = await load();
      await pump(tester, p);

      await tester.tap(inRow('c_trans', find.byKey(WebKeys.budgetRowRemove)));
      await tester.pumpAndSettle();
      expect(find.text('Remove from budget?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(p.budgetFor('c_trans'), isNotNull);

      await tester.tap(inRow('c_trans', find.byKey(WebKeys.budgetRowRemove)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(p.budgetFor('c_trans'), isNull);
      expect(find.byKey(WebBudgetKeys.row('c_trans')), findsNothing);
      expect(find.text('Removed "Transportation" from the budget.'),
          findsOneWidget);
    });
  });

  group('donut', () {
    testWidgets('legend sums to the allocation', (tester) async {
      final p = await load();
      await pump(tester, p);

      final chart = tester.widget<WebDonutChart>(find.byType(WebDonutChart));
      final total = chart.slices.fold<double>(0, (s, e) => s + e.value);
      expect(total, p.totalAllocated);
      expect(chart.slices.map((s) => s.label),
          ['Essentials', 'Variable', 'Savings']);

      Finder legend(String g) => find.descendant(
          of: find.byKey(WebBudgetKeys.legend(g)), matching: find.byType(Text));
      expect(
        tester.widgetList<Text>(legend(ess)).map((t) => t.data),
        containsAll(['Essentials', formatPeso(24000), '81%']),
      );
      expect(
        tester.widgetList<Text>(legend(vari)).map((t) => t.data),
        containsAll(['Variable', formatPeso(2500), '8%']),
      );
      expect(
        tester.widgetList<Text>(legend(sav)).map((t) => t.data),
        containsAll(['Savings', formatPeso(3000), '10%']),
      );
    });
  });

  group('Manage groups', () {
    testWidgets(
        'opens, adds, renames and deletes — moving the deleted '
        "group's categories to the first expense group", (tester) async {
      final p = await load();
      await pump(tester, p);

      await tester.tap(find.byKey(WebKeys.budgetManageGroups));
      await tester.pumpAndSettle();
      expect(find.text('Budget groups'), findsOneWidget);
      expect(find.byKey(WebBudgetKeys.groupRow(ess)), findsOneWidget);
      expect(find.textContaining('· 2 categories'), findsNWidgets(2));
      // Built-in groups cannot be deleted (they come back from defaults).
      expect(find.byKey(WebKeys.budgetGroupsDelete), findsNothing);
      expect(find.byKey(WebKeys.budgetGroupsRename), findsNWidgets(3));
      expect(
        find.textContaining('moves its categories to "Essentials"'),
        findsOneWidget,
      );

      // Add: type a name, Enter.
      await tester.enterText(find.byKey(WebKeys.budgetGroupsAdd), 'Travel');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final travel = p.groups.where((g) => g.name == 'Travel').single;
      expect(travel.isBuiltIn, isFalse);
      expect(savedGroups.any((g) => g.id == travel.id), isTrue);
      expect(find.byKey(WebBudgetKeys.groupRow(travel.id)), findsOneWidget);
      expect(find.byKey(WebKeys.budgetGroupsDelete), findsOneWidget);

      // A blank name is rejected silently.
      await tester.enterText(find.byKey(WebKeys.budgetGroupsAdd), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(p.groups.length, 4);

      // Rename: through the kit prompt.
      await tester.tap(find.descendant(
        of: find.byKey(WebBudgetKeys.groupRow(travel.id)),
        matching: find.byKey(WebKeys.budgetGroupsRename),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Rename group'), findsOneWidget);
      await tester.enterText(
          find.byKey(WebBudgetKeys.groupsRenameField), 'Trips');
      await tester.tap(find.byKey(WebBudgetKeys.groupsRenameSave));
      await tester.pumpAndSettle();
      expect(p.groups.where((g) => g.id == travel.id).single.name, 'Trips');
      expect(find.textContaining('Trips ·'), findsOneWidget);

      // Put a category in the new group, then delete it.
      await p.setBudget('c_health', 500,
          group: travel.id, budgetType: BudgetType.variable);
      await tester.pumpAndSettle();
      expect(find.textContaining('Trips · 1 category'), findsOneWidget);

      await tester.tap(find.byKey(WebKeys.budgetGroupsDelete));
      await tester.pumpAndSettle();
      expect(find.text('Delete group?'), findsOneWidget);
      expect(
        find.textContaining('Categories in "Trips" move to "Essentials"'),
        findsOneWidget,
      );
      // The row's own Delete is a TextButton; the confirm's is the FilledButton.
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(p.groups.any((g) => g.id == travel.id), isFalse);
      expect(p.budgetFor('c_health')!.group, ess,
          reason: 'the row is kept and moves to the first expense group');
      expect(savedBudgets.where((b) => b.categoryId == 'c_health').single.group,
          ess);

      // Done closes.
      await tester.tap(find.byKey(WebKeys.budgetGroupsClose));
      await tester.pumpAndSettle();
      expect(find.text('Budget groups'), findsNothing);
      // The page picked the moved row up under Essentials.
      expect(inGroup(ess, find.text('ESSENTIALS · 3')), findsOneWidget);
    });
  });
}
