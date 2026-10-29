import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/utils/finance_query.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

// ── Fixture ──────────────────────────────────────────────────────────────────
// Four months, 2026-03 to 2026-06, with 2026-04 empty. "Today" is 2026-06-20.
// Every row that a screen must NOT count is here: transfers (one stamped with
// an expense category), a pocket-to-pocket move, a reimbursable and its
// repayment, an installment purchase record, and an "exclude from totals"
// category on both sides.

final today = DateTime(2026, 6, 20);

FinancialAccount _acc(String id, String name, AccountCategory category) =>
    FinancialAccount(
      id: id,
      name: name,
      category: category,
      balance: 0,
      colorHex: '#FFFFFF',
      icon: 'wallet',
    );

FinanceCategory _cat(String id, String name, CategoryType type,
        {bool exclude = false}) =>
    FinanceCategory(
      id: id,
      name: name,
      type: type,
      icon: 'tag',
      colorHex: '#FFFFFF',
      excludeFromTotals: exclude,
    );

final accounts = [
  _acc('cash', 'CASH', AccountCategory.bank),
  _acc('gcash', 'GCash', AccountCategory.ewallet),
  _acc('sav', 'BPI Savings', AccountCategory.savings),
  _acc('japan', 'Japan Fund', AccountCategory.goal),
  _acc('card', 'BPI Card', AccountCategory.creditCard),
];

final categories = [
  _cat('food', 'Food', CategoryType.expense),
  _cat('transpo', 'Transport', CategoryType.expense),
  _cat('gadgets', 'Gadgets', CategoryType.expense),
  _cat('salary', 'Salary', CategoryType.income),
  _cat('refund', 'Refunds', CategoryType.income, exclude: true),
];

TransactionRecord _t(
  String id,
  int month,
  int day,
  double amount,
  String description, {
  TransactionType type = TransactionType.outflow,
  String account = 'cash',
  String category = 'food',
  String? note,
  String? transferTo,
  String? group,
  bool reimbursable = false,
  String? reimbursementId,
  String? receivableId,
  String? installmentId,
  bool isInstallment = false,
}) =>
    TransactionRecord(
      id: id,
      date: DateTime(2026, month, day),
      accountId: account,
      categoryId: category,
      amount: amount,
      type: type,
      description: description,
      note: note,
      month: '2026-${month.toString().padLeft(2, '0')}',
      transferToAccountId: transferTo,
      transferGroupId: group,
      reimbursable: reimbursable,
      reimbursementReceivableId: reimbursementId,
      receivableId: receivableId,
      installmentId: installmentId,
      isInstallment: isInstallment,
    );

/// Both legs of a transfer, the way `addTransfer` stores them.
List<TransactionRecord> _transfer(
        String group, int month, int day, double amount, String from, String to,
        {String category = 'food'}) =>
    [
      _t('$group-out', month, day, amount, 'Transfer',
          account: from, transferTo: to, group: group, category: category),
      _t('$group-in', month, day, amount, 'Transfer',
          type: TransactionType.inflow,
          account: to,
          transferTo: from,
          group: group,
          category: category),
    ];

final transactions = <TransactionRecord>[
  // 2026-03 — the ledger's first month.
  _t('m1', 3, 1, 30000, 'Salary',
      type: TransactionType.inflow, category: 'salary'),
  _t('m2', 3, 5, 500, 'Jollibee lunch'),
  // Stamped with an expense category, as old transfers were.
  ..._transfer('g1', 3, 7, 5000, 'cash', 'sav'),
  _t('m4', 3, 10, 200, 'Grab ride', account: 'gcash', category: 'transpo'),
  // 2026-04 — nothing.
  // 2026-05
  _t('n1', 5, 1, 30000, 'Salary',
      type: TransactionType.inflow, category: 'salary'),
  _t('n2', 5, 3, 1200, 'Grab food', account: 'gcash', note: 'late dinner'),
  _t('n3', 5, 4, 800, 'Client lunch',
      reimbursable: true, reimbursementId: 'r1'),
  _t('n4', 5, 20, 800, 'Payback Acme',
      type: TransactionType.inflow, category: 'salary', receivableId: 'r1'),
  _t('n5', 5, 8, 36000, 'iPhone',
      account: 'card',
      category: 'gadgets',
      installmentId: 'i1',
      isInstallment: true),
  _t('n6', 5, 25, 3000, 'iPhone installment',
      account: 'card', category: 'gadgets', installmentId: 'i1'),
  _t('n7', 5, 15, 1000, 'Refund from friend',
      type: TransactionType.inflow, category: 'refund'),
  ..._transfer('g2', 5, 16, 2000, 'sav', 'japan'),
  ..._transfer('g3', 5, 17, 500, 'japan', 'cash'),
  // 2026-06 — in progress.
  _t('p1', 6, 1, 30000, 'Salary',
      type: TransactionType.inflow, category: 'salary'),
  _t('p2', 6, 2, 450, 'Jollibee lunch'),
  ..._transfer('g4', 6, 10, 3000, 'gcash', 'sav'),
  _t('p4', 6, 12, 300, 'Excluded thing', category: 'refund'),
  _t('p5', 6, 15, 3000, 'iPhone installment',
      account: 'card', category: 'gadgets', installmentId: 'i1'),
];

