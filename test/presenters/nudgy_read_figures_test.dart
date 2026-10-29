import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/budget.dart';
import 'package:intermittent_fasting/models/finance/budget_group_def.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 1b: Nudgy's budget reads give the Budget tab's figures.

FinancialAccount _acc(String id, String name, AccountCategory category) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name) => FinanceCategory(
      id: id,
      name: name,
      type: CategoryType.expense,
      icon: 'tag',
      colorHex: '#FFFFFF',
    );

Budget _budget(String id, String categoryId, double amount, String group,
        {String month = '2026-08'}) =>
    Budget(
      id: id,
      categoryId: categoryId,
      month: month,
      allocatedAmount: amount,
      group: group,
      budgetType: BudgetType.monthly,
    );

TransactionRecord _txn(String id, String accountId, String categoryId,
        double amount, TransactionType type, String month,
        {String? group}) =>
    TransactionRecord(
      id: id,
      date: DateTime.parse('$month-10'),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: id,
      month: month,
      transferGroupId: group,
    );

void main() {
  late FinanceActionsExecutor ex;

  setUp(() async {
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    final bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-10');
    final accounts = [
      _acc('bpi', 'BPI', AccountCategory.bank),
      _acc('braces', 'Braces Fund', AccountCategory.goal),
    ];
    final txns = [
      // August: ₱900 food, ₱2,000 into the Braces fund.
      _txn('food1', 'bpi', 'food', 900, TransactionType.outflow, '2026-08'),
      _txn('in1', 'braces', 'xfer', 2000, TransactionType.inflow, '2026-08',
          group: 'g1'),
      _txn('out1', 'bpi', 'xfer', 2000, TransactionType.outflow, '2026-08',
          group: 'g1'),
      // October, which the Budget tab will NOT be on.
      _txn('food2', 'bpi', 'food', 50, TransactionType.outflow, '2026-10'),
    ];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [_cat('food', 'Food')]);
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => [
          _budget('bf', 'food', 3000, BudgetGroupDef.idVariableOptional),
          _budget('bs', 'braces', 2500, BudgetGroupDef.idSavings),
        ]);
    when(storage.loadBudgetGroups()).thenAnswer((_) async => []);
    when(storage.loadWarnedBudgetKeys()).thenAnswer((_) async => <String>{});
    when(stats.stats).thenReturn(UserStats.initial());

    final ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final budget =
        BudgetPresenter(storage, stats, null, MockNotificationService());
    await budget.load();
    ex = FinanceActionsExecutor(bills: bills, budget: budget, ledger: ledger);
  });

  Future<String> read(String tool, Map<String, Object?> input) async =>
      (await ex.runRead(AiToolCall(id: 't', name: tool, input: input))).summary;

  test('a savings row is named by its account and matches by name', () async {
    final s =
        await read('findBudgets', {'query': 'braces', 'month': '2026-08'});
    expect(s, contains('"Braces Fund"'));
    expect(s, isNot(contains('"braces"')));
    expect(s, contains('funded ₱2000'));
  });

  test('spend is for the month asked, not the Budget tab\'s month', () async {
    final s = await read('findBudgets', {'query': 'food', 'month': '2026-08'});
    expect(s, contains('spent ₱900'));
    expect(s, contains('left ₱2100'));
  });

  test('budget groups read the month asked for', () async {
    final s = await read('findBudgetGroups', {'month': '2026-08'});
    expect(s, contains('allocated ₱3000, spent ₱900'));
    expect(s, contains('allocated ₱2500, funded ₱2000'));
  });
}
