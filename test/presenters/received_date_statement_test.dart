import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intermittent_fasting/utils/credit_statement_breakdown.dart';

import '../mocks.mocks.dart';

/// Plan 072: Shopee PayLater posts an order when it is received. The order
/// date stays the record's date; an optional received date decides which
/// statement it lands on.
void main() {
  // Statement day 4: the cycle closing Nov 4 runs Oct 5 – Nov 4.
  FinancialAccount spay({bool postsOnReceipt = true, double balance = 0}) =>
      FinancialAccount(
        id: 'spay',
        name: 'SPayLater',
        category: AccountCategory.bnpl,
        balance: balance,
        creditLimit: 20000,
        statementDay: 4,
        paymentDueDay: 15,
        colorHex: '#EE4D2D',
        icon: 'wallet',
        postsOnReceipt: postsOnReceipt,
      );

  TransactionRecord order(String id, DateTime date, double amount,
          {DateTime? postedDate}) =>
      TransactionRecord(
        id: id,
        date: date,
        accountId: 'spay',
        categoryId: 'shop',
        amount: amount,
        type: TransactionType.outflow,
        description: id,
        month: '${date.year}-${date.month.toString().padLeft(2, '0')}',
        postedDate: postedDate,
      );

  group('models', () {
    test('transaction received date round-trips and can be cleared', () {
      final t = order('a', DateTime(2026, 10, 28), 500,
          postedDate: DateTime(2026, 11, 6));
      final back = TransactionRecord.fromJson(t.toJson());
      expect(back.postedDate, DateTime(2026, 11, 6));
      expect(back.statementDate, DateTime(2026, 11, 6));
      expect(back.postsOnDifferentDay, isTrue);
      final cleared = back.copyWith(postedDate: null);
      expect(cleared.postedDate, isNull);
      expect(cleared.statementDate, DateTime(2026, 10, 28));
      // Omitting it keeps it.
      expect(back.copyWith(amount: 1).postedDate, DateTime(2026, 11, 6));
    });

    test('a record saved before the field loads with no received date', () {
      final json = order('a', DateTime(2026, 10, 28), 500).toJson()
        ..remove('postedDate');
      expect(TransactionRecord.fromJson(json).postedDate, isNull);
    });

    test('account flag and installment received date round-trip', () {
      expect(FinancialAccount.fromJson(spay().toJson()).postsOnReceipt, isTrue);
      expect(
          FinancialAccount.fromJson(spay(postsOnReceipt: false).toJson())
              .postsOnReceipt,
          isFalse);
      final plan = Installment(
        id: 'p',
        name: 'Phone',
        accountId: 'spay',
        totalAmount: 6000,
        monthlyAmount: 1000,
        totalMonths: 6,
        startMonth: '2026-11',
        purchaseDate: DateTime(2026, 10, 28),
        postedDate: DateTime(2026, 11, 6),
      );
      final back = Installment.fromJson(plan.toJson());
      expect(back.postedDate, DateTime(2026, 11, 6));
      expect(back.copyWith(postedDate: null).postedDate, isNull);
    });
  });

  group('statement breakdown', () {
    final octClose = spay().cycleClosingIn(2026, 11)!; // Oct 5 – Nov 4
    final novClose = spay().cycleClosingIn(2026, 12)!; // Nov 5 – Dec 4
    Bill bill(String month, double amount) => Bill(
          id: 'b$month',
          name: 'SPayLater statement',
          amount: amount,
          dueDay: 15,
          month: month,
          billType: BillType.creditCard,
          categoryId: 'cat-cc',
          accountId: 'spay',
        );

    test('an order received after the close moves to the next statement', () {
      final txns = [
        order('early', DateTime(2026, 10, 10), 100),
        order('late', DateTime(2026, 10, 28), 500,
            postedDate: DateTime(2026, 11, 6)),
      ];
      final oct = buildStatementBreakdown(
        account: spay(balance: 600),
        bill: bill('2026-11', 100),
        cycle: octClose,
        transactions: txns,
        paid: 0,
      );
      expect(oct.purchases.map((l) => l.txn.id), ['early']);

      final nov = buildStatementBreakdown(
        account: spay(balance: 600),
        bill: bill('2026-12', 600),
        cycle: novClose,
        transactions: txns,
        paid: 0,
      );
      final late = nov.purchases.single;
      expect(late.txn.id, 'late');
      expect(late.dateLabel, 'Ordered 28 Oct · Received 06 Nov');
      expect(late.needsReceivedDate, isFalse);
    });

    test('only unconfirmed orders near the close are flagged', () {
      final txns = [
        order('early', DateTime(2026, 10, 10), 100), // > 14 days before
        order('near', DateTime(2026, 10, 25), 200), // within 14 days
        order('close', DateTime(2026, 11, 4), 300), // on the close
        order('confirmed', DateTime(2026, 11, 1), 50,
            postedDate: DateTime(2026, 11, 1)),
      ];
      final b = buildStatementBreakdown(
        account: spay(balance: 650),
        bill: bill('2026-11', 650),
        cycle: octClose,
        transactions: txns,
        paid: 0,
      );
      expect(
          b.linesNeedingReceivedDate.map((l) => l.txn.id), ['near', 'close']);
      expect(
          b.receivedDateNotice, startsWith('2 orders may post when received'));
    });

    test('accounts without the setting are never flagged', () {
      final b = buildStatementBreakdown(
        account: spay(postsOnReceipt: false, balance: 300),
        bill: bill('2026-11', 300),
        cycle: octClose,
        transactions: [order('close', DateTime(2026, 11, 4), 300)],
        paid: 0,
      );
      expect(b.linesNeedingReceivedDate, isEmpty);
      expect(b.receivedDateNotice, isNull);
    });
  });

  group('ledger', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;
    late LedgerPresenter ledger;

    setUp(() async {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      var savedAccounts = [spay(balance: 600)];
      var savedTxns = [
        order('early', DateTime(2026, 10, 10), 100),
        order('late', DateTime(2026, 10, 28), 500),
      ];
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => savedAccounts);
      when(storage.saveAccounts(any)).thenAnswer((inv) async {
        savedAccounts =
            List.of(inv.positionalArguments.first as List<FinancialAccount>);
      });
      when(storage.loadTransactions()).thenAnswer((_) async => savedTxns);
      when(storage.saveTransactions(any)).thenAnswer((inv) async {
        savedTxns =
            List.of(inv.positionalArguments.first as List<TransactionRecord>);
      });
      when(storage.loadFinanceCategories()).thenAnswer((_) async => []);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(stats.stats).thenReturn(UserStats.initial());
      ledger = LedgerPresenter(storage, stats);
      for (var i = 0; i < 40 && ledger.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    double balance() => ledger.accounts.single.balance;

    test('the statement amount follows the received date; balance does not',
        () async {
      final close = DateTime(2026, 11, 4);
      expect(ledger.payableAsOf('spay', close), 600);

      await ledger.setPostedDate('late', DateTime(2026, 11, 6, 15, 30));
      expect(
          ledger.allTransactions.firstWhere((t) => t.id == 'late').postedDate,
          DateTime(2026, 11, 6),
          reason: 'stored as a day');
      expect(ledger.payableAsOf('spay', close), 100);
      expect(balance(), 600);

      await ledger.setPostedDate('late', null);
      expect(ledger.payableAsOf('spay', close), 600);
    });

    test('"received on order day" confirms several records at once', () async {
      await ledger.markReceivedOnOrderDay(['early', 'late']);
      final byId = {for (final t in ledger.allTransactions) t.id: t};
      expect(byId['early']!.postedDate, DateTime(2026, 10, 10));
      expect(byId['late']!.postedDate, DateTime(2026, 10, 28));
      expect(ledger.payableAsOf('spay', DateTime(2026, 11, 4)), 600);
      expect(balance(), 600);
    });

    test('postsOnReceipt reads the account flag', () {
      expect(ledger.postsOnReceipt('spay'), isTrue);
      expect(ledger.postsOnReceipt('missing'), isFalse);
    });

    test('an installment plan starts from the received date', () {
      final plan = Installment(
        id: 'p',
        name: 'Phone',
        accountId: 'spay',
        totalAmount: 6000,
        monthlyAmount: 1000,
        totalMonths: 6,
        startMonth: '2026-11',
        purchaseDate: DateTime(2026, 10, 28),
      );
      final account = ledger.accounts.single;
      final ordered = ledger.editedPlan(
        plan,
        previousDate: DateTime(2026, 10, 1),
        account: account,
        accountId: 'spay',
        amount: 6000,
        months: 6,
        interestRate: 0,
        date: DateTime(2026, 10, 28),
        name: 'Phone',
        note: null,
        categoryId: null,
      );
      final received = ledger.editedPlan(
        plan,
        previousDate: DateTime(2026, 10, 1),
        account: account,
        accountId: 'spay',
        amount: 6000,
        months: 6,
        interestRate: 0,
        date: DateTime(2026, 10, 28),
        name: 'Phone',
        note: null,
        categoryId: null,
        postedDate: DateTime(2026, 11, 6),
      );
      // Oct 28 is on the statement closing Nov 4 (due Nov 15); a Nov 6
      // receipt is on the one closing Dec 4 (due Dec 15).
      expect(ordered.startMonth, '2026-11');
      expect(received.startMonth, '2026-12');
      expect(received.postedDate, DateTime(2026, 11, 6));
    });
  });
}
