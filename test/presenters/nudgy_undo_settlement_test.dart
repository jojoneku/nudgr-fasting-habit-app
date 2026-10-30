import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/finance_tool_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 4 parity: undo a bill payment or a receipt from chat
/// through the Bills tab's own undo, with the row naming every ledger entry
/// the undo deletes. Real bills and ledger presenters, so the row is checked
/// against what the undo really removes.

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

Bill _bill(String id,
        {double amount = 500,
        BillType type = BillType.utility,
        String? accountId}) =>
    Bill(
      id: id,
      name: id == 'stmt' ? 'BPI Card statement' : 'Meralco',
      billType: type,
      amount: amount,
      dueDay: 10,
      month: _month,
      categoryId: '',
      accountId: accountId,
    );

Receivable _receivable() => Receivable(
      id: 'r1',
      name: 'Jana loan',
      receivableType: ReceivableType.other,
      amount: 400,
      month: _month,
      categoryId: '',
    );

AiToolCall _call(String name, String id) =>
    AiToolCall(id: 'c1', name: name, input: {'id': id});

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
          _acc('cc', 'BPI Card',
              category: AccountCategory.creditCard, balance: 3000),
        ]);
    when(storage.loadTransactions()).thenAnswer((_) async => []);
    when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadBills()).thenAnswer((_) async => []);
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

  test('both tools are updates that take only a find id', () {
    for (final name in ['markBillUnpaid', 'markReceivableNotReceived']) {
      final tool = financeToolNamed(name)!;
      expect(tool.kind, AiToolKind.update);
      expect(tool.inputSchema['required'], ['id']);
      expect((tool.inputSchema['properties'] as Map).keys, ['id']);
    }
  });

  group('markBillUnpaid', () {
    test('names the outflow it deletes, is T3, and deletes exactly that',
        () async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      await build();
      await bills.markBillPaid('b1',
          paidAmount: 500, accountId: 'gcash', paidDate: DateTime(2026, 3, 9));
      expect(balance('gcash'), 4500);

      final answer = ex.propose(_call('markBillUnpaid', 'b1'));
      await Future<void>.delayed(Duration.zero);

      expect(ex.pending!.title, 'Mark bill unpaid: Meralco (₱500)');
      expect(rows('Status'), ['Paid ₱500 on 2026-03-09 → Unpaid']);
      expect(rows('Deletes'), ['"Meralco" ₱500 out of GCash, 2026-03-09']);
      expect(ex.pending!.tier, ProposalTier.destructive);
      expect(ex.pending!.editable, isEmpty);

      await ex.confirm();
      final r = await answer;
      expect(r.ok, isTrue);
      expect(r.summary, contains('"Meralco" ₱500 out of GCash'));
      expect(bills.allBills.single.isPaid, isFalse);
      expect(ledger.allTransactions, isEmpty);
      expect(balance('gcash'), 5000);
    });

    test('a card statement names both transfer legs it deletes', () async {
      when(storage.loadBills()).thenAnswer((_) async => [
            _bill('stmt',
                amount: 1000, type: BillType.creditCard, accountId: 'cc')
          ]);
      await build();
      await bills.markBillPaid('stmt',
          paidAmount: 1000, accountId: 'gcash', paidDate: DateTime(2026, 3, 9));
      expect(ledger.allTransactions, hasLength(2));

      final answer = ex.propose(_call('markBillUnpaid', 'stmt'));
      await Future<void>.delayed(Duration.zero);
      final deletes = rows('Deletes');
      expect(deletes, hasLength(2));
      expect(deletes.where((d) => d.contains('out of GCash')), hasLength(1));
      expect(deletes.where((d) => d.contains('into BPI Card')), hasLength(1));

      await ex.confirm();
      expect((await answer).ok, isTrue);
      expect(ledger.allTransactions, isEmpty);
      expect(balance('gcash'), 5000);
      expect(balance('cc'), 3000);
    });

    test('a payment flagged without a ledger entry is T2 and deletes nothing',
        () async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      await build();
      await bills.markBillPaid('b1', paidAmount: 500, recordInLedger: false);

      final answer = ex.propose(_call('markBillUnpaid', 'b1'));
      await Future<void>.delayed(Duration.zero);
      expect(rows('Deletes'), isEmpty);
      expect(rows('Ledger').single, contains('No ledger entry'));
      expect(ex.pending!.tier, ProposalTier.change);

      await ex.confirm();
      expect((await answer).summary, contains('no ledger entry was deleted'));
      expect(bills.allBills.single.isPaid, isFalse);
      expect(balance('gcash'), 5000);
    });

    test('an unpaid bill and an unknown id are refused before any row',
        () async {
      when(storage.loadBills()).thenAnswer((_) async => [_bill('b1')]);
      await build();

      final unpaid = await ex.propose(_call('markBillUnpaid', 'b1'));
      expect(unpaid.ok, isFalse);
      expect(unpaid.summary, contains('is not paid'));
      expect(ex.batch, isNull);

      final unknown = await ex.propose(_call('markBillUnpaid', 'nope'));
      expect(unknown.ok, isFalse);
      expect(unknown.summary, contains('No bill has the id "nope"'));
      expect(ex.batch, isNull);
    });
  });

  group('markReceivableNotReceived', () {
    test('names the inflow it deletes, is T3, and deletes exactly that',
        () async {
      when(storage.loadReceivables()).thenAnswer((_) async => [_receivable()]);
      await build();
      await bills.markReceivableReceived('r1',
          receivedAmount: 400,
          accountId: 'gcash',
          receivedDate: DateTime(2026, 3, 20));
      expect(balance('gcash'), 5400);

      final answer = ex.propose(_call('markReceivableNotReceived', 'r1'));
      await Future<void>.delayed(Duration.zero);

      expect(ex.pending!.title, 'Mark not received: Jana loan (₱400)');
      expect(rows('Status'), ['Received ₱400 on 2026-03-20 → Not received']);
      expect(rows('Deletes'), hasLength(1));
      expect(rows('Deletes').single, contains('₱400 into GCash, 2026-03-20'));
      expect(ex.pending!.tier, ProposalTier.destructive);

      await ex.confirm();
      final r = await answer;
      expect(r.ok, isTrue);
      expect(r.summary, contains('₱400 into GCash'));
      expect(bills.allReceivables.single.isReceived, isFalse);
      expect(ledger.allTransactions, isEmpty);
      expect(balance('gcash'), 5000);
    });

    test('a receivable not received and an unknown id are refused', () async {
      when(storage.loadReceivables()).thenAnswer((_) async => [_receivable()]);
      await build();

      final open = await ex.propose(_call('markReceivableNotReceived', 'r1'));
      expect(open.ok, isFalse);
      expect(open.summary, contains('not marked received'));

      final unknown =
          await ex.propose(_call('markReceivableNotReceived', 'nope'));
      expect(unknown.ok, isFalse);
      expect(unknown.summary, contains('No receivable has the id "nope"'));
      expect(ex.batch, isNull);
    });
  });
}
