import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/extracted_entry.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/installment.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../utils/credit_cycle.dart';
import '../utils/finance_entry_extraction.dart';
import '../utils/finance_format.dart';
import '../utils/model_date_guard.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'finance_tool_executor.dart';
import 'installment_presenter.dart';
import 'ledger_presenter.dart';
import 'treasury_dashboard_presenter.dart';

/// Runs Nudgy's finance tools against the presenters that own the data.
///
/// Assembled in `TreasuryPresenters` (CLAUDE.md #9), never in a shell, and it
/// writes only through the owning presenter's mutators (CLAUDE.md #8) — bills
/// owns set-asides and receivables, budget owns budgets.
///
/// A read runs immediately. A mutation does not: [propose] parks a
/// [PendingFinanceAction] and returns a future that only completes when the
/// user answers, so there is no code path from a model reply to a write.
///
/// `logTransactions` is the one mutation that does not park a
/// [PendingFinanceAction], because transactions already have a confirm
/// surface: the ledger's review card, where every gap is a picker. It hands
/// the rows there and returns immediately, and the card — not this class —
/// commits when the user taps Log.
class FinanceActionsExecutor extends ChangeNotifier
    implements FinanceToolExecutor, FinanceProposalHost {
  FinanceActionsExecutor({
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

  /// Owner of transactions. Nullable for the same reason [_budget] is: a build
  /// that cannot log must fail the call plainly rather than pretend.
  final LedgerPresenter? _ledger;
  final InstallmentPresenter? _installments;
  final TreasuryDashboardPresenter? _dashboard;

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

      case 'findInstallments':
        final installments = _installments;
        if (installments == null) {
          return AiToolResult.failed(
              call.id, 'Installments are not available here.');
        }
        final accountQuery = _str(call.input['account']).toLowerCase();
        final accounts = {
          for (final a in _ledger?.accounts ?? const <FinancialAccount>[])
            a.id: a.name
        };
        final txns = _ledger?.allTransactions ?? const <TransactionRecord>[];
        final rows = installments.allInstallments.where((inst) {
          if (!matches(inst.name)) return false;
          if (accountQuery.isNotEmpty) {
            final accName = (accounts[inst.accountId] ?? '').toLowerCase();
            if (!accName.contains(accountQuery)) return false;
          }
          return true;
        }).map((inst) {
          final accName = accounts[inst.accountId] ?? inst.accountId;
          final unbilled = inst.remainingAmount(txns);
          final paid = inst.paidCount(txns);
          final interest =
              inst.hasInterest ? ' (+${inst.interestRate}%/mo int)' : '';
          return 'id=${inst.id} "${inst.name}" on $accName: '
              '${_peso(inst.monthlyAmount)}/mo ($paid/${inst.totalMonths} paid)$interest, '
              'unbilled ${_peso(unbilled)}, original ${_peso(inst.totalAmount)}';
        });
        return _rows(call, rows, 'installments', month);

      case 'findAccounts':
        final ledger = _ledger;
        if (ledger == null) {
          return AiToolResult.failed(
              call.id, 'Accounts are not available here.');
        }
        final typeFilter = _str(call.input['type']).toLowerCase();
        final accounts = ledger.accounts.where((a) {
          if (!matches(a.name)) return false;
          if (typeFilter == 'liquid' && !a.isLiquid) return false;
          if (typeFilter == 'liability' && !a.isLiability) return false;
          if (typeFilter == 'savings' && !a.isSavingsPocket) return false;
          return true;
        }).map((a) {
          final balanceStr = _peso(a.balance);
          final String details;
          if (a.isLiability) {
            final limitStr = a.creditLimit != null
                ? ' (limit ${_peso(a.creditLimit!)}, available ${_peso(a.availableCredit ?? 0)})'
                : '';
            details = 'owed $balanceStr$limitStr [${a.category.name}]';
          } else {
            details = 'balance $balanceStr [${a.category.name}]';
          }
          return 'id=${a.id} "${a.name}" $details';
        });
        return _rows(call, accounts, 'accounts', 'active accounts');

      case 'checkAffordability':
        final dashboard = _dashboard;
        final amount = _num(call.input['amount']);
        if (amount <= 0) {
          return AiToolResult.failed(
              call.id, 'Amount must be greater than zero.');
        }
        if (dashboard == null) {
          return AiToolResult.failed(
              call.id, 'Affordability check is not available here.');
        }
        final accountName = _str(call.input['account']);
        FinancialAccount? targetAcc;
        if (accountName.isNotEmpty) {
          targetAcc = _accountFor(accountName);
        }
        final forecast = dashboard.forecastedNetBalance;
        final liquid = dashboard.totalLiquidCash;
        final spareAfter = forecast - amount;

        final String verdict;
        final String tier;
        if (targetAcc != null && amount > targetAcc.balance) {
          tier = 'no';
          verdict =
              'Not enough balance on ${targetAcc.name}: has ${_peso(targetAcc.balance)} vs ${_peso(amount)} needed.';
        } else if (amount > forecast) {
          tier = 'no';
          verdict =
              'No — exceeds your projected spare cash this month. After bills and planned savings, you only have ${_peso(forecast)} projected spare.';
        } else if (amount > forecast * 0.8) {
          tier = 'tight';
          verdict =
              'Tight — fits, but leaves only ${_peso(spareAfter)} projected spare cash for the rest of the month.';
        } else {
          tier = 'yes';
          verdict =
              'Yes — fits comfortably! You will still have about ${_peso(spareAfter)} spare cash projected after bills and savings.';
        }
        return AiToolResult(
          toolUseId: call.id,
          ok: true,
          summary:
              'Affordability check for ${_peso(amount)}: [$tier] $verdict (Current liquid cash: ${_peso(liquid)}, Projected spare: ${_peso(forecast)}).',
        );

      case 'findBudgetGroups':
        final budget = _budget;
        if (budget == null) {
          return AiToolResult.failed(
              call.id, 'Budgets are not available here.');
        }
        final groups = budget.groups;
        final rows = groups.map((g) {
          final allocated = budget.sectionAllocated(g.id);
          final spent = budget.sectionSpent(g.id);
          final remaining = allocated - spent;
          return '"${g.name}": allocated ${_peso(allocated)}, spent ${_peso(spent)}, remaining ${_peso(remaining)}';
        });
        return _rows(call, rows, 'budget groups', month);

      case 'findTransactions':
        return _findTransactions(call);
    }
    return AiToolResult.failed(call.id, 'Unknown read tool "${call.name}".');
  }

  /// Default and ceiling on rows returned by `findTransactions`. The totals
  /// always cover every match, so a capped list is never mistaken for the
  /// whole period.
  static const int _txnDefaultLimit = 50;
  static const int _txnMaxLimit = 150;

  /// The ledger, filtered on demand. No ids: nothing can edit or delete a
  /// transaction through Nudgy, so an id would only be something to misuse.
  ///
  /// A transfer is stored as two legs; only the outflow leg is listed, as
  /// "from → to", so moving money between accounts reads as one movement and
  /// is never counted as spending or income.
  AiToolResult _findTransactions(AiToolCall call) {
    final ledger = _ledger;
    if (ledger == null) {
      return AiToolResult.failed(
          call.id, 'Transactions are not available here.');
    }
    final i = call.input;
    final query = _str(i['query']).toLowerCase();
    final categoryQuery = _str(i['category']).toLowerCase();
    final accountQuery = _str(i['account']).toLowerCase();
    final type = _str(i['type']);
    var from = DateTime.tryParse(_str(i['from']));
    var to = DateTime.tryParse(_str(i['to']));
    var askedMonth = _str(i['month']);

    // A period that ends before the first transaction ever logged can only be
    // the model's year slipping ("2024-09" for this September), so rebase it
    // rather than report an empty month the user knows is full. A period that
    // overlaps real history is a genuine look back and is left alone.
    final now = DateTime.now();
    String? rebasedNote;
    final earliest = ledger.allTransactions.isEmpty
        ? null
        : ledger.allTransactions
            .map((t) => DateTime(t.date.year, t.date.month, t.date.day))
            .reduce((a, b) => a.isBefore(b) ? a : b);
    if (earliest != null) {
      final earliestMonth = _day(earliest).substring(0, 7);
      if (askedMonth.isNotEmpty && askedMonth.compareTo(earliestMonth) < 0) {
        final rebased = rebaseStaleMonthKey(askedMonth, now);
        if (rebased != askedMonth) {
          rebasedNote = 'Asked for $askedMonth, before the ledger begins; '
              'searched $rebased instead.';
          askedMonth = rebased;
        }
      }
      final end = to ?? from;
      if (end != null && end.isBefore(earliest)) {
        final f = from == null ? null : rebaseStaleDate(from, now);
        final t = to == null ? null : rebaseStaleDate(to, now);
        if (f != from || t != to) {
          rebasedNote = 'Asked for dates before the ledger begins; searched '
              '${f == null ? 'the start' : _day(f)} to '
              '${t == null ? 'today' : _day(t)} instead.';
          from = f;
          to = t;
        }
      }
    }

    // Final copies: the filter closure below cannot promote a captured var.
    final rangeFrom = from;
    final rangeTo = to;

    // A query with no dates means "find it wherever it is"; nothing at all
    // means "this month", the same default every other find tool uses.
    final month = askedMonth.isNotEmpty
        ? askedMonth
        : (query.isEmpty && rangeFrom == null && rangeTo == null)
            ? _bills.selectedMonth
            : null;
    // Not [_int]: that falls back to 1, and a missing limit means the default.
    final raw = i['limit'];
    final asked = raw is num ? raw.toInt() : int.tryParse(_str(raw));
    final limit = asked == null || asked <= 0
        ? _txnDefaultLimit
        : min(asked, _txnMaxLimit);

    final accounts = {for (final a in ledger.accounts) a.id: a.name};
    final categories = {for (final c in ledger.categories) c.id: c.name};

    bool isTransfer(TransactionRecord t) =>
        t.transferGroupId != null || t.type == TransactionType.transfer;

    final matched = ledger.allTransactions.where((t) {
      if (isTransfer(t) && t.type == TransactionType.inflow) return false;
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      if (rangeFrom != null || rangeTo != null) {
        if (rangeFrom != null && day.isBefore(rangeFrom)) return false;
        if (rangeTo != null && day.isAfter(rangeTo)) return false;
      } else if (month != null && t.month != month) {
        return false;
      }
      final kind = isTransfer(t) ? 'transfer' : t.type.name;
      if (type.isNotEmpty && kind != type) return false;
      final account = accounts[t.accountId] ?? '';
      final toAccount = accounts[t.transferToAccountId] ?? '';
      final category = categories[t.categoryId] ?? '';
      if (accountQuery.isNotEmpty &&
          !account.toLowerCase().contains(accountQuery) &&
          !toAccount.toLowerCase().contains(accountQuery)) {
        return false;
      }
      if (categoryQuery.isNotEmpty &&
          !category.toLowerCase().contains(categoryQuery)) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [
          t.description,
          t.note ?? '',
          category,
          account,
          toAccount,
          t.owedBy ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final scope = rangeFrom != null || rangeTo != null
        ? '${rangeFrom == null ? 'the start' : _day(rangeFrom)} to '
            '${rangeTo == null ? 'today' : _day(rangeTo)}'
        : month ?? 'all history';
    if (matched.isEmpty) {
      return AiToolResult(
        toolUseId: call.id,
        ok: true,
        summary: '${rebasedNote == null ? '' : '$rebasedNote '}'
            'No transactions matched in $scope. Do not invent any — say '
            'you could not find them, and offer a wider search.',
      );
    }

    var spent = 0.0;
    var received = 0.0;
    for (final t in matched) {
      if (isTransfer(t)) continue;
      if (t.type == TransactionType.outflow) spent += t.amount;
      if (t.type == TransactionType.inflow) received += t.amount;
    }

    final rows = matched.take(limit).map((t) {
      final account = accounts[t.accountId] ?? 'unknown account';
      final String flow;
      if (isTransfer(t)) {
        flow = 'transfer $account → '
            '${accounts[t.transferToAccountId] ?? 'unknown account'}';
      } else {
        final category = categories[t.categoryId] ?? 'Uncategorised';
        flow = '${t.type == TransactionType.inflow ? 'in' : 'out'} · '
            '$category · $account';
      }
      final owedBy = (t.owedBy ?? '').trim();
      final owed = !t.reimbursable
          ? ''
          : owedBy.isEmpty
              ? ' [reimbursable]'
              : ' [reimbursable, owed by $owedBy]';
      final note =
          (t.note ?? '').trim().isEmpty ? '' : ' — note: "${t.note!.trim()}"';
      return 'id=${t.id} ${_day(t.date)} "${t.description}" ${_peso(t.amount)} '
          '$flow$owed$note';
    }).toList();

    final shown = rows.length < matched.length
        ? 'Showing the newest ${rows.length} of ${matched.length}; narrow by '
            'month, dates or query to see the rest.'
        : 'All ${matched.length} shown.';
    return AiToolResult(
      toolUseId: call.id,
      ok: true,
      summary: '${rebasedNote == null ? '' : '$rebasedNote '}'
          '${matched.length} transactions in $scope. '
          'Spent ${_peso(spent)}, received ${_peso(received)} '
          '(transfers between the user\'s own accounts excluded from both). '
          '$shown\n${rows.join('\n')}',
    );
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
    // Transactions have their own confirm surface — the ledger's review card,
    // the same one the extractor fills — so they do not become a
    // [PendingFinanceAction]. Handing them to that card IS the proposal.
    if (call.name == 'logTransactions') {
      return Future.value(_handOffToLedger(call));
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

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Binds the model's entries against the user's real accounts and categories
  /// and puts them on the ledger's review card.
  ///
  /// Nothing is written here, and the result says so in as many words: the
  /// model is told the rows are waiting on a tap, because a summary that reads
  /// like a save is how the user ends up believing money was logged when it was
  /// not (advisor rule 8).
  ///
  /// The binding is the extractor's own, reused verbatim — an account or
  /// category name the model invented is dropped to a picker on the row rather
  /// than fabricated into an id, exactly as it is on the typed-message path.
  AiToolResult _handOffToLedger(AiToolCall call) {
    final ledger = _ledger;
    if (ledger == null) {
      return AiToolResult.failed(
          call.id, 'Logging transactions is not available here.');
    }
    if (!ledger.isSelectedDateToday) {
      return AiToolResult.failed(
          call.id,
          'The ledger is parked on a past day, so nothing can be logged. Ask '
          'the user to go back to today first.');
    }
    final raw = call.input['entries'];
    if (raw is! List || raw.isEmpty) {
      return AiToolResult.failed(
          call.id, 'No entries were given, so there is nothing to log.');
    }

    // parseFinanceExtractionResponse reads text, not maps: it is the extractor
    // response parser, and re-encoding here is what keeps ONE binder in the
    // app rather than a second, subtly different one for tool calls.
    final bound = parseFinanceExtractionResponse(
      text: jsonEncode({'entries': raw}),
      accounts: ledger.accounts,
      categories: ledger.categories,
      now: DateTime.now(),
    );
    final entries = bound?.entries ?? const <ExtractedEntry>[];
    if (entries.isEmpty) {
      return AiToolResult.failed(
          call.id,
          "I couldn't read those entries. Each one needs an amount and a "
          'description.');
    }

    ledger.presentEntriesForReview(entries);
    notifyListeners();

    final lines = <String>[];
    for (final e in entries) {
      final gaps = e.missing.map((f) => f.label.toLowerCase()).join(', ');
      // The date is echoed so the model reports the day the card actually
      // holds, not the one it asked for.
      lines.add('- ${e.txn.description.isEmpty ? "entry" : e.txn.description} '
          '${_peso(e.txn.amount ?? 0)}'
          '${e.txn.date == null ? ' (today)' : ' (${_day(e.txn.date!)})'}'
          '${gaps.isEmpty ? "" : " — still needs: $gaps"}');
    }
    final needsInput = entries.any((e) => e.missing.isNotEmpty);
    return AiToolResult(
      toolUseId: call.id,
      ok: true,
      summary: 'NOT SAVED YET. ${entries.length} '
          '${entries.length == 1 ? "entry is" : "entries are"} on the review '
          'card in front of the user:\n${lines.join('\n')}\n'
          '${needsInput ? "Tell them which chip to fill, then to tap Log." : "Tell them to tap Log to commit."} '
          'Do not repeat the list back and do not say anything was recorded.',
    );
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
      case 'addInstallment':
        final months = _int(i['months']).clamp(1, 120);
        final rate = _num(i['interestRate']);
        final monthly = Installment.computeMonthlyAmount(
          principal: amount,
          months: months,
          monthlyRate: rate,
        );
        final totalPayable = monthly * months;
        final totalInterest =
            (totalPayable - amount).clamp(0.0, double.infinity);
        final rateLabel = rate == rate.roundToDouble()
            ? '${rate.round()}%'
            : '${rate.toStringAsFixed(2)}%';
        return PendingFinanceAction(
          call: call,
          title: 'Add installment: $name, ${_peso(amount)} ($months mo)',
          isRecurring: false,
          details: [
            (label: 'Total amount', value: _peso(amount)),
            (label: 'Duration', value: '$months months'),
            (label: 'Monthly payment', value: _peso(monthly)),
            if (rate > 0) ...[
              (label: 'Interest rate', value: '$rateLabel / mo'),
              (label: 'Total interest', value: _peso(totalInterest)),
              (label: 'Total payable', value: _peso(totalPayable)),
            ],
            if (_str(i['account']).isNotEmpty)
              (label: 'Account', value: _str(i['account'])),
            if (_str(i['category']).isNotEmpty)
              (label: 'Category', value: _str(i['category'])),
            if (_str(i['date']).isNotEmpty)
              (label: 'Date', value: _str(i['date'])),
          ],
        );
      case 'payCredit':
        final cardName = _str(i['creditAccount']);
        final fromName = _str(i['fromAccount']);
        final card = _accountFor(cardName);
        final cardDisplay = card?.name ?? cardName;
        return PendingFinanceAction(
          call: call,
          title: 'Pay ${_peso(amount)} to $cardDisplay',
          isRecurring: false,
          confirmLabel: 'Confirm Payment',
          details: [
            (label: 'Payment to', value: cardDisplay),
            (label: 'Amount', value: _peso(amount)),
            if (fromName.isNotEmpty) (label: 'Pay from', value: fromName),
            if (_str(i['date']).isNotEmpty)
              (label: 'Date', value: _str(i['date'])),
            if (_str(i['note']).isNotEmpty)
              (label: 'Note', value: _str(i['note'])),
          ],
        );
      case 'markBillPaid':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final billName = bill?.name ?? 'Bill';
        final billAmt = _num(i['paidAmount']) > 0
            ? _num(i['paidAmount'])
            : (bill?.amount ?? 0);
        return PendingFinanceAction(
          call: call,
          title: 'Mark bill paid: $billName (${_peso(billAmt)})',
          isRecurring: false,
          confirmLabel: 'Mark Paid',
          details: [
            (label: 'Bill', value: billName),
            (label: 'Amount', value: _peso(billAmt)),
            if (_str(i['account']).isNotEmpty)
              (label: 'Paid from', value: _str(i['account'])),
            if (_str(i['paidDate']).isNotEmpty)
              (label: 'Paid date', value: _str(i['paidDate'])),
          ],
        );
      case 'markReceivableReceived':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        final recName = rec?.name ?? 'Receivable';
        final recAmt = _num(i['receivedAmount']) > 0
            ? _num(i['receivedAmount'])
            : (rec?.amount ?? 0);
        return PendingFinanceAction(
          call: call,
          title: 'Mark received: $recName (${_peso(recAmt)})',
          isRecurring: false,
          confirmLabel: 'Mark Received',
          details: [
            (label: 'Receivable', value: recName),
            (label: 'Amount', value: _peso(recAmt)),
            if (_str(i['account']).isNotEmpty)
              (label: 'Deposit into', value: _str(i['account'])),
            if (_str(i['receivedDate']).isNotEmpty)
              (label: 'Date received', value: _str(i['receivedDate'])),
          ],
        );
      case 'editBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final billName = bill?.name ?? 'Bill';
        return PendingFinanceAction(
          call: call,
          title: 'Update bill: $billName',
          isRecurring: bill?.isRecurring ?? false,
          confirmLabel: 'Update Bill',
          details: [
            if (_str(i['name']).isNotEmpty)
              (label: 'Name', value: '${bill?.name} → ${_str(i['name'])}'),
            if (i['amount'] != null)
              (
                label: 'Amount',
                value:
                    '${_peso(bill?.amount ?? 0)} → ${_peso(_num(i['amount']))}'
              ),
            if (i['dueDay'] != null)
              (
                label: 'Due day',
                value: '${bill?.dueDay} → ${_int(i['dueDay'])}'
              ),
            if (_str(i['category']).isNotEmpty)
              (label: 'Category', value: _str(i['category'])),
          ],
        );
      case 'deleteBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final billName = bill?.name ?? 'Bill';
        final billAmt = bill?.amount ?? 0;
        return PendingFinanceAction(
          call: call,
          title: 'Delete bill: $billName (${_peso(billAmt)})',
          isRecurring: bill?.isRecurring ?? false,
          confirmLabel: 'Delete Bill',
          isDestructive: true,
          details: [
            (label: 'Bill', value: billName),
            (label: 'Amount', value: _peso(billAmt)),
            if (bill != null) (label: 'Month', value: bill.month),
          ],
        );
      case 'editReceivable':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        final recName = rec?.name ?? 'Receivable';
        return PendingFinanceAction(
          call: call,
          title: 'Update receivable: $recName',
          isRecurring: rec?.isRecurring ?? false,
          confirmLabel: 'Update Receivable',
          details: [
            if (_str(i['name']).isNotEmpty)
              (label: 'Name', value: '${rec?.name} → ${_str(i['name'])}'),
            if (i['amount'] != null)
              (
                label: 'Amount',
                value:
                    '${_peso(rec?.amount ?? 0)} → ${_peso(_num(i['amount']))}'
              ),
            if (i['expectedDay'] != null)
              (
                label: 'Expected day',
                value:
                    '${rec?.expectedDate?.day ?? "-"} → ${_int(i['expectedDay'])}'
              ),
          ],
        );
      case 'deleteReceivable':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        final recName = rec?.name ?? 'Receivable';
        final recAmt = rec?.amount ?? 0;
        return PendingFinanceAction(
          call: call,
          title: 'Delete receivable: $recName (${_peso(recAmt)})',
          isRecurring: rec?.isRecurring ?? false,
          confirmLabel: 'Delete Receivable',
          isDestructive: true,
          details: [
            (label: 'Receivable', value: recName),
            (label: 'Amount', value: _peso(recAmt)),
            if (rec != null) (label: 'Month', value: rec.month),
          ],
        );
      case 'editSetAside':
        final id = _str(i['id']);
        final e =
            _bills.allBudgetedExpenses.where((e) => e.id == id).firstOrNull;
        final eName = e?.name ?? 'Set-aside';
        return PendingFinanceAction(
          call: call,
          title: 'Update set-aside: $eName',
          isRecurring: e?.isRecurring ?? false,
          confirmLabel: 'Update Set-Aside',
          details: [
            if (_str(i['name']).isNotEmpty)
              (label: 'Name', value: '${e?.name} → ${_str(i['name'])}'),
            if (i['amount'] != null)
              (
                label: 'Amount',
                value:
                    '${_peso(e?.allocatedAmount ?? 0)} → ${_peso(_num(i['amount']))}'
              ),
            if (_str(i['type']).isNotEmpty)
              (label: 'Type', value: _setAsideType(i['type']).name),
            if (_str(i['destinationAccount']).isNotEmpty)
              (label: 'Into', value: _str(i['destinationAccount'])),
          ],
        );
      case 'deleteSetAside':
        final id = _str(i['id']);
        final e =
            _bills.allBudgetedExpenses.where((e) => e.id == id).firstOrNull;
        final eName = e?.name ?? 'Set-aside';
        final eAmt = e?.allocatedAmount ?? 0;
        return PendingFinanceAction(
          call: call,
          title: 'Delete set-aside: $eName (${_peso(eAmt)})',
          isRecurring: e?.isRecurring ?? false,
          confirmLabel: 'Delete Set-Aside',
          isDestructive: true,
          details: [
            (label: 'Set-aside', value: eName),
            (label: 'Allocated', value: _peso(eAmt)),
            if (e != null) (label: 'Month', value: e.month),
          ],
        );
      case 'editTransaction':
        final id = _str(i['id']);
        final t = _ledger?.allTransactions.where((t) => t.id == id).firstOrNull;
        final tDesc = t?.description ?? 'Transaction';
        return PendingFinanceAction(
          call: call,
          title: 'Edit transaction: $tDesc',
          isRecurring: false,
          confirmLabel: 'Save Changes',
          details: [
            if (_str(i['description']).isNotEmpty)
              (
                label: 'Description',
                value: '${t?.description} → ${_str(i['description'])}'
              ),
            if (i['amount'] != null)
              (
                label: 'Amount',
                value: '${_peso(t?.amount ?? 0)} → ${_peso(_num(i['amount']))}'
              ),
            if (_str(i['date']).isNotEmpty)
              (
                label: 'Date',
                value: '${t != null ? _day(t.date) : ""} → ${_str(i['date'])}'
              ),
            if (_str(i['category']).isNotEmpty)
              (label: 'Category', value: _str(i['category'])),
            if (_str(i['account']).isNotEmpty)
              (label: 'Account', value: _str(i['account'])),
            if (_str(i['note']).isNotEmpty)
              (label: 'Note', value: _str(i['note'])),
          ],
        );
      case 'deleteTransaction':
        final id = _str(i['id']);
        final t = _ledger?.allTransactions.where((t) => t.id == id).firstOrNull;
        final tDesc = t?.description ?? 'Transaction';
        final tAmt = t?.amount ?? 0;
        return PendingFinanceAction(
          call: call,
          title: 'Delete transaction: $tDesc (${_peso(tAmt)})',
          isRecurring: false,
          confirmLabel: 'Delete Entry',
          isDestructive: true,
          details: [
            (label: 'Transaction', value: tDesc),
            (label: 'Amount', value: _peso(tAmt)),
            if (t != null) (label: 'Date', value: _day(t.date)),
            (
              label: 'Warning',
              value: 'Permanently removes this transaction and adjusts balances'
            ),
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
      case 'payCredit':
        final cardName = _str(i['creditAccount']);
        final card = _accountFor(cardName);
        if (card == null || !card.isLiability) {
          throw StateError('Could not find liability account "$cardName"');
        }
        final fromName = _str(i['fromAccount']);
        final from = _liquidAccountFor(fromName);
        if (from == null) {
          throw StateError('Could not find liquid funding account "$fromName"');
        }
        final dateStr = _str(i['date']);
        final date = (dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null) ??
            DateTime.now();
        await _bills.quickPayCard(
          accountId: card.id,
          fromAccountId: from.id,
          amount: amount,
          date: date,
        );
        return 'Paid ${_peso(amount)} on ${card.name} from ${from.name}.';

      case 'markBillPaid':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        if (bill == null) throw StateError('Bill "$id" not found');
        final paidAmt =
            _num(i['paidAmount']) > 0 ? _num(i['paidAmount']) : bill.amount;
        final dateStr = _str(i['paidDate']);
        final date = dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null;
        final acc = _str(i['account']).isNotEmpty
            ? _accountFor(_str(i['account']))
            : null;
        await _bills.markBillPaid(
          bill.id,
          paidAmount: paidAmt,
          paidDate: date,
          accountId: acc?.id,
        );
        return 'Marked bill "${bill.name}" as paid (${_peso(paidAmt)}).';

      case 'markReceivableReceived':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        if (rec == null) throw StateError('Receivable "$id" not found');
        final recAmt = _num(i['receivedAmount']) > 0
            ? _num(i['receivedAmount'])
            : rec.amount;
        final dateStr = _str(i['receivedDate']);
        final date = dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null;
        final acc = _str(i['account']).isNotEmpty
            ? _accountFor(_str(i['account']))
            : null;
        await _bills.markReceivableReceived(
          rec.id,
          receivedAmount: recAmt,
          receivedDate: date,
          accountId: acc?.id,
        );
        return 'Marked receivable "${rec.name}" as received (${_peso(recAmt)}).';

      case 'editBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        if (bill == null) throw StateError('Bill "$id" not found');
        final updated = bill.copyWith(
          name: _str(i['name']).isNotEmpty ? _str(i['name']) : null,
          amount: i['amount'] != null ? _num(i['amount']) : null,
          dueDay: i['dueDay'] != null ? _int(i['dueDay']).clamp(1, 31) : null,
          categoryId: _str(i['category']).isNotEmpty
              ? _categoryIdFor(_str(i['category']))
              : null,
        );
        await _bills.updateBill(updated, applyToFuture: applyToFuture);
        return 'Updated bill "${updated.name}" ($month$scope).';

      case 'deleteBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        await _bills.deleteBill(id, applyToFuture: applyToFuture);
        return 'Deleted bill "${bill?.name ?? id}"$scope.';

      case 'editReceivable':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        if (rec == null) throw StateError('Receivable "$id" not found');
        final updated = rec.copyWith(
          name: _str(i['name']).isNotEmpty ? _str(i['name']) : null,
          expectedDate: i['expectedDay'] != null
              ? DateTime(DateTime.now().year, DateTime.now().month,
                  _int(i['expectedDay']).clamp(1, 31))
              : null,
        );
        await _bills.updateReceivable(updated, applyToFuture: applyToFuture);
        return 'Updated receivable "${updated.name}"$scope.';

      case 'deleteReceivable':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        await _bills.deleteReceivable(id, applyToFuture: applyToFuture);
        return 'Deleted receivable "${rec?.name ?? id}"$scope.';

      case 'editSetAside':
        final id = _str(i['id']);
        final e =
            _bills.allBudgetedExpenses.where((e) => e.id == id).firstOrNull;
        if (e == null) throw StateError('Set-aside "$id" not found');
        final destAcc = _str(i['destinationAccount']).isNotEmpty
            ? _accountFor(_str(i['destinationAccount']))
            : null;
        final updated = e.copyWith(
          name: _str(i['name']).isNotEmpty ? _str(i['name']) : null,
          allocatedAmount: i['amount'] != null ? _num(i['amount']) : null,
          budgetedType:
              _str(i['type']).isNotEmpty ? _setAsideType(i['type']) : null,
          destinationAccountId: destAcc?.id,
        );
        await _bills.updateBudgetedExpense(updated,
            applyToFuture: applyToFuture);
        return 'Updated set-aside "${updated.name}"$scope.';

      case 'deleteSetAside':
        final id = _str(i['id']);
        final e =
            _bills.allBudgetedExpenses.where((e) => e.id == id).firstOrNull;
        await _bills.deleteBudgetedExpense(id, applyToFuture: applyToFuture);
        return 'Deleted set-aside "${e?.name ?? id}"$scope.';

      case 'editTransaction':
        final ledger = _ledger;
        if (ledger == null) throw StateError('Ledger is not available');
        final id = _str(i['id']);
        final txn = ledger.allTransactions.where((t) => t.id == id).firstOrNull;
        if (txn == null) throw StateError('Transaction "$id" not found');
        final newDesc = _str(i['description']);
        final newAmt = i['amount'] != null ? _num(i['amount']) : null;
        final newDateStr = _str(i['date']);
        final newDate =
            newDateStr.isNotEmpty ? DateTime.tryParse(newDateStr) : null;
        final newCategory = _str(i['category']).isNotEmpty
            ? _categoryIdFor(_str(i['category']))
            : null;
        final newAcc = _str(i['account']).isNotEmpty
            ? _accountFor(_str(i['account']))
            : null;
        final newNote = _str(i['note']);
        final updated = txn.copyWith(
          description: newDesc.isNotEmpty ? newDesc : null,
          amount: newAmt != null && newAmt > 0 ? newAmt : null,
          date: newDate,
          month: newDate != null ? toMonthKey(newDate) : null,
          categoryId: newCategory,
          accountId: newAcc?.id,
          note: newNote.isNotEmpty ? newNote : null,
        );
        await ledger.updateTransaction(updated);
        return 'Updated transaction "${updated.description}" (${_peso(updated.amount)}).';

      case 'deleteTransaction':
        final ledger = _ledger;
        if (ledger == null) throw StateError('Ledger is not available');
        final id = _str(i['id']);
        final txn = ledger.allTransactions.where((t) => t.id == id).firstOrNull;
        await ledger.deleteTransactionOrGroup(id);
        return 'Deleted transaction "${txn?.description ?? id}".';
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

      case 'addInstallment':
        final ledger = _ledger;
        if (ledger == null) {
          throw StateError(
              'Ledger is not available to log installment purchase');
        }
        final months = _int(i['months']).clamp(1, 120);
        final rate = _num(i['interestRate']);
        final accountName = _str(i['account']);
        final acc = _accountFor(accountName);
        if (acc == null) {
          throw StateError('Could not find account "$accountName"');
        }
        final categoryName = _str(i['category']);
        final categoryId = _categoryIdFor(categoryName);
        final dateStr = _str(i['date']);
        final date = (dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null) ??
            DateTime.now();
        final startMonth = calculateInstallmentStartMonth(
          acc,
          date,
          deferralMonths: 0,
        );
        final monthly = Installment.computeMonthlyAmount(
          principal: amount,
          months: months,
          monthlyRate: rate,
        );
        final inst = Installment(
          id: _id(),
          name: name,
          accountId: acc.id,
          totalAmount: amount,
          monthlyAmount: double.parse(monthly.toStringAsFixed(2)),
          totalMonths: months,
          startMonth: startMonth,
          purchaseDate: date,
          deferralMonths: 0,
          interestRate: rate,
          note: _str(i['note']).isEmpty ? null : _str(i['note']),
          categoryId: categoryId.isEmpty ? null : categoryId,
          isActive: true,
        );
        final txn = TransactionRecord(
          id: _id(),
          date: date,
          accountId: acc.id,
          categoryId: categoryId,
          amount: amount,
          type: TransactionType.outflow,
          description: name,
          note: _str(i['note']).isEmpty ? null : _str(i['note']),
          month: toMonthKey(date),
          installmentId: inst.id,
          isInstallment: true,
        );
        await ledger.addInstallmentPurchase(inst, transaction: txn);
        return 'Added installment purchase "$name" for ${_peso(amount)} ($months months at ${_peso(monthly)}/mo) on ${acc.name}.';
    }
    throw StateError('no writer for ${call.name}');
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  /// Resolve an account NAME or partial name to a FinancialAccount.
  /// Falls back to the first liability account if not matched or empty.
  FinancialAccount? _accountFor(String name) {
    final accounts = _ledger?.accounts ?? const [];
    if (accounts.isEmpty) return null;
    if (name.isEmpty) {
      return accounts.where((a) => a.isLiability).firstOrNull ??
          accounts.firstOrNull;
    }
    final lower = name.toLowerCase();
    for (final a in accounts) {
      if (a.name.toLowerCase() == lower) return a;
    }
    for (final a in accounts) {
      if (a.name.toLowerCase().contains(lower)) return a;
    }
    return accounts.where((a) => a.isLiability).firstOrNull ??
        accounts.firstOrNull;
  }

  /// Resolve a liquid funding account (bank, e-wallet, cash).
  FinancialAccount? _liquidAccountFor(String name) {
    final accounts = _ledger?.accounts ?? const [];
    if (accounts.isEmpty) return null;
    if (name.isNotEmpty) {
      final lower = name.toLowerCase();
      for (final a in accounts) {
        if (a.isLiquid && a.name.toLowerCase() == lower) return a;
      }
      for (final a in accounts) {
        if (a.isLiquid && a.name.toLowerCase().contains(lower)) return a;
      }
    }
    return accounts.where((a) => a.isLiquid).firstOrNull;
  }

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

  /// The month a proposal lands in. A year the model slipped back to its own
  /// training year ("2024-09" for this September) is rebased, or the bill
  /// would be created in a month nobody will ever scroll back to.
  String _month(Map<String, Object?> input) {
    final given = _str(input['month']);
    return RegExp(r'^\d{4}-\d{2}$').hasMatch(given)
        ? rebaseStaleMonthKey(given, DateTime.now())
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