FinanceQueryResult run(FinanceQuery q) => runFinanceQuery(
      q,
      transactions: transactions,
      accounts: accounts,
      categories: categories,
      today: today,
    );

Map<String, double> byLabel(FinanceQueryResult r) =>
    {for (final g in r.groups) g.label: g.value};

void main() {
  group('metric totals over the whole history', () {
    test(
        'spend leaves out transfers, reimbursables, installment records '
        'and excluded categories', () {
      final r = run(const FinanceQuery(metric: FinanceMetric.spend));
      // 500 + 200 | 1200 + 3000 | 450 + 3000
      expect(r.total, 8350);
      expect(r.entries, 6);
    });

    test('income leaves out transfers, repayments and excluded categories', () {
      final r = run(const FinanceQuery(metric: FinanceMetric.income));
      expect(r.total, 90000);
      expect(r.entries, 3);
    });

    test('net is income minus spend', () {
      final r = run(const FinanceQuery(metric: FinanceMetric.net));
      expect(r.total, 90000 - 8350);
    });

    test('count counts each transfer once', () {
      final r = run(const FinanceQuery(metric: FinanceMetric.count));
      // 4 in March, 9 in May, 5 in June.
      expect(r.total, 18);
    });

    test('setAside: into pockets, less out of them; pocket to pocket nets 0',
        () {
      final r = run(const FinanceQuery(metric: FinanceMetric.setAside));
      // +5000 | +2000 −2000 −500 | +3000
      expect(r.total, 7500);
    });
  });

  group('groupBy', () {
    test('spend by category', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend, groupBy: FinanceGroupBy.category));
      expect(byLabel(r), {'Gadgets': 6000, 'Food': 2150, 'Transport': 200});
      expect(r.groups.first.label, 'Gadgets');
      expect(r.groups.first.entries, 2);
    });

    test('spend by account', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend, groupBy: FinanceGroupBy.account));
      expect(byLabel(r), {'BPI Card': 6000, 'GCash': 1400, 'CASH': 950});
    });

    test('spend by month lists the empty month as 0, in calendar order', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend, groupBy: FinanceGroupBy.month));
      expect(r.groups.map((g) => g.label),
          ['2026-03', '2026-04', '2026-05', '2026-06']);
      expect(r.groups.map((g) => g.value), [700, 0, 4200, 3450]);
    });

    test('spend by description merges case and spacing', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend, groupBy: FinanceGroupBy.description));
      expect(byLabel(r)['iPhone installment'], 6000);
      expect(byLabel(r)['Jollibee lunch'], 950);
      expect(byLabel(r), isNot(contains('iPhone')));
    });

    test('income by category and by account', () {
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.income, groupBy: FinanceGroupBy.category))),
          {'Salary': 90000});
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.income, groupBy: FinanceGroupBy.account))),
          {'CASH': 90000});
    });

    test('income by month and by description', () {
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.income, groupBy: FinanceGroupBy.month))
              .groups
              .map((g) => g.value),
          [30000, 0, 30000, 30000]);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.income,
              groupBy: FinanceGroupBy.description))),
          {'Salary': 90000});
    });

    test('net by month, category, account and description', () {
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.net, groupBy: FinanceGroupBy.month))
              .groups
              .map((g) => g.value),
          [29300, 0, 25800, 26550]);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.net, groupBy: FinanceGroupBy.category))),
          {
            'Salary': 90000,
            'Gadgets': -6000,
            'Food': -2150,
            'Transport': -200
          });
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.net,
              groupBy: FinanceGroupBy.account)))['CASH'],
          90000 - 950);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.net,
              groupBy: FinanceGroupBy.description)))['Grab food'],
          -1200);
    });

    test('count by month, category, account and description', () {
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.count, groupBy: FinanceGroupBy.month))
              .groups
              .map((g) => g.value),
          [4, 0, 9, 5]);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.count,
              groupBy: FinanceGroupBy.category)))['Salary'],
          4);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.count,
              groupBy: FinanceGroupBy.account)))['BPI Card'],
          3);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.count,
              groupBy: FinanceGroupBy.description)))['Jollibee lunch'],
          2);
    });

    test('setAside by account, month and description', () {
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.setAside,
              groupBy: FinanceGroupBy.account))),
          {'BPI Savings': 6000, 'Japan Fund': 1500});
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.setAside,
                  groupBy: FinanceGroupBy.month))
              .groups
              .map((g) => g.value),
          [5000, 0, -500, 3000]);
      expect(
          byLabel(run(const FinanceQuery(
              metric: FinanceMetric.setAside,
              groupBy: FinanceGroupBy.description))),
          {'Transfer': 7500});
    });

    test('setAside by category is refused: transfers have no category', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.setAside, groupBy: FinanceGroupBy.category));
      expect(r.error, contains('no category'));
    });
  });

  group('filters', () {
    test('query matches all words in any order', () {
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.spend, query: 'lunch jollibee'))
              .total,
          950);
      expect(
          run(const FinanceQuery(metric: FinanceMetric.spend, query: 'grab'))
              .total,
          1400);
      // The note is searched too.
      expect(
          run(const FinanceQuery(
                  metric: FinanceMetric.spend, query: 'dinner grab'))
              .total,
          1200);
    });

    test('category and account match part of the name', () {
      expect(
          run(const FinanceQuery(metric: FinanceMetric.spend, category: 'foo'))
              .total,
          2150);
      expect(
          run(const FinanceQuery(metric: FinanceMetric.spend, account: 'gcash'))
              .total,
          1400);
    });

    test('type narrows by direction', () {
      expect(
          run(const FinanceQuery(metric: FinanceMetric.count, type: 'inflow'))
              .total,
          5);
      expect(
          run(const FinanceQuery(metric: FinanceMetric.count, type: 'transfer'))
              .total,
          4);
    });

    test('month and from/to', () {
      expect(
          run(const FinanceQuery(metric: FinanceMetric.spend, month: '2026-05'))
              .total,
          4200);
      final r = run(FinanceQuery(
          metric: FinanceMetric.spend,
          from: DateTime(2026, 5, 10),
          to: DateTime(2026, 6, 5)));
      // n6 (3000) and p2 (450).
      expect(r.total, 3450);
      expect(r.months, ['2026-05', '2026-06']);
    });

    test('top keeps the biggest groups and reports the rest', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend,
          groupBy: FinanceGroupBy.category,
          top: 2));
      expect(r.groups.map((g) => g.label), ['Gadgets', 'Food']);
      expect(r.otherGroups, 1);
      expect(r.otherValue, 200);
      expect(r.total, 8350);
    });

    test('a bad month is refused', () {
      expect(
          run(const FinanceQuery(metric: FinanceMetric.spend, month: '2026-5'))
              .error,
          isNotNull);
    });
  });

  group('range and average', () {
    test('average since the start counts the empty month as 0', () {
      final r =
          run(const FinanceQuery(metric: FinanceMetric.spend, average: true));
      expect(r.months, ['2026-03', '2026-04', '2026-05', '2026-06']);
      expect(r.monthlyAverage, 8350 / 4);
      expect(r.clampedStart, isFalse);
    });

    test('a start before the ledger is clamped to its first month', () {
      final r = run(FinanceQuery(
          metric: FinanceMetric.spend,
          from: DateTime(2025, 1, 1),
          average: true));
      expect(r.clampedStart, isTrue);
      expect(r.from, DateTime(2026, 3, 1));
      expect(r.monthlyAverage, 8350 / 4);
    });

    test('an end after today is cut to today', () {
      final r = run(FinanceQuery(
          metric: FinanceMetric.spend,
          from: DateTime(2026, 5, 1),
          to: DateTime(2026, 12, 31),
          average: true));
      expect(r.clampedEnd, isTrue);
      expect(r.to, DateTime(2026, 6, 20));
      expect(r.months, ['2026-05', '2026-06']);
    });

    test('group averages divide by the months covered', () {
      final r = run(const FinanceQuery(
          metric: FinanceMetric.spend,
          groupBy: FinanceGroupBy.category,
          average: true));
      expect(r.averageOf(r.groups.first.value), 6000 / 4);
    });
  });

  group('describeFinanceQuery', () {
    test('states the range, months, clamp, total, average and definition', () {
      final text = describeFinanceQuery(
          run(FinanceQuery(
              metric: FinanceMetric.spend,
              groupBy: FinanceGroupBy.category,
              from: DateTime(2025, 1, 1),
              average: true)),
          today);
      expect(text, contains('2026-03-01 to 2026-06-20'));
      expect(
          text, contains('4 months: 2026-03 to 2026-06, 2026-06 in progress'));
      expect(
          text,
          contains("clamped to start at the ledger's first month, "
              '2026-03'));
      expect(text,
          contains('Gadgets: ₱6,000.00 (2 entries) · avg ₱1,500.00/month'));
      expect(text, contains('Total: ₱8,350.00 over 6 entries.'));
      expect(text, contains('Average: ₱2,087.50 a month over 4 months'));
      expect(
          text,
          contains('Definition: spend = outflows the app counts as '
              'spending: excludes transfers, reimbursables, installment purchase '
              'records'));
    });

    test('a negative figure carries a minus sign', () {
      final text = describeFinanceQuery(
          run(const FinanceQuery(
              metric: FinanceMetric.setAside, month: '2026-05')),
          today);
      expect(text, contains('Total: −₱500.00'));
    });

    test('a month before the ledger says so', () {
      final text = describeFinanceQuery(
          run(const FinanceQuery(
              metric: FinanceMetric.spend, month: '2025-05')),
          today);
      expect(
          text,
          contains('before the ledger begins (first entry in '
              '2026-03)'));
    });

    test('a count is a number, not pesos', () {
      final text = describeFinanceQuery(
          run(const FinanceQuery(metric: FinanceMetric.count)), today);
      expect(text, contains('Total: 18.'));
    });
  });

  // The screens and this tool must give one figure for one concept (Plan 065
  // rule 4), so each month is checked against the presenter that shows it.
  group('matches the screens', () {
    late MockStorageService storage;
    late MockStatsPresenter stats;

    setUp(() {
      storage = MockStorageService();
      stats = MockStatsPresenter();
      when(storage.loadNotificationPreferences())
          .thenAnswer((_) async => NotificationPreferences.defaults());
      when(storage.loadAccounts()).thenAnswer((_) async => accounts);
      when(storage.loadFinanceCategories()).thenAnswer((_) async => categories);
      when(storage.loadTransactions()).thenAnswer((_) async => transactions);
      when(storage.loadFinanceDictionary()).thenAnswer((_) async => []);
      when(storage.saveTransactions(any)).thenAnswer((_) async {});
      when(storage.saveAccounts(any)).thenAnswer((_) async {});
      when(storage.saveFinanceCategories(any)).thenAnswer((_) async {});
      when(storage.saveFinanceDictionary(any)).thenAnswer((_) async {});
      when(stats.addXp(any)).thenAnswer((_) async {});
      when(stats.stats).thenReturn(UserStats.initial());
    });

    test('ledger month spend, income and net; History set-aside', () async {
      final ledger = LedgerPresenter(storage, stats);
      // Built while the ledger loads, so it mirrors the loaded ledger.
      final history = TreasuryHistoryPresenter(storage, ledger);
      while (ledger.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (final month in ['2026-03', '2026-04', '2026-05', '2026-06']) {
        ledger.setMonth(month);
        double total(FinanceMetric m) =>
            run(FinanceQuery(metric: m, month: month)).total;
        expect(total(FinanceMetric.spend), ledger.filteredMonthOutflow,
            reason: 'spend $month');
        expect(total(FinanceMetric.income), ledger.filteredMonthInflow,
            reason: 'income $month');
        expect(total(FinanceMetric.net), ledger.filteredMonthNet,
            reason: 'net $month');
        expect(total(FinanceMetric.setAside),
            history.monthlySavingsContribution(month),
            reason: 'setAside $month');
      }
      history.dispose();
    });
  });
}
