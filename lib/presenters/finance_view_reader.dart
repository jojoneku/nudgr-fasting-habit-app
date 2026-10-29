import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/financial_account.dart';
import '../models/grocery/item_unit.dart';
import '../utils/finance_format.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'grocery_cart_presenter.dart';
import 'installment_presenter.dart';
import 'ledger_presenter.dart';
import 'treasury_dashboard_presenter.dart';
import 'treasury_history_presenter.dart';

/// The screens Nudgy's `getView` can read, in the order the tool lists them.
const List<String> kFinanceViews = [
  'dashboard',
  'budget',
  'bills',
  'ledger',
  'history',
  'accounts',
  'installments',
  'grocery',
];

/// Reads a finance screen's figures for Nudgy's `getView` tool.
///
/// One rule, held for every line: a figure comes from the presenter getter the
/// screen itself renders, never from maths done here. Where a screen only
/// computed for the month its tab shows, the presenter gained a month-aware
/// method its getter now delegates to (`BudgetPresenter.totalSpentIn`,
/// `BillsReceivablesPresenter.billsIn`, …), so asking about another month
/// never pages a tab and never changes any UI state.
///
/// The output is labelled the way the screen labels it and says which month
/// each block is for, so the model can quote it and never has to add anything
/// up (Plan 065, rule 2).
///
/// Assembled in `TreasuryPresenters` (CLAUDE.md #9) and reached only through
/// [FinanceActionsExecutor].
class FinanceViewReader {
  FinanceViewReader({
    required LedgerPresenter ledger,
    required BudgetPresenter budget,
    required BillsReceivablesPresenter bills,
    required TreasuryDashboardPresenter dashboard,
    required TreasuryHistoryPresenter history,
    required InstallmentPresenter installments,
    required GroceryCartPresenter groceryCart,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _budget = budget,
        _bills = bills,
        _dashboard = dashboard,
        _history = history,
        _installments = installments,
        _grocery = groceryCart,
        _clock = clock ?? DateTime.now;

  final LedgerPresenter _ledger;
  final BudgetPresenter _budget;
  final BillsReceivablesPresenter _bills;
  final TreasuryDashboardPresenter _dashboard;
  final TreasuryHistoryPresenter _history;
  final InstallmentPresenter _installments;
  final GroceryCartPresenter _grocery;

  /// "Today", for the default month. Injected so tests can pin it.
  final DateTime Function() _clock;

  static final RegExp _monthKey = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  /// Runs a `getView` call: `view` is one of [kFinanceViews], `month` is an
  /// optional `YYYY-MM` that defaults to today's month.
  AiToolResult run(AiToolCall call) {
    final view = '${call.input['view'] ?? ''}'.trim().toLowerCase();
    final rawMonth = '${call.input['month'] ?? ''}'.trim();
    if (!kFinanceViews.contains(view)) {
      return AiToolResult.failed(
          call.id,
          'Unknown view "$view". Use one of: '
          '${kFinanceViews.join(', ')}.');
    }
    if (rawMonth.isNotEmpty && !_monthKey.hasMatch(rawMonth)) {
      return AiToolResult.failed(
          call.id, 'Month "$rawMonth" is not YYYY-MM. Omit it for this month.');
    }
    final month = rawMonth.isEmpty ? toMonthKey(_clock()) : rawMonth;
    final text = read(view, month);
    return text == null
        ? AiToolResult.failed(call.id, _noMonthHint(view, month))
        : AiToolResult(toolUseId: call.id, ok: true, summary: text);
  }

  /// The figures [view] shows for [month], or null when that screen cannot
  /// show [month] at all.
  String? read(String view, String month) => switch (view) {
        'dashboard' => _readDashboard(month),
        'budget' => _readBudget(month),
        'bills' => _readBills(month),
        'ledger' => _readLedger(month),
        'history' => _readHistory(month),
        'accounts' => _readAccounts(month),
        'installments' => _readInstallments(month),
        'grocery' => _readGrocery(month),
        _ => null,
      };

  String _noMonthHint(String view, String month) => switch (view) {
        'dashboard' => 'The Dashboard has no month picker: it shows '
            '${monthLabel(_dashboard.currentMonth)} only. For '
            '${monthLabel(month)}, read view "history" (closed months) or '
            '"budget", "bills" or "ledger".',
        _ => 'The $view screen has nothing for ${monthLabel(month)}.',
      };

  static String _header(String title, String month) =>
      '$title — ${monthLabel(month)} ($month). Labels are the screen\'s own; '
      'quote the figures, do not add them up.';

  static String _peso(double v) => formatPeso(v);

  static String _pct(double fraction) => formatPercent(fraction);

  // ── Dashboard ──────────────────────────────────────────────────────────────

  String? _readDashboard(String month) {
    final d = _dashboard;
    if (month != d.currentMonth) return null;
    final delta = d.netWorthMonthDelta;
    final deltaPct = d.netWorthMonthDeltaPct;
    final next = d.nextMonthForecast;
    final rate = d.savingsRate;
    return [
      _header('Dashboard', month),
      'Balances are as of now; the month lines are for $month.',
      'NET WORTH: ${_peso(d.netWorth)}',
      if (delta != null)
        'Change this month: ${formatPesoSigned(delta)}'
            '${deltaPct == null ? '' : ' (${_pct(deltaPct)})'}',
      'Liquid cash: ${_peso(d.totalLiquidCash)}',
      'Credit owed: ${_peso(d.totalCreditOwed)}',
      'Credit available: ${_peso(d.totalCreditAvailable)}',
      '${monthLabel(month)} cashflow: in ${_peso(d.monthTotalInflow)}, '
          'out ${_peso(d.monthTotalOutflow)}, '
          'net cash flow ${formatPesoSigned(d.monthNetCashFlow)}',
      if (rate != null) 'Savings rate: ${_pct(rate)}',
      'Days left in the month: ${d.daysLeftInMonth}',
      'Month-End Outlook ($month):',
      '- Liquid Now: ${_peso(d.totalLiquidCash)}',
      '- To Receive: ${_peso(d.pendingReceivables)}',
      '- Upcoming Bills: ${_peso(d.monthUnpaidBills)}',
      '- Budget / Savings Due: ${_peso(d.budgetedExpensesRemaining)}',
      '- Budget Left: ${_peso(d.budgetRemainingNetOfObligations)} '
          '(budget still to spend, less what a bill or set-aside already '
          'reserves)',
      '- Proj. Month-End Cash: ${_peso(d.forecastedNetBalance)}',
      'Next Month Forecast (${next.monthName}, ${next.month}):',
      '- Starting cash (projected end of ${monthShortLabel(next.fromMonth)}): '
          '${next.startingCashLabel}',
      '- To receive: ${_peso(next.toReceive)}',
      '- Bills: ${_peso(next.bills)}',
      '- Installments: ${_peso(next.installments)}',
      '- Set-asides: ${_peso(next.setAsides)}',
      '- Budget: ${_peso(next.budget)} (${next.budgetCaption})',
      '- ${next.endingTitle}: ${next.endingLabel} (${next.changeLabel})',
      'Budget This Month: spent ${_peso(d.totalExpenseBudgetSpent)} of '
          '${_peso(d.totalExpenseBudgetAllocated)} (expense budgets only)',
      'Spend pace is on the Budget screen: read view "budget".',
    ].join('\n');
  }

  // ── Budget ─────────────────────────────────────────────────────────────────

  String _readBudget(String month) {
    final b = _budget;
    final sections = b.budgetSectionsIn(month);
    if (sections.isEmpty) {
      return '${_header('Budget', month)}\nNo budget is set for $month.';
    }
    final remaining = b.totalRemainingIn(month);
    final pace = b.paceLabelIn(month);
    final lines = [
      _header('Budget', month),
      'SPENT: ${_peso(b.totalSpentIn(month))} of '
          '${_peso(b.totalAllocatedIn(month))} '
          '(${_pct(b.percentUsedIn(month))} spent; savings funded counts as '
          'spent here)',
      remaining < 0
          ? '${_peso(remaining.abs())} over'
          : '${_peso(remaining)} left',
      pace == null
          ? 'Pace: no pace pill ($month is not in progress)'
          : 'Pace: $pace (${_pct(b.monthElapsedFractionOf(month))} of the '
              'month gone)',
    ];
    for (final s in sections) {
      lines.add('${s.name}${s.isSavings ? ' (savings)' : ''}: '
          '${_peso(s.spent)} / ${_peso(s.allocated)}');
      for (final r in s.rows) {
        if (r.isSavings) {
          lines.add('- ${r.name}: funded ${_peso(r.actual)} of '
              '${_peso(r.allocated)}'
              '${r.targetFromSetAside ? ' (target from this month\'s set-aside)' : ''}, '
              '${_peso(r.left)} left to fund'
              '${r.withdrawn > 0 ? ', ${_peso(r.withdrawn)} withdrawn' : ''}'
              '${r.met ? ' [met]' : ''}');
        } else if (r.isIncome) {
          lines.add('- ${r.name}: received ${_peso(r.actual)} of '
              '${_peso(r.allocated)}, ${_peso(r.left)} still to receive');
        } else {
          lines.add('- ${r.name}: spent ${_peso(r.actual)} of '
              '${_peso(r.allocated)}, '
              '${r.isOver ? 'over by ${_peso(r.overBy)}' : '${_peso(r.left)} left'}');
        }
      }
    }
    return lines.join('\n');
  }

  // ── Bills ──────────────────────────────────────────────────────────────────

  String _readBills(String month) {
    final p = _bills;
    final bills = p.billsIn(month);
    final receivables = p.receivablesIn(month);
    final setAsides = p.budgetedExpensesIn(month);
    final comingUp = p.comingUpItems(_installments, month: month);
    final lines = [
      _header('Bills', month),
      'Pending: ${_peso(p.totalBillsPendingIn(month))}',
      'Paid: ${_peso(p.totalBillsPaidIn(month))}',
      'Installments: ${_peso(_installments.totalDueIn(month))}',
      'Receivables pending: ${_peso(p.totalReceivablesPendingIn(month))}',
      'Received: ${_peso(p.totalReceivedIn(month))}',
      'Coming up (next ${comingUp.length}):',
      for (final c in comingUp)
        '- ${c.name}: ${c.isInflow ? '+' : ''}${_peso(c.amount)} · '
            '${c.dateLabel}',
      'Bills · ${bills.length}:',
    ];
    for (final b in bills) {
      lines.add('- ${b.name}: ${_peso(b.amount)}, due day ${b.dueDay}'
          '${b.isPaid ? ', paid ${_peso(b.paidAmount ?? b.amount)}' : ''}');
      if (b.billType == BillType.creditCard) lines.addAll(_statement(b));
    }
    lines.add('Receivables · ${receivables.length}:');
    for (final r in receivables) {
      final expected = r.expectedDate;
      lines.add('- ${r.name}: ${_peso(r.amount)}'
          '${expected == null ? ', ASAP' : ', expected ${_day(expected)}'}'
          '${r.isReceived ? ', received ${_peso(r.receivedAmount ?? r.amount)}' : ''}');
    }
    lines.add('Set-asides (Budgeted) · ${setAsides.length}:');
    for (final e in setAsides) {
      lines.add('- ${e.name}: ${_peso(e.allocatedAmount)}, '
          'funded ${_peso(e.spentAmount)}${e.isPaid ? ' [paid]' : ''}');
    }
    return lines.join('\n');
  }

  /// A credit statement's line items, as the statement breakdown sheet lists
  /// them.
  List<String> _statement(Bill b) {
    final s = _bills.statementBreakdown(b);
    if (s == null) return const [];
    return [
      '  Statement ${s.periodLabel}, ${s.itemCountLabel}: unpaid '
          '${_peso(s.unpaid)}, ${s.dueLabel}',
      if (s.hasCarriedOver) '  Carried over: ${s.carriedOverLabel}',
      for (final section in s.sections) ...[
        '  ${section.title} (${section.countLabel}): ${section.totalLabel}',
        for (final l in section.lines)
          '    ${l.title}${l.installmentLabel == null ? '' : ' ${l.installmentLabel}'}'
              ' · ${l.dateLabel} · ${l.amountLabel}',
      ],
    ];
  }

  // ── Ledger ─────────────────────────────────────────────────────────────────

  String _readLedger(String month) {
    final l = _ledger;
    return [
      _header('Ledger', month),
      'All accounts, no filters. For the rows themselves call '
          'findTransactions.',
      'In: ${_peso(l.monthInflowIn(month))}',
      'Out: ${_peso(l.monthOutflowIn(month))}',
      'Net: ${formatPesoSigned(l.monthNetIn(month))}',
      'Owed (outstanding reimbursables): '
          '${_peso(l.outstandingOwedTotalIn(month))}',
      'Calendar daily average spend (days with spending only): '
          '${_peso(l.averageDailyOutflowIn(month))}',
    ].join('\n');
  }

  // ── History ────────────────────────────────────────────────────────────────

  String _readHistory(String month) {
    final h = _history;
    final lines = [
      _header('History', month),
      'Overview, across ${h.closedMonthCount} closed months:',
      '- AVG IN: ${_peso(h.averageInflow)}',
      '- AVG OUT: ${_peso(h.averageOutflow)}',
      '- AVG SAVED: ${_peso(h.averageNetSavings)}',
      '- Keeps ${_pct(h.averageSavingsRate)} of income',
      '- ${formatPesoSigned(h.cumulativeNetSavings)} net all-time',
    ];
    final s = h.summaryFor(month);
    if (s == null) {
      lines.add('$month has no closed summary yet.');
      return lines.join('\n');
    }
    final live = month == toMonthKey(_clock());
    final names = {for (final a in h.accounts) a.id: a.name};
    final categories = {for (final c in h.categories) c.id: c.name};
    final rate = s.savingsRate;
    lines.addAll([
      live
          ? '${monthLabel(month)} (in progress, not closed; balances are '
              'today\'s):'
          : '${monthLabel(month)} (closed):',
      '- IN: ${_peso(s.totalInflow)}',
      '- OUT: ${_peso(s.totalOutflow)}',
      '- NET: ${formatPesoSigned(s.netSavings)}',
      '- Saved ${rate == null ? '— (no income)' : _pct(rate)} of income',
      if (s.savingsContribution != null)
        '- Set aside into savings: ${_peso(s.savingsContribution!)}',
      '- Ending cash: ${_peso(s.endingCash)}',
      if (s.netWorth != null) '- Net worth: ${_peso(s.netWorth!)}',
      '- Bills paid: ${s.billsPaidCount}/${s.billCount}, '
          '${_peso(s.totalBillsPaid)} of ${_peso(s.totalBills)}',
      '- Receivables received: ${_peso(s.totalReceived)} of '
          '${_peso(s.totalReceivables)}',
      if (s.categorySpend.isNotEmpty) '- Spending by category:',
      for (final e in s.categorySpend.entries)
        '  ${categories[e.key] ?? e.key}: ${_peso(e.value)}',
      if (s.accountSnapshots.isNotEmpty)
        live ? '- Account balances now:' : '- Account balances at close:',
      for (final e in s.accountSnapshots.entries)
        '  ${names[e.key] ?? e.key}: ${_peso(e.value)}',
    ]);
    return lines.join('\n');
  }

  // ── Accounts ───────────────────────────────────────────────────────────────

  String _readAccounts(String month) {
    final d = _dashboard;
    final held = d.heldAmountByAccountId;
    final yours = d.yoursByAccountId;
    final names = {for (final a in d.accounts) a.id: a.name};
    final lines = [
      'Accounts — balances as of now (this screen has no month; '
          '$month is ignored). Labels are the screen\'s own; quote the '
          'figures, do not add them up.',
      'Liquid cash: ${_peso(d.totalLiquidCash)}',
      'Savings & goals: ${_peso(d.totalSavingsAndGoals)}',
      'Credit owed: ${_peso(d.totalCreditOwed)}',
      'Credit available: ${_peso(d.totalCreditAvailable)}',
      'Held for others: ${_peso(d.totalHeldForOthers)}',
    ];
    for (final a in d.accounts.where((a) => a.isActive)) {
      lines.add(_accountLine(a, held[a.id] ?? 0, yours[a.id], names));
    }
    return lines.join('\n');
  }

  String _accountLine(FinancialAccount a, double held, double? yours,
      Map<String, String> names) {
    final parent = a.parentAccountId;
    final linked = a.linkedAccountId;
    final role = [
      if (parent != null) 'sub-account of ${names[parent] ?? parent}',
      if (a.isCustodian)
        'held for others${linked == null ? '' : ' in ${names[linked] ?? linked}'}',
    ].join(', ');
    final head = '- ${a.name} [${a.category.name}]'
        '${role.isEmpty ? '' : ' ($role)'}';
    if (!a.isLiability) {
      return '$head: balance ${_peso(a.balance)}'
          '${held > 0 ? ', ${_peso(held)} held, yours ${_peso(yours ?? a.balance)}' : ''}';
    }
    final limit = a.creditLimit;
    final available = a.availableCredit;
    final due = _dashboard.creditDueInfo(a);
    return [
      '$head: owe ${_peso(a.totalDebt)}',
      if (a.unbilledInstallments > 0)
        'incl. ${_peso(a.unbilledInstallments)} installment months not yet '
            'billed',
      if (limit != null) 'limit ${_peso(limit)}',
      if (available != null) 'available ${_peso(available)}',
      if (a.statementDay != null) 'statement day ${a.statementDay}',
      if (a.dueDaysAfterStatement != null)
        'due ${a.dueDaysAfterStatement} days after the statement'
      else if (a.paymentDueDay != null)
        'due day ${a.paymentDueDay}',
      if (due != null) due.label,
    ].join(', ');
  }

  // ── Installments ───────────────────────────────────────────────────────────

  String _readInstallments(String month) {
    final p = _installments;
    final names = {for (final a in _ledger.accounts) a.id: a.name};
    final plans = p.allInstallments;
    final lines = [
      _header('Installments', month),
      'Due in $month: ${_peso(p.totalDueIn(month))}, paid '
          '${_peso(p.totalPaidIn(month))}',
      'Plans · ${plans.length} (months paid are as of now):',
    ];
    for (final i in plans) {
      lines.add('- ${i.name} on ${names[i.accountId] ?? i.accountId}: '
          '${_peso(i.monthlyAmount)}/mo, ${i.startMonth} to ${i.endMonth}, '
          '${p.paidCount(i.id)}/${i.totalMonths} paid, '
          '${_peso(p.remainingAmount(i.id))} left, '
          'total interest ${_peso(i.totalInterest)}, '
          'total payable ${_peso(i.totalPayable)}'
          '${i.isActive ? '' : ' [cancelled]'}'
          '${i.isActive && i.isDueIn(month) ? (p.isPaidIn(i.id, month) ? ' [paid for $month]' : ' [due in $month]') : ''}');
    }
    return lines.join('\n');
  }

  // ── Grocery ────────────────────────────────────────────────────────────────

  String _readGrocery(String month) {
    final g = _grocery;
    final budget = g.budget;
    final remaining = g.budgetRemaining;
    final prices = g.priceMemory;
    final trips = g.tripHistory.take(5).toList();
    return [
      'Grocery — the cart as of now (this screen has no month; $month is '
          'ignored). Labels are the screen\'s own; quote the figures, do not '
          'add them up.',
      'Cart total: ${_peso(g.grandTotal)} (${_peso(g.confirmedTotal)} '
          'confirmed, ~${_peso(g.estimatedTotal)} est, ${g.unpricedCount} '
          'unpriced)',
      if (budget != null && remaining != null)
        g.isOverBudget
            ? 'Over by ${_peso(remaining.abs())} (budget ${_peso(budget)})'
            : '${_peso(remaining)} left of ${_peso(budget)}',
      'Cart · ${g.itemCount}:',
      for (final i in g.items)
        '- ${i.name} ×${_qty(i.quantity)} ${i.unit.label}: '
            '${i.isPriced ? _peso(i.lineTotal) : 'unpriced'} '
            '(${i.priceState.name})',
      'Price book: ${g.priceBookSummary}',
      for (final p in prices.take(20))
        '- ${p.displayName}: ${_peso(p.lastPrice)}/${p.unit.label}, '
            'bought ${p.timesSeen}×, last ${_day(p.lastSeen)}',
      if (prices.length > 20) '- … ${prices.length - 20} more',
      'Last trips · ${trips.length}:',
      for (final t in trips)
        '- ${_day(t.savedAt)}: ${_peso(t.total)}, ${t.itemCount} items'
            '${t.postedToLedger ? ', posted to the ledger' : ''}',
    ].join('\n');
  }

  static String _qty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
