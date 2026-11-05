import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budget.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/installment.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../utils/credit_cycle.dart';
import '../utils/finance_find_match.dart';
import '../utils/finance_format.dart';
import '../utils/model_date_guard.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'installment_presenter.dart';
import 'ledger_presenter.dart';
import 'treasury_dashboard_presenter.dart';

/// What `find` can look up. Transactions are not here: rows in a period are
/// `findTransactions`, which has its own date and type filters.
enum FindEntity {
  bill,
  receivable,
  setAside,
  budget,
  budgetGroup,
  installment,
  account;

  /// The entities whose rows belong to one month.
  bool get isMonthly =>
      this != FindEntity.installment && this != FindEntity.account;

  static FindEntity? parse(String raw) {
    final r = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    for (final e in FindEntity.values) {
      if (e.name.toLowerCase() == r) return e;
    }
    return switch (r) {
      'bills' => FindEntity.bill,
      'receivables' => FindEntity.receivable,
      'setasides' || 'sinkingfund' || 'goal' => FindEntity.setAside,
      'budgets' => FindEntity.budget,
      'budgetgroups' || 'group' => FindEntity.budgetGroup,
      'installments' || 'plan' => FindEntity.installment,
      'accounts' || 'card' => FindEntity.account,
      _ => null,
    };
  }
}

/// One row a find can return: its id, the text a query is matched against,
/// a one-line summary for a list, and every field for a single match.
class _Row {
  const _Row({
    required this.id,
    required this.name,
    required this.haystack,
    required this.line,
    required this.detail,
    this.month,
  });

  final String? id;
  final String name;
  final String haystack;
  final String line;
  final List<String> Function() detail;
  final String? month;
}

/// Answers Nudgy's `find` tool (Plan 065 phase 3), which replaces the seven
/// `find*` tools.
///
/// Every reply starts with a status the model can act on:
/// - `found`: the rows, and every field when exactly one matched — so "when
///   did I pay Meralco in August?" takes one lookup, not a find and a detail
///   call.
/// - `ambiguous`: several rows matched a query; it lists them and says to ask
///   or narrow.
/// - `not_found`: nothing matched; the nearest names, and any match in
///   another month.
/// - `error`: the call itself was wrong, with how to fix it.
///
/// Reads only, through the presenters that own the data (CLAUDE.md #8). No
/// figure is computed here that a presenter already computes.
class FinanceFinder {
  const FinanceFinder({
    required BillsReceivablesPresenter bills,
    BudgetPresenter? budget,
    LedgerPresenter? ledger,
    InstallmentPresenter? installments,
    TreasuryDashboardPresenter? dashboard,
  })  : _bills = bills,
        _budget = budget,
        _ledger = ledger,
        _installments = installments,
        _dashboard = dashboard;

  final BillsReceivablesPresenter _bills;
  final BudgetPresenter? _budget;
  final LedgerPresenter? _ledger;
  final InstallmentPresenter? _installments;
  final TreasuryDashboardPresenter? _dashboard;

  AiToolResult find(AiToolCall call, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final i = call.input;
    final rawEntity = i['entity'] is String ? i['entity'] as String : '';
    final entity = FindEntity.parse(rawEntity);
    if (entity == null) {
      return _error(
          call,
          'Unknown entity "$rawEntity". Use one of: '
          '${FindEntity.values.map((e) => e.name).join(', ')}. For '
          'transactions use findTransactions.');
    }
    final query =
        parseFindQuery(i['query'] is String ? i['query'] as String : '');

    // The month: the one given, else one the query named ("meralco aug"),
    // else today's. Never the month a tab is showing.
    final given = i['month'] is String ? (i['month'] as String).trim() : '';
    final String month;
    final bool monthChosen;
    if (given.isNotEmpty) {
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(given)) {
        return _error(call, 'month must be YYYY-MM, not "$given".');
      }
      month = rebaseStaleMonthKey(given, today);
      monthChosen = true;
    } else if (query.monthNumber != null) {
      final m = query.monthNumber!;
      final year = m > today.month ? today.year - 1 : today.year;
      month = toMonthKey(DateTime(year, m));
      monthChosen = true;
    } else {
      month = toMonthKey(today);
      monthChosen = false;
    }

