import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/presenters/ai_coach_presenter.dart';

void main() {
  group('AiCoachContext.financeSnapshotSummary', () {
    test('renders PHP-formatted figures with thousands separators', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        totalLiquidCash: 42350.75,
        forecastedNetBalance: 12800,
        netWorth: 1234567,
        monthNetCashFlow: -5400,
        savingsRatePct: 18,
        monthBudget: 20000,
        monthSpent: 15250,
        totalCreditOwed: 3000,
        totalCreditAvailable: 47000,
        daysLeftInMonth: 9,
        outstandingBillsTotal: 4200,
        outstandingBills: [
          AdvisorBillLine(name: 'Internet', amount: 1699),
          AdvisorBillLine(name: 'Electricity', amount: 2501),
        ],
        topCategories: [
          AdvisorCategoryLine(name: 'Groceries', target: 6000, actual: 5800),
          AdvisorCategoryLine(name: 'Dining', actual: 3200),
        ],
      );

      final s = ctx.financeSnapshotSummary();

      expect(s, contains('Total liquid cash: ₱42,351'));
      expect(s, contains('Forecasted ending cash'));
      expect(s, contains('₱1,234,567'));
      expect(s, contains('Net cash flow this month: -₱5,400'));
      expect(s, contains('Savings rate this month: 18%'));
      expect(s, contains('₱15,250 spent of ₱20,000 target (₱4,750 remaining)'));
      expect(s, contains('unused capacity'));
      expect(s, contains('Days left in month: 9'));
      // Bills itemised + totalled.
      expect(s, contains('Internet: ₱1,699'));
      expect(s, contains('Total outstanding: ₱4,200'));
      // Category with a budget shows actual vs target; one without says so.
      expect(s, contains('Groceries: ₱5,800 of ₱6,000 target'));
      expect(s, contains('Dining: ₱3,200 spent (no budget set)'));
    });

    test('empty snapshot yields a clear placeholder', () {
      const ctx = AiCoachContext(entryPoint: AiCoachEntryPoint.financeAdvisor);
      expect(ctx.financeSnapshotSummary(), '(no financial data available)');
    });

    test('surfaces receivables, income, savings and next-month look-ahead', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        monthIncome: 32000,
        totalSavingsAndGoals: 88000,
        pendingReceivablesTotal: 5000,
        pendingReceivables: [
          AdvisorReceivableLine(
              name: 'Freelance invoice', amount: 5000, expectedLabel: 'Aug 5'),
        ],
        nextMonthBillsTotal: 4200,
        nextMonthReceivablesTotal: 32000,
      );

      final s = ctx.financeSnapshotSummary();
      expect(s, contains('Income received this month: ₱32,000'));
      expect(s, contains('Savings & goals set aside: ₱88,000'));
      // Receivables are money coming IN and must be itemised + labelled.
      expect(s, contains('money coming IN'));
      expect(s, contains('Freelance invoice: ₱5,000 (Aug 5)'));
      expect(s, contains('Total incoming: ₱5,000'));
      // Forward look into next month.
      expect(s, contains('Next month so far:'));
      expect(s, contains('₱4,200 in scheduled bills'));
      expect(s, contains('₱32,000 expected receivables'));
    });

    test('itemises credit cards per-card with due + minimum', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        totalCreditOwed: 12000,
        totalCreditAvailable: 38000,
        creditLines: [
          AdvisorCreditLine(
            name: 'UnionBank',
            owed: 12000,
            available: 38000,
            dueLabel: 'Due in 5 days',
            minimumDue: 850,
          ),
        ],
      );

      final s = ctx.financeSnapshotSummary();
      expect(s, contains('Credit cards / lines'));
      expect(
          s,
          contains(
              'UnionBank: ₱12,000 owed, ₱38,000 available, min due ₱850, Due in 5 days'));
      expect(s, contains('Total owed: ₱12,000'));
    });

    test('credit line shows utilization and monthly interest', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        creditLines: [
          AdvisorCreditLine(
            name: 'RCBC',
            owed: 12000,
            available: 8000,
            utilization: 0.6,
            aprMonthly: 0.0357,
          ),
        ],
      );
      final s = ctx.financeSnapshotSummary();
      expect(s, contains('60% utilized'));
      expect(s, contains('3.6%/mo interest'));
    });

    test('lists recent spending so the coach sees where money went', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        recentTransactions: [
          AdvisorTxnLine(
            dateLabel: 'Jul 21',
            description: 'Grab to office',
            amount: 180,
            category: 'Transport',
          ),
          AdvisorTxnLine(
            dateLabel: 'Jul 20',
            description: '',
            amount: 1200,
            category: 'Groceries',
          ),
        ],
      );
      final s = ctx.financeSnapshotSummary();
      expect(s, contains('Recent spending (most recent first):'));
      expect(s, contains('Jul 21: Grab to office — ₱180 (Transport)'));
      // A blank description falls back to the category name.
      expect(s, contains('Jul 20: Groceries — ₱1,200 (Groceries)'));
    });

    test('bills carry their due labels', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        outstandingBills: [
          AdvisorBillLine(
              name: 'Electricity', amount: 2501, dueLabel: 'Due tomorrow'),
        ],
      );
      expect(ctx.financeSnapshotSummary(),
          contains('Electricity: ₱2,501 (Due tomorrow)'));
    });

    test('breaks down goals, accounts, budget groups and installments', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        totalLiquidCash: 9978,
        liquidAccounts: [
          AdvisorAccountLine(name: 'Maya', balance: 3500),
          AdvisorAccountLine(name: 'BPI', balance: 6478),
        ],
        heldForOthers: 1200,
        totalSavingsAndGoals: 25000,
        goals: [
          AdvisorGoalLine(name: 'Travel Fund', saved: 3500, target: 25000),
          AdvisorGoalLine(name: 'Emergency', saved: 8000),
        ],
        budgetGroups: [
          AdvisorBudgetGroupLine(
              name: 'Non-negotiables', allocated: 12000, spent: 9000),
          AdvisorBudgetGroupLine(
              name: 'Guilt-Free', allocated: 5000, spent: 2200),
        ],
        setAsidesRemaining: 1500,
        installments: [
          AdvisorInstallmentLine(
            name: 'MacBook',
            monthlyAmount: 4200,
            remainingMonths: 8,
            remainingAmount: 33600,
          ),
        ],
        installmentsMonthlyLoad: 4200,
      );

      final s = ctx.financeSnapshotSummary();
      // Per-account cash answers "which account holds what".
      expect(s, contains('Cash by account:'));
      expect(s, contains('Maya: ₱3,500'));
      expect(s, contains('BPI: ₱6,478'));
      expect(s, contains('held for someone else'));
      expect(s, contains('₱1,200'));
      // Per-goal progress with percentage.
      expect(s, contains('Travel Fund: ₱3,500 of ₱25,000 (14%)'));
      expect(s, contains('Emergency: ₱8,000 saved (no target set)'));
      // Budget by group.
      expect(s, contains('Non-negotiables: ₱9,000 of ₱12,000'));
      expect(s, contains('Guilt-Free: ₱2,200 of ₱5,000'));
      expect(s, contains('Set-asides still to fund'));
      // Installments as fixed monthly commitments.
      expect(s, contains('MacBook: ₱4,200/mo, 8 mo left (₱33,600 remaining)'));
      expect(s, contains('Total installment load this month: ₱4,200'));
    });

    test('surfaces spending pace, net-worth momentum and maturities', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        netWorth: 200000,
        netWorthMonthDelta: 5400,
        netWorthMonthDeltaPct: 0.0277,
        avgDailySpend: 780,
        peakDaySpend: 2100,
        peakDayLabel: 'Jul 18',
        todaySpend: 340,
        maturities: [
          AdvisorMaturityLine(
              name: 'BPI TD', amount: 50000, dateLabel: 'Sep 1, 2026'),
        ],
      );

      final s = ctx.financeSnapshotSummary();
      // Momentum reads with sign and percent.
      expect(s, contains('Net worth change vs last month: +₱5,400 (+2.8%)'));
      // Pace line combines the three figures.
      expect(s, contains('Spending pace:'));
      expect(s, contains('₱780/day average (last 7 days)'));
      expect(s, contains('peak ₱2,100 on Jul 18'));
      expect(s, contains('₱340 spent today'));
      // Maturity as a future liquidity event.
      expect(s, contains('BPI TD: ₱50,000 on Sep 1, 2026'));
    });

    test('negative net-worth momentum reads with a minus sign', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        netWorthMonthDelta: -3200,
        netWorthMonthDeltaPct: -0.015,
      );
      expect(ctx.financeSnapshotSummary(),
          contains('Net worth change vs last month: -₱3,200 (-1.5%)'));
    });

    test('itemises recurring commitments and scheduled future obligations', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        nextMonthBillsTotal: 999,
        recurringCommitments: [
          AdvisorRecurringLine(
              name: 'Internet', amount: 999, dueDay: 15, isInflow: false),
          AdvisorRecurringLine(
              name: 'Salary', amount: 32000, dueDay: 30, isInflow: true),
        ],
        scheduledFuture: [
          AdvisorScheduledLine(
            name: 'Insurance renewal',
            amount: 5000,
            monthLabel: 'Sep 2026',
            dateLabel: 'Sep 3',
            isInflow: false,
          ),
        ],
      );

      final s = ctx.financeSnapshotSummary();
      // The exact thing the user wanted: line item + amount + when it's due.
      expect(s, contains('Recurring monthly commitments'));
      expect(s, contains('Internet: ₱999 out, around day 15 each month'));
      expect(s, contains('Salary: ₱32,000 in, around day 30 each month'));
      // One-off future obligations carry their month + date.
      expect(s, contains('Other obligations already scheduled ahead'));
      expect(s, contains('Insurance renewal: ₱5,000 out (Sep 3)'));
    });

    test('goal with a monthly plan projects a timeline to target', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        goals: [
          AdvisorGoalLine(
            name: 'Braces',
            saved: 3000,
            target: 50000,
            monthlyContribution: 2500,
          ),
          AdvisorGoalLine(name: 'Vacation', saved: 1000, target: 20000),
        ],
      );

      final s = ctx.financeSnapshotSummary();
      // (50000 - 3000) / 2500 = 18.8 → 19 months.
      expect(
        s,
        contains(
          'Braces: ₱3,000 of ₱50,000 (6%), +₱2,500/mo planned '
          '(~19 mo to target at this pace)',
        ),
      );
      expect(s, contains('Vacation: ₱1,000 of ₱20,000 (5%)'));
      expect(s, isNot(contains('Vacation: ₱1,000 of ₱20,000 (5%), +')));
    });

    test('present: paid bills, received receivables and itemized set-asides',
        () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        paidBillsThisMonth: [AdvisorBillLine(name: 'Rent', amount: 8000)],
        receivedThisMonth: [
          AdvisorReceivableLine(name: 'Payroll', amount: 32000),
        ],
        setAsides: [
          AdvisorSetAsideLine(
            name: 'Emergency',
            allocated: 3000,
            funded: 1000,
            remaining: 2000,
            isFunded: false,
          ),
          AdvisorSetAsideLine(
            name: 'Gadget',
            allocated: 1500,
            funded: 1500,
            remaining: 0,
            isFunded: true,
          ),
        ],
      );

      final s = ctx.financeSnapshotSummary();
      expect(s, contains('Bills already paid this month:'));
      expect(s, contains('Rent: ₱8,000'));
      expect(s, contains('Receivables already received this month:'));
      expect(s, contains('Payroll: ₱32,000'));
      expect(s, contains('Set-asides this month'));
      expect(s, contains('Emergency: ₱1,000 of ₱3,000, ₱2,000 to go'));
      expect(s, contains('Gadget: funded'));
    });

    test('past: bills & receivables totals per closed month', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        monthlyLedger: [
          AdvisorMonthLedger(
            label: 'Jun',
            billed: 9000,
            billsPaid: 9000,
            receivablesExpected: 32000,
            received: 32000,
            netSavings: 11000,
          ),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('Bills & receivables by closed month'));
      expect(
        h,
        contains(
          'Jun: bills ₱9,000 (paid ₱9,000), receivables ₱32,000 '
          '(received ₱32,000), saved ₱11,000',
        ),
      );
      // Past detail must NOT leak into the live snapshot.
      expect(ctx.financeSnapshotSummary(), '(no financial data available)');
    });

    test('historical summary is separate from the live snapshot', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        netWorthTrend: [
          AdvisorNetWorthPoint(label: 'May', value: 100000),
          AdvisorNetWorthPoint(label: 'Jun', value: 120000),
        ],
        incomeExpenseTrend: [
          AdvisorMonthFlow(label: 'Jun', income: 32000, expense: 21000),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('Net worth by month'));
      expect(h, contains('May ₱100,000'));
      expect(h, contains('Jun ₱120,000'));
      expect(h, contains('Jun: ₱32,000 in / ₱21,000 out (net ₱11,000)'));
      // The trends must NOT bleed into the live liquidity snapshot.
      expect(ctx.financeSnapshotSummary(), '(no financial data available)');
    });

    test('income-vs-expense months carry set-aside and cumulative figures', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        incomeExpenseTrend: [
          AdvisorMonthFlow(
            label: 'Jun 2026',
            income: 32000,
            expense: 21000,
            savingsContribution: 6000,
            cumulativeNet: 44000,
          ),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('₱6,000 set aside into pockets'));
      expect(h, contains('cumulative net ₱44,000'));
    });

    test('a month that set nothing aside says nothing about set-asides', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        incomeExpenseTrend: [
          AdvisorMonthFlow(
            label: 'Jun 2026',
            income: 32000,
            expense: 21000,
            savingsContribution: 0,
          ),
        ],
      );

      // Zero is not the same claim as "₱0 set aside" — an unstated figure
      // invites no conclusion, whereas a stated zero reads as a finding.
      expect(ctx.financeHistoricalSummary(), isNot(contains('set aside')));
    });

    test('category x month grid renders aligned to the month spine', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        historyMonthLabels: ['Apr 2026', 'May 2026', 'Jun 2026'],
        categoryHistory: [
          AdvisorCategoryHistoryRow(
            name: 'Groceries',
            amounts: [4200, 5100, 6300],
            total: 15600,
          ),
          // A category bought once: the empty months must read as absent, not
          // as zero spend the advisor might treat as a deliberate cut.
          AdvisorCategoryHistoryRow(
            name: 'Medical',
            amounts: [null, 2500, null],
            total: 2500,
          ),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('Apr 2026 | May 2026 | Jun 2026'));
      expect(
          h, contains('Groceries: ₱4,200 | ₱5,100 | ₱6,300 (total ₱15,600)'));
      expect(h, contains('Medical: - | ₱2,500 | - (total ₱2,500)'));
    });

    test('the grid is omitted when there is no month spine to align it to', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        categoryHistory: [
          AdvisorCategoryHistoryRow(
            name: 'Groceries',
            amounts: [4200],
            total: 4200,
          ),
        ],
      );

      // Cells with no months naming them are worse than no cells: the advisor
      // would have to guess which month each figure belonged to.
      expect(ctx.financeHistoricalSummary(), isNot(contains('Groceries')));
    });

    test('savings-pocket grid marks a net withdrawal as negative', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        historyMonthLabels: ['May 2026', 'Jun 2026'],
        savingsHistory: [
          AdvisorSavingsHistoryRow(
            name: 'Braces',
            amounts: [2500, -1200],
            total: 1300,
          ),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('NEGATIVE figure'));
      expect(h, contains('Braces: ₱2,500 | -₱1,200 (net ₱1,300)'));
    });

    test('per-month digests state the whole month, not just the sample', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        spendingByMonth: [
          AdvisorMonthSpendingDigest(
            monthLabel: 'Jun 2026',
            monthTotal: 21400,
            itemCount: 47,
            items: [
              AdvisorTxnLine(
                dateLabel: 'Jun 14',
                description: 'Laptop stand',
                amount: 3200,
                category: 'Gear',
              ),
              // Blank description falls back to the category, as elsewhere.
              AdvisorTxnLine(
                dateLabel: 'Jun 2',
                description: '   ',
                amount: 1800,
                category: 'Groceries',
              ),
            ],
          ),
        ],
      );

      final h = ctx.financeHistoricalSummary();
      expect(h, contains('Jun 2026 — ₱21,400 across 47 expenses; largest:'));
      expect(h, contains('Jun 14: Laptop stand — ₱3,200 (Gear)'));
      expect(h, contains('Jun 2: Groceries — ₱1,800 (Groceries)'));
    });

    test('a single-expense month is pluralised correctly', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        spendingByMonth: [
          AdvisorMonthSpendingDigest(
            monthLabel: 'Jan 2026',
            monthTotal: 900,
            itemCount: 1,
            items: [
              AdvisorTxnLine(
                dateLabel: 'Jan 3',
                description: 'Domain renewal',
                amount: 900,
                category: 'Software',
              ),
            ],
          ),
        ],
      );

      expect(ctx.financeHistoricalSummary(),
          contains('across 1 expense; largest:'));
    });

    test('history never leaks into the current-liquidity snapshot', () {
      const ctx = AiCoachContext(
        entryPoint: AiCoachEntryPoint.financeAdvisor,
        historyMonthLabels: ['Jun 2026'],
        categoryHistory: [
          AdvisorCategoryHistoryRow(
            name: 'Groceries',
            amounts: [6300],
            total: 6300,
          ),
        ],
        savingsHistory: [
          AdvisorSavingsHistoryRow(
              name: 'Braces', amounts: [2500], total: 2500),
        ],
        spendingByMonth: [
          AdvisorMonthSpendingDigest(
            monthLabel: 'Jun 2026',
            monthTotal: 6300,
            itemCount: 2,
            items: [],
          ),
        ],
      );

      // Rule: the snapshot is what is true NOW. Past figures reaching it would
      // let the advisor answer "what can I spend" with last month's numbers.
      expect(ctx.financeSnapshotSummary(), '(no financial data available)');
      expect(ctx.financeHistoricalSummary(), isNotEmpty);
    });
  });

  group('AiCoachPresenter.looksLikeExpenseLog', () {
    test('treats questions as advice, never logs', () {
      expect(
          AiCoachPresenter.looksLikeExpenseLog('can I afford a ₱4000 dinner?'),
          isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('how is my positioning?'),
          isFalse);
    });

    test('detects clear logging phrases', () {
      expect(
          AiCoachPresenter.looksLikeExpenseLog('spent 500 on lunch'), isTrue);
      expect(AiCoachPresenter.looksLikeExpenseLog('paid ₱1,699 for internet'),
          isTrue);
      expect(AiCoachPresenter.looksLikeExpenseLog('coffee 120'), isTrue);
    });

    test('advisory prose without an amount is not a log', () {
      expect(AiCoachPresenter.looksLikeExpenseLog('should I start investing'),
          isFalse);
    });

    test('a bare number the user types in conversation is not a log', () {
      // Regression: these used to be hijacked into the ledger's log pipeline,
      // which rejected them with an "amount" error mid-conversation.
      expect(AiCoachPresenter.looksLikeExpenseLog('12k'), isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('5000'), isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('₱3,000'), isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('i have 12k'), isFalse);
      expect(AiCoachPresenter.looksLikeExpenseLog('about 5000'), isFalse);
    });
  });
}
