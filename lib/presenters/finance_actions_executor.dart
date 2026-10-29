import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/extracted_entry.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/installment.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../utils/credit_cycle.dart';
import '../utils/finance_entry_extraction.dart';
import '../utils/finance_flows.dart';
import '../utils/finance_format.dart';
import '../utils/model_date_guard.dart';
import 'bills_receivables_presenter.dart';
import 'budget_presenter.dart';
import 'finance_finder.dart';
import 'finance_tool_executor.dart';
import 'finance_view_reader.dart';
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
    FinanceViewReader? views,
  })  : _bills = bills,
        _budget = budget,
        _ledger = ledger,
        _installments = installments,
        _dashboard = dashboard,
        _views = views;

  final BillsReceivablesPresenter _bills;
  final BudgetPresenter? _budget;

  /// Owner of transactions. Nullable for the same reason [_budget] is: a build
  /// that cannot log must fail the call plainly rather than pretend.
  final LedgerPresenter? _ledger;
  final InstallmentPresenter? _installments;
  final TreasuryDashboardPresenter? _dashboard;

  /// Reads a whole screen's figures for `getView`. Nullable like the other
  /// owners: a build without every screen fails the call plainly.
  final FinanceViewReader? _views;

  PendingFinanceAction? _pending;
  Completer<AiToolResult>? _decision;

  /// The bound installment behind [_pending], when it is an `addInstallment`.
  /// The card is drawn from it and [confirm] writes it, so the account the
  /// user approved is the account that gets the plan.
  _InstallmentPlan? _pendingPlan;

  @override
  PendingFinanceAction? get pending => _pending;

  // ── Reads ─────────────────────────────────────────────────────────────────

  @override
  Future<AiToolResult> runRead(AiToolCall call) async {
    switch (call.name) {
      case 'find':
        return FinanceFinder(
          bills: _bills,
          budget: _budget,
          ledger: _ledger,
          installments: _installments,
          dashboard: _dashboard,
        ).find(call);

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

      case 'findTransactions':
        return _findTransactions(call);

      case 'getView':
        return _views?.run(call) ??
            AiToolResult.failed(call.id, 'Screens are not available here.');
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
            ? toMonthKey(now)
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

    // An installment purchase record carries the full principal but moves no
    // cash: the plan's monthly payments are the spending, and they are rows of
    // their own. Counting both would report the purchase twice, so it is left
    // out here exactly as every spending aggregation leaves it out
    // (isSpendingOutflow). It is still listed, labelled as what it is.
    //
    // The totals use the app's own rules (isSpendingOutflow, isIncomeInflow):
    // a reimbursable, a category marked "exclude from totals" and a loan
    // repayment are listed but not counted, exactly as every screen leaves
    // them out. Counting them made Nudgy's "Spent" larger than the app's.
    final excluded = excludedCashFlowCategoryIds(ledger.categories);
    final reimbursements = reimbursementReceivableIds(ledger.allTransactions);
    bool counted(TransactionRecord t) => t.type == TransactionType.outflow
        ? isSpendingOutflow(t, excluded)
        : isIncomeInflow(t, reimbursements, excluded);
    var spent = 0.0;
    var received = 0.0;
    var installmentPurchases = 0;
    var uncounted = 0;
    for (final t in matched) {
      if (isTransfer(t)) continue;
      if (t.isInstallment) {
        installmentPurchases++;
        continue;
      }
      if (!counted(t)) {
        uncounted++;
        continue;
      }
      if (t.type == TransactionType.outflow) spent += t.amount;
      if (t.type == TransactionType.inflow) received += t.amount;
    }

    final rows = matched.take(limit).map((t) {
      final account = accounts[t.accountId] ?? 'unknown account';
      final String flow;
      if (isTransfer(t)) {
        flow = 'transfer $account → '
            '${accounts[t.transferToAccountId] ?? 'unknown account'}';
      } else if (t.isInstallment) {
        final category = categories[t.categoryId] ?? 'Uncategorised';
        flow = 'installment purchase, not counted in Spent · $category · '
            '$account';
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
      final skipped = isTransfer(t) || t.isInstallment || counted(t)
          ? ''
          : ' [not counted]';
      return 'id=${t.id} ${_day(t.date)} "${t.description}" ${_peso(t.amount)} '
          '$flow$owed$skipped$note';
    }).toList();

    final purchasesNote = installmentPurchases == 0
        ? ''
        : '; $installmentPurchases installment '
            '${installmentPurchases == 1 ? 'purchase is' : 'purchases are'} '
            'listed but not counted, since a plan\'s monthly payments are the '
            'spending';
    final uncountedNote = uncounted == 0
        ? ''
        : '; $uncounted marked [not counted] — reimbursable, a loan '
            'repayment, or a category set to "exclude from totals" — are '
            'listed but left out, as the app leaves them out';
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
          '(transfers between the user\'s own accounts excluded from both'
          '$purchasesNote$uncountedNote). '
          '$shown\n${rows.join('\n')}',
    );
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
    // An installment is checked and bound before any card is shown: a plan
    // the user cannot sensibly confirm (no amount, no months, an account that
    // is not credit) is sent back to the model with the reason, instead of
    // being parked behind a card that would save something else.
    final problem = _proposalProblem(call);
    if (problem != null) {
      return Future.value(AiToolResult.failed(call.id, problem));
    }
    _InstallmentPlan? plan;
    if (call.name == 'addInstallment') {
      final resolved = _resolveInstallment(call.input);
      final error = resolved.error;
      if (error != null) {
        return Future.value(AiToolResult.failed(call.id, error));
      }
      plan = resolved.plan;
    }
    final action =
        plan != null ? _describeInstallment(call, plan) : _describe(call);
    if (action == null) {
      return Future.value(
          AiToolResult.failed(call.id, 'Unknown tool "${call.name}".'));
    }
    _pending = action;
    _pendingPlan = plan;
    _decision = Completer<AiToolResult>();
    notifyListeners();
    return _decision!.future;
  }

  /// The user said yes. [applyToFuture] comes from the card, never the model:
  /// it spreads the change across later months of the series, and no chat
  /// sentence reliably asks for that.
  @override
  Future<void> confirm(
      {bool applyToFuture = false, bool? alreadyLogged}) async {
    final action = _pending;
    final decision = _decision;
    if (action == null || decision == null) return;
    final plan = _pendingPlan;
    _pending = null;
    _pendingPlan = null;
    _decision = null;

    try {
      final summary = await _write(action,
          applyToFuture: applyToFuture,
          alreadyLogged:
              alreadyLogged ?? action.ledgerChoice?.alreadyLogged ?? false,
          plan: plan);
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
    _pendingPlan = null;
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
            // Every row below shows what is saved: the resolved name, not the
            // model's words. A name that does not resolve never reaches here
            // (_proposalProblem refuses it).
            if (_categoryFor(_str(i['category'])) case final c?)
              (label: 'Category', value: c.name),
            if (_accountFor(_str(i['account'])) case final a?)
              (label: 'Pay from', value: a.name),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
          ],
        );
      case 'addReceivable':
        final expected = _expectedDate(_month(i), i['expectedDay']);
        return PendingFinanceAction(
          call: call,
          title: 'Add receivable: $name, ${_peso(amount)}',
          isRecurring: recurring,
          details: [
            (label: 'Amount', value: _peso(amount)),
            (label: 'Month', value: _month(i)),
            if (expected != null) (label: 'Expected', value: _day(expected)),
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
            if (_accountFor(_str(i['destinationAccount'])) case final a?)
              (label: 'Into', value: a.name),
            (label: 'Month', value: _month(i)),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
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
            (
              label: 'Pay from',
              value: _liquidAccountFor(fromName)?.name ?? fromName,
            ),
            if (_str(i['date']).isNotEmpty)
              (label: 'Date', value: _str(i['date'])),
            if (_str(i['note']).isNotEmpty)
              (label: 'Note', value: _str(i['note'])),
          ],
        );
      case 'markBillPaid':
        final s = _billSettlement(i);
        if (s == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Mark bill paid: ${s.name} (${_peso(s.amount)})',
          isRecurring: false,
          confirmLabel: 'Mark Paid',
          ledgerChoice: s.choice,
          details: [
            (label: 'Bill', value: s.name),
            (label: 'Amount', value: _peso(s.amount)),
            if (s.account case final a?) (label: 'Paid from', value: a.name),
            (label: 'Paid date', value: _day(s.date)),
          ],
        );
      case 'markReceivableReceived':
        final s = _receivableSettlement(i);
        if (s == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Mark received: ${s.name} (${_peso(s.amount)})',
          isRecurring: false,
          confirmLabel: 'Mark Received',
          ledgerChoice: s.choice,
          details: [
            (label: 'Receivable', value: s.name),
            (label: 'Amount', value: _peso(s.amount)),
            if (s.account case final a?) (label: 'Deposit into', value: a.name),
            (label: 'Date received', value: _day(s.date)),
          ],
        );
      case 'editBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final billName = bill?.name ?? 'Bill';
        final newCategory = _categoryFor(_str(i['category']));
        return PendingFinanceAction(
          call: call,
          title: 'Update bill: $billName',
          isRecurring: bill?.isRecurring ?? false,
          confirmLabel: 'Update Bill',
          details: [
            if (_str(i['name']).isNotEmpty)
              (label: 'Name', value: '${bill?.name} → ${_str(i['name'])}'),
            if (_amountOrNull(i['amount']) case final amt?)
              (
                label: 'Amount',
                value: '${_peso(bill?.amount ?? 0)} → ${_peso(amt)}'
              ),
            if (i['dueDay'] != null)
              (
                label: 'Due day',
                value: '${bill?.dueDay} → ${_int(i['dueDay'])}'
              ),
            if (newCategory != null)
              (
                label: 'Category',
                value: '${_categoryName(bill?.categoryId)} → '
                    '${newCategory.name}'
              ),
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
        final expected =
            rec == null ? null : _expectedDate(rec.month, i['expectedDay']);
        return PendingFinanceAction(
          call: call,
          title: 'Update receivable: $recName',
          isRecurring: rec?.isRecurring ?? false,
          confirmLabel: 'Update Receivable',
          details: [
            if (_str(i['name']).isNotEmpty)
              (label: 'Name', value: '${rec?.name} → ${_str(i['name'])}'),
            if (_amountOrNull(i['amount']) case final amt?)
              (
                label: 'Amount',
                value: '${_peso(rec?.amount ?? 0)} → ${_peso(amt)}'
              ),
            if (expected != null)
              (
                label: 'Expected',
                value:
                    '${rec?.expectedDate == null ? "-" : _day(rec!.expectedDate!)}'
                        ' → ${_day(expected)}'
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
            if (_amountOrNull(i['amount']) case final amt?)
              (
                label: 'Amount',
                value: '${_peso(e?.allocatedAmount ?? 0)} → ${_peso(amt)}'
              ),
            if (_str(i['type']).isNotEmpty)
              (label: 'Type', value: _setAsideType(i['type']).name),
            if (_accountFor(_str(i['destinationAccount'])) case final a?)
              (label: 'Into', value: a.name),
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
            if (_amountOrNull(i['amount']) case final amt?)
              (
                label: 'Amount',
                value: '${_peso(t?.amount ?? 0)} → ${_peso(amt)}'
              ),
            if (_str(i['date']).isNotEmpty)
              (
                label: 'Date',
                value: '${t != null ? _day(t.date) : ""} → ${_str(i['date'])}'
              ),
            if (_categoryFor(_str(i['category'])) case final c?)
              (
                label: 'Category',
                value: '${_categoryName(t?.categoryId)} → ${c.name}'
              ),
            if (_accountFor(_str(i['account'])) case final a?)
              (
                label: 'Account',
                value: '${_accountName(t?.accountId)} → ${a.name}'
              ),
            if (_str(i['note']).isNotEmpty)
              (label: 'Note', value: _str(i['note'])),
          ],
        );
      case 'deleteTransaction':
        final id = _str(i['id']);
        final t = _ledger?.allTransactions.where((t) => t.id == id).firstOrNull;
        if (t == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Delete transaction: ${t.description} (${_peso(t.amount)})',
          isRecurring: false,
          confirmLabel: 'Delete Entry',
          isDestructive: true,
          details: [
            (label: 'Transaction', value: t.description),
            (label: 'Amount', value: _peso(t.amount)),
            (label: 'Date', value: _day(t.date)),
            ..._deleteCascade(t),
            (
              label: 'Warning',
              value: 'Permanently removes this and adjusts balances'
            ),
          ],
        );
    }
    return null;
  }

  // ── Installments ──────────────────────────────────────────────────────────

  /// Fewest payments a plan may have. One payment is an ordinary purchase,
  /// and a missing `months` must not quietly become one.
  static const int _minInstallmentMonths = 2;
  static const int _maxInstallmentMonths = 120;

  /// Highest monthly add-on rate accepted, in percent. BSP caps credit card
  /// finance charges at 3% a month; BNPL and credit lines can run a little
  /// higher, so the bound is generous. Anything above it is far more likely an
  /// annual rate or a typo than a real monthly one.
  static const double _maxMonthlyRate = 10;

  /// Checks an `addInstallment` call and binds it to the user's real accounts
  /// and categories. Returns the plan, or the reason it cannot be proposed —
  /// written for the model, which relays it or asks the user.
  ({_InstallmentPlan? plan, String? error}) _resolveInstallment(
      Map<String, Object?> i) {
    ({_InstallmentPlan? plan, String? error}) fail(String error) =>
        (plan: null, error: error);

    if (_ledger == null) return fail('Installments are not available here.');

    final name = _str(i['name']);
    if (name.isEmpty) {
      return fail('An installment needs a name, e.g. "iPhone 16". Ask the '
          'user what they bought.');
    }

    final amount = _numOrNull(i['amount']);
    if (amount == null || !amount.isFinite || amount <= 0) {
      return fail('The amount must be the total purchase price in pesos, '
          'above zero. Ask the user for it.');
    }

    final rawMonths = i['months'];
    final months = _numOrNull(rawMonths);
    if (months == null) {
      return fail('How many monthly payments is it? Ask the user rather than '
          'guessing — e.g. 3, 6, 12 or 24.');
    }
    if (months != months.roundToDouble()) {
      return fail('The number of months must be a whole number, not $months.');
    }
    if (months < _minInstallmentMonths) {
      return fail('An installment needs at least $_minInstallmentMonths '
          'monthly payments. A purchase paid in one go is an ordinary '
          'transaction — log it with logTransactions instead.');
    }
    if (months > _maxInstallmentMonths) {
      return fail('${months.toInt()} months is longer than any installment '
          'plan ($_maxInstallmentMonths at most). Check the term with the '
          'user.');
    }

    final rawRate = i['interestRate'];
    final double rate;
    if (rawRate == null || (rawRate is String && rawRate.trim().isEmpty)) {
      rate = 0;
    } else {
      final parsed = _numOrNull(rawRate);
      if (parsed == null || !parsed.isFinite) {
        return fail('The interest rate must be a number: the monthly add-on '
            'rate in percent, or 0 for a 0% plan.');
      }
      rate = parsed.toDouble();
    }
    if (rate < 0) {
      return fail('The interest rate cannot be negative. Use 0 for a 0% '
          'plan.');
    }
    if (rate > _maxMonthlyRate) {
      return fail('${_rateLabel(rate)} a month is not a plausible installment '
          'rate (BSP caps credit card finance charges at 3% a month). If the '
          'user quoted a yearly rate, divide it by 12; otherwise ask them to '
          'check it.');
    }

    final account = _creditAccountFor(_str(i['account']));
    final accountError = account.error;
    if (accountError != null) return fail(accountError);

    final rawDate = _str(i['date']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var date = today;
    String? dateNote;
    if (rawDate.isNotEmpty) {
      final given = DateTime.tryParse(rawDate);
      if (given == null) {
        return fail('The purchase date must be YYYY-MM-DD, not "$rawDate".');
      }
      // The same year-slip guard every other tool applies to a model date.
      final rebased = rebaseStaleDate(given, now);
      date = DateTime(rebased.year, rebased.month, rebased.day);
      if (date.isAfter(today)) {
        return fail('The purchase date $rawDate is in the future. Use the day '
            'it was bought, or leave the date out for today.');
      }
      if (date != DateTime(given.year, given.month, given.day)) {
        dateNote = 'moved from $rawDate';
      }
    }

    final note = _str(i['note']);
    return (
      plan: _InstallmentPlan(
        name: name,
        amount: amount.toDouble(),
        months: months.toInt(),
        rate: rate,
        account: account.account!,
        category: _categoryFor(_str(i['category'])),
        requestedCategory: _str(i['category']),
        date: date,
        dateNote: dateNote,
        note: note.isEmpty ? null : note,
      ),
      error: null,
    );
  }

  /// The credit account an installment goes on, resolved only among active
  /// credit cards, credit lines and BNPL accounts — a plan on anything else is
  /// never billed and holds no credit.
  ///
  /// An exact name wins, then a single account whose name contains the given
  /// one, then a single account whose name the given one contains ("BDO
  /// Credit Card" for "BDO"). No match, or more than one at the first tier
  /// that matches at all, is an error naming the choices: the user picks, the
  /// executor never does.
  ({FinancialAccount? account, String? error}) _creditAccountFor(String name) {
    final all = _ledger?.accounts ?? const <FinancialAccount>[];
    final credit = all.where((a) => a.isLiability && a.isActive).toList();
    if (credit.isEmpty) {
      return (
        account: null,
        error: 'The user has no credit card, credit line or BNPL account, so '
            'an installment has nowhere to go. Ask them to add one in '
            'Accounts first.',
      );
    }
    final choices = credit.map((a) => '"${a.name}"').join(', ');
    String ask(String why) => '$why Credit accounts: $choices. Ask the user '
        'which one it is on.';

    final q = name.trim().toLowerCase();
    if (q.isEmpty) {
      if (credit.length == 1) return (account: credit.single, error: null);
      return (account: null, error: ask('No account was given.'));
    }

    String norm(FinancialAccount a) => a.name.trim().toLowerCase();
    final tiers = <List<FinancialAccount>>[
      credit.where((a) => norm(a) == q).toList(),
      credit.where((a) => norm(a).contains(q)).toList(),
      credit.where((a) => norm(a).isNotEmpty && q.contains(norm(a))).toList(),
    ];
    for (final tier in tiers) {
      if (tier.length == 1) return (account: tier.single, error: null);
      if (tier.length > 1) {
        return (
          account: null,
          error: ask('"$name" matches more than one credit account.'),
        );
      }
    }

    final other = all
        .where((a) => !a.isLiability && (norm(a) == q || norm(a).contains(q)))
        .firstOrNull;
    if (other != null) {
      return (
        account: null,
        error: ask('"${other.name}" is not a credit account — an installment '
            'only goes on a credit card, credit line or BNPL account.'),
      );
    }
    return (
      account: null,
      error: ask('No credit account matches "$name".'),
    );
  }

  /// The confirm card for a bound installment. Every row shows what will be
  /// saved — the resolved account and category, the resolved date — never the
  /// model's raw words, so a wrong binding is visible before it is written.
  PendingFinanceAction _describeInstallment(
      AiToolCall call, _InstallmentPlan p) {
    final monthly = p.monthly;
    final totalPayable = monthly * p.months;
    final totalInterest = (totalPayable - p.amount).clamp(0.0, double.infinity);
    final category = p.category;
    return PendingFinanceAction(
      call: call,
      title: 'Add installment: ${p.name}, ${_peso(p.amount)} '
          '(${p.months} mo)',
      isRecurring: false,
      details: [
        (label: 'Account', value: p.account.name),
        (label: 'Total amount', value: _peso(p.amount)),
        (label: 'Duration', value: '${p.months} months'),
        (label: 'Monthly payment', value: _peso(monthly)),
        if (p.rate > 0) ...[
          (label: 'Interest rate', value: '${_rateLabel(p.rate)} / mo'),
          (label: 'Total interest', value: _peso(totalInterest)),
          (label: 'Total payable', value: _peso(totalPayable)),
        ],
        if (category != null)
          (label: 'Category', value: category.name)
        else if (p.requestedCategory.isNotEmpty)
          (
            label: 'Category',
            value: 'None — no category named "${p.requestedCategory}"',
          ),
        (
          label: 'Purchase date',
          value: p.dateNote == null
              ? _day(p.date)
              : '${_day(p.date)} (${p.dateNote})',
        ),
      ],
    );
  }

  static String _rateLabel(double rate) => rate == rate.roundToDouble()
      ? '${rate.round()}%'
      : '${rate.toStringAsFixed(2)}%';

  Future<String> _write(PendingFinanceAction action,
      {required bool applyToFuture,
      required bool alreadyLogged,
      _InstallmentPlan? plan}) async {
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
        final note = _str(i['note']);
        await _bills.quickPayCard(
          accountId: card.id,
          fromAccountId: from.id,
          amount: amount,
          date: date,
          note: note.isEmpty ? null : note,
        );
        return 'Paid ${_peso(amount)} on ${card.name} from ${from.name}.';

      case 'markBillPaid':
        final s = _billSettlement(i);
        if (s == null) throw StateError('Bill "${_str(i['id'])}" not found');
        final record = _recordsInLedger(s, alreadyLogged);
        await _bills.markBillPaid(
          s.id,
          paidAmount: s.amount,
          paidDate: s.date,
          accountId: record ? s.account!.id : null,
          recordInLedger: record,
        );
        return 'Marked bill "${s.name}" as paid (${_peso(s.amount)}'
            '${record ? ' from ${s.account!.name}' : ', already in the ledger, so no new entry'}).';

      case 'markReceivableReceived':
        final s = _receivableSettlement(i);
        if (s == null) {
          throw StateError('Receivable "${_str(i['id'])}" not found');
        }
        final record = _recordsInLedger(s, alreadyLogged);
        await _bills.markReceivableReceived(
          s.id,
          receivedAmount: s.amount,
          receivedDate: s.date,
          accountId: record ? s.account!.id : null,
          recordInLedger: record,
        );
        return 'Marked receivable "${s.name}" as received (${_peso(s.amount)}'
            '${record ? ' into ${s.account!.name}' : ', already in the ledger, so no new entry'}).';

      case 'editBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        if (bill == null) throw StateError('Bill "$id" not found');
        final updated = bill.copyWith(
          name: _str(i['name']).isNotEmpty ? _str(i['name']) : null,
          amount: _amountOrNull(i['amount']),
          dueDay: i['dueDay'] != null ? _int(i['dueDay']).clamp(1, 31) : null,
          // Null keeps the bill's category: an unknown name was refused before
          // the card, so it can never clear one here.
          categoryId: _categoryFor(_str(i['category']))?.id,
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
          amount: _amountOrNull(i['amount']),
          // In the receivable's own month, the one the card showed — not the
          // calendar month the user happens to be chatting in.
          expectedDate: _expectedDate(rec.month, i['expectedDay']),
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
          allocatedAmount: _amountOrNull(i['amount']),
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
        final newAmt = _amountOrNull(i['amount']);
        final newDateStr = _str(i['date']);
        final newDate =
            newDateStr.isNotEmpty ? DateTime.tryParse(newDateStr) : null;
        final newCategory = _categoryFor(_str(i['category']))?.id;
        final newAcc = _str(i['account']).isNotEmpty
            ? _accountFor(_str(i['account']))
            : null;
        final newNote = _str(i['note']);
        final updated = txn.copyWith(
          description: newDesc.isNotEmpty ? newDesc : null,
          amount: newAmt,
          date: newDate,
          month: newDate != null ? toMonthKey(newDate) : null,
          categoryId: newCategory,
          accountId: newAcc?.id,
          note: newNote.isNotEmpty ? newNote : null,
        );
        // The same path as the ledger grid's inline edit: an installment
        // purchase carries its plan along instead of drifting from it.
        if (!await ledger.updateRecordInline(updated)) {
          throw StateError('Edit refused for installment purchase "$id"');
        }
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
            accountId: _accountFor(_str(i['account']))?.id,
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
            expectedDate: _expectedDate(month, i['expectedDay']),
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
            destinationAccountId:
                _accountFor(_str(i['destinationAccount']))?.id,
            isRecurring: recurring,
            recurrenceType: recurring ? RecurrenceType.monthly : null,
          ),
          applyToFuture: applyToFuture,
        );
        return 'Set aside ${_peso(amount)} for "$name" in $month$scope.';

      case 'addInstallment':
        // Bound and checked at propose time; the card showed exactly this.
        final ledger = _ledger;
        final p = plan;
        if (ledger == null || p == null) {
          throw StateError('addInstallment confirmed without a bound plan');
        }
        final monthly = p.monthly;
        final inst = Installment(
          id: _id(),
          name: p.name,
          accountId: p.account.id,
          totalAmount: p.amount,
          monthlyAmount: double.parse(monthly.toStringAsFixed(2)),
          totalMonths: p.months,
          startMonth: calculateInstallmentStartMonth(
            p.account,
            p.date,
            deferralMonths: 0,
          ),
          purchaseDate: p.date,
          deferralMonths: 0,
          interestRate: p.rate,
          note: p.note,
          categoryId: p.category?.id,
          isActive: true,
        );
        // The same presenter call the ledger's add sheet makes. The presenter
        // writes the purchase record itself, so chat and form cannot drift.
        await ledger.addInstallmentPurchase(inst);
        return 'Added installment purchase "${p.name}" for '
            '${_peso(p.amount)} (${p.months} months at ${_peso(monthly)}/mo) '
            'on ${p.account.name}.';
    }
    throw StateError('no writer for ${call.name}');
  }

  // ── Settlements ───────────────────────────────────────────────────────────

  /// A `markBillPaid` call bound against the live bill and accounts. The card
  /// is drawn from it, and the write binds the call again the same way, so
  /// the account the card named is the account the payment comes from.
  _Settlement? _billSettlement(Map<String, Object?> i) {
    final bill =
        _bills.allBills.where((b) => b.id == _str(i['id'])).firstOrNull;
    if (bill == null) return null;
    final amount = _amountOrNull(i['paidAmount']) ?? bill.amount;
    final date = _settleDate(i['paidDate']);
    // The named account, else the bill's own "pay from" account. A liability
    // is never the default: a statement is paid FROM a bank or wallet, and
    // the presenter refuses one paid from the card it belongs to.
    final named = _str(i['account']);
    final from = named.isNotEmpty
        ? _accountFor(named)
        : _activeAccounts
            .where((a) => a.id == bill.accountId && !a.isLiability)
            .firstOrNull;
    final match = _ledgerMatch(
      type: TransactionType.outflow,
      amount: amount,
      months: {bill.month, toMonthKey(date)},
      name: bill.name,
    );
    return _Settlement(
      id: bill.id,
      name: bill.name,
      amount: amount,
      date: date,
      account: from,
      choice: LedgerEntryChoice(
        alreadyLogged: i['alreadyLogged'] == true || match != null,
        canRecord: from != null,
        match: match == null ? null : _matchLabel(match),
      ),
    );
  }

  /// The receivable twin of [_billSettlement].
  _Settlement? _receivableSettlement(Map<String, Object?> i) {
    final rec =
        _bills.allReceivables.where((r) => r.id == _str(i['id'])).firstOrNull;
    if (rec == null) return null;
    final amount = _amountOrNull(i['receivedAmount']) ?? rec.amount;
    final date = _settleDate(i['receivedDate']);
    final named = _str(i['account']);
    final into = named.isNotEmpty
        ? _accountFor(named)
        : _activeAccounts.where((a) => a.id == rec.accountId).firstOrNull;
    final match = _ledgerMatch(
      type: TransactionType.inflow,
      amount: amount,
      months: {rec.month, toMonthKey(date)},
      name: rec.name,
    );
    return _Settlement(
      id: rec.id,
      name: rec.name,
      amount: amount,
      date: date,
      account: into,
      choice: LedgerEntryChoice(
        alreadyLogged: i['alreadyLogged'] == true || match != null,
        canRecord: into != null,
        match: match == null ? null : _matchLabel(match),
      ),
    );
  }

  /// Whether a confirmed settlement writes a ledger entry. Recording needs an
  /// account; the card cannot offer it without one, so reaching here without
  /// one is a bug, not a choice.
  static bool _recordsInLedger(_Settlement s, bool alreadyLogged) {
    if (alreadyLogged) return false;
    if (s.account == null) {
      throw StateError('"${s.name}" has no account to record the money in');
    }
    return true;
  }

  /// A ledger entry that is probably this settlement, already logged by hand:
  /// same direction and amount, in the month due or the month settled, and
  /// not linked to another bill or receivable. One whose text names the item
  /// wins; otherwise only a single candidate counts — two lookalikes are not
  /// evidence of either.
  TransactionRecord? _ledgerMatch({
    required TransactionType type,
    required double amount,
    required Set<String> months,
    required String name,
  }) {
    final candidates = (_ledger?.allTransactions ?? const <TransactionRecord>[])
        .where((t) =>
            t.type == type &&
            months.contains(t.month) &&
            (t.amount - amount).abs() < 0.005 &&
            t.billId == null &&
            t.receivableId == null &&
            !t.isInstallment)
        .toList();
    if (candidates.isEmpty) return null;
    final word = name.trim().toLowerCase().split(RegExp(r'\s+')).first;
    if (word.length >= 3) {
      final named = candidates.where((t) =>
          '${t.description} ${t.note ?? ''}'.toLowerCase().contains(word));
      if (named.isNotEmpty) return named.first;
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  String _matchLabel(TransactionRecord t) =>
      '"${t.description}" ${_peso(t.amount)} on ${_day(t.date)}';

  /// A settlement date from the model, or today. A year the model slipped is
  /// rebased, as everywhere else a model date lands.
  static DateTime _settleDate(Object? raw) {
    final now = DateTime.now();
    final given = DateTime.tryParse(_str(raw));
    final d = given == null ? now : rebaseStaleDate(given, now);
    return DateTime(d.year, d.month, d.day);
  }

  // ── Delete warnings ───────────────────────────────────────────────────────

  /// What else goes when transaction [t] is deleted, named on the card:
  /// [LedgerPresenter.deleteTransactionOrGroup] takes a transfer's other leg
  /// and an installment purchase's plan and payments with it, and retires a
  /// reimbursable's "owed back" entry.
  List<({String label, String value})> _deleteCascade(TransactionRecord t) {
    final txns = _ledger?.allTransactions ?? const <TransactionRecord>[];
    final rows = <({String label, String value})>[];
    final group = t.transferGroupId;
    if (group != null) {
      final partner = txns
          .where((o) => o.transferGroupId == group && o.id != t.id)
          .firstOrNull;
      if (partner != null) {
        final direction =
            partner.type == TransactionType.inflow ? 'into' : 'out of';
        rows.add((
          label: 'Also deletes',
          value: 'the other side of this transfer: ${_peso(partner.amount)} '
              '$direction ${_accountName(partner.accountId)}',
        ));
      }
    }
    final planId = t.installmentId;
    if (t.isInstallment && planId != null) {
      final plan = _installments?.allInstallments
          .where((p) => p.id == planId)
          .firstOrNull;
      final payments =
          txns.where((o) => o.installmentId == planId && o.id != t.id).length;
      rows.add((
        label: 'Also deletes',
        value: 'the installment plan "${plan?.name ?? t.description}"'
            '${payments == 0 ? '' : ' and its $payments recorded '
                '${payments == 1 ? 'payment' : 'payments'}'}',
      ));
    }
    if (t.reimbursable && t.reimbursementReceivableId != null) {
      rows.add((
        label: 'Also deletes',
        value: 'the "owed back" receivable for this expense',
      ));
    }
    return rows;
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  /// The one account in [pool] that [name] names: an exact name, else a
  /// single account whose name contains it, else a single account whose name
  /// it contains ("BDO Card Visa" → "BDO Card"). Null when none or several
  /// match — never a guess. A wrong guess here pays the wrong card or moves a
  /// transaction to an account the user never mentioned.
  static FinancialAccount? _matchAccount(
      String name, Iterable<FinancialAccount> pool) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return null;
    String norm(FinancialAccount a) => a.name.trim().toLowerCase();
    final tiers = <List<FinancialAccount>>[
      pool.where((a) => norm(a) == q).toList(),
      pool.where((a) => norm(a).contains(q)).toList(),
      pool.where((a) => norm(a).isNotEmpty && q.contains(norm(a))).toList(),
    ];
    for (final tier in tiers) {
      if (tier.length == 1) return tier.single;
      if (tier.length > 1) return null;
    }
    return null;
  }

  List<FinancialAccount> get _activeAccounts =>
      (_ledger?.accounts ?? const <FinancialAccount>[])
          .where((a) => a.isActive)
          .toList();

  /// The active account [name] names, or null (see [_matchAccount]).
  FinancialAccount? _accountFor(String name) =>
      _matchAccount(name, _activeAccounts);

  /// The bank, e-wallet or cash account [name] names. With no name, the only
  /// such account when there is exactly one; otherwise null.
  FinancialAccount? _liquidAccountFor(String name) {
    final liquid = _activeAccounts.where((a) => a.isLiquid).toList();
    if (name.trim().isEmpty) return liquid.length == 1 ? liquid.single : null;
    return _matchAccount(name, liquid);
  }

  /// Why [call] cannot be shown as a card — an account it names does not
  /// resolve to exactly one of the user's accounts, or an edit would break a
  /// transfer pair or an installment purchase — or null when it can. Sent back
  /// to the model, which asks the user.
  String? _proposalProblem(AiToolCall call) {
    final i = call.input;
    String list(Iterable<FinancialAccount> pool) =>
        pool.map((a) => '"${a.name}"').join(', ');
    String? check(String field, Iterable<FinancialAccount> pool, String kind,
        {bool required = false}) {
      final name = _str(i[field]);
      if (name.isEmpty && !required) return null;
      final hit = kind == 'bank, e-wallet or cash'
          ? _liquidAccountFor(name)
          : _matchAccount(name, pool);
      if (hit != null) return null;
      final what = name.isEmpty
          ? 'No $kind account was given'
          : '"$name" does not match exactly one $kind account';
      return '$what. Choices: ${list(pool)}. Ask the user which one.';
    }

    final unknown = _unknownIdProblem(call);
    if (unknown != null) return unknown;

    final active = _activeAccounts;
    switch (call.name) {
      case 'addBill':
        return check('account', active, 'active') ?? _categoryProblem(i);
      case 'addSetAside':
        return check('destinationAccount', active, 'active');
      case 'payCredit':
        return check(
                'creditAccount', active.where((a) => a.isLiability), 'credit',
                required: true) ??
            check('fromAccount', active.where((a) => a.isLiquid),
                'bank, e-wallet or cash',
                required: true);
      case 'editTransaction':
        final txn = _ledger?.allTransactions
            .where((t) => t.id == _str(i['id']))
            .firstOrNull;
        if (txn?.transferGroupId != null &&
            (i['amount'] != null || _str(i['account']).isNotEmpty)) {
          return 'That record is one leg of a transfer; changing its amount or '
              'account here would break the pair. Ask the user to edit the '
              'transfer in the Ledger.';
        }
        if (txn != null &&
            txn.isInstallment &&
            _str(i['account']).isNotEmpty &&
            _accountFor(_str(i['account']))?.isLiability != true) {
          return 'That record is an installment purchase; it can only move to '
              'another credit account. Ask the user to change it in the Ledger.';
        }
        return check('account', active, 'active') ?? _categoryProblem(i);
      case 'markBillPaid':
        final bill = _bills.allBills.firstWhere((b) => b.id == _str(i['id']));
        if (bill.isPaid) {
          return 'The bill "${bill.name}" is already marked paid'
              '${bill.paidDate == null ? '' : ' on ${_day(bill.paidDate!)}'}. '
              'Nothing to change — tell the user.';
        }
        final named = _accountFor(_str(i['account']));
        if (named != null && named.isLiability && named.id == bill.accountId) {
          return '"${bill.name}" is the statement of ${named.name}, so it '
              'cannot be paid from ${named.name} itself. Ask the user which '
              'bank, e-wallet or cash account paid it.';
        }
        return check('account', active, 'active') ??
            _settlementProblem(_billSettlement(i)!, 'paid from', active);
      case 'markReceivableReceived':
        final rec =
            _bills.allReceivables.firstWhere((r) => r.id == _str(i['id']));
        if (rec.isReceived) {
          return 'The receivable "${rec.name}" is already marked received'
              '${rec.receivedDate == null ? '' : ' on ${_day(rec.receivedDate!)}'}. '
              'Nothing to change — tell the user.';
        }
        return check('account', active, 'active') ??
            _settlementProblem(
                _receivableSettlement(i)!, 'deposited into', active);
      case 'editBill':
        return _categoryProblem(i);
      case 'editReceivable':
        return check('account', active, 'active');
      case 'editSetAside':
        return check('destinationAccount', active, 'active');
    }
    return null;
  }

  /// Why an id-taking call names no real row, or null when it does.
  ///
  /// Refused before any card. A card for an id that matches nothing showed
  /// "Delete transaction: Transaction (₱0)", and approving it did nothing —
  /// the user approved a change that was never going to happen (design D2:
  /// an id only ever comes from a find result).
  String? _unknownIdProblem(AiToolCall call) {
    final id = _str(call.input['id']);
    final (String kind, String finder, bool exists) = switch (call.name) {
      'markBillPaid' || 'editBill' || 'deleteBill' => (
          'bill',
          'find (entity bill)',
          _bills.allBills.any((b) => b.id == id),
        ),
      'markReceivableReceived' || 'editReceivable' || 'deleteReceivable' => (
          'receivable',
          'find (entity receivable)',
          _bills.allReceivables.any((r) => r.id == id),
        ),
      'editSetAside' || 'deleteSetAside' => (
          'set-aside',
          'find (entity setAside)',
          _bills.allBudgetedExpenses.any((e) => e.id == id),
        ),
      'editTransaction' || 'deleteTransaction' => (
          'transaction',
          'findTransactions',
          _ledger?.allTransactions.any((t) => t.id == id) ?? false,
        ),
      _ => ('', '', true),
    };
    if (exists) return null;
    return 'No $kind has the id "$id". Call $finder and use an id from its '
        'result — never one you made up. If it is not there, tell the user '
        'you could not find it.';
  }

  /// Why a category NAME in the call matches no category, or null.
  ///
  /// Refused rather than saved as "no category": an edit that could not bind
  /// the name used to clear the row's category while the card still showed
  /// the typed name.
  String? _categoryProblem(Map<String, Object?> i) {
    final name = _str(i['category']);
    if (name.isEmpty || _categoryFor(name) != null) return null;
    final names = _categories.map((c) => '"${c.name}"').join(', ');
    return 'No category is named "$name". Categories: $names. Use one of '
        'these names, or leave the category out.';
  }

  /// Why settlement [s] cannot be shown: the user would have to record the
  /// money, and no account resolves to record it against.
  static String? _settlementProblem(
      _Settlement s, String verb, List<FinancialAccount> active) {
    if (s.choice.alreadyLogged || s.choice.canRecord) return null;
    final choices = active.map((a) => '"${a.name}"').join(', ');
    return 'Which account was "${s.name}" $verb? Choices: $choices. Ask the '
        'user. If they already logged this money in the Ledger, call again '
        'with alreadyLogged true instead.';
  }

  /// Every category the user has. The budget owns the list; a build without
  /// a budget presenter reads the ledger's copy.
  List<FinanceCategory> get _categories =>
      _budget?.allCategories ??
      _ledger?.categories ??
      const <FinanceCategory>[];

  String _categoryName(String? id) =>
      _categories.where((c) => c.id == id).firstOrNull?.name ?? 'none';

  String _accountName(String? id) =>
      (_ledger?.accounts ?? const <FinancialAccount>[])
          .where((a) => a.id == id)
          .firstOrNull
          ?.name ??
      'unknown account';

  /// Resolve a category NAME to its id. The model never sees ids, so it sends
  /// names and the client binds them — the same contract the expense extractor
  /// uses. An unresolved name leaves the category empty rather than guessing.
  String _categoryIdFor(String name) => _categoryFor(name)?.id ?? '';

  FinanceCategory? _categoryFor(String name) {
    if (name.isEmpty) return null;
    final lower = name.toLowerCase();
    final categories = _categories;
    for (final c in categories) {
      if (c.name.toLowerCase() == lower) return c;
    }
    for (final c in categories) {
      if (c.name.toLowerCase().startsWith(lower)) return c;
    }
    return null;
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

  /// A number, or null when absent or unreadable — unlike [_num] and [_int],
  /// which fall back to a value and so cannot tell "missing" from "zero".
  static num? _numOrNull(Object? v) =>
      v is num ? v : (v is String ? num.tryParse(v.trim()) : null);

  static int _int(Object? v) =>
      v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 1 : 1);

  /// A new amount from an edit, or null to keep the old one. Zero and below
  /// are not amounts, so they keep it too — on the card and in the write.
  static double? _amountOrNull(Object? v) {
    final n = _numOrNull(v);
    return n == null || !n.isFinite || n <= 0 ? null : n.toDouble();
  }

  /// The expected date for day [rawDay] of [monthKey] ("YYYY-MM"), clamped to
  /// the month's length; null when no day was given. Built in the row's own
  /// month, never the calendar month the chat happens in.
  static DateTime? _expectedDate(String monthKey, Object? rawDay) {
    if (rawDay == null) return null;
    final parts = monthKey.split('-');
    final year = int.tryParse(parts.first);
    final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (year == null || month == null) return null;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, _int(rawDay).clamp(1, last));
  }

  static String _peso(double v) => '₱${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}

/// A `markBillPaid` or `markReceivableReceived` call bound against the live
/// row and accounts. Both the card and the write are drawn from one.
class _Settlement {
  const _Settlement({
    required this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.account,
    required this.choice,
  });

  final String id;
  final String name;
  final double amount;
  final DateTime date;

  /// Where the money goes from or into. Null when none resolves; the card
  /// then offers "already in the ledger" only.
  final FinancialAccount? account;
  final LedgerEntryChoice choice;
}

/// An `addInstallment` call checked and bound against the user's real
/// accounts and categories at propose time. The confirm card is drawn from it
/// and the write saves it, so what the user approves is what is saved.
class _InstallmentPlan {
  const _InstallmentPlan({
    required this.name,
    required this.amount,
    required this.months,
    required this.rate,
    required this.account,
    required this.category,
    required this.requestedCategory,
    required this.date,
    required this.dateNote,
    required this.note,
  });

  final String name;
  final double amount;
  final int months;

  /// Monthly add-on rate, in percent.
  final double rate;

  /// Always an active credit card, credit line or BNPL account.
  final FinancialAccount account;

  /// Null when no category was given or none matched [requestedCategory].
  final FinanceCategory? category;
  final String requestedCategory;
  final DateTime date;

  /// Set when the model's date was moved (a slipped year), to say so.
  final String? dateNote;
  final String? note;

  double get monthly => Installment.computeMonthlyAmount(
        principal: amount,
        months: months,
        monthlyRate: rate,
      );
}
