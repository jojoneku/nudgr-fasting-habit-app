// Credit billing cycles end to end: which closed cycles become statement bills,
// what the dashboard says is due, and when the due reminder fires.
//
// Every test pins "today" through the presenters' injected clock, because the
// whole point is the calendar: a charge the day after a close rides the NEXT
// statement, and a statement that closed at ₱0 asks for nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intermittent_fasting/models/finance/bill.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/utils/credit_cycle.dart';
import 'package:intermittent_fasting/utils/credit_finance_charge.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

import '../mocks.mocks.dart';

/// Maya Easy Credit as the user set it up: closes the 20th, due 15 days later
/// (entered as "the 5th" before the offset existed). Pay-in-full by default.
FinancialAccount _maya(double balance) => FinancialAccount(
      id: 'maya',
      name: 'Maya Easy Credit',
      category: AccountCategory.creditLine,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 20000,
      statementDay: 20,
      paymentDueDay: 5,
      dueDaysAfterStatement: 15,
    );

/// Maribank card: closes the 5th, due the 14th.
FinancialAccount _maribank(double balance) => FinancialAccount(
      id: 'maribank',
      name: 'Maribank',
      category: AccountCategory.creditCard,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 20000,
      statementDay: 5,
      paymentDueDay: 14,
    );

FinancialAccount _card(
  String id, {
  required double balance,
  required int statementDay,
  required int paymentDueDay,
  AccountCategory category = AccountCategory.creditCard,
  CreditMinimumRule? minimumRule,
  double? minimumFixedAmount,
}) =>
    FinancialAccount(
      id: id,
      name: id,
      category: category,
      balance: balance,
      colorHex: '#FFFFFF',
      icon: 'creditCard',
      creditLimit: 200000,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      minimumRule: minimumRule,
      minimumFixedAmount: minimumFixedAmount,
    );

FinancialAccount _bank(String id) => FinancialAccount(
      id: id,
      name: id,
      category: AccountCategory.bank,
      balance: 50000,
      colorHex: '#FFFFFF',
      icon: 'bank',
    );

TransactionRecord _charge(
        String id, String accountId, double amount, DateTime on) =>
    TransactionRecord(
      id: id,
      date: on,
      accountId: accountId,
      categoryId: 'c1',
      amount: amount,
      type: TransactionType.outflow,
      description: id,
      month: toMonthKey(on),
    );

Bill _statement({
  required String id,
  required String accountId,
  required String month,
  required double amount,
  int dueDay = 14,
  bool auto = true,
  bool isPaid = false,
  String? transactionId,
}) =>
    Bill(
      id: id,
      name: '$accountId statement',
      billType: BillType.creditCard,
      amount: amount,
      dueDay: dueDay,
      month: month,
      categoryId: 'c1',
      accountId: accountId,
      isPaid: isPaid,
      paidAmount: isPaid ? amount : null,
      transactionId: transactionId,
      paymentNote: auto ? Bill.autoStatementNote : null,
    );

FinanceCategory _expenseCat(String id) => FinanceCategory(
      id: id,
      name: 'Misc',
      type: CategoryType.expense,
      icon: 'x',
      colorHex: '#FFFFFF',
    );

