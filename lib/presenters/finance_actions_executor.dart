import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../utils/finance_format.dart';
import '../utils/finance_nlp_parser.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'finance_tool_executor.dart';
import 'ledger_presenter.dart';

/// Runs Nudgy's finance tools against the presenters that own the data.
///
/// Assembled in `TreasuryPresenters` (CLAUDE.md #9), never in a shell, and it
/// writes only through the owning presenter's mutators (CLAUDE.md #8) — bills
/// owns set-asides and receivables, budget owns budgets, ledger owns
/// transactions, accounts and categories.
///
/// A read runs immediately. A mutation does not: [propose] parks a
/// [PendingFinanceAction] and returns a future that only completes when the
/// user answers, so there is no code path from a model reply to a write.
class FinanceActionsExecutor extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  FinanceActionsExecutor({
    required BillsReceivablesPresenter bills,
    BudgetPresenter? budget,
    LedgerPresenter? ledger,
  })  : _bills = bills,
        _budget = budget,
        _ledger = ledger;

  final BillsReceivablesPresenter _bills;
  final BudgetPresenter? _budget;

  /// Owns transactions, accounts and categories. Null on a surface built
  /// without a ledger, which is why `addTransaction` reports its absence
  /// rather than assuming one.
  final LedgerPresenter? _ledger;

  PendingFinanceAction? _pending;
  Completer<AiToolResult>? _decision;

  @override
  PendingFinanceAction? get pending => _pending;

  // ── Reads ─────────────────────────────────────────────────────────────────

  @override
  Future<AiToolResult> runRead(AiToolCall call) async {
    final query = _str(call.input['query']).toLowerCase();
    final month = _str(call.input['month']).isEmpty
        ? _bills.selectedMonth
        : _str(call.input['month']);

    bool matches(String name) =>
        query.isEmpty || name.toLowerCase().contains(query);

    switch (call.name) {
      case 'findBills':
        final rows = _bills.allBills
            .where((b) => b.month == month && matches(b.name))
            .map((b) => 'id=${b.id} "${b.name}" ${_peso(b.amount)} '
                'due day ${b.dueDay}${b.isRecurring ? ' (recurring)' : ''}'
                '${b.isPaid ? ' [paid]' : ''}');
        return _rows(call, rows, 'bills', month);

      case 'findReceivables':
        final rows = _bills.allReceivables
            .where((r) => r.month == month && matches(r.name))
            .map((r) => 'id=${r.id} "${r.name}" ${_peso(r.amount)}'
                '${r.isRecurring ? ' (recurring)' : ''}'
                '${r.isReceived ? ' [received]' : ''}');
        return _rows(call, rows, 'receivables', month);

      case 'findSetAsides':
        final rows = _bills.allBudgetedExpenses
            .where((e) => e.month == month && matches(e.name))
            .map((e) => 'id=${e.id} "${e.name}" ${e.budgetedType.name} '
                'allocated ${_peso(e.allocatedAmount)} '
                'funded ${_peso(e.spentAmount)}'
                '${e.isRecurring ? ' (recurring)' : ''}');
        return _rows(call, rows, 'set-asides', month);

      case 'findBudgets':
        final budget = _budget;
        if (budget == null) {
          return AiToolResult.failed(
              call.id, 'Budgets are not available here.');
        }
        final names = {
          for (final c in budget.allCategories) c.id: c.name,
        };
        final rows = budget.allBudgets
            .where(
                (b) => b.month == month && matches(names[b.categoryId] ?? ''))
            .map((b) => 'id=${b.id} "${names[b.categoryId] ?? b.categoryId}" '
                'limit ${_peso(b.allocatedAmount)}');
        return _rows(call, rows, 'budgets', month);
    }
    return AiToolResult.failed(call.id, 'Unknown read tool "${call.name}".');
  }

  /// A search that found nothing says so plainly. Returning an empty list with
  /// no explanation invites the model to invent an id and carry on.
  AiToolResult _rows(
      AiToolCall call, Iterable<String> rows, String kind, String month) {
    final list = rows.toList();
    return AiToolResult(
      toolUseId: call.id,
      ok: true,
      summary: list.isEmpty
          ? 'No $kind matched in $month. Do not guess an id — say you could '
              'not find it.'
          : '${list.length} $kind in $month:\n${list.join('\n')}',
    );
  }

  // ── Proposals ─────────────────────────────────────────────────────────────

  @override
  Future<AiToolResult> propose(AiToolCall call) {
    // A second proposal while one is pending would strand the first future
    // forever. Refuse rather than silently dropping it.
    if (_decision != null) {
      return Future.value(AiToolResult.failed(
          call.id, 'Another change is still waiting to be confirmed.'));
    }
    // Validation runs before the card, not on it. A card can only ask yes or
    // no, so a call that never named an account has nothing to confirm —
    // showing one anyway would put a blank field in front of the user and make
    // the model's omission look like their decision. Failing instead hands the
    // model the real names so it can fix the call on its next hop, or ask.
    final rejection = _validate(call);
    if (rejection != null) {
      return Future.value(AiToolResult.failed(call.id, rejection));
    }
    final action = _describe(call);
    if (action == null) {
      return Future.value(
          AiToolResult.failed(call.id, 'Unknown tool "${call.name}".'));
    }
    _pending = action;
    _decision = Completer<AiToolResult>();
    notifyListeners();
    return _decision!.future;
  }

  /// The user said yes. [applyToFuture] comes from the card, never the model:
  /// it spreads the change across later months of the series, and no chat
  /// sentence reliably asks for that.
  @override
  Future<void> confirm({bool applyToFuture = false}) async {
    final action = _pending;
    final decision = _decision;
    if (action == null || decision == null) return;
    _pending = null;
    _decision = null;

    try {
      final summary = await _write(action, applyToFuture: applyToFuture);
      decision.complete(
          AiToolResult(toolUseId: action.call.id, ok: true, summary: summary));
    } catch (e) {
      debugPrint('FinanceActionsExecutor write failed: $e');
      decision.complete(AiToolResult.failed(
          action.call.id, 'Saving that failed, so nothing was changed.'));
    }
    notifyListeners();
  }

  /// The user said no. Reported as a decline, never as a quiet success.
  @override
  void decline() {
    final action = _pending;
    final decision = _decision;
    if (action == null || decision == null) return;
    _pending = null;
    _decision = null;
    decision.complete(AiToolResult.declined(action.call.id));
    notifyListeners();
  }

  // ── Describing and writing ────────────────────────────────────────────────

  PendingFinanceAction? _describe(AiToolCall call) {
    final i = call.input;
    final name = _str(i['name']);
    final amount = _num(i['amount']);
    final recurring = i['isRecurring'] == true;

    switch (call.name) {
      case 'addBill':
        return PendingFinanceAction(
          call: call,
          title: 'Add bill: $name, ${_peso(amount)}',
          isRecurring: recurring,
          details: [
            (label: 'Amount', value: _peso(amount)),
            (label: 'Due day', value: '${_int(i['dueDay'])}'),
            (label: 'Month', value: _month(i)),
            if (_str(i['category']).isNotEmpty)
              (label: 'Category', value: _str(i['category'])),
            if (_str(i['account']).isNotEmpty)
              (label: 'Pay from', value: _str(i['account'])),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
          ],
        );
      case 'addReceivable':
        return PendingFinanceAction(
          call: call,
          title: 'Add receivable: $name, ${_peso(amount)}',
          isRecurring: recurring,
          details: [
            (label: 'Amount', value: _peso(amount)),
            if (_str(i['owedBy']).isNotEmpty)
              (label: 'Owed by', value: _str(i['owedBy'])),
            (label: 'Month', value: _month(i)),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
          ],
        );
      case 'addTransaction':
        // Every `!` below is safe because [propose] runs [_validate] first and
        // returns a failure rather than reaching here when a name does not
        // resolve. Describing a transaction is not the place to re-decide
        // whether it is describable.
        final kind = _txnType(i['type'])!;
        final desc = _str(i['description']);
        final pool = chatEligibleAccounts(_ledger!.accounts);
        final from = _accountFor(_str(i['account']), pool)!;
        final date = _date(i);
        final reimbursable =
            i['reimbursable'] == true && kind == TransactionType.outflow;
        return PendingFinanceAction(
          call: call,
          // Never recurring: a transaction is a single dated event, so there
          // is no series for the card's future-months scope to spread across.
          isRecurring: false,
          title: switch (kind) {
            TransactionType.transfer =>
              'Transfer ${_peso(amount)} from ${from.name} to '
                  '${_accountFor(_str(i['toAccount']), pool)!.name}',
            TransactionType.inflow => 'Log income: $desc, ${_peso(amount)}',
            TransactionType.outflow => 'Log expense: $desc, ${_peso(amount)}',
          },
          details: [
            (label: 'Amount', value: _peso(amount)),
            (label: 'Date', value: _dateLabel(date)),
            if (kind == TransactionType.transfer) ...[
              (label: 'From', value: from.name),
              (
                label: 'To',
                value: _accountFor(_str(i['toAccount']), pool)!.name
              ),
            ] else ...[
              (label: 'Account', value: from.name),
              (
                label: 'Category',
                value: _categoryFor(_str(i['category']), kind)!.name
              ),
            ],
            if (_str(i['note']).isNotEmpty)
              (label: 'Note', value: _str(i['note'])),
            if (reimbursable)
              (
                label: 'Owed back',
                value: _str(i['owedBy']).isEmpty
                    ? 'Yes, payer not named'
                    : 'Yes, by ${_str(i['owedBy'])}'
              ),
          ],
        );
      case 'addSetAside':
        return PendingFinanceAction(
          call: call,
          title: 'Set aside ${_peso(amount)} for $name',
          isRecurring: recurring,
          details: [
            (label: 'Amount', value: _peso(amount)),
            (label: 'Type', value: _setAsideType(i['type']).name),
            if (_str(i['destinationAccount']).isNotEmpty)
              (label: 'Into', value: _str(i['destinationAccount'])),
            (label: 'Month', value: _month(i)),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
          ],
        );
    }
    return null;
  }

  Future<String> _write(PendingFinanceAction action,
      {required bool applyToFuture}) async {
    final call = action.call;
    final i = call.input;
    final name = _str(i['name']);
    final amount = _num(i['amount']);
    final month = _month(i);
    final recurring = i['isRecurring'] == true;
    final scope = applyToFuture ? ' and to later months' : '';

    switch (call.name) {
      case 'addBill':
        await _bills.addBill(
          Bill(
            id: _id(),
            name: name,
            billType: BillType.other,
            amount: amount,
            dueDay: _int(i['dueDay']).clamp(1, 31),
            month: month,
            categoryId: _categoryIdFor(_str(i['category'])),
            isRecurring: recurring,
            recurrenceType: recurring ? RecurrenceType.monthly : null,
          ),
          applyToFuture: applyToFuture,
        );
        return 'Added the bill "$name" for ${_peso(amount)} in $month$scope.';

      case 'addReceivable':
        await _bills.addReceivable(
          Receivable(
            id: _id(),
            name: name,
            receivableType: ReceivableType.other,
            amount: amount,
            month: month,
            categoryId: '',
            isRecurring: recurring,
            recurrenceType: recurring ? RecurrenceType.monthly : null,
          ),
          applyToFuture: applyToFuture,
        );
        return 'Added the receivable "$name" for ${_peso(amount)} in '
            '$month$scope.';

      case 'addTransaction':
        return _writeTransaction(call);

      case 'addSetAside':
        await _bills.addBudgetedExpense(
          BudgetedExpense(
            id: _id(),
            name: name,
            budgetedType: _setAsideType(i['type']),
            month: month,
            allocatedAmount: amount,
            // A set-aside moves money between the user's own accounts, so it
            // is never spending and carries no expense category — the same
            // empty value the Bills sheet saves.
            categoryId: '',
            isRecurring: recurring,
            recurrenceType: recurring ? RecurrenceType.monthly : null,
          ),
          applyToFuture: applyToFuture,
        );
        return 'Set aside ${_peso(amount)} for "$name" in $month$scope.';
    }
    throw StateError('no writer for ${call.name}');
  }

  /// Books the transaction the user just confirmed.
  ///
  /// Names are re-resolved here rather than carried on the proposal: the
  /// proposal is a description, not a half-built entity, and resolving against
  /// the live lists at write time is what keeps a confirm from writing to an
  /// account that no longer exists. [_validate] already proved they resolve,
  /// so a null here means the data changed underneath and the throw is caught
  /// by [confirm] as a failed write.
  Future<String> _writeTransaction(AiToolCall call) async {
    final i = call.input;
    final ledger = _ledger!;
    final kind = _txnType(i['type'])!;
    final amount = _num(i['amount']);
    final date = _date(i);
    final description = _str(i['description']);
    final note = _str(i['note']).isEmpty ? null : _str(i['note']);
    final pool = chatEligibleAccounts(ledger.accounts);
    final from = _accountFor(_str(i['account']), pool);
    if (from == null) throw StateError('account vanished');

    if (kind == TransactionType.transfer) {
      final to = _accountFor(_str(i['toAccount']), pool);
      if (to == null) throw StateError('destination account vanished');
      await ledger.addTransfer(
        fromAccountId: from.id,
        toAccountId: to.id,
        amount: amount,
        description: description,
        date: date,
        note: note,
      );
      return 'Moved ${_peso(amount)} from "${from.name}" to "${to.name}" on '
          '${_dateLabel(date)}.';
    }

    final category = _categoryFor(_str(i['category']), kind);
    if (category == null) throw StateError('category vanished');
    final reimbursable =
        i['reimbursable'] == true && kind == TransactionType.outflow;
    final owedBy = _str(i['owedBy']);

    final record = TransactionRecord(
      id: _id(),
      date: date,
      accountId: from.id,
      categoryId: category.id,
      amount: amount,
      type: kind,
      description: description,
      note: note,
      month: toMonthKey(date),
      reimbursable: reimbursable,
      // Pre-generated because the ledger stamps the link onto the outflow
      // before spawning the receivable it points at.
      reimbursementReceivableId: reimbursable ? _id() : null,
      owedBy: reimbursable && owedBy.isNotEmpty ? owedBy : null,
    );

    if (reimbursable) {
      // Null expected date keeps the form's "ASAP" default: nothing in the
      // schema asks the model for a payback date, and inventing one here
      // would put a deadline on the user's behalf.
      await ledger.addReimbursableExpense(record,
          expectedReimbursementDate: null);
      return 'Logged the reimbursable expense "$description" for '
          '${_peso(amount)} on ${_dateLabel(date)}, and started tracking the '
          'payback.';
    }

    await ledger.addTransaction(record);
    final verb = kind == TransactionType.inflow ? 'income' : 'expense';
    return 'Logged the $verb "$description" for ${_peso(amount)} to '
        '"${from.name}" on ${_dateLabel(date)}.';
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Why [call] cannot become a proposal at all, or null when it can.
  ///
  /// Only `addTransaction` is checked: the other creates have no argument
  /// whose absence changes what gets written, so a missing field there degrades
  /// to a sensible default the card shows. A transaction is different — the
  /// account and category decide which balance moves and which budget it lands
  /// in, and neither has a safe default.
  ///
  /// Every message names the real options, because the model gets another hop:
  /// a failure it can act on ends the turn correctly, and one it cannot ends
  /// it with an apology.
  String? _validate(AiToolCall call) {
    if (call.name != 'addTransaction') return null;

    final ledger = _ledger;
    if (ledger == null) {
      return 'The ledger is not available here, so nothing can be logged.';
    }

    final i = call.input;
    if (_num(i['amount']) <= 0) {
      return 'Amount must be a positive number of pesos. Direction comes from '
          '"type", not from a minus sign.';
    }
    if (_str(i['description']).isEmpty) {
      return 'A description is required — say what the transaction was for.';
    }

    final kind = _txnType(i['type']);
    if (kind == null) {
      return 'Unknown type "${_str(i['type'])}". Use expense, income or '
          'transfer.';
    }

    // The ledger records what happened, so an entry cannot be dated forward.
    // Money the user expects to move later is a bill or a receivable, and
    // saying so points the model at the tool that actually fits.
    final now = DateTime.now();
    if (_date(i).isAfter(DateTime(now.year, now.month, now.day))) {
      return 'The ledger cannot hold a future-dated entry. If this is money '
          'that has not moved yet, propose a bill or a receivable instead.';
    }

    final pool = chatEligibleAccounts(ledger.accounts);
    if (pool.isEmpty) {
      return 'There are no accounts to log against yet. The user has to create '
          'one first.';
    }
    final from = _accountFor(_str(i['account']), pool);
    if (from == null) {
      return _str(i['account']).isEmpty
          ? 'Which account? Ask the user, or name one of: ${_names(pool.map((a) => a.name))}.'
          : 'No account matches "${_str(i['account'])}". The accounts are: '
              '${_names(pool.map((a) => a.name))}.';
    }

    if (kind == TransactionType.transfer) {
      if (_str(i['toAccount']).isEmpty) {
        return 'A transfer needs "toAccount" as well. The accounts are: '
            '${_names(pool.map((a) => a.name))}.';
      }
      final to = _accountFor(_str(i['toAccount']), pool);
      if (to == null) {
        return 'No account matches "${_str(i['toAccount'])}". The accounts '
            'are: ${_names(pool.map((a) => a.name))}.';
      }
      if (to.id == from.id) {
        return 'A transfer needs two different accounts.';
      }
      return null;
    }

    // Expense and income both have to land in a category, or the entry is
    // invisible to every budget and category total in the app. There is no
    // safe fallback, so an unresolved name is a failure rather than a blank.
    final wanted = kind == TransactionType.inflow ? 'income' : 'expense';
    final options = _categoryPool(kind);
    if (options.isEmpty) {
      return 'There are no $wanted categories yet. The user has to create one '
          'first.';
    }
    if (_categoryFor(_str(i['category']), kind) == null) {
      return _str(i['category']).isEmpty
          ? 'Which category? The $wanted categories are: ${_names(options.map((c) => c.name))}.'
          : 'No $wanted category matches "${_str(i['category'])}". They are: '
              '${_names(options.map((c) => c.name))}.';
    }
    return null;
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  /// Resolve a category NAME to its id. The model never sees ids, so it sends
  /// names and the client binds them — the same contract the expense extractor
  /// uses. An unresolved name leaves the category empty rather than guessing.
  String _categoryIdFor(String name) {
    if (name.isEmpty) return '';
    final lower = name.toLowerCase();
    final categories = _budget?.allCategories ?? const [];
    for (final c in categories) {
      if (c.name.toLowerCase() == lower) return c.id;
    }
    for (final c in categories) {
      if (c.name.toLowerCase().startsWith(lower)) return c.id;
    }
    return '';
  }

  /// Resolve an account NAME against the pool chat is allowed to name.
  ///
  /// Exact, then prefix, then contained — the same widening the expense
  /// extractor uses, so "bpi" finds "BPI Savings" and a partial name resolves
  /// instead of failing. An empty name falls back to the sole account only
  /// when there is exactly one; with several, silence is not a choice.
  FinancialAccount? _accountFor(String name, List<FinancialAccount> pool) {
    if (name.isEmpty) return pool.length == 1 ? pool.single : null;
    final lower = name.toLowerCase();
    for (final a in pool) {
      if (a.name.toLowerCase() == lower) return a;
    }
    for (final a in pool) {
      if (a.name.toLowerCase().startsWith(lower)) return a;
    }
    for (final a in pool) {
      if (a.name.toLowerCase().contains(lower)) return a;
    }
    return null;
  }

  /// The categories a transaction of [kind] may be filed under.
  ///
  /// Filtered by direction: an expense filed under an income category would
  /// count the wrong way in every total that reads the category type.
  List<FinanceCategory> _categoryPool(TransactionType kind) {
    final wanted = kind == TransactionType.inflow
        ? CategoryType.income
        : CategoryType.expense;
    return (_ledger?.categories ?? const <FinanceCategory>[])
        .where((c) => c.type == wanted)
        .toList();
  }

  FinanceCategory? _categoryFor(String name, TransactionType kind) {
    if (name.isEmpty) return null;
    final pool = _categoryPool(kind);
    final lower = name.toLowerCase();
    for (final c in pool) {
      if (c.name.toLowerCase() == lower) return c;
    }
    for (final c in pool) {
      if (c.name.toLowerCase().startsWith(lower)) return c;
    }
    return null;
  }

  /// Maps the schema's user-facing words onto the ledger's directions. Returns
  /// null for anything else, so an unrecognised value fails loudly instead of
  /// silently booking an expense.
  static TransactionType? _txnType(Object? raw) {
    // Anything that is not a string was not the enum, and coercing it would
    // book an expense off a value nobody meant as one. Only true absence
    // defaults.
    if (raw != null && raw is! String) return null;
    return switch (_str(raw)) {
      '' || 'expense' => TransactionType.outflow,
      'income' => TransactionType.inflow,
      'transfer' => TransactionType.transfer,
      _ => null,
    };
  }

  /// The date the entry lands on. Defaults to today, never to the month being
  /// viewed: the ledger's selected month is a reading position, and filing an
  /// entry there because the user happened to be scrolled to it is how a log
  /// ends up on a day nobody chose.
  static DateTime _date(Map<String, Object?> input) {
    final given = _str(input['date']);
    final parsed = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(given)
        ? DateTime.tryParse(given)
        : null;
    final now = DateTime.now();
    return parsed == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _dateLabel(DateTime d) => DateFormat('MMM d, yyyy').format(d);

  /// Names for an error message. Capped so a user with fifty categories does
  /// not push the rest of the turn out of the model's window.
  static String _names(Iterable<String> raw) {
    final names = [for (final n in raw) '"$n"'];
    return names.length <= 20
        ? names.join(', ')
        : '${names.take(20).join(', ')} and ${names.length - 20} more';
  }

  String _month(Map<String, Object?> input) {
    final given = _str(input['month']);
    return RegExp(r'^\d{4}-\d{2}$').hasMatch(given)
        ? given
        : _bills.selectedMonth;
  }

  SetAsideType _setAsideType(Object? raw) =>
      setAsideTypeFromName(_str(raw).isEmpty ? null : _str(raw));

  static String _str(Object? v) => v is String ? v.trim() : '';

  static double _num(Object? v) =>
      v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

  static int _int(Object? v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 1 : 1);

  static String _peso(double v) => '₱${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}