    final List<_Row> all;
    switch (entity) {
      case FindEntity.bill:
        all = [for (final b in _bills.allBills) _billRow(b)];
      case FindEntity.receivable:
        all = [for (final r in _bills.allReceivables) _receivableRow(r)];
      case FindEntity.setAside:
        all = [for (final e in _bills.allBudgetedExpenses) _setAsideRow(e)];
      case FindEntity.budget:
        final budget = _budget;
        if (budget == null) return _error(call, 'Budgets are not available.');
        all = [for (final b in budget.allBudgets) _budgetRow(budget, b)];
      case FindEntity.budgetGroup:
        final budget = _budget;
        if (budget == null) return _error(call, 'Budgets are not available.');
        all = _groupRows(budget, month);
      case FindEntity.installment:
        if (_installments == null) {
          return _error(call, 'Installments are not available.');
        }
        all = [for (final p in _installments.allInstallments) _planRow(p)];
      case FindEntity.account:
        if (_ledger == null) return _error(call, 'Accounts are not available.');
        all = [for (final a in _ledger.accounts) _accountRow(a)];
    }

    final inScope =
        entity.isMonthly ? all.where((r) => r.month == month).toList() : all;
    final hits = inScope.where((r) => findMatches(query, r.haystack)).toList();
    final scope = entity.isMonthly ? month : 'all';
    final head = 'entity: ${entity.name} · month: $scope'
        '${query.isEmpty ? '' : ' · words: ${query.words.join(' ')}'}';

    if (hits.isEmpty) {
      final lines = <String>['status: not_found', head];
      if (!query.isEmpty) {
        // The same name in other months, newest first: a bill asked for in
        // the wrong month is still that bill.
        final elsewhere = entity.isMonthly
            ? (all
                    .where((r) =>
                        r.month != month && findMatches(query, r.haystack))
                    .toList()
                  ..sort((a, b) => (b.month ?? '').compareTo(a.month ?? '')))
                .take(5)
                .toList()
            : const <_Row>[];
        if (elsewhere.isNotEmpty) {
          lines.add('Matches in other months:');
          lines.addAll(elsewhere.map((r) => '- ${r.line}'));
        }
        final near = nearestNames(query, inScope.map((r) => r.name));
        if (near.isNotEmpty) {
          lines.add('Nearest names in $scope: '
              '${near.map((n) => '"$n"').join(', ')}');
        }
      }
      lines.add(
          'hint: Do not guess an id. ${monthChosen || !entity.isMonthly ? '' : 'Pass month for another month. '}'
          'Use a matching name above, or tell the user you could not find it.');
      return _ok(call, lines);
    }

    if (hits.length == 1 && !query.isEmpty) {
      return _ok(call, [
        'status: found',
        head,
        ...hits.single.detail(),
      ]);
    }

