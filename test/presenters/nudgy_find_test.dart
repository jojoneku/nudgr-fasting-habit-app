import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_tool.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/finance_actions_executor.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/finance_find_match.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// Plan 065 phase 3: one `find` tool replaces the seven `find*` tools.
///
/// Fixed fixture data, so these run free and deterministically.

FinancialAccount _acc(String id, String name,
        [AccountCategory c = AccountCategory.bank]) =>
    FinancialAccount(
      id: id,
      name: name,
      category: c,
      balance: 1000,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

Bill _bill(String id, String name, String month,
        {bool paid = false, String? txnId}) =>
    Bill(
      id: id,
      name: name,
      billType: BillType.utility,
      amount: 3500,
      dueDay: 15,
      month: month,
      categoryId: '',
      accountId: 'bpi',
      paymentNote: 'Acct 99',
      isRecurring: true,
      isPaid: paid,
      paidDate: paid ? DateTime.parse('$month-14') : null,
      paidAmount: paid ? 3480 : null,
      transactionId: txnId,
    );

void main() {
  group('query matching', () {
    test('filler words and the entity word are dropped', () {
      expect(parseFindQuery('my internet bill').words, ['internet']);
    });

    test('a month name sets the month instead of matching as text', () {
      final q = parseFindQuery('meralco aug');
      expect(q.words, ['meralco']);
      expect(q.monthNumber, 8);
    });

    test('a lone month word is a name, not a month', () {
      expect(parseFindQuery('may').words, ['may']);
    });

    test('all words must match, in any order', () {
      final q = parseFindQuery('card bpi');
      expect(findMatches(q, 'BPI Credit Card'), isTrue);
      expect(findMatches(q, 'BDO Credit Card'), isFalse);
    });

    test('nearest names rank shared words, then spelling', () {
      final near = nearestNames(
          parseFindQuery('meralko'), ['Internet', 'Meralco', 'Maynilad']);
      expect(near.first, 'Meralco');
    });
  });

  group('find', () {
    late MockBillsReceivablesPresenter bills;
    late FinanceActionsExecutor ex;
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final aug = '${now.month >= 8 ? now.year : now.year - 1}-08';

    setUp(() async {
      bills = MockBillsReceivablesPresenter();
      when(bills.selectedMonth).thenReturn('2020-01'); // a tab parked far away
      when(bills.allBills).thenReturn([
        _bill('b_aug', 'Meralco', aug, paid: true, txnId: 't1'),
        _bill('b_now', 'Meralco', thisMonth),
        _bill('b_net', 'PLDT Internet', thisMonth),
        _bill('b_net2', 'Converge Internet', thisMonth),
      ]);
      when(bills.allReceivables).thenReturn([
        Receivable(
          id: 'r1',
          name: 'Mark - concert',
          receivableType: ReceivableType.other,
          amount: 2500,
          month: thisMonth,
          categoryId: '',
        ),
      ]);
      when(bills.allBudgetedExpenses).thenReturn([]);

      final storage = MockStorageService();
      final stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => [
            _acc('bpi', 'BPI'),
            _acc('cc', 'BPI Credit Card', AccountCategory.creditCard),
          ]);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadTransactions()).thenAnswer((_) async => [
            TransactionRecord(
              id: 't1',
              date: DateTime.parse('$aug-14'),
              accountId: 'bpi',
              categoryId: '',
              amount: 3480,
              type: TransactionType.outflow,
              description: 'Meralco bill',
              month: aug,
            ),
          ]);
      when(storage.loadInstallments()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(stats.stats).thenReturn(UserStats.initial());
      final ledger = LedgerPresenter(storage, stats);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      ex = FinanceActionsExecutor(bills: bills, ledger: ledger);
    });

    Future<String> find(Map<String, Object?> input) async =>
        (await ex.runRead(AiToolCall(id: 't', name: 'find', input: input)))
            .summary;

    test('"when did I pay Meralco in August" is one lookup with every field',
        () async {
      final s = await find({'entity': 'bill', 'query': 'meralco aug'});
      expect(s, startsWith('status: found'));
      expect(s, contains('month: $aug'));
      expect(s, contains('paid date: $aug-14'));
      expect(s, contains('paid amount: ₱3480'));
      expect(s, contains('pay from: BPI'));
      expect(s, contains('payment note: Acct 99'));
      expect(s, contains('ledger entry: "Meralco bill" ₱3480 on $aug-14'));
    });

    test('no month means today\'s month, not the month a tab is on', () async {
      final s = await find({'entity': 'bill', 'query': 'meralco'});
      expect(s, startsWith('status: found'));
      expect(s, contains('id: b_now'));
    });

    test('several matches are ambiguous and listed with ids', () async {
      final s = await find({'entity': 'bill', 'query': 'internet'});
      expect(s, startsWith('status: ambiguous'));
      expect(s, contains('id=b_net'));
      expect(s, contains('id=b_net2'));
    });

    test('no query lists every row of the month as found', () async {
      final s = await find({'entity': 'bill'});
      expect(s, startsWith('status: found'));
      expect(s, contains('3 matched'));
    });

    test('not found names the nearest and the match in another month',
        () async {
      final s = await find(
          {'entity': 'bill', 'query': 'meralko', 'month': thisMonth});
      expect(s, startsWith('status: not_found'));
      expect(s, contains('"Meralco"'));

      final elsewhere = await find({
        'entity': 'bill',
        'query': 'meralco',
        'month':
            '${now.year}-${(now.month % 12 + 1).toString().padLeft(2, '0')}',
      });
      expect(elsewhere, contains('Matches in other months'));
      expect(elsewhere, contains('id=b_now'));
    });

    test('a receivable is matched by the person in its name', () async {
      final s = await find({'entity': 'receivable', 'query': 'mark'});
      expect(s, startsWith('status: found'));
      expect(s, contains('amount expected: ₱2500'));
    });

    test('accounts are not month-scoped', () async {
      final s = await find({'entity': 'account', 'query': 'bpi card'});
      expect(s, startsWith('status: found'));
      expect(s, contains('month: all'));
      expect(s, contains('name: BPI Credit Card'));
    });

    test('an unknown entity is an error that says how to fix it', () async {
      final r = await ex.runRead(const AiToolCall(
          id: 't', name: 'find', input: {'entity': 'transactions'}));
      expect(r.ok, isFalse);
      expect(r.summary, startsWith('status: error'));
      expect(r.summary, contains('findTransactions'));
    });
  });

  test('the catalogue has one find read and none of the seven old ones', () {
    expect(financeToolNamed('find')?.kind, AiToolKind.read);
    for (final old in [
      'findBills',
      'findReceivables',
      'findSetAsides',
      'findBudgets',
      'findInstallments',
      'findAccounts',
      'findBudgetGroups',
    ]) {
      expect(financeToolNamed(old), isNull, reason: old);
    }
  });
}
