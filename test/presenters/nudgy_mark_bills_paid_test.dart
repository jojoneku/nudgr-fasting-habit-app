import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: mark several bills paid in one step through the
/// Bills tab's own batch path (one write), with the one row listing every
/// bill and amount that is saved. Real bills and ledger presenters.

const _month = '2026-03';

FinancialAccount _acc(String id, String name,
        {AccountCategory category = AccountCategory.ewallet,
        double balance = 5000}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

Bill _bill(String id, String name, double amount,
        {BillType type = BillType.utility,
        String? accountId,
        bool paid = false}) =>
    Bill(
      id: id,
      name: name,
      billType: type,
      amount: amount,
      dueDay: 10,
      month: _month,
      categoryId: '',
      accountId: accountId,
      isPaid: paid,
    );

AiToolCall _call(Map<String, Object?> input) =>
    AiToolCall(id: 'c1', name: 'markBillsPaid', input: input);

void main() {
  late MockStorageService storage;
  late MockStatsPresenter stats;
  late LedgerPresenter ledger;
  late BillsReceivablesPresenter bills;
  late FinanceActionsExecutor ex;

  setUp(() {
    storage = MockStorageService();
    stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _acc('gcash', 'GCash'),
          _acc('bpi', 'BPI', category: AccountCategory.bank),
          _acc('cc', 'BPI Card',
              category: AccountCategory.creditCard, balance: 3000),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => [
          _bill('b1', 'Meralco', 2500, accountId: 'gcash'),
          _bill('b2', 'Water', 600, accountId: 'gcash'),
          _bill('b3', 'Rent', 9000, paid: true),
          _bill('stmt', 'BPI Card statement', 1000,
              type: BillType.creditCard, accountId: 'cc'),
        ]);
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.saveBills(any)).thenAnswer((_) async {});
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.saveBudgetedExpenses(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  });

  Future<void> build() async {
    ledger = LedgerPresenter(storage, stats);
    bills = BillsReceivablesPresenter(storage, ledger, stats);
    await bills.load();
    await bills.setMonth(_month);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    ex = FinanceActionsExecutor(bills: bills, ledger: ledger);
  }

  double balance(String id) =>
      ledger.accounts.firstWhere((a) => a.id == id).balance;

  List<String> rows(String label) => [
        for (final d in ex.pending!.details)
          if (d.label == label) d.value
      ];

  Bill billOf(String id) => bills.allBills.firstWhere((b) => b.id == id);

  test('the tool is an update with a bills list and no scope field', () {
    final tool = financeToolNamed('markBillsPaid')!;
    expect(tool.kind, AiToolKind.update);
    expect(tool.inputSchema['required'], ['bills']);
    expect((tool.inputSchema['properties'] as Map).containsKey('applyToFuture'),
        isFalse);
  });

  test('one T3 row lists each bill and amount; one write saves exactly them',
      () async {
    await build();
    final answer = ex.propose(_call({
      'bills': [
        {'id': 'b1', 'paidAmount': 2400},
        {'id': 'b2'},
      ],
      'paidDate': '2026-03-09',
    }));
    await Future<void>.delayed(Duration.zero);

    expect(ex.batch!.actions, hasLength(1));
    expect(ex.pending!.title, 'Mark 2 bills paid (₱3000)');
    expect(rows('Bill'), ['Meralco — ₱2400', 'Water — ₱600']);
    expect(rows('Paid from'), ['GCash']);
    expect(rows('Paid date'), ['2026-03-09']);
    expect(ex.pending!.tier, ProposalTier.destructive);
    expect(ex.pending!.ledgerChoice!.canRecord, isTrue);

    await ex.confirm();
    final r = await answer;
    expect(r.ok, isTrue);
    expect(r.summary, contains('Meralco ₱2400'));
    expect(r.summary, contains('Water ₱600'));
    expect(billOf('b1').isPaid, isTrue);
    expect(billOf('b1').paidAmount, 2400);
    expect(billOf('b2').paidAmount, 600);
    expect(balance('gcash'), 5000 - 3000);
    final outflows =
        ledger.allTransactions.where((t) => t.type == TransactionType.outflow);
    expect(outflows.map((t) => t.amount).toList()..sort(), [600, 2400]);
    // One save for the whole batch, not one per bill.
    verify(storage.saveBills(any)).called(1);
  });

  test('"already in the ledger" flags them paid and writes no entry', () async {
    await build();
    final answer = ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'b2'},
      ],
      'alreadyLogged': true,
    }));
    await Future<void>.delayed(Duration.zero);
    expect(ex.pending!.ledgerChoice!.alreadyLogged, isTrue);

    await ex.confirm();
    expect((await answer).summary, contains('already in the ledger'));
    expect(billOf('b1').isPaid, isTrue);
    expect(billOf('b2').isPaid, isTrue);
    expect(ledger.allTransactions, isEmpty);
    expect(balance('gcash'), 5000);
  });

  test('a named account wins and is the account debited', () async {
    await build();
    final answer = ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'stmt'},
      ],
      'account': 'BPI',
    }));
    await Future<void>.delayed(Duration.zero);
    expect(rows('Paid from'), ['BPI']);

    await ex.confirm();
    expect((await answer).ok, isTrue);
    expect(balance('bpi'), 5000 - 3500);
    expect(billOf('stmt').isPaid, isTrue);
  });

  test('a card statement cannot be paid from its own card', () async {
    await build();
    final r = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'stmt'},
      ],
      'account': 'BPI Card',
    }));
    expect(r.ok, isFalse);
    expect(r.summary, contains('BPI Card statement'));
    expect(ex.batch, isNull);
  });

  test('unknown ids, a paid bill, one bill and a repeat are refused', () async {
    await build();
    final unknown = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'nope'},
      ],
    }));
    expect(unknown.ok, isFalse);
    expect(unknown.summary, contains('"nope"'));
    expect(unknown.summary, contains('find'));

    final paid = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'b3'},
      ],
    }));
    expect(paid.summary, contains('Rent'));
    expect(paid.summary, contains('already marked paid'));

    final one = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
      ],
    }));
    expect(one.summary, contains('markBillPaid'));

    final twice = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'b1'},
      ],
    }));
    expect(twice.summary, contains('more than once'));

    expect(ex.batch, isNull);
    expect(ledger.allTransactions, isEmpty);
  });

  test('no shared account and none named asks which account paid', () async {
    await build();
    final r = await ex.propose(_call({
      'bills': [
        {'id': 'b1'},
        {'id': 'stmt'},
      ],
    }));
    expect(r.ok, isFalse);
    expect(r.summary, contains('Which account paid'));
  });

  test('editing the account in place re-checks and shows the new one',
      () async {
    await build();
    ex
        .propose(_call({
          'bills': [
            {'id': 'b1'},
            {'id': 'b2'},
          ],
        }))
        .ignore();
    await Future<void>.delayed(Duration.zero);
    expect(ex.editAction('c1', {'account': 'BPI'}), isNull);
    expect(rows('Paid from'), ['BPI']);
    ex.decline();
  });
}