    final listed = hits.take(_maxRows).toList();
    return _ok(call, [
      query.isEmpty ? 'status: found' : 'status: ambiguous',
      head,
      '${hits.length} matched${hits.length > listed.length ? ', showing ${listed.length}' : ''}:',
      ...listed.map((r) => '- ${r.line}'),
      if (!query.isEmpty)
        'hint: Several rows match. If the user means one, call find again '
            'with more of its name, or ask which. If they asked for a list, '
            'these are all the matches.',
    ]);
  }

  static const int _maxRows = 40;

  // ── Rows ─────────────────────────────────────────────────────────────────

  _Row _billRow(Bill b) {
    final category = _categoryName(b.categoryId);
    final account = _accountName(b.accountId);
    final status = b.isPaid
        ? 'paid${b.paidDate == null ? '' : ' ${_day(b.paidDate!)}'}'
        : (b.paidAmount ?? 0) > 0
            ? '${_peso(b.paidAmount!)} paid so far'
            : 'unpaid';
    return _Row(
      id: b.id,
      name: b.name,
      month: b.month,
      haystack: '${b.name} $category $account ${b.paymentNote ?? ''} '
          '${b.billType.name}',
      line: 'id=${b.id} "${b.name}" ${_peso(b.amount)} due day ${b.dueDay} '
          '(${b.month}) [$status]${b.isRecurring ? ' (recurring)' : ''}',
      detail: () => [
        'id: ${b.id}',
        'name: ${b.name}',
        'month: ${b.month}',
        'amount billed: ${_peso(b.amount)}',
        if (b.nextMonthAmount != null)
          'next month\'s amount: ${_peso(b.nextMonthAmount!)}',
        'due: day ${b.dueDay}',
        'type: ${b.billType.name}',
        'category: ${category.isEmpty ? 'none' : category}',
        'pay from: ${account.isEmpty ? 'not set' : account}',
        if ((b.paymentNote ?? '').trim().isNotEmpty)
          'payment note: ${b.paymentNote!.trim()}',
        'status: $status',
        if (b.paidAmount != null) 'paid amount: ${_peso(b.paidAmount!)}',
        if (b.paidDate != null) 'paid date: ${_day(b.paidDate!)}',
        if (_txnLine(b.transactionId) case final t?) 'ledger entry: $t',
        'repeats: ${b.isRecurring ? (b.recurrenceType?.name ?? 'monthly') : 'no'}'
            '${b.seriesId == null ? '' : ' (series ${b.seriesId})'}',
        if (b.reminderDaysBefore != null)
          'reminder: ${b.reminderDaysBefore} days before',
      ],
    );
  }

  _Row _receivableRow(Receivable r) {
    final account = _accountName(r.accountId);
    final status = r.isReceived
        ? 'received${r.receivedDate == null ? '' : ' ${_day(r.receivedDate!)}'}'
        : 'not received';
    final forTxn = _txnLine(r.reimbursementForTxnId);
    return _Row(
      id: r.id,
      name: r.name,
      month: r.month,
      haystack: '${r.name} $account ${r.receivableType.name}',
      line: 'id=${r.id} "${r.name}" ${_peso(r.amount)} (${r.month}) [$status]'
          '${r.isRecurring ? ' (recurring)' : ''}',
      detail: () => [
        'id: ${r.id}',
        'name: ${r.name}',
        'month: ${r.month}',
        'amount expected: ${_peso(r.amount)}',
        if (r.nextMonthAmount != null)
          'next month\'s amount: ${_peso(r.nextMonthAmount!)}',
        'expected: ${r.expectedDate == null ? 'no date' : _day(r.expectedDate!)}',
        'type: ${r.receivableType.name}',
        'status: $status',
        if (r.receivedAmount != null)
          'received amount: ${_peso(r.receivedAmount!)}',
        'deposit into: ${account.isEmpty ? 'not set' : account}',
        if (forTxn != null) 'reimburses: $forTxn',
        if (_txnLine(r.transactionId) case final t?) 'ledger entry: $t',
        'repeats: ${r.isRecurring ? (r.recurrenceType?.name ?? 'monthly') : 'no'}',
      ],
    );
  }

  _Row _setAsideRow(BudgetedExpense e) {
    final from = _accountName(e.accountId);
    final into = _accountName(e.destinationAccountId);
    final left =
        (e.allocatedAmount - e.spentAmount).clamp(0.0, double.infinity);
    return _Row(
      id: e.id,
      name: e.name,
      month: e.month,
      haystack: '${e.name} $from $into ${e.note ?? ''} ${e.budgetedType.name}',
      line: 'id=${e.id} "${e.name}" ${e.budgetedType.name} allocated '
          '${_peso(e.allocatedAmount)} funded ${_peso(e.spentAmount)} '
          '(${e.month})${e.isRecurring ? ' (recurring)' : ''}',
      detail: () => [
        'id: ${e.id}',
        'name: ${e.name}',
        'month: ${e.month}',
        'type: ${e.budgetedType.name}',
        'allocated: ${_peso(e.allocatedAmount)}',
        'funded: ${_peso(e.spentAmount)}',
        'still to fund: ${_peso(left)}',
        'status: ${e.isPaid ? 'funded' : 'open'}',
        'from account: ${from.isEmpty ? 'not set' : from}',
        'into account: ${into.isEmpty ? 'not set' : into}',
        if ((e.note ?? '').trim().isNotEmpty) 'note: ${e.note!.trim()}',
        if (_txnLine(e.transactionId) case final t?) 'ledger entry: $t',
        'repeats: ${e.isRecurring ? (e.recurrenceType?.name ?? 'monthly') : 'no'}',
      ],
    );
  }

  _Row _budgetRow(BudgetPresenter budget, Budget b) {
    final savings = budget.isSavingsGroup(b.group);
    // A savings row's "categoryId" is the id of the account it funds.
    final name =
        savings ? _accountName(b.categoryId) : _categoryName(b.categoryId);
    final group =
        budget.groups.where((g) => g.id == b.group).firstOrNull?.name ??
            b.group;
    final income = budget.isCategoryIncome(b.categoryId);
    final used = income ? 0.0 : budget.spentForBudget(b);
    final verb = savings ? 'funded' : 'spent';
    final label = name.isEmpty ? 'unknown' : name;
    return _Row(
      id: b.id,
      name: label,
      month: b.month,
      haystack: '$label $group',
      line: income
          ? 'id=${b.id} "$label" [$group] income target '
              '${_peso(b.allocatedAmount)} — not spending'
          : 'id=${b.id} "$label" [$group] limit ${_peso(b.allocatedAmount)}, '
              '$verb ${_peso(used)}, left ${_peso(b.allocatedAmount - used)}',
      detail: () => [
        'id: ${b.id}',
        'name: $label',
        'month: ${b.month}',
        'group: $group',
        'kind: ${income ? 'income target (not spending)' : savings ? 'savings (money set aside into $label)' : 'expense'}',
        'limit: ${_peso(b.allocatedAmount)}',
        if (!income) '$verb: ${_peso(used)}',
        if (!income) 'left: ${_peso(b.allocatedAmount - used)}',
        'budget type: ${b.budgetType.name}',
      ],
    );
  }

  List<_Row> _groupRows(BudgetPresenter budget, String month) {
    final rows = <_Row>[];
    for (final g in budget.groups) {
      final inGroup =
          budget.allBudgets.where((b) => b.month == month && b.group == g.id);
      if (inGroup.isEmpty) continue;
      final allocated = inGroup.fold(0.0, (s, b) => s + b.allocatedAmount);
      final used = inGroup.fold(0.0, (s, b) => s + budget.spentForBudget(b));
      final verb = budget.isSavingsGroup(g.id) ? 'funded' : 'spent';
      final line = '"${g.name}": allocated ${_peso(allocated)}, $verb '
          '${_peso(used)}, remaining ${_peso(allocated - used)}';
      rows.add(_Row(
        id: null,
        name: g.name,
        month: month,
        haystack: g.name,
        line: line,
        detail: () => [
          'group: ${g.name}',
          'month: $month',
          'allocated: ${_peso(allocated)}',
          '$verb: ${_peso(used)}',
          'remaining: ${_peso(allocated - used)}',
          'rows: ${inGroup.length}',
        ],
      ));
    }
    return rows;
  }

  _Row _planRow(Installment p) {
    final txns = _ledger?.allTransactions ?? const <TransactionRecord>[];
    final account = _accountName(p.accountId);
    final paid = p.paidCount(txns);
    final unbilled = p.remainingAmount(txns);
    final status = p.isActive ? 'active' : 'cancelled';
    return _Row(
      id: p.id,
      name: p.name,
      haystack: '${p.name} $account ${p.note ?? ''}',
      line: 'id=${p.id} "${p.name}" on $account: ${_peso(p.monthlyAmount)}/mo '
          '($paid/${p.totalMonths} paid), unbilled ${_peso(unbilled)}, '
          'original ${_peso(p.totalAmount)} [$status]',
      detail: () => [
        'id: ${p.id}',
        'name: ${p.name}',
        'account: $account',
        'status: $status',
        'purchase price: ${_peso(p.totalAmount)}',
        if (p.purchaseDate != null) 'purchase date: ${_day(p.purchaseDate!)}',
        'monthly payment: ${_peso(p.monthlyAmount)}',
        'months: ${p.totalMonths} ($paid paid)',
        'first payment month: ${p.startMonth}${_startMonthNote(p)}',
        'last payment month: ${p.endMonth}',
        if (p.deferralMonths > 0) 'deferred: ${p.deferralMonths} months',
        'interest: ${p.hasInterest ? '${p.interestRate}% a month' : '0%'}',
        'total interest: ${_peso(p.totalInterest)}',
        'total payable: ${_peso(p.totalPayable)}',
        'not yet billed: ${_peso(unbilled)}',
        if (_categoryName(p.categoryId) case final c when c.isNotEmpty)
          'category: $c',
        if ((p.note ?? '').trim().isNotEmpty) 'note: ${p.note!.trim()}',
      ],
    );
  }

  _Row _accountRow(FinancialAccount a) {
    final parent = _accountName(a.parentAccountId);
    final held = _dashboard?.heldAmountByAccountId[a.id];
    final String summary;
    if (a.isLiability) {
      summary = 'owed ${_peso(a.totalDebt)}'
          '${a.creditLimit == null ? '' : ', limit ${_peso(a.creditLimit!)}, '
              'available ${_peso(a.availableCredit ?? 0)}'}';
    } else {
      summary = 'balance ${_peso(a.balance)}';
    }
    return _Row(
      id: a.id,
      name: a.name,
      haystack: '${a.name} ${a.category.name} $parent',
      line: 'id=${a.id} "${a.name}" $summary'
          '${a.isLiability ? '; ${_statementLine(a)}' : ''} '
          '[${a.category.name}]${a.isActive ? '' : ' [archived]'}',
      detail: () => [
        'id: ${a.id}',
        'name: ${a.name}',
        'type: ${a.category.name}',
        'status: ${a.isActive ? 'active' : 'archived'}',
        if (a.isLiability) ...[
          'owed (incl. installment months not yet billed): ${_peso(a.totalDebt)}',
          if (a.unbilledInstallments > 0)
            'installment months not yet billed: ${_peso(a.unbilledInstallments)}',
          if (a.creditLimit != null) 'credit limit: ${_peso(a.creditLimit!)}',
          if (a.availableCredit != null)
            'available credit: ${_peso(a.availableCredit!)}',
          if (a.statementDay != null) 'statement closes: day ${a.statementDay}',
          if (a.paymentDueDay != null) 'payment due: day ${a.paymentDueDay}',
          _statementLine(a),
        ] else
          'balance: ${_peso(a.balance)}',
        if (held != null && held > 0)
          'held for someone else: ${_peso(held)} (yours: ${_peso(a.balance - held)})',
        if (parent.isNotEmpty) 'inside: $parent',
        if (a.goalTarget != null) 'goal target: ${_peso(a.goalTarget!)}',
        if (a.maturityDate != null) 'matures: ${_day(a.maturityDate!)}',
        if (a.currency != 'PHP') 'currency: ${a.currency}',
      ],
    );
  }

  /// The open statement of credit account [a], as the Accounts tab says it.
  String _statementLine(FinancialAccount a) {
    final statement = findOpenCreditStatement(_bills.allBills, a.id);
    if (statement == null) return 'statement: none owed right now';
    final p = CreditStatementProgress.ofBill(statement, a);
    final due = creditStatementDueDate(statement);
    return 'statement: ${_peso(p.amount)}, ${_peso(p.paid)} paid, '
        '${_peso(p.remaining)} left, minimum left ${_peso(p.minimumRemaining)}'
        '${due == null ? '' : ', due ${_day(due)}'}';
  }

  // ── Small helpers ────────────────────────────────────────────────────────

  String? _txnLine(String? id) {
    if (id == null) return null;
    final t = _ledger?.allTransactions.where((t) => t.id == id).firstOrNull;
    if (t == null) return null;
    return '"${t.description}" ${_peso(t.amount)} on ${_day(t.date)} '
        'from ${_accountName(t.accountId)}';
  }

  List<FinanceCategory> get _categories =>
      _budget?.allCategories ?? _ledger?.categories ?? const [];

  String _categoryName(String? id) => id == null || id.isEmpty
      ? ''
      : _categories.where((c) => c.id == id).firstOrNull?.name ?? '';

  String _accountName(String? id) => id == null || id.isEmpty
      ? ''
      : (_ledger?.accounts ?? const <FinancialAccount>[])
              .where((a) => a.id == id)
              .firstOrNull
              ?.name ??
          '';

  static AiToolResult _ok(AiToolCall call, List<String> lines) =>
      AiToolResult(toolUseId: call.id, ok: true, summary: lines.join('\n'));

  static AiToolResult _error(AiToolCall call, String why) => AiToolResult(
        toolUseId: call.id,
        ok: false,
        summary: 'status: error\n$why',
      );

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// " (set by hand; the card cycle gives 2027-02)" after an installment's
  /// first payment month, or nothing (Plan 068).
  String _startMonthNote(Installment p) {
    final note = _installments?.startMonthNote(p);
    return note == null ? '' : ' ($note)';
  }

  static String _peso(double v) => '₱${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';
}