Future<void> _waitForLoad(LedgerPresenter p) async {
  while (p.isLoading) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStorageService storage;
  late MockStatsPresenter stats;
  late MockNotificationService notifications;

  /// What the bills presenter last saved — read back by [TreasuryDashboard
  /// Presenter.load], as it is in the app.
  late List<Bill> storedBills;

  void stubStorage({
    required List<FinancialAccount> accounts,
    List<TransactionRecord> transactions = const [],
    List<Bill> bills = const [],
  }) {
    storedBills = [...bills];
    when(storage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    when(storage.loadAccounts()).thenAnswer((_) async => accounts);
    when(storage.saveAccounts(any)).thenAnswer((_) async {});
    when(storage.loadFinanceCategories())
        .thenAnswer((_) async => [_expenseCat('c1')]);
    when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
    when(storage.loadTransactions()).thenAnswer((_) async => transactions);
    when(storage.saveTransactions(any)).thenAnswer((_) async {});
    when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
    when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
    when(storage.loadBills()).thenAnswer((_) async => storedBills);
    when(storage.saveBills(any)).thenAnswer((inv) async {
      storedBills = List<Bill>.from(inv.positionalArguments.first as List);
    });
    when(storage.loadReceivables()).thenAnswer((_) async => []);
    when(storage.saveReceivables(any)).thenAnswer((_) async {});
    when(storage.loadBudgetedExpenses()).thenAnswer((_) async => []);
    when(storage.loadBudgets()).thenAnswer((_) async => []);
    when(storage.loadMonthlySummaries()).thenAnswer((_) async => []);
    when(storage.saveMonthlySummaries(any)).thenAnswer((_) async {});
    when(storage.loadAwardedXpKeys()).thenAnswer((_) async => <String>{});
    when(storage.saveAwardedXpKeys(any)).thenAnswer((_) async {});
    when(stats.addXp(any)).thenAnswer((_) async {});
    when(stats.stats).thenReturn(UserStats.initial());
  }

  /// Ledger + bills (loaded, statements generated) + dashboard, all at [today].
  Future<
      ({
        LedgerPresenter ledger,
        BillsReceivablesPresenter bills,
        TreasuryDashboardPresenter dashboard,
      })> buildGraph(DateTime today) async {
    DateTime clock() => today;
    final ledger = LedgerPresenter(storage, stats);
    await _waitForLoad(ledger);
    final bills = BillsReceivablesPresenter(storage, ledger, stats,
        notifications: notifications, clock: clock);
    await bills.load();
    final dashboard =
        TreasuryDashboardPresenter(storage, ledger, null, bills, clock);
    await dashboard.load();
    return (ledger: ledger, bills: bills, dashboard: dashboard);
  }

  FinancialAccount accountIn(LedgerPresenter ledger, String id) =>
      ledger.accounts.firstWhere((a) => a.id == id);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = MockStorageService();
    stats = MockStatsPresenter();
    notifications = MockNotificationService();
  });

  final oct3 = DateTime(2026, 10, 3, 10);

  group('the Maya case (today Oct 3)', () {
    // ₱10,006 drawn on Sep 21 — the day AFTER the Sep 20 close — so the Sep
    // statement closed at ₱0 and the draw rides the Oct 20 statement (due
    // Nov 4). Maribank's Sep 10 charge likewise sits on its Oct 5 statement.
    // Maribank's paid August statement reaches the backfill window back into
    // September, which is what made the old generator file ₱0 bills for both.
    void stubMaya({List<Bill> extraBills = const []}) => stubStorage(
          accounts: [_maya(10006), _maribank(2711.35), _bank('gcash')],
          transactions: [
            _charge('draw', 'maya', 10006, DateTime(2026, 9, 21, 14)),
            _charge('mari', 'maribank', 2711.35, DateTime(2026, 9, 10, 12)),
          ],
          bills: [
            _statement(
                id: 'mari-aug',
                accountId: 'maribank',
                month: '2026-08',
                amount: 1200,
                isPaid: true),
            ...extraBills,
          ],
        );

    test('no statement is generated, and no ₱0 bill appears', () async {
      stubMaya();
      final g = await buildGraph(oct3);

      expect(
        g.bills.allBills.where((b) => !b.isPaid && b.amount <= 0),
        isEmpty,
        reason: 'a cycle that closed owing nothing is no bill',
      );
      expect(g.bills.allBills.where((b) => b.accountId == 'maya'), isEmpty,
          reason: 'the Sep 20 statement was ₱0; the draw is on Oct 20');
      expect(
        g.bills.allBills.where((b) => b.accountId == 'maribank' && !b.isPaid),
        isEmpty,
        reason: 'the Sep 10 charge is on the Oct 5 statement, not closed yet',
      );
    });

    test('the dashboard says nothing is due, and where the draw will land',
        () async {
      stubMaya();
      final g = await buildGraph(oct3);
      final maya = accountIn(g.ledger, 'maya');

      final due = g.dashboard.creditDueInfo(maya);
      expect(due?.label, 'No payment due');
      expect(due?.imminent, isFalse);
      expect(g.dashboard.creditMinimumDue(maya), isNull);
      expect(g.dashboard.openCreditStatement(maya), isNull);

      final note = g.dashboard.creditCycleNote(maya);
      expect(note?.warning, isFalse);
      expect(note?.label, 'Statement closes Oct 20 · due Nov 4');

      final mari = accountIn(g.ledger, 'maribank');
      expect(g.dashboard.creditDueInfo(mari)?.label, 'No payment due');
      expect(g.dashboard.creditCycleNote(mari)?.label,
          'Statement closes Oct 5 · due Oct 14');
    });

    test('no due reminder is scheduled; any old one is cancelled', () async {
      stubMaya();
      await buildGraph(oct3);

      verifyNever(notifications.scheduleCreditStatementDueReminder(
        accountId: anyNamed('accountId'),
        accountName: anyNamed('accountName'),
        dueDate: anyNamed('dueDate'),
      ));
      verify(notifications.cancelCreditDueReminder('maya'))
          .called(greaterThan(0));
      verify(notifications.cancelCreditDueReminder('maribank'))
          .called(greaterThan(0));
    });

    test('the phantom ₱0 bills the old generator stored are swept on load',
        () async {
      stubMaya(extraBills: [
        _statement(
            id: 'phantom-maya',
            accountId: 'maya',
            month: '2026-10',
            amount: 0,
            dueDay: 5),
        _statement(
            id: 'phantom-mari',
            accountId: 'maribank',
            month: '2026-09',
            amount: 0),
      ]);
      final g = await buildGraph(oct3);

      final ids = g.bills.allBills.map((b) => b.id).toSet();
      expect(ids, isNot(contains('phantom-maya')));
      expect(ids, isNot(contains('phantom-mari')));
      expect(storedBills.map((b) => b.id), isNot(contains('phantom-maya')),
          reason: 'the sweep is persisted');
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'maya'))?.label,
          'No payment due');
    });
  });

  group('₱0 placeholder sweep', () {
    test('removes an unpaid ₱0 auto-statement, keeps paid and transacted ones',
        () async {
      stubStorage(
        accounts: [_card('sp', balance: 0, statementDay: 5, paymentDueDay: 14)],
        bills: [
          _statement(
              id: 'phantom', accountId: 'sp', month: '2026-09', amount: 0),
          _statement(
              id: 'paid-zero',
              accountId: 'sp',
              month: '2026-08',
              amount: 0,
              isPaid: true),
          _statement(
              id: 'txn-zero',
              accountId: 'sp',
              month: '2026-07',
              amount: 0,
              transactionId: 't1'),
          // A ₱0 bill the USER keyed is theirs to delete.
          _statement(
              id: 'manual-zero',
              accountId: 'sp',
              month: '2026-06',
              amount: 0,
              auto: false),
        ],
      );
      final g = await buildGraph(oct3);

      final ids = g.bills.allBills.map((b) => b.id).toSet();
      expect(ids, isNot(contains('phantom')));
      expect(
          ids, containsAll(<String>['paid-zero', 'txn-zero', 'manual-zero']));
    });
  });

  group('backfill of the cycle that closed last month', () {
    test('bills the balance at close, under the due month and due day',
        () async {
      // Closes the 25th, due the 10th: the Sep 25 statement is due Oct 10 —
      // still ahead on Oct 3. ₱500 charged after the close is next cycle's.
      stubStorage(
        accounts: [
          _card('bpi', balance: 3500, statementDay: 25, paymentDueDay: 10),
        ],
        transactions: [
          _charge('in-cycle', 'bpi', 3000, DateTime(2026, 9, 15)),
          _charge('after-close', 'bpi', 500, DateTime(2026, 9, 28)),
        ],
      );
      final g = await buildGraph(oct3);

      final stmts =
          g.bills.allBills.where((b) => b.accountId == 'bpi').toList();
      expect(stmts, hasLength(1));
      expect(stmts.single.isAutoStatement, isTrue);
      expect(stmts.single.month, '2026-10');
      expect(stmts.single.dueDay, 10);
      expect(stmts.single.amount, closeTo(3000, 0.001));

      final bpi = accountIn(g.ledger, 'bpi');
      final due = g.dashboard.creditDueInfo(bpi);
      expect(due?.label, 'Due in 7 days · min ₱850.00');
      expect(due?.imminent, isFalse);
      expect(g.dashboard.creditMinimumDue(bpi), 850);

      verify(notifications.scheduleCreditStatementDueReminder(
        accountId: 'bpi',
        accountName: 'bpi',
        dueDate: DateTime(2026, 10, 10),
      )).called(greaterThan(0));
    });

    test('a cycle already past due is not backfilled', () async {
      // Closes the 10th, due the 25th: the Sep 10 statement was due Sep 25 —
      // past on Oct 3. Its unpaid balance rides the Oct 10 statement, so
      // billing it too would count the same debt twice. An older paid
      // statement stretches the window back to August as well.
      stubStorage(
        accounts: [
          _card('ub', balance: 4000, statementDay: 10, paymentDueDay: 25),
        ],
        transactions: [
          _charge('aug', 'ub', 1500, DateTime(2026, 8, 5)),
          _charge('sep', 'ub', 2500, DateTime(2026, 9, 5)),
        ],
        bills: [
          _statement(
              id: 'ub-jul',
              accountId: 'ub',
              month: '2026-07',
              amount: 900,
              dueDay: 25,
              isPaid: true),
        ],
      );
      final g = await buildGraph(oct3);

      expect(
        g.bills.allBills.where((b) => b.accountId == 'ub' && !b.isPaid),
        isEmpty,
      );
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'ub'))?.label,
          'No payment due');
    });
  });

  group('days-after-close account', () {
    test('files under the due month with the offset due day (Oct 20 + 15)',
        () async {
      final oct21 = DateTime(2026, 10, 21, 9);
      stubStorage(
        accounts: [_maya(5000), _bank('gcash')],
        transactions: [_charge('draw', 'maya', 5000, DateTime(2026, 10, 1))],
      );
      final g = await buildGraph(oct21);

      final maya = accountIn(g.ledger, 'maya');
      final cycle = maya.cycleClosingIn(2026, 10)!;
      expect(cycle.dueMonthKey, '2026-11');
      expect(cycle.due.day, 4);

      final stmts =
          g.bills.allBills.where((b) => b.accountId == 'maya').toList();
      expect(stmts, hasLength(1),
          reason: 'the Sep 20 cycle (due Oct 5) is past due — not backfilled');
      expect(stmts.single.month, cycle.dueMonthKey);
      expect(stmts.single.dueDay, cycle.due.day);
      expect(stmts.single.amount, closeTo(5000, 0.001));

      final due = g.dashboard.creditDueInfo(maya);
      expect(due?.label, 'Due in 14 days · ₱5,000.00 in full');
      expect(due?.imminent, isFalse);
      expect(g.dashboard.creditMinimumDue(maya), 5000);
      expect(g.dashboard.creditCycleNote(maya)?.label,
          'Statement closes Nov 20 · due Dec 5');

      verify(notifications.scheduleCreditStatementDueReminder(
        accountId: 'maya',
        accountName: 'Maya Easy Credit',
        dueDate: DateTime(2026, 11, 4),
      )).called(greaterThan(0));
    });

    test('quickPayCard clearing the line settles its next-month statement',
        () async {
      final oct21 = DateTime(2026, 10, 21, 9);
      stubStorage(
        accounts: [_maya(5000), _bank('gcash')],
        transactions: [_charge('draw', 'maya', 5000, DateTime(2026, 10, 1))],
      );
      final g = await buildGraph(oct21);

      await g.bills.quickPayCard(
          accountId: 'maya', fromAccountId: 'gcash', amount: 5000);

      final stmt = g.bills.allBills.singleWhere((b) => b.accountId == 'maya');
      expect(stmt.isPaid, isTrue);
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'maya'))?.label,
          'No payment due');
      verify(notifications.cancelCreditDueReminder('maya'))
          .called(greaterThan(0));
    });
  });

  group('dashboard due line with an open statement (today Oct 3)', () {
    Future<TreasuryDashboardPresenter> dashboardWith(
      List<FinancialAccount> accounts,
      List<Bill> bills,
    ) async {
      stubStorage(accounts: accounts, bills: bills);
      final p =
          TreasuryDashboardPresenter(storage, null, null, null, () => oct3);
      await p.load();
      return p;
    }

    test('percent of balance: the floor on a small statement', () async {
      final cc =
          _card('cc', balance: 9000, statementDay: 25, paymentDueDay: 10);
      final p = await dashboardWith([
        cc
      ], [
        _statement(
            id: 's',
            accountId: 'cc',
            month: '2026-10',
            amount: 3000,
            dueDay: 10),
      ]);
      // 3000 × 3.57% = 107.10 → the ₱850 floor. The live ₱9,000 balance is
      // not what is due.
      expect(p.creditMinimumDue(cc), 850);
      expect(p.creditDueInfo(cc)?.label, 'Due in 7 days · min ₱850.00');
    });

    test('percent of balance: the rate on a large statement', () async {
      final cc =
          _card('cc', balance: 100000, statementDay: 25, paymentDueDay: 4);
      final p = await dashboardWith([
        cc
      ], [
        _statement(
            id: 's',
            accountId: 'cc',
            month: '2026-10',
            amount: 100000,
            dueDay: 4),
      ]);
      expect(p.creditMinimumDue(cc), closeTo(3570, 0.001));
      final due = p.creditDueInfo(cc);
      expect(due?.label, 'Due tomorrow · min ₱3,570.00');
      expect(due?.imminent, isTrue);
    });

    test('fixed amount, and capped at the statement', () async {
      final line = _card('line',
          balance: 4000,
          statementDay: 20,
          paymentDueDay: 5,
          category: AccountCategory.creditLine,
          minimumRule: CreditMinimumRule.fixedAmount,
          minimumFixedAmount: 1500);
      final small = _card('small',
          balance: 1000,
          statementDay: 20,
          paymentDueDay: 3,
          category: AccountCategory.creditLine,
          minimumRule: CreditMinimumRule.fixedAmount,
          minimumFixedAmount: 1500);
      final p = await dashboardWith([
        line,
        small
      ], [
        _statement(
            id: 's1',
            accountId: 'line',
            month: '2026-10',
            amount: 4000,
            dueDay: 5),
        _statement(
            id: 's2',
            accountId: 'small',
            month: '2026-10',
            amount: 1000,
            dueDay: 3),
      ]);

      expect(p.creditMinimumDue(line), 1500);
      final lineDue = p.creditDueInfo(line);
      expect(lineDue?.label, 'Due in 2 days · min ₱1,500.00');
      expect(lineDue?.imminent, isTrue);

      expect(p.creditMinimumDue(small), 1000,
          reason: 'a fixed minimum never exceeds the statement');
      expect(p.creditDueInfo(small)?.label, 'Due today · min ₱1,000.00');
    });

    test('pay in full, overdue', () async {
      final bnpl = _card('bnpl',
          balance: 2500,
          statementDay: 15,
          paymentDueDay: 1,
          category: AccountCategory.bnpl);
      final p = await dashboardWith([
        bnpl
      ], [
        _statement(
            id: 's',
            accountId: 'bnpl',
            month: '2026-10',
            amount: 2500,
            dueDay: 1),
      ]);
      expect(p.creditMinimumDue(bnpl), 2500);
      final due = p.creditDueInfo(bnpl);
      expect(due?.label, 'Overdue by 2 days · ₱2,500.00 in full');
      expect(due?.imminent, isTrue);
    });

    test('the earliest-due unpaid statement wins; paid ones are ignored',
        () async {
      final cc = _card('cc', balance: 5000, statementDay: 25, paymentDueDay: 2);
      final p = await dashboardWith([
        cc
      ], [
        _statement(
            id: 'paid',
            accountId: 'cc',
            month: '2026-08',
            amount: 900,
            dueDay: 2,
            isPaid: true),
        _statement(
            id: 'later',
            accountId: 'cc',
            month: '2026-11',
            amount: 4000,
            dueDay: 2),
        // Hand-keyed statements count too.
        _statement(
            id: 'sep',
            accountId: 'cc',
            month: '2026-10',
            amount: 1000,
            dueDay: 2,
            auto: false),
      ]);
      expect(p.openCreditStatement(cc)?.id, 'sep');
      expect(p.creditDueInfo(cc)?.label, 'Overdue by 1 day · min ₱850.00');
    });

    test('non-credit accounts have no due line', () async {
      final bank = _bank('bpi');
      final p = await dashboardWith([bank], []);
      expect(p.creditDueInfo(bank), isNull);
      expect(p.creditMinimumDue(bank), isNull);
      expect(p.creditCycleNote(bank), isNull);
    });
  });

  group('statement payment progress is read off the ledger', () {
    // BPI closes the 25th, due the 10th. ₱2,711.35 was charged inside the
    // Sep 25 cycle; ₱500 after the close rides the next one. So the Sep 25
    // statement (due Oct 10) is ₱2,711.35, minimum ₱850 (the floor).
    void stubBpi() => stubStorage(
          accounts: [
            _card('bpi', balance: 3211.35, statementDay: 25, paymentDueDay: 10),
            _bank('gcash'),
          ],
          transactions: [
            _charge('in-cycle', 'bpi', 2711.35, DateTime(2026, 9, 15)),
            _charge('post-close', 'bpi', 500, DateTime(2026, 9, 28)),
          ],
        );

    Bill statementOf(BillsReceivablesPresenter bills, String accountId) =>
        bills.allBills.singleWhere((b) => b.accountId == accountId);

    test('a payment below the minimum leaves the statement open', () async {
      stubBpi();
      final g = await buildGraph(oct3);
      final stmt = statementOf(g.bills, 'bpi');
      expect(stmt.amount, closeTo(2711.35, 0.001));

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 350, accountId: 'gcash', paidDate: oct3);

      final after = statementOf(g.bills, 'bpi');
      expect(after.isPaid, isFalse,
          reason: '₱350 on a ₱2,711.35 statement does not settle it');
      expect(after.paidAmount, closeTo(350, 0.001));
      final progress = g.bills.statementProgress(after)!;
      expect(progress.remaining, closeTo(2361.35, 0.001));
      expect(progress.minimumMet, isFalse);

      final bpi = accountIn(g.ledger, 'bpi');
      final due = g.dashboard.creditDueInfo(bpi);
      expect(due?.label, 'Due in 7 days · ₱500.00 left of min');
      expect(due?.imminent, isFalse);
      expect(g.dashboard.creditMinimumDue(bpi), closeTo(500, 0.001));
      expect(g.dashboard.monthUnpaidBills, closeTo(2361.35, 0.001),
          reason: 'only what is left on the statement is still to pay');
    });

    test('once the minimum is met it reads "Min paid", never imminent',
        () async {
      stubBpi();
      final g = await buildGraph(oct3);
      final stmt = statementOf(g.bills, 'bpi');

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 850, accountId: 'gcash', paidDate: oct3);

      expect(statementOf(g.bills, 'bpi').isPaid, isFalse);
      final bpi = accountIn(g.ledger, 'bpi');
      final due = g.dashboard.creditDueInfo(bpi);
      expect(due?.label, 'Min paid · ₱1,861.35 left to avoid interest');
      expect(due?.imminent, isFalse);
      expect(g.dashboard.creditMinimumDue(bpi), isNull);
    });

    test('the bill shows what is paid, what is left, and can be undone',
        () async {
      stubBpi();
      final g = await buildGraph(oct3);
      final stmt = statementOf(g.bills, 'bpi');
      expect(g.bills.statementProgressNote(stmt), isNull,
          reason: 'nothing paid yet: no progress line');
      expect(g.bills.statementProgressFraction(stmt), isNull);
      expect(g.bills.billAmountOwed(stmt), closeTo(2711.35, 0.001));
      expect(g.bills.hasUndoablePayment(stmt), isFalse);

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 350, accountId: 'gcash', paidDate: oct3);
      var after = statementOf(g.bills, 'bpi');
      expect(g.bills.statementProgressNote(after), 'Paid ₱350.00 of ₱2,711.35');
      expect(g.bills.statementProgressFraction(after),
          closeTo(350 / 2711.35, 0.0001));
      expect(g.bills.billAmountOwed(after), closeTo(2361.35, 0.001),
          reason: 'the pay sheet prefills what is left');
      expect(g.bills.hasUndoablePayment(after), isTrue);

      await g.bills.markBillPaid(after.id,
          paidAmount: 500, accountId: 'gcash', paidDate: oct3);
      after = statementOf(g.bills, 'bpi');
      expect(g.bills.statementProgressNote(after),
          'Paid ₱850.00 of ₱2,711.35 · min met');

      await g.bills.markBillPaid(after.id,
          paidAmount: 1861.35, accountId: 'gcash', paidDate: oct3);
      after = statementOf(g.bills, 'bpi');
      expect(after.isPaid, isTrue);
      expect(g.bills.statementProgressNote(after), isNull,
          reason: 'fully paid reads as an ordinary paid bill');
      expect(g.bills.billAmountOwed(after), 0);
    });

    test('minimum met and past the due date is still not imminent', () async {
      stubStorage(
        accounts: [
          _card('bpi', balance: 1861.35, statementDay: 25, paymentDueDay: 10),
          _bank('gcash'),
        ],
        transactions: [
          _charge('in-cycle', 'bpi', 2711.35, DateTime(2026, 9, 15)),
          TransactionRecord(
            id: 'pay',
            date: DateTime(2026, 10, 1),
            accountId: 'bpi',
            categoryId: 'c1',
            amount: 850,
            type: TransactionType.inflow,
            description: 'payment',
            month: '2026-10',
          ),
        ],
        // Generated on Oct 3, before the due date passed.
        bills: [
          _statement(
              id: 'sep',
              accountId: 'bpi',
              month: '2026-10',
              amount: 2711.35,
              dueDay: 10),
        ],
      );
      // An existing install: the one-time relocation of pre-fix statements
      // has long run (otherwise it would move this correctly filed one).
      SharedPreferences.setMockInitialValues(
          {'bills.migration.shifted_cc_statement_month_v1': true});
      final g = await buildGraph(DateTime(2026, 10, 12, 9));

      final due = g.dashboard.creditDueInfo(accountIn(g.ledger, 'bpi'));
      expect(due?.label, 'Min paid · ₱1,861.35 left to avoid interest');
      expect(due?.imminent, isFalse, reason: 'no late fee once min is paid');
    });

    test('paying the statement exactly settles it despite newer charges',
        () async {
      stubBpi();
      final g = await buildGraph(oct3);

      await g.bills.quickPayCard(
          accountId: 'bpi', fromAccountId: 'gcash', amount: 2711.35);

      final stmt = statementOf(g.bills, 'bpi');
      expect(stmt.isPaid, isTrue,
          reason: 'the ₱500 still on the card is next statement\'s');
      expect(accountIn(g.ledger, 'bpi').currentPayable, closeTo(500, 0.001));
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'bpi'))?.label,
          'No payment due');
    });

    test('an overpayment settles it and stays on the card', () async {
      stubBpi();
      final g = await buildGraph(oct3);

      await g.bills
          .quickPayCard(accountId: 'bpi', fromAccountId: 'gcash', amount: 3000);

      final stmt = statementOf(g.bills, 'bpi');
      expect(stmt.isPaid, isTrue);
      expect(stmt.paidAmount, closeTo(2711.35, 0.001));
      expect(accountIn(g.ledger, 'bpi').currentPayable, closeTo(211.35, 0.001),
          reason: 'the excess simply lowers what is owed on the card');
    });

    test('a pay-in-full line paid in part stays due with the remainder',
        () async {
      final oct21 = DateTime(2026, 10, 21, 9);
      stubStorage(
        accounts: [_maya(5000), _bank('gcash')],
        transactions: [_charge('draw', 'maya', 5000, DateTime(2026, 10, 1))],
      );
      final g = await buildGraph(oct21);
      final stmt = statementOf(g.bills, 'maya');

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 2000, accountId: 'gcash', paidDate: oct21);

      expect(statementOf(g.bills, 'maya').isPaid, isFalse);
      final maya = accountIn(g.ledger, 'maya');
      final due = g.dashboard.creditDueInfo(maya);
      expect(due?.label, 'Due in 14 days · ₱3,000.00 left to pay');
      expect(g.dashboard.creditMinimumDue(maya), closeTo(3000, 0.001));
    });

    test('a transfer logged by hand in the ledger after the close counts',
        () async {
      stubBpi();
      final g = await buildGraph(oct3);

      await g.ledger.addTransfer(
        fromAccountId: 'gcash',
        toAccountId: 'bpi',
        amount: 2711.35,
        description: 'BPI payment',
        date: DateTime(2026, 10, 2),
      );

      expect(statementOf(g.bills, 'bpi').isPaid, isTrue);
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'bpi'))?.label,
          'No payment due');
    });

    test('a payment dated on the close day belongs to the statement itself',
        () async {
      // Paid ₱1,000 ON Sep 25: it is netted into the statement (₱1,711.35),
      // so counting it again toward paying that statement would be double.
      stubStorage(
        accounts: [
          _card('bpi', balance: 1711.35, statementDay: 25, paymentDueDay: 10),
          _bank('gcash'),
        ],
        transactions: [
          _charge('in-cycle', 'bpi', 2711.35, DateTime(2026, 9, 15)),
          TransactionRecord(
            id: 'pay-on-close',
            date: DateTime(2026, 9, 25, 18),
            accountId: 'bpi',
            categoryId: 'c1',
            amount: 1000,
            type: TransactionType.inflow,
            description: 'payment',
            month: '2026-09',
          ),
        ],
      );
      final g = await buildGraph(oct3);

      final stmt = statementOf(g.bills, 'bpi');
      expect(stmt.amount, closeTo(1711.35, 0.001));
      expect(stmt.isPaid, isFalse);
      expect(stmt.paidAmount, isNull);
      expect(
          g.ledger.paymentsToLiabilitySince('bpi', DateTime(2026, 9, 25)), 0);
    });

    test('undoing a payment reopens the statement and restores the card',
        () async {
      stubBpi();
      final g = await buildGraph(oct3);
      final stmt = statementOf(g.bills, 'bpi');

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 2711.35, accountId: 'gcash', paidDate: oct3);
      expect(statementOf(g.bills, 'bpi').isPaid, isTrue);

      await g.bills.markBillUnpaid(stmt.id);

      final reopened = statementOf(g.bills, 'bpi');
      expect(reopened.isPaid, isFalse);
      expect(reopened.paidAmount, isNull);
      expect(
          accountIn(g.ledger, 'bpi').currentPayable, closeTo(3211.35, 0.001));
      expect(g.dashboard.creditDueInfo(accountIn(g.ledger, 'bpi'))?.label,
          'Due in 7 days · min ₱850.00');
    });

    test('a partial payment can be undone too', () async {
      stubBpi();
      final g = await buildGraph(oct3);
      final stmt = statementOf(g.bills, 'bpi');

      await g.bills.markBillPaid(stmt.id,
          paidAmount: 350, accountId: 'gcash', paidDate: oct3);
      expect(g.bills.billHasLedgerEntry(statementOf(g.bills, 'bpi')), isTrue);

      await g.bills.markBillUnpaid(stmt.id);

      expect(statementOf(g.bills, 'bpi').paidAmount, isNull);
      expect(
          accountIn(g.ledger, 'bpi').currentPayable, closeTo(3211.35, 0.001));
    });

    test('non-credit bills keep the plain paid flag for any amount', () async {
      stubStorage(
        accounts: [_bank('gcash')],
        bills: [
          Bill(
            id: 'net',
            name: 'Internet',
            billType: BillType.utility,
            amount: 1500,
            dueDay: 20,
            month: '2026-10',
            categoryId: 'c1',
          ),
        ],
      );
      final g = await buildGraph(oct3);

      await g.bills.markBillPaid('net',
          paidAmount: 1000, accountId: 'gcash', paidDate: oct3);

      final net = g.bills.allBills.singleWhere((b) => b.id == 'net');
      expect(net.isPaid, isTrue);
      expect(net.paidAmount, 1000);
      expect(g.bills.statementProgress(net), isNull);
    });
  });

  group('pure helpers', () {
    test('computeMinimumForRule by rule', () {
      expect(
          computeMinimumForRule(
              rule: CreditMinimumRule.percentOfBalance, statement: 3000),
          850);
      expect(
          computeMinimumForRule(
              rule: CreditMinimumRule.fixedAmount,
              statement: 3000,
              fixedAmount: 1200),
          1200);
      expect(
          computeMinimumForRule(
              rule: CreditMinimumRule.fixedAmount, statement: 3000),
          3000,
          reason: 'no fixed amount set → the whole statement');
      expect(
          computeMinimumForRule(
              rule: CreditMinimumRule.payInFull, statement: 3000),
          3000);
      expect(
          computeMinimumForRule(
              rule: CreditMinimumRule.payInFull, statement: 0),
          0);
    });

    test('creditStatementDueDate clamps the day to the month', () {
      final b = _statement(
          id: 'x', accountId: 'a', month: '2026-02', amount: 1, dueDay: 31);
      expect(creditStatementDueDate(b), DateTime(2026, 2, 28));
    });
  });
}
