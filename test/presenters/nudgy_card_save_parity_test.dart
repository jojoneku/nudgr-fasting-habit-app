import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/budgeted_expense.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 1a: the confirm card shows exactly what is saved.
///
/// Each test here failed before the fix (audit 065a, part 2.1 #1–9): the card
/// showed one thing and the write saved another, or nothing at all.

FinancialAccount _acc(String id, String name,
        {AccountCategory category = AccountCategory.bank}) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: 1000,
      creditLimit: category == AccountCategory.creditCard ? 20000 : null,
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

TransactionRecord _txn(
  String id, {
  required double amount,
  String accountId = 'mari',
  String categoryId = 'util',
  TransactionType type = TransactionType.outflow,
  String description = 'Meralco',
  String month = '2026-09',
  String? transferGroupId,
  String? transferToAccountId,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime.parse('$month-12'),
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      description: description,
      month: month,
      transferGroupId: transferGroupId,
      transferToAccountId: transferToAccountId,
    );

AiToolCall _call(String name, Map<String, Object?> input) =>
    AiToolCall(id: 'tu_1', name: name, input: input);

void main() {
  late MockBillsReceivablesPresenter bills;

  setUp(() {
    bills = MockBillsReceivablesPresenter();
    when(bills.selectedMonth).thenReturn('2026-09');
    when(bills.allBills).thenReturn([]);
    when(bills.allReceivables).thenReturn([]);
    when(bills.allBudgetedExpenses).thenReturn([]);
  });

  Future<(FinanceActionsExecutor, LedgerPresenter)> build(
      {List<TransactionRecord> txns = const []}) async {
    final storage = MockStorageService();
    final stats = MockStatsPresenter();
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => [
          _acc('mari', 'MariBank'),
          _acc('gcash', 'GCash'),
          _acc('gold', 'BPI Gold', category: AccountCategory.creditCard),
        ]);
    when(storage.loadFinanceCategories()).thenAnswer(
        (_) async => [_cat('util', 'Utilities'), _cat('food', 'Food')]);
    when(storage.loadTransactions()).thenAnswer((_) async => txns);
    when(storage.loadInstallments()).thenAnswer((_) async => []);
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
    final ledger = LedgerPresenter(storage, stats);
    while (ledger.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return (FinanceActionsExecutor(bills: bills, ledger: ledger), ledger);
  }

  /// Proposes [c] and waits for its card, without waiting for the answer.
  Future<void> show(FinanceActionsExecutor ex, AiToolCall c) async {
    ex.propose(c).ignore();
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, String> rows(FinanceActionsExecutor ex) =>
      {for (final d in ex.pending!.details) d.label: d.value};

  Bill bill({String? accountId, bool isPaid = false}) => Bill(
        id: 'b1',
        name: 'Meralco',
        billType: BillType.utility,
        amount: 3500,
        dueDay: 15,
        month: '2026-09',
        categoryId: 'util',
        accountId: accountId,
        isPaid: isPaid,
      );

  test('#1 addBill saves the "Pay from" account the card showed', () async {
    final (ex, _) = await build();
    await show(
        ex,
        _call('addBill', {
          'name': 'Internet',
          'amount': 1299,
          'dueDay': 20,
          'account': 'gcash',
          'category': 'util',
        }));
    expect(rows(ex)['Pay from'], 'GCash');
    expect(rows(ex)['Category'], 'Utilities');

    await ex.confirm();
    final saved = verify(
            bills.addBill(captureAny, applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Bill;
    expect(saved.accountId, 'gcash');
    expect(saved.categoryId, 'util');
  });

  test('#1 addBill with an unknown account is refused, not saved blank',
      () async {
    final (ex, _) = await build();
    final result = await ex.propose(_call('addBill',
        {'name': 'Internet', 'amount': 1299, 'dueDay': 20, 'account': 'BDO'}));
    expect(result.ok, isFalse);
    expect(ex.pending, isNull);
  });

  test('#2 addReceivable has no owedBy, and saves the expected day', () async {
    final schema = financeToolNamed('addReceivable')!.inputSchema;
    expect((schema['properties'] as Map).containsKey('owedBy'), isFalse);

    final (ex, _) = await build();
    await show(
        ex,
        _call('addReceivable', {
          'name': 'Mark - concert',
          'amount': 2500,
          'owedBy': 'Mark',
          'expectedDay': 31,
          'month': '${DateTime.now().year}-02',
        }));
    final card = rows(ex);
    expect(card.containsKey('Owed by'), isFalse);
    final feb = DateTime(DateTime.now().year, 3, 0).day;
    expect(card['Expected'], '${DateTime.now().year}-02-$feb');

    await ex.confirm();
    final saved = verify(bills.addReceivable(captureAny,
            applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Receivable;
    expect(saved.expectedDate, DateTime(DateTime.now().year, 2, feb));
  });

  test('#3 addSetAside saves the destination account the card showed',
      () async {
    final (ex, _) = await build();
    await show(
        ex,
        _call('addSetAside', {
          'name': 'Braces',
          'amount': 3000,
          'type': 'goal',
          'destinationAccount': 'gcash',
        }));
    expect(rows(ex)['Into'], 'GCash');

    await ex.confirm();
    final saved = verify(bills.addBudgetedExpense(captureAny,
            applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as BudgetedExpense;
    expect(saved.destinationAccountId, 'gcash');
  });

  test('#3 addSetAside into an unknown account is refused', () async {
    final (ex, _) = await build();
    final result = await ex.propose(_call('addSetAside', {
      'name': 'Braces',
      'amount': 3000,
      'type': 'goal',
      'destinationAccount': 'Tonik',
    }));
    expect(result.ok, isFalse);
  });

  test('#4 editReceivable applies the amount, in the receivable\'s month',
      () async {
    when(bills.allReceivables).thenReturn([
      Receivable(
        id: 'r1',
        name: 'Alex loan',
        receivableType: ReceivableType.other,
        amount: 2000,
        month: '2026-03',
        categoryId: '',
      ),
    ]);
    final (ex, _) = await build();
    await show(
        ex,
        _call(
            'editReceivable', {'id': 'r1', 'amount': 2500, 'expectedDay': 10}));
    expect(rows(ex)['Amount'], '₱2000 → ₱2500');
    expect(rows(ex)['Expected'], '- → 2026-03-10');

    await ex.confirm();
    final saved = verify(bills.updateReceivable(captureAny,
            applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Receivable;
    expect(saved.amount, 2500);
    expect(saved.expectedDate, DateTime(2026, 3, 10));
  });

  test('#5 editBill with an unknown category is refused, not cleared',
      () async {
    when(bills.allBills).thenReturn([bill()]);
    final (ex, _) = await build();
    final result = await ex
        .propose(_call('editBill', {'id': 'b1', 'category': 'Electricity'}));
    expect(result.ok, isFalse);
    expect(result.summary, contains('"Utilities"'));
    verifyNever(
        bills.updateBill(any, applyToFuture: anyNamed('applyToFuture')));
  });

  test('#5 editBill with a known category shows and saves it', () async {
    when(bills.allBills).thenReturn([bill()]);
    final (ex, _) = await build();
    await show(ex, _call('editBill', {'id': 'b1', 'category': 'food'}));
    expect(rows(ex)['Category'], 'Utilities → Food');
    await ex.confirm();
    final saved = verify(bills.updateBill(captureAny,
            applyToFuture: anyNamed('applyToFuture')))
        .captured
        .single as Bill;
    expect(saved.categoryId, 'food');
  });

  test('#5 editTransaction with an unknown category is refused', () async {
    final (ex, ledger) =
        await build(txns: [_txn('t1', amount: 150, categoryId: 'food')]);
    final result = await ex
        .propose(_call('editTransaction', {'id': 't1', 'category': 'Snacks'}));
    expect(result.ok, isFalse);
    expect(ledger.allTransactions.single.categoryId, 'food');
  });

  test('#6 payCredit saves the note the card showed', () async {
    final (ex, _) = await build();
    await show(
        ex,
        _call('payCredit', {
          'creditAccount': 'BPI Gold',
          'fromAccount': 'MariBank',
          'amount': 850,
          'note': 'ref 123',
        }));
    expect(rows(ex)['Note'], 'ref 123');
    await ex.confirm();
    verify(bills.quickPayCard(
      accountId: 'gold',
      fromAccountId: 'mari',
      amount: 850,
      date: anyNamed('date'),
      note: 'ref 123',
    )).called(1);
  });

  group('#7 markBillPaid never records a payment twice', () {
    test('a matching ledger entry defaults to "already added"', () async {
      when(bills.allBills).thenReturn([bill(accountId: 'mari')]);
      final (ex, _) = await build(txns: [_txn('t1', amount: 3500)]);
      await show(ex, _call('markBillPaid', {'id': 'b1'}));
      final choice = ex.pending!.ledgerChoice!;
      expect(choice.alreadyLogged, isTrue);
      expect(choice.match, contains('Meralco'));

      await ex.confirm();
      verify(bills.markBillPaid('b1',
              paidAmount: 3500,
              paidDate: anyNamed('paidDate'),
              accountId: null,
              recordInLedger: false))
          .called(1);
    });

    test('the user can still choose to record it from the card', () async {
      when(bills.allBills).thenReturn([bill(accountId: 'mari')]);
      final (ex, _) = await build(txns: [_txn('t1', amount: 3500)]);
      await show(ex, _call('markBillPaid', {'id': 'b1'}));
      await ex.confirm(alreadyLogged: false);
      verify(bills.markBillPaid('b1',
              paidAmount: 3500,
              paidDate: anyNamed('paidDate'),
              accountId: 'mari',
              recordInLedger: true))
          .called(1);
    });

    test('no match records from the account the card names', () async {
      when(bills.allBills).thenReturn([bill()]);
      final (ex, _) = await build();
      await show(ex, _call('markBillPaid', {'id': 'b1', 'account': 'GCash'}));
      expect(rows(ex)['Paid from'], 'GCash');
      expect(ex.pending!.ledgerChoice!.alreadyLogged, isFalse);
      await ex.confirm();
      verify(bills.markBillPaid('b1',
              paidAmount: 3500,
              paidDate: anyNamed('paidDate'),
              accountId: 'gcash',
              recordInLedger: true))
          .called(1);
    });

    test('no account and no match asks, instead of a card that crashes',
        () async {
      when(bills.allBills).thenReturn([bill()]);
      final (ex, _) = await build();
      final result = await ex.propose(_call('markBillPaid', {'id': 'b1'}));
      expect(result.ok, isFalse);
      expect(result.summary, contains('alreadyLogged'));
    });

    test('a bill already paid is refused', () async {
      when(bills.allBills).thenReturn([bill(isPaid: true)]);
      final (ex, _) = await build();
      final result = await ex
          .propose(_call('markBillPaid', {'id': 'b1', 'account': 'GCash'}));
      expect(result.ok, isFalse);
      expect(result.summary, contains('already marked paid'));
    });
  });

  test('#8 deleting a transfer leg names the other leg on the card', () async {
    final (ex, _) = await build(txns: [
      _txn('out',
          amount: 1000,
          categoryId: '__transfer__',
          description: 'To GCash',
          transferGroupId: 'g1',
          transferToAccountId: 'gcash'),
      _txn('in',
          amount: 1000,
          accountId: 'gcash',
          categoryId: '__transfer__',
          type: TransactionType.inflow,
          description: 'To GCash',
          transferGroupId: 'g1'),
    ]);
    await show(ex, _call('deleteTransaction', {'id': 'out'}));
    expect(rows(ex)['Also deletes'], contains('into GCash'));
  });

  group('#9 an unknown id is refused before any card', () {
    for (final name in [
      'deleteTransaction',
      'editTransaction',
      'deleteBill',
      'markBillPaid',
      'deleteReceivable',
      'editSetAside',
    ]) {
      test(name, () async {
        final (ex, _) = await build();
        final result = await ex.propose(_call(name, {'id': 'nope'}));
        expect(result.ok, isFalse);
        expect(result.summary, contains('"nope"'));
        expect(ex.pending, isNull);
      });
    }
  });
}
