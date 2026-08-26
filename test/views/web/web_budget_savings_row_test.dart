import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
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
import 'package:intermittent_fasting/views/web/pages/budget/web_budget_page.dart';

import '../../mocks.mocks.dart';

/// How a savings row reads on the web Budget page once it has been drawn down.
///
/// Netting the withdrawal into progress made the row lie twice: it showed a
/// fund you had fully funded as barely started, and the money you took out
/// appeared nowhere at all. Progress now counts what went in, and the row says
/// what came back out.
void main() {
  final month = toMonthKey(DateTime.now());

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  TransactionRecord txn({
    required String id,
    required String accountId,
    required double amount,
    required TransactionType type,
  }) =>
      TransactionRecord(
        id: id,
        date: DateTime.parse('$month-15'),
        accountId: accountId,
        categoryId: 'cat',
        amount: amount,
        type: type,
        description: id,
        month: month,
      );

  Future<BudgetPresenter> load({
    required List<FinancialAccount> accounts,
    required List<Budget> budgets,
    List<TransactionRecord> transactions = const [],
  }) async {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
    when(storage.loadBudgets()).thenAnswer((_) async => budgets);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => <FinanceCategory>[]);
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveWarnedBudgetKeys(any)).thenAnswer((_) async {});
    when(storage.saveBudgets(any)).thenAnswer((_) async {});
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

  final bracesAccount = FinancialAccount(
    id: 'braces',
    name: 'Braces',
    category: AccountCategory.savings,
    balance: 0,
    colorHex: '#46BD6B',
    icon: 'savings',
  );

  final bracesBudget = Budget(
    id: 'b1',
    categoryId: 'braces',
    month: month,
    allocatedAmount: 3000,
    group: BudgetGroupDef.idSavings,
    budgetType: BudgetType.monthly,
  );

  testWidgets('a fund spent from shows what went in and what came out',
      (tester) async {
    final p = await load(
      accounts: [bracesAccount],
      budgets: [bracesBudget],
      transactions: [
        txn(
          id: 'fund',
          accountId: 'braces',
          amount: 3000,
          type: TransactionType.inflow,
        ),
        txn(
          id: 'dentist',
          accountId: 'braces',
          amount: 1800,
          type: TransactionType.outflow,
        ),
      ],
    );
    await pump(tester, p);

    expect(find.text('Braces'), findsOneWidget);
    expect(
      find.text('${formatPeso(3000)} in · ${formatPeso(1800)} out'),
      findsOneWidget,
      reason: 'the withdrawal must be stated, not netted into the bar',
    );
    // Fully funded reads as funded, not as 40% of the goal. (The figure shows
    // twice — once on the row, once in the page summary that sums to it.)
    expect(find.text('100%'), findsWidgets);
    expect(find.text('Funded'), findsOneWidget);
    expect(find.text('Over'), findsNothing);
  });

  testWidgets('a fund with no withdrawals carries no in/out line',
      (tester) async {
    final p = await load(
      accounts: [bracesAccount],
      budgets: [bracesBudget],
      transactions: [
        txn(
          id: 'fund',
          accountId: 'braces',
          amount: 1500,
          type: TransactionType.inflow,
        ),
      ],
    );
    await pump(tester, p);

    expect(find.textContaining(' in · '), findsNothing);
    expect(find.text('50%'), findsWidgets);
    expect(find.text('On track'), findsOneWidget);
  });

  testWidgets('funding past the goal is never flagged as over', (tester) async {
    final p = await load(
      accounts: [bracesAccount],
      budgets: [bracesBudget],
      transactions: [
        txn(
          id: 'fund',
          accountId: 'braces',
          amount: 4500,
          type: TransactionType.inflow,
        ),
      ],
    );
    await pump(tester, p);

    // An expense row at 150% is the thing the red badge exists for; beating a
    // savings goal by the same margin is the opposite of a problem.
    expect(find.text('Funded'), findsOneWidget);
    expect(find.text('Over'), findsNothing);
  });
}
