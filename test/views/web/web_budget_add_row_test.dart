import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/views/web/design/web_theme.dart';
import 'package:intermittent_fasting/views/web/pages/budget/web_budget_page.dart';

import '../../mocks.mocks.dart';

/// The web Budget page's inline add-row.
///
/// Adding two savings goals in one sitting used to strand the second one: the
/// Savings toggle and the group actually written were separate pieces of state,
/// and a successful add reset the group to Variable while leaving the toggle on
/// Savings. The second row was then saved with an account id under an expense
/// group, where nothing could render it — though its allocation still showed up
/// in the header total.
///
/// Writing this test turned up a second way the mode was lost: the pace ring
/// and the empty state swap places around the setup card on the first budget of
/// a month, which reindexed the card and gave the add-row a fresh State. The
/// first test covers both — it adds the month's first budget *and* a second.
void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;
  late List<Budget> saved;

  FinancialAccount savings(String id, String name) => FinancialAccount(
        id: id,
        name: name,
        category: AccountCategory.savings,
        balance: 0,
        colorHex: '#46BD6B',
        icon: 'savings',
      );

  FinanceCategory category(String id, String name) => FinanceCategory(
        id: id,
        name: name,
        type: CategoryType.expense,
        icon: 'receipt',
        colorHex: '#F6685E',
      );

  Future<BudgetPresenter> load({
    List<FinancialAccount> accounts = const [],
    List<FinanceCategory> categories = const [],
  }) async {
    saved = [];
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((inv) async {
      saved = List<Budget>.from(inv.positionalArguments.first as List<Budget>);
    });
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    final p = BudgetPresenter(storage, stats, null, notifications);
    await p.load();
    return p;
  }

  Future<void> pump(WidgetTester tester, BudgetPresenter presenter) async {
    tester.view.physicalSize = const Size(1800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildWebDarkTheme(),
      home: Scaffold(body: WebBudgetPage(presenter: presenter)),
    ));
    await tester.pumpAndSettle();
  }

  /// Drives the add-row once: open the picker, choose [entryLabel], type
  /// [amount], press the confirm button.
  Future<void> addRow(
    WidgetTester tester, {
    required String entryLabel,
    required String amount,
  }) async {
    await tester.tap(find.text('Choose an account…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(entryLabel).last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, amount);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a second savings goal added in one sitting still lands in '
      'the Savings group', (tester) async {
    final p = await load(
      accounts: [
        savings('ef', 'Emergency Fund'),
        savings('braces', 'Braces'),
      ],
      categories: [category('c1', 'Food')],
    );
    await pump(tester, p);

    // Switch the add-row into Savings mode once, the way a user would.
    await tester.tap(find.text('Savings').last);
    await tester.pumpAndSettle();

    await addRow(tester, entryLabel: 'Emergency Fund', amount: '5000');
    await addRow(tester, entryLabel: 'Braces', amount: '3000');

    expect(
      p.savingsBudgets.map((e) => e.account.name).toList(),
      ['Emergency Fund', 'Braces'],
      reason: 'both rows should be visible, not just the first',
    );
    expect(
      p.allBudgets.map((b) => b.group).toSet(),
      {BudgetGroupDef.idSavings},
      reason: 'neither may be written under an expense group',
    );
    // What was persisted has to agree with what the page shows — the old bug
    // was invisible in memory-only assertions because the total still matched.
    expect(saved.every((b) => b.group == BudgetGroupDef.idSavings), isTrue);
    expect(p.totalAllocated, 8000);
  });

  testWidgets(
      'the picked target is cleared after an add, so a second confirm '
      'cannot silently rewrite it', (tester) async {
    final p = await load(accounts: [savings('ef', 'Emergency Fund')]);
    await pump(tester, p);

    await tester.tap(find.text('Savings').last);
    await tester.pumpAndSettle();
    await addRow(tester, entryLabel: 'Emergency Fund', amount: '5000');

    // The account has left the picker (it has a row of its own now), so the
    // field is back to its hint. Typing an amount and confirming with nothing
    // picked must be a no-op rather than re-writing the last target.
    await tester.enterText(find.byType(TextField).last, '999');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    expect(p.budgetFor('ef')!.allocatedAmount, 5000);
    expect(p.totalAllocated, 5000);
  });

  testWidgets('expense mode is unaffected — the group still resets to Variable',
      (tester) async {
    final p = await load(
      accounts: [savings('ef', 'Emergency Fund')],
      categories: [category('c1', 'Food'), category('c2', 'Transport')],
    );
    await pump(tester, p);

    await tester.tap(find.text('Choose a category…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '4000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
    await tester.pumpAndSettle();

    expect(p.budgetFor('c1')!.group, BudgetGroupDef.idVariableOptional);
    expect(p.savingsBudgets, isEmpty);
  });
}
