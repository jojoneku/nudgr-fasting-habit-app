import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/services/cloud_ai_coach_service.dart';
import 'package:intermittent_fasting/utils/finance_tool_catalogue.dart';

/// The fixtures the model tool-choice eval sends to Bedrock (Plan 065 phase 2).
///
/// `backend/ai-coach/evals/run_eval.py` cannot run Dart, so it reads the tool
/// catalogue and the snapshot from committed JSON. These tests fail when the
/// catalogue or the snapshot renderer changes and the JSON was not
/// regenerated, so the eval never scores an old catalogue. Regenerate with:
///
///     flutter test test/utils/nudgy_eval_fixtures_test.dart \
///         --dart-define=UPDATE_EVAL_FIXTURES=true
const _update = bool.fromEnvironment('UPDATE_EVAL_FIXTURES');
const _dir = 'backend/ai-coach/evals';

String _pretty(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

/// Compare with the committed file, or write it when regenerating. Line
/// endings are normalised: a Windows checkout may carry CRLF.
void _expectFixture(String name, Object? json) {
  final file = File('$_dir/$name');
  final want = _pretty(json);
  if (_update) {
    file.writeAsStringSync(want);
    return;
  }
  expect(file.existsSync(), isTrue, reason: '$name is missing. Regenerate it.');
  final have = file.readAsStringSync().replaceAll('\r\n', '\n');
  expect(have, want,
      reason: '$name is stale. Run: flutter test '
          'test/utils/nudgy_eval_fixtures_test.dart '
          '--dart-define=UPDATE_EVAL_FIXTURES=true');
}

/// The eval's "today". Every date in the fixture is relative to it, and the
/// questions name months ("August", "June") against it.
final _today = DateTime(2026, 10, 15);

/// A made-up but realistic Treasury user in mid-October 2026. No real data.
///
/// Some answers are left out of the snapshot on purpose, as they are in the
/// real app: Mark's receivable is September's, Meralco's August bill is
/// closed, the iPhone plan shows no end date or interest, and per-account
/// balances at a past month-end are not in the history. Those questions need
/// a tool.
final _context = AiCoachContext(
  entryPoint: AiCoachEntryPoint.financeAdvisor,
  today: _today,
  totalLiquidCash: 59620,
  forecastedNetBalance: 14280,
  netWorth: 312450,
  monthNetCashFlow: 8930,
  savingsRatePct: 21,
  monthIncome: 42500,
  expenseBudgetAllocated: 31500,
  expenseBudgetSpent: 19870,
  allBudgetsAllocated: 39500,
  allBudgetsUsed: 24870,
  totalCreditOwed: 18740,
  totalCreditAvailable: 41260,
  outstandingBillsTotal: 4179,
  daysLeftInMonth: 16,
  pendingReceivablesTotal: 42500,
  totalSavingsAndGoals: 96500,
  setAsidesRemaining: 2000,
  nextMonthBillsTotal: 23109,
  nextMonthReceivablesTotal: 85000,
  heldForOthers: 4000,
  installmentsMonthlyLoad: 6050,
  avgDailySpend: 1180,
  peakDaySpend: 3260,
  peakDayLabel: 'Oct 11',
  todaySpend: 240,
  netWorthMonthDelta: 7820,
  netWorthMonthDeltaPct: 0.0257,
  topCategories: const [
    AdvisorCategoryLine(
        name: 'Groceries',
        target: 8000,
        actual: 6820,
        trailingAverage: 7640,
        trailingMonths: 5),
    AdvisorCategoryLine(
        name: 'Food & Dining',
        target: 5000,
        actual: 4350,
        trailingAverage: 5210,
        trailingMonths: 5),
    AdvisorCategoryLine(
        name: 'Shopping',
        target: 2500,
        actual: 3900,
        trailingAverage: 2180,
        trailingMonths: 5),
    AdvisorCategoryLine(
        name: 'Transport',
        target: 3000,
        actual: 2100,
        trailingAverage: 2740,
        trailingMonths: 5),
    AdvisorCategoryLine(
        name: 'Health',
        target: 1500,
        actual: 1200,
        trailingAverage: 900,
        trailingMonths: 5),
    AdvisorCategoryLine(
        name: 'Entertainment',
        target: 1500,
        actual: 1500,
        trailingAverage: 1320,
        trailingMonths: 5),
  ],
  outstandingBills: const [
    AdvisorBillLine(
        name: 'Meralco',
        amount: 3180,
        dueLabel: 'Oct 18',
        payFrom: 'BPI Savings',
        paymentNote: 'CAN 3141-5926-53'),
    AdvisorBillLine(
        name: 'Globe Postpaid',
        amount: 999,
        dueLabel: 'Oct 22',
        payFrom: 'GCash'),
  ],
  paidBillsThisMonth: const [
    AdvisorBillLine(
        name: 'Rent', amount: 15000, dueLabel: 'Oct 1', payFrom: 'BPI Savings'),
    AdvisorBillLine(
        name: 'Gym membership',
        amount: 2500,
        dueLabel: 'Oct 5',
        payFrom: 'BPI Credit Card'),
    AdvisorBillLine(
        name: 'Netflix',
        amount: 549,
        dueLabel: 'Oct 9',
        payFrom: 'BPI Credit Card'),
  ],
  pendingReceivables: const [
    AdvisorReceivableLine(
        name: 'Salary (2nd half)', amount: 42500, expectedLabel: 'Oct 30'),
  ],
  receivedThisMonth: const [
    AdvisorReceivableLine(
        name: 'Salary (1st half)', amount: 42500, expectedLabel: 'Oct 15'),
  ],
  setAsides: const [
    AdvisorSetAsideLine(
        name: 'Emergency fund',
        allocated: 5000,
        funded: 5000,
        remaining: 0,
        isFunded: true),
    AdvisorSetAsideLine(
        name: 'Christmas gifts',
        allocated: 2000,
        funded: 0,
        remaining: 2000,
        isFunded: false),
  ],
  creditLines: const [
    AdvisorCreditLine(
      name: 'BPI Credit Card',
      owed: 18740,
      available: 41260,
      dueLabel: 'Nov 5',
      minimumDue: 850,
      aprMonthly: 0.03,
      utilization: 0.31,
      statementAmount: 12430,
      statementPaid: 0,
      statementRemaining: 12430,
      statementCloseLabel: 'Oct 20',
      sinceClose: 6310,
      nextCloseLabel: 'Nov 20',
      installmentsUnbilled: 67900,
    ),
  ],
  recurringCommitments: const [
    AdvisorRecurringLine(
        name: 'Rent', amount: 15000, dueDay: 1, isInflow: false),
    AdvisorRecurringLine(
        name: 'Gym membership', amount: 2500, dueDay: 5, isInflow: false),
    AdvisorRecurringLine(
        name: 'Netflix', amount: 549, dueDay: 9, isInflow: false),
    AdvisorRecurringLine(
        name: 'Meralco', amount: 3180, dueDay: 18, isInflow: false),
    AdvisorRecurringLine(
        name: 'Globe Postpaid', amount: 999, dueDay: 22, isInflow: false),
    AdvisorRecurringLine(
        name: 'Salary (1st half)', amount: 42500, dueDay: 15, isInflow: true),
    AdvisorRecurringLine(
        name: 'Salary (2nd half)', amount: 42500, dueDay: 30, isInflow: true),
  ],
  scheduledFuture: const [
    AdvisorScheduledLine(
        name: 'Car registration',
        amount: 2880,
        monthLabel: 'Nov 2026',
        dateLabel: 'Nov 12',
        isInflow: false),
    AdvisorScheduledLine(
        name: '13th month pay',
        amount: 42500,
        monthLabel: 'Dec 2026',
        dateLabel: 'Dec 15',
        isInflow: true),
  ],
  liquidAccounts: const [
    AdvisorAccountLine(name: 'BPI Savings', balance: 48250, held: 4000),
    AdvisorAccountLine(name: 'GCash', balance: 6420),
    AdvisorAccountLine(name: 'Maya', balance: 3100),
    AdvisorAccountLine(name: 'Cash', balance: 1850),
  ],
  heldForOthersLines: const [
    AdvisorHeldLine(name: 'Mom', amount: 4000, insideAccount: 'BPI Savings'),
  ],
  savingsAccounts: const [
    AdvisorAccountLine(name: 'Maya Savings', balance: 41500),
  ],
  investmentAccounts: const [
    AdvisorAccountLine(name: 'Pag-IBIG MP2', balance: 120000),
  ],
  subAccounts: const [
    AdvisorSubAccountLine(
        name: 'Emergency fund', balance: 35000, parentName: 'Maya Savings'),
  ],
  goals: const [
    AdvisorGoalLine(
        name: 'Japan trip',
        saved: 55000,
        target: 90000,
        monthlyContribution: 5000),
  ],
  completedGoals: const [
    AdvisorCompletedGoalLine(
        name: 'New laptop', target: 65000, spent: 62990, dateLabel: 'Jul 2026'),
  ],
  budgetGroups: const [
    AdvisorBudgetGroupLine(name: 'Needs', allocated: 20000, spent: 13020),
    AdvisorBudgetGroupLine(name: 'Wants', allocated: 11500, spent: 6850),
    AdvisorBudgetGroupLine(name: 'Savings', allocated: 8000, spent: 5000),
  ],
  installments: const [
    AdvisorInstallmentLine(
        name: 'iPhone 16 Pro',
        monthlyAmount: 4850,
        remainingMonths: 14,
        remainingAmount: 67900,
        account: 'BPI Credit Card'),
    AdvisorInstallmentLine(
        name: 'Air purifier',
        monthlyAmount: 1200,
        remainingMonths: 3,
        remainingAmount: 3600,
        account: 'BPI Credit Card'),
  ],
  maturities: const [
    AdvisorMaturityLine(
        name: 'BPI Time Deposit', amount: 50000, dateLabel: 'Jan 20, 2027'),
  ],
  recentTransactions: const [
    AdvisorTxnLine(
        dateLabel: 'Oct 15',
        description: 'Starbucks',
        amount: 240,
        category: 'Food & Dining',
        account: 'GCash'),
    AdvisorTxnLine(
        dateLabel: 'Oct 14',
        description: 'Grab ride',
        amount: 186,
        category: 'Transport',
        account: 'GCash'),
    AdvisorTxnLine(
        dateLabel: 'Oct 13',
        description: 'Mercury Drug',
        amount: 640,
        category: 'Health',
        account: 'Cash'),
    AdvisorTxnLine(
        dateLabel: 'Oct 12',
        description: 'SM Supermarket',
        amount: 1980,
        category: 'Groceries',
        account: 'BPI Credit Card'),
    AdvisorTxnLine(
        dateLabel: 'Oct 11',
        description: 'Uniqlo',
        amount: 3260,
        category: 'Shopping',
        account: 'BPI Credit Card'),
    AdvisorTxnLine(
        dateLabel: 'Oct 10',
        description: 'Jollibee',
        amount: 420,
        category: 'Food & Dining',
        account: 'Maya'),
    AdvisorTxnLine(
        dateLabel: 'Oct 9',
        description: 'Netflix',
        amount: 549,
        category: 'Entertainment',
        account: 'BPI Credit Card'),
    AdvisorTxnLine(
        dateLabel: 'Oct 8',
        description: 'Shell gas',
        amount: 1500,
        category: 'Transport',
        account: 'BPI Credit Card'),
  ],
  netWorthTrend: const [
    AdvisorNetWorthPoint(label: 'May 2026', value: 271300),
    AdvisorNetWorthPoint(label: 'Jun 2026', value: 280950),
    AdvisorNetWorthPoint(label: 'Jul 2026', value: 289400),
    AdvisorNetWorthPoint(label: 'Aug 2026', value: 297120),
    AdvisorNetWorthPoint(label: 'Sep 2026', value: 304630),
  ],
  incomeExpenseTrend: const [
    AdvisorMonthFlow(
        label: 'May 2026',
        income: 85000,
        expense: 61200,
        savingsContribution: 12000),
    AdvisorMonthFlow(
        label: 'Jun 2026',
        income: 85000,
        expense: 63850,
        savingsContribution: 10000),
    AdvisorMonthFlow(
        label: 'Jul 2026',
        income: 85000,
        expense: 70420,
        savingsContribution: 8000),
    AdvisorMonthFlow(
        label: 'Aug 2026',
        income: 87500,
        expense: 66310,
        savingsContribution: 10000),
    AdvisorMonthFlow(
        label: 'Sep 2026',
        income: 85000,
        expense: 64980,
        savingsContribution: 12000),
  ],
  monthlyLedger: const [
    AdvisorMonthLedger(
        label: 'Aug 2026',
        billed: 23860,
        billsPaid: 23860,
        receivablesExpected: 87500,
        received: 87500,
        netSavings: 21190),
    AdvisorMonthLedger(
        label: 'Sep 2026',
        billed: 23410,
        billsPaid: 23410,
        receivablesExpected: 88700,
        received: 85000,
        netSavings: 20020),
  ],
  historyMonthLabels: const [
    'May 2026',
    'Jun 2026',
    'Jul 2026',
    'Aug 2026',
    'Sep 2026',
  ],
  categoryHistory: const [
    AdvisorCategoryHistoryRow(
        name: 'Groceries',
        amounts: [7120, 7480, 8210, 7690, 7700],
        total: 38200),
    AdvisorCategoryHistoryRow(
        name: 'Food & Dining',
        amounts: [4980, 5320, 6110, 5040, 4600],
        total: 26050),
    AdvisorCategoryHistoryRow(
        name: 'Transport',
        amounts: [2650, 2810, 2960, 2700, 2580],
        total: 13700),
    AdvisorCategoryHistoryRow(
        name: 'Shopping',
        amounts: [1900, 2400, 3850, 1700, 1050],
        total: 10900),
  ],
  savingsHistory: const [
    AdvisorSavingsHistoryRow(
        name: 'Emergency fund',
        amounts: [5000, 5000, 3000, 5000, 5000],
        total: 23000),
    AdvisorSavingsHistoryRow(
        name: 'Japan trip',
        amounts: [7000, 5000, 5000, 5000, 7000],
        total: 29000),
  ],
  spendingByMonth: const [
    AdvisorMonthSpendingDigest(
      monthLabel: 'Sep 2026',
      monthTotal: 64980,
      itemCount: 47,
      items: [
        AdvisorTxnLine(
            dateLabel: 'Sep 1',
            description: 'Rent',
            amount: 15000,
            category: 'Housing',
            account: 'BPI Savings'),
        AdvisorTxnLine(
            dateLabel: 'Sep 20',
            description: 'Concert tickets',
            amount: 7000,
            category: 'Entertainment',
            account: 'BPI Credit Card'),
        AdvisorTxnLine(
            dateLabel: 'Sep 18',
            description: 'Meralco',
            amount: 3240,
            category: 'Utilities',
            account: 'BPI Savings'),
      ],
    ),
    AdvisorMonthSpendingDigest(
      monthLabel: 'Aug 2026',
      monthTotal: 66310,
      itemCount: 52,
      items: [
        AdvisorTxnLine(
            dateLabel: 'Aug 1',
            description: 'Rent',
            amount: 15000,
            category: 'Housing',
            account: 'BPI Savings'),
        AdvisorTxnLine(
            dateLabel: 'Aug 23',
            description: 'Dental cleaning',
            amount: 3500,
            category: 'Health',
            account: 'GCash'),
        AdvisorTxnLine(
            dateLabel: 'Aug 14',
            description: 'S&R',
            amount: 3120,
            category: 'Groceries',
            account: 'BPI Credit Card'),
      ],
    ),
  ],
);

void main() {
  test('tools.json is financeToolsRequestJson()', () {
    _expectFixture('tools.json', financeToolsRequestJson());
  });

  test('snapshot.json is the context the app sends for the fixture', () {
    // The same payload builder the app uses, so the eval sends what the
    // phone sends. Messages and tools are left out: the eval supplies its own
    // questions, and tools.json carries the catalogue.
    final payload = CloudAiCoachService.advisorPayload(
      messages: const [],
      context: _context,
      historical: _context.financeHistoricalSummary(),
    );
    _expectFixture('snapshot.json', {
      'today': '2026-10-15',
      ...(payload['context']! as Map<String, Object?>),
    });
  });

  test('the fixture keeps the answers the questions need a tool for', () {
    final s = _context.financeSnapshotSummary();
    // These must stay out of the snapshot, or the questions about them no
    // longer test a tool choice.
    expect(s, isNot(contains('Mark')));
    expect(s, isNot(contains('Landers')));
    expect(s, isNot(contains('August')));
    expect(s, contains('iPhone 16 Pro'));
  });
}
