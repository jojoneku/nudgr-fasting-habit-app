import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/receivable.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'finance_tool_executor.dart';

/// A change Nudgy proposed, waiting for the user to say yes or no.
///
/// Deliberately a plain description rather than a half-built entity: the card
/// renders these fields, and the entity is only constructed once the user has
/// confirmed. Nothing that could accidentally be persisted exists until then.
class PendingFinanceAction {
  const PendingFinanceAction({
    required this.call,
    required this.title,
    required this.details,
    required this.isRecurring,
  });

  final AiToolCall call;

  /// One line naming what will happen, e.g. "Set aside ₱3,000 for Braces".
  final String title;

  /// Label/value rows for the card body.
  final List<({String label, String value})> details;

  /// Whether the proposal repeats. Only a recurring action offers the
  /// future-months scope choice, because only a recurring one has a series to
  /// spread across.
  final bool isRecurring;
}

/// Runs Nudgy's finance tools against the presenters that own the data.
///
/// Assembled in `TreasuryPresenters` (CLAUDE.md #9), never in a shell, and it
/// writes only through the owning presenter's mutators (CLAUDE.md #8) — bills
/// owns set-asides and receivables, budget owns budgets.
///
/// A read runs immediately. A mutation does not: [propose] parks a
/// [PendingFinanceAction] and returns a future that only completes when the
/// user answers, so there is no code path from a model reply to a write.
class FinanceActionsExecutor extends ChangeNotifier
    implements FinanceToolExecutor {
  FinanceActionsExecutor({
    required BillsReceivablesPresenter bills,
    BudgetPresenter? budget,
  })  : _bills = bills,
        _budget = budget;

  final BillsReceivablesPresenter _bills;
  final BudgetPresenter? _budget;

  PendingFinanceAction? _pending;
  Completer<AiToolResult>? _decision;

  /// The change awaiting confirmation, or null when nothing is pending.
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
