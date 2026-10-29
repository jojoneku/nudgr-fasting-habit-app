import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4: the executor's batch — tiers, in-place edits, Remove,
/// revise by chat, and ledger rows in the same list.

AiToolCall _call(String id, String name, Map<String, Object?> input) =>
    AiToolCall(id: id, name: name, input: input);

void main() {
  late MockBillsReceivablesPresenter bills;
  late LedgerPresenter ledger;
  late FinanceActionsExecutor ex;

  setUp(() async {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([
      Bill(
        id: 'b1',
        name: 'Gym',
        billType: BillType.other,
        amount: 1500,
        dueDay: 5,
        month: '2026-09',
        categoryId: '',
      ),
    ]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          FinancialAccount(
            id: 'cash',
            name: 'CASH',
            category: AccountCategory.cash,
            balance: 1000,
            colorHex: '#FFFFFF',
            icon: 'wallet',
          ),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => [
          FinanceCategory(
            id: 'food',
            name: 'Food',
            type: CategoryType.expense,
            icon: 'tag',
            colorHex: '#FFFFFF',
          ),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    when(stats.addXp(any)).thenAnswer((_) async {});
    ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    ex = FinanceActionsExecutor(bills: bills, ledger: ledger);
  });

  Future<List<AiToolResult>> open(List<AiToolCall> calls) async {
    final f = ex.proposeBatch(calls);
    await Future<void>.delayed(Duration.zero);
    return f;
  }

  test('tiers: create T1, edit or money move T2, delete T3', () async {
    final answer = open([
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3}),
      _call('e', 'editBill', {'id': 'b1', 'amount': 1600}),
      _call('p', 'payCredit', {'creditAccount': 'x', 'amount': 1}),
      _call('d', 'deleteBill', {'id': 'b1'}),
    ]);
    await Future<void>.delayed(Duration.zero);
    final tiers = {for (final a in ex.batch!.actions) a.call.id: a.tier};
    expect(tiers['a'], ProposalTier.create);
    expect(tiers['e'], ProposalTier.change);
    expect(tiers['d'], ProposalTier.destructive);
    // payCredit names no credit account, so it never became a row.
    expect(tiers.containsKey('p'), isFalse);
    expect(ex.batch!.hasDestructive, isTrue);
    ex.decline();
    final results = await answer;
    expect(results[2].ok, isFalse);
    expect(results[2].summary, contains('credit'));
  });

  test('an in-place edit re-describes the row and is what gets saved',
      () async {
    final answer = open([
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3})
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(ex.editAction('a', {'amount': 1299}), isNull);
    expect(ex.pending!.title, 'Add bill: Net, ₱1299');

    // A name that resolves to nothing is refused and the row is unchanged.
    expect(ex.editAction('a', {'account': 'Nowhere'}), isNotNull);
    expect(ex.pending!.title, 'Add bill: Net, ₱1299');

    await ex.approveAll();
    await answer;
    final saved = verify(
            bills.addBill(captureAny, applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Bill;
    expect(saved.amount, 1299);
  });

  test('Remove answers that one call and keeps the rest open', () async {
    final answer = open([
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3}),
      _call('d', 'deleteBill', {'id': 'b1'}),
    ]);
    await Future<void>.delayed(Duration.zero);

    ex.removeAction('d');
    expect(ex.batch!.actions.map((a) => a.call.id), ['a']);
    await ex.approveAll();
    final results = await answer;
    expect(results[0].ok, isTrue);
    expect(results[1].summary, contains('removed'));
    verifyNever(
        bills.deleteBill(any, applyToFuture: anyNamed('applyToFuture')));
  });

  test('revise answers every open call with the user\'s words', () async {
    final answer = open([
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3}),
    ]);
    await Future<void>.delayed(Duration.zero);

    ex.reviseAll('make it the 20th');
    final r = (await answer).single;
    expect(r.ok, isFalse);
    expect(r.summary, contains('make it the 20th'));
    expect(ex.batch, isNull);
  });

  test('ledger rows and other changes are one batch, approved together',
      () async {
    final answer = open([
      _call('l', 'logTransactions', {
        'entries': [
          {
            'amount': 120,
            'description': 'Coffee',
            'account': 'CASH',
            'category': 'Food',
          },
        ],
      }),
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3}),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(ex.batchHasLedgerRows, isTrue);
    expect(ex.openRowCount, 2);
    expect(ex.canApproveAll, isTrue);

    await ex.approveAll();
    final results = await answer;
    expect(results[0].summary, contains('Logged 1 entry'));
    expect(results[1].ok, isTrue);
    expect(ledger.allTransactions.single.amount, 120);
  });

  test('a second batch while one is open is refused, not dropped', () async {
    final first = open([
      _call('a', 'addBill', {'name': 'Net', 'amount': 999, 'dueDay': 3}),
    ]);
    final second = await ex.proposeBatch([
      _call('b', 'addBill', {'name': 'Gas', 'amount': 1, 'dueDay': 3}),
    ]);
    expect(second.single.ok, isFalse);
    ex.decline();
    await first;
  });
}
