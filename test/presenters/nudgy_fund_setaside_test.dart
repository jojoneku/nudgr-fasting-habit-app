import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: fund a set-aside through the Bills tab's own
/// "Set aside into" path, with the row showing exactly what moves.

FinancialAccount _acc(String id, String name, AccountCategory c) =>
    FinancialAccount(
      id: id,
      name: name,
      category: c,
      balance: 5000,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

BudgetedExpense _setAside({
  SetAsideType type = SetAsideType.goal,
  String? from = 'bpi',
  String? into = 'braces',
  bool paid = false,
}) =>
    BudgetedExpense(
      id: 'sa1',
      name: 'Braces',
      budgetedType: type,
      month: '2026-09',
      allocatedAmount: 3000,
      categoryId: '',
      accountId: from,
      destinationAccountId: into,
      isPaid: paid,
    );

AiToolCall _fund(Map<String, Object?> input) =>
    AiToolCall(id: 'f1', name: 'fundSetAside', input: {'id': 'sa1', ...input});

void main() {
  late MockBillsReceivablesPresenter bills;
  late FinanceActionsExecutor ex;

  Future<void> build(BudgetedExpense e) async {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([e]);
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _acc('bpi', 'BPI', AccountCategory.bank),
          _acc('gcash', 'GCash', AccountCategory.ewallet),
          _acc('braces', 'Braces Fund', AccountCategory.goal),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(stats.stats).thenReturn(UserStats.initial());
    final ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    ex = FinanceActionsExecutor(bills: bills, ledger: ledger);
  }

  Map<String, String> rows() =>
      {for (final d in ex.pending!.details) d.label: d.value};

  test('the tool is an update with no recurrence scope field', () {
    final tool = financeToolNamed('fundSetAside')!;
    expect(tool.kind, AiToolKind.update);
    expect((tool.inputSchema['properties'] as Map).containsKey('applyToFuture'),
        isFalse);
  });

  test('defaults to the set-aside\'s own accounts and amount; saves them',
      () async {
    await build(_setAside());
    final answer = ex.propose(_fund({}));
    await Future<void>.delayed(Duration.zero);

    expect(rows()['Amount'], '₱3000');
    expect(rows()['From'], 'BPI');
    expect(rows()['Into'], 'Braces Fund');
    expect(ex.pending!.tier, ProposalTier.change);

    await ex.confirm();
    expect((await answer).summary, contains('into Braces Fund'));
    verify(bills.markExpensePaid('sa1',
            paidAmount: 3000,
            accountId: 'bpi',
            toAccountId: 'braces',
            paidDate: anyNamed('paidDate')))
        .called(1);
  });

  test('named accounts and amount win, and are what is saved', () async {
    await build(_setAside());
    final answer = ex.propose(_fund({'amount': 1500, 'fromAccount': 'gcash'}));
    await Future<void>.delayed(Duration.zero);
    expect(rows()['From'], 'GCash');
    expect(rows()['Amount'], '₱1500');

    await ex.confirm();
    await answer;
    verify(bills.markExpensePaid('sa1',
            paidAmount: 1500,
            accountId: 'gcash',
            toAccountId: 'braces',
            paidDate: anyNamed('paidDate')))
        .called(1);
  });

  test('a goal with nowhere to go is refused, not booked as spending',
      () async {
    await build(_setAside(into: null));
    final r = await ex.propose(_fund({}));
    expect(r.ok, isFalse);
    expect(r.summary, contains('which account it goes into'));
    expect(ex.batch, isNull);
  });

  test('a gift with no destination is shown as spending', () async {
    await build(_setAside(type: SetAsideType.gift, into: null));
    ex.propose(_fund({})).ignore();
    await Future<void>.delayed(Duration.zero);
    expect(rows()['Into'], 'none — recorded as spending');
    ex.decline();
  });

  test('an already funded set-aside and an unknown id are refused', () async {
    await build(_setAside(paid: true));
    expect((await ex.propose(_fund({}))).summary, contains('already funded'));
    final unknown = await ex.propose(
        const AiToolCall(id: 'x', name: 'fundSetAside', input: {'id': 'nope'}));
    expect(unknown.ok, isFalse);
    expect(unknown.summary, contains('"nope"'));
  });

  test('no funding account anywhere asks which', () async {
    await build(_setAside(from: null));
    final r = await ex.propose(_fund({}));
    expect(r.ok, isFalse);
    expect(r.summary, contains('come from'));
  });
}
