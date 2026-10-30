import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budget.dart';
import '../models/finance/budget_group_def.dart';
import '../models/finance/budgeted_expense.dart';
import '../models/finance/extracted_entry.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/installment.dart';
import '../models/finance/receivable.dart';
import '../models/finance/transaction_record.dart';
import '../utils/category_colors.dart';
import '../utils/category_icon_catalog.dart';
import '../utils/credit_cycle.dart';
import '../utils/finance_entry_extraction.dart';
import '../utils/finance_flows.dart';
import '../utils/finance_format.dart';
import '../utils/finance_query.dart';
import '../utils/finance_tool_catalogue.dart';
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
/// A read runs immediately. A mutation does not: [proposeBatch] parks every
/// write of one model step as one [PendingBatch] and returns a future that
/// only completes when the user answers, so there is no code path from a
/// model reply to a write (Plan 065 phase 4: one list, Approve all).
///
/// `logTransactions` joins the batch through the ledger's own review rows,
/// where every gap is a picker: its rows show in the same list, and Approve
/// all commits them through the ledger. Its result, like every other, says
/// what was actually saved.
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

  PendingBatch? _batch;
  int _batchSeq = 0;

  /// One completer per open call of [_batch], keyed by tool call id. A call
  /// leaves this map the moment it is answered.
  final Map<String, Completer<AiToolResult>> _open = {};

  /// The bound installment behind an `addInstallment` row, by call id. The
  /// row is drawn from it and the write saves it, so the account the user
  /// approved is the account that gets the plan.
  final Map<String, _InstallmentPlan> _plans = {};

  /// The `logTransactions` call whose rows wait on the ledger's review card,
  /// or null.
  String? _ledgerCallId;

  /// Categories that an `addCategory` row EARLIER in the batch adds, by
  /// lower-case name. Set only while rows are built or written, so a later
  /// row of the same batch may name one (resolved in call order: its
  /// category is saved first); empty at every other time.
  Map<String, String> _newCategories = const {};

  /// True while [approveAll] commits the ledger rows, so the ledger emptying
  /// its card is not mistaken for the user removing them.
  bool _approving = false;

  @override
  PendingBatch? get batch => _batch;

  @override
  PendingFinanceAction? get pending => _batch?.actions.firstOrNull;

  @override
  bool get batchHasLedgerRows => _batch != null && _ledgerCallId != null;

  @override
  int get openRowCount =>
      (_batch?.actions.length ?? 0) +
      (batchHasLedgerRows ? _ledger?.chatState.entries.length ?? 0 : 0);

  @override
  bool get canApproveAll =>
      !batchHasLedgerRows || (_ledger?.chatState.isReadyToCommit ?? false);

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

      case 'queryFinance':
        return _queryFinance(call);
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

  /// A sum or group-by over the ledger, computed by [runFinanceQuery] with the
  /// screens' own rules. This only reads the inputs and words the result: the
  /// range, the months covered and the metric's definition are always said,
  /// so the model never has to work out a figure or guess what one means.
  AiToolResult _queryFinance(AiToolCall call) {
    final ledger = _ledger;
    if (ledger == null) {
      return AiToolResult.failed(
          call.id, 'Transactions are not available here.');
    }
    final i = call.input;
    final metric = FinanceMetric.values
        .where((m) => m.name == _str(i['metric']))
        .firstOrNull;
    if (metric == null) {
      return AiToolResult.failed(call.id,
          'metric must be one of spend, income, net, count, setAside.');
    }
    final groupByRaw = _str(i['groupBy']);
    final groupBy = groupByRaw.isEmpty
        ? FinanceGroupBy.none
        : FinanceGroupBy.values.where((g) => g.name == groupByRaw).firstOrNull;
    if (groupBy == null) {
      return AiToolResult.failed(call.id,
          'groupBy must be one of none, category, account, month, description.');
    }
    DateTime? date(String key) {
      final raw = _str(i[key]);
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    for (final key in ['from', 'to']) {
      if (_str(i[key]).isNotEmpty && date(key) == null) {
        return AiToolResult.failed(call.id, '$key must be YYYY-MM-DD.');
      }
    }
    final rawTop = _numOrNull(i['top']);
    final rawAverage = i['average'];
    final now = DateTime.now();

    final result = runFinanceQuery(
      FinanceQuery(
        metric: metric,
        groupBy: groupBy,
        category: _str(i['category']),
        account: _str(i['account']),
        query: _str(i['query']),
        type: _str(i['type']),
        from: date('from'),
        to: date('to'),
        month: _str(i['month']),
        top: rawTop == null || rawTop <= 0 ? 10 : rawTop.toInt(),
        average: rawAverage == true || _str(rawAverage) == 'true',
      ),
      transactions: ledger.allTransactions,
      accounts: ledger.accounts,
      categories: ledger.categories,
      today: now,
    );
    final error = result.error;
    if (error != null) return AiToolResult.failed(call.id, error);
    return AiToolResult(
      toolUseId: call.id,
      ok: true,
      summary: describeFinanceQuery(result, now),
    );
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Proposals ─────────────────────────────────────────────────────────────

  @override
  Future<AiToolResult> propose(AiToolCall call) async =>
      (await proposeBatch([call])).single;

  @override
  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls) async {
    // A second batch while one is open would strand the first one's futures.
    // Refuse rather than silently dropping it.
    if (_batch != null) {
      return [
        for (final c in calls)
          AiToolResult.failed(
              c.id, 'Another set of changes is still waiting to be confirmed.'),
      ];
    }
    final immediate = <String, AiToolResult>{};
    final actions = <PendingFinanceAction>[];
    String? ledgerCall;
    final proposed = {
      for (final c in calls)
        if (c.name == 'addCategory') _str(c.input['name']).toLowerCase(),
    };
    _newCategories = {};
    try {
      for (final call in calls) {
        if (call.name == 'logTransactions') {
          if (ledgerCall != null) {
            immediate[call.id] = AiToolResult.failed(call.id,
                'Put every entry in one logTransactions call, not several.');
            continue;
          }
          final handed = _handOffToLedger(call, proposed);
          if (!handed.ok) {
            immediate[call.id] = handed;
            continue;
          }
          ledgerCall = call.id;
          continue;
        }
        // Checked and bound before any row is shown: a change the user
        // cannot sensibly confirm is sent back to the model with the reason,
        // instead of being parked behind a row that would save something
        // else.
        final built = _build(_withoutCardControls(call));
        final error = built.error;
        if (error != null) {
          immediate[call.id] = AiToolResult.failed(call.id, error);
          continue;
        }
        actions.add(built.action!);
        if (call.name == 'addCategory') {
          final name = _str(call.input['name']);
          _newCategories = {..._newCategories, name.toLowerCase(): name};
        }
      }
    } finally {
      _newCategories = const {};
    }
    if (actions.isEmpty && ledgerCall == null) {
      return [for (final c in calls) immediate[c.id]!];
    }

    final waiting = <String, Future<AiToolResult>>{};
    for (final a in actions) {
      final c = Completer<AiToolResult>();
      _open[a.call.id] = c;
      waiting[a.call.id] = c.future;
    }
    if (ledgerCall != null) {
      final c = Completer<AiToolResult>();
      _open[ledgerCall] = c;
      waiting[ledgerCall] = c.future;
      _ledgerCallId = ledgerCall;
      _ledger?.addListener(_onLedgerChanged);
    }
    _batch = PendingBatch(id: 'batch_${++_batchSeq}', actions: actions);
    notifyListeners();

    final answered = <String, AiToolResult>{};
    for (final e in waiting.entries) {
      answered[e.key] = await e.value;
    }
    return [for (final c in calls) immediate[c.id] ?? answered[c.id]!];
  }

  /// The single-proposal answer, kept for a batch of one.
  @override
  Future<void> confirm({bool applyToFuture = false, bool? alreadyLogged}) {
    final ids = [for (final a in _batch?.actions ?? const []) a.call.id];
    return approveAll(
      applyToFuture: {for (final id in ids) id: applyToFuture},
      alreadyLogged: {
        if (alreadyLogged != null)
          for (final id in ids) id: alreadyLogged,
      },
    );
  }

  /// The user said yes to every row still open. Scope and "already in the
  /// ledger" come from the card, per row, never from the model: they spread a
  /// change across later months or skip a ledger entry, and no chat sentence
  /// reliably asks for either.
  @override
  Future<void> approveAll({
    Map<String, bool> applyToFuture = const {},
    Map<String, bool> alreadyLogged = const {},
  }) async {
    final batch = _batch;
    if (batch == null) return;
    // The rows leave the screen at once; each result follows its write.
    _batch = PendingBatch(id: batch.id, actions: const []);
    notifyListeners();

    // Written in call order, so a category is saved before a later row that
    // names it. Should its save fail, that name binds to nothing and the
    // later row fails too, rather than saving some other category.
    _newCategories = _addedCategoriesIn(batch.actions);
    try {
      for (final action in batch.actions) {
        final id = action.call.id;
        try {
          final summary = await _write(
            action,
            applyToFuture: applyToFuture[id] ?? false,
            alreadyLogged: alreadyLogged[id] ??
                action.ledgerChoice?.alreadyLogged ??
                false,
            plan: _plans[id],
          );
          _answer(id, AiToolResult(toolUseId: id, ok: true, summary: summary));
        } catch (e) {
          debugPrint('FinanceActionsExecutor write failed: $e');
          _answer(
              id,
              AiToolResult.failed(
                  id, 'Saving that failed, so nothing was changed.'));
        }
      }
    } finally {
      _newCategories = const {};
    }
    final ledgerCall = _ledgerCallId;
    if (ledgerCall != null) {
      _answer(ledgerCall, await _commitLedgerRows(ledgerCall));
    }
    notifyListeners();
  }

  /// The user said no to everything still open. Reported as a decline, never
  /// as a quiet success.
  @override
  void decline() => _answerAll((id) => AiToolResult.declined(id));

  @override
  void reviseAll(String userText) => _answerAll((id) => AiToolResult(
        toolUseId: id,
        ok: false,
        summary: 'Not approved, and nothing was saved. Instead of answering '
            'the card, the user wrote: "$userText". Read it and, if they '
            'still want changes, propose the whole new set in one step.',
      ));

  @override
  void removeAction(String callId) {
    final batch = _batch;
    final removed =
        batch?.actions.where((a) => a.call.id == callId).firstOrNull;
    if (batch == null || removed == null) return;
    // A row that names the category this row adds goes with it: left alone,
    // it would save without the category its row showed.
    final added = removed.call.name == 'addCategory'
        ? _str(removed.call.input['name'])
        : '';
    final dependents = [
      for (final a in batch.actions)
        if (added.isNotEmpty &&
            _str(a.call.input['category']).toLowerCase() == added.toLowerCase())
          a.call.id,
    ];
    _batch = PendingBatch(
      id: batch.id,
      actions: [
        for (final a in batch.actions)
          if (a.call.id != callId && !dependents.contains(a.call.id)) a
      ],
    );
    _answer(
        callId,
        AiToolResult(
          toolUseId: callId,
          ok: false,
          summary: 'The user removed this change from the list, so it was '
              'not saved.',
        ));
    for (final id in dependents) {
      _answer(
          id,
          AiToolResult(
            toolUseId: id,
            ok: false,
            summary: 'Not saved: it used the new category "$added", which the '
                'user removed from the list.',
          ));
    }
    notifyListeners();
  }

  @override
  String? editAction(String callId, Map<String, Object?> patch) {
    final batch = _batch;
    final index = batch?.actions.indexWhere((a) => a.call.id == callId) ?? -1;
    if (batch == null || index < 0) return 'That change is no longer open.';
    final old = batch.actions[index].call;
    final edited = AiToolCall(
      id: old.id,
      name: old.name,
      input: {...old.input, ...patch},
    );
    _newCategories = _addedCategoriesIn(batch.actions.take(index));
    final ({PendingFinanceAction? action, String? error}) built;
    try {
      built = _build(edited);
    } finally {
      _newCategories = const {};
    }
    final error = built.error;
    if (error != null) return error;
    _batch = PendingBatch(
      id: batch.id,
      actions: [...batch.actions]..[index] = built.action!,
    );
    notifyListeners();
    return null;
  }

  /// Answers every open call with [result] and closes the batch.
  void _answerAll(AiToolResult Function(String id) result) {
    if (_batch == null) return;
    final ledgerCall = _ledgerCallId;
    for (final id in [..._open.keys]) {
      _answer(id, result(id));
    }
    if (ledgerCall != null) _ledger?.cancelChat();
    notifyListeners();
  }

  /// Completes call [id] with [result] and drops it from the batch. The batch
  /// closes when its last call is answered.
  void _answer(String id, AiToolResult result) {
    final c = _open.remove(id);
    if (c == null) return;
    _plans.remove(id);
    if (id == _ledgerCallId) {
      _ledger?.removeListener(_onLedgerChanged);
      _ledgerCallId = null;
    }
    c.complete(result);
    final batch = _batch;
    if (batch != null) {
      _batch = PendingBatch(
        id: batch.id,
        actions: [
          for (final a in batch.actions)
            if (a.call.id != id) a
        ],
      );
    }
    if (_open.isEmpty) _batch = null;
  }

  /// The user emptied the ledger rows (Remove on each, or Cancel) while the
  /// batch was open: that call is reported as not saved.
  void _onLedgerChanged() {
    final id = _ledgerCallId;
    final ledger = _ledger;
    if (id == null || ledger == null || _approving) return;
    final state = ledger.chatState;
    if (state.phase == ChatPhase.reviewing && state.entries.isNotEmpty) return;
    _answer(
        id,
        AiToolResult(
          toolUseId: id,
          ok: false,
          summary: 'The user removed these entries from the list, so nothing '
              'was logged.',
        ));
    notifyListeners();
  }

  /// Commits the ledger rows of the batch and says exactly which were saved.
  Future<AiToolResult> _commitLedgerRows(String id) async {
    final ledger = _ledger;
    if (ledger == null) {
      return AiToolResult.failed(id, 'Logging is not available here.');
    }
    final rows = ledger.chatState.entries;
    final ready = rows.where((e) => e.isReady).toList();
    if (ready.isEmpty) {
      return AiToolResult.failed(
          id, 'Nothing was logged: every entry still needed a field.');
    }
    _approving = true;
    try {
      await ledger.confirmEntries();
    } finally {
      _approving = false;
    }
    final left = rows.length - ready.length;
    final lines = [
      for (final e in ready)
        '- ${e.txn.description.isEmpty ? "entry" : e.txn.description} '
            '${_peso(e.txn.amount ?? 0)}'
            '${e.txn.date == null ? ' (today)' : ' (${_day(e.txn.date!)})'}',
    ];
    return AiToolResult(
      toolUseId: id,
      ok: true,
      summary: 'Logged ${ready.length} '
          '${ready.length == 1 ? "entry" : "entries"} to the ledger:\n'
          '${lines.join('\n')}'
          '${left == 0 ? '' : '\n$left still need a field and wait on the card.'}',
    );
  }

  /// [call] without the keys only a row's controls set (design D8): a
  /// model that sends one is ignored, so the user ticks the box.
  static AiToolCall _withoutCardControls(AiToolCall call) =>
      call.input.containsKey(_addSetAsideKey)
          ? AiToolCall(
              id: call.id,
              name: call.name,
              input: {...call.input}..remove(_addSetAsideKey),
            )
          : call;

  /// Checks [call], binds it, and draws its row — or says why it cannot be
  /// shown. Used when a batch opens and again on every in-place edit.
  ({PendingFinanceAction? action, String? error}) _build(AiToolCall call) {
    final problem = _proposalProblem(call);
    if (problem != null) return (action: null, error: problem);
    _InstallmentPlan? plan;
    if (call.name == 'addInstallment') {
      final resolved = _resolveInstallment(call.input);
      final error = resolved.error;
      if (error != null) return (action: null, error: error);
      plan = resolved.plan;
    }
    final described =
        plan != null ? _describeInstallment(call, plan) : _describe(call);
    if (described == null) {
      return (action: null, error: 'Unknown tool "${call.name}".');
    }
    if (plan != null) {
      _plans[call.id] = plan;
    } else {
      _plans.remove(call.id);
    }
    return (
      action: described.withReview(
        // A row may ask for more care than its tool does by default: a row
        // that deletes something (an undo that takes its ledger entry with
        // it), or an installment edit that reschedules later months, is T3.
        tier: described.isDestructive ||
                described.tier == ProposalTier.destructive
            ? ProposalTier.destructive
            : _tierFor(call.name),
        editable: _editableFor(call.name),
      ),
      error: null,
    );
  }

  /// Plan 065 tiers: a delete is T3; an edit, a settlement, a card payment or
  /// an installment (it holds credit and books months ahead) is T2; any other
  /// create is T1. A recurring row becomes T3 on the card when the user
  /// widens it to later months.
  static ProposalTier _tierFor(String tool) {
    // A bulk change is T3: one approval settles several bills at once.
    if (tool == 'markBillsPaid') return ProposalTier.destructive;
    final kind = financeToolNamed(tool)?.kind;
    if (kind == AiToolKind.destroy) return ProposalTier.destructive;
    if (kind == AiToolKind.update) return ProposalTier.change;
    if (tool == 'payCredit' ||
        tool == 'addInstallment' ||
        tool == 'fundSetAside') {
      return ProposalTier.change;
    }
    return ProposalTier.create;
  }

  /// The fields each row edits in place, mapped to the input key they write.
  static Map<ProposalField, String> _editableFor(String tool) => switch (tool) {
        'addBill' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.day: 'dueDay',
            ProposalField.account: 'account',
            ProposalField.category: 'category',
          },
        'addReceivable' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.day: 'expectedDay',
          },
        'addSetAside' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.account: 'destinationAccount',
          },
        'addInstallment' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.account: 'account',
            ProposalField.category: 'category',
            ProposalField.date: 'date',
          },
        'payCredit' => const {
            ProposalField.amount: 'amount',
            ProposalField.account: 'fromAccount',
            ProposalField.date: 'date',
          },
        'markBillPaid' => const {
            ProposalField.amount: 'paidAmount',
            ProposalField.account: 'account',
            ProposalField.date: 'paidDate',
          },
        'markBillsPaid' => const {
            ProposalField.account: 'account',
            ProposalField.date: 'paidDate',
          },
        'markReceivableReceived' => const {
            ProposalField.amount: 'receivedAmount',
            ProposalField.account: 'account',
            ProposalField.date: 'receivedDate',
          },
        'editBill' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.day: 'dueDay',
            ProposalField.category: 'category',
          },
        'fundSetAside' => const {
            ProposalField.amount: 'amount',
            ProposalField.account: 'fromAccount',
            ProposalField.date: 'date',
          },
        'editReceivable' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.day: 'expectedDay',
          },
        'editSetAside' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.account: 'destinationAccount',
          },
        'markInstallmentMonthPaid' => const {
            ProposalField.amount: 'amount',
            ProposalField.date: 'date',
          },
        'editInstallment' => const {
            ProposalField.name: 'name',
            ProposalField.amount: 'amount',
            ProposalField.account: 'account',
            ProposalField.category: 'category',
            ProposalField.date: 'date',
          },
        'editAccount' => const {ProposalField.name: 'name'},
        'setBudget' || 'editBudget' => const {
            ProposalField.amount: 'amount',
          },
        'editTransaction' => const {
            ProposalField.name: 'description',
            ProposalField.amount: 'amount',
            ProposalField.date: 'date',
            ProposalField.account: 'account',
            ProposalField.category: 'category',
          },
        _ => const {},
      };

  // ── Transactions ──────────────────────────────────────────────────────────

  /// Binds the model's entries against the user's real accounts and categories
  /// and puts them on the ledger's review rows, which join the open batch.
  ///
  /// Nothing is written here. A failure comes back as the call's result; on
  /// success the batch answers the call later, after Approve all, with what
  /// was actually logged (design D3).
  ///
  /// The binding is the extractor's own, reused verbatim — an account or
  /// category name the model invented is dropped to a picker on the row rather
  /// than fabricated into an id, exactly as it is on the typed-message path.
  AiToolResult _handOffToLedger(AiToolCall call, Set<String> newCategories) {
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
    // These rows live on the ledger's review card, which binds and offers
    // only saved categories: a category this batch only proposes would show
    // there as "Add category". So they wait for the next step.
    for (final e in raw) {
      final named = e is Map ? _str(e['category']) : '';
      final lower = named.toLowerCase();
      if (named.isEmpty ||
          !newCategories.contains(lower) ||
          _categories.any((c) => c.name.toLowerCase() == lower)) {
        continue;
      }
      return AiToolResult.failed(
          call.id,
          'Nothing was logged. The entries use the category "$named", which '
          'addCategory only proposes in this list: it is not saved yet, and '
          'logged entries can only use a saved category. Once the user '
          'approves the new category, call logTransactions in the next step.');
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
            if (_categoryLabel(_str(i['category'])) case final c?)
              (label: 'Category', value: c),
            if (_accountFor(_str(i['account'])) case final a?)
              (label: 'Pay from', value: a.name),
            (label: 'Repeats', value: recurring ? 'Monthly' : 'One-off'),
          ],
        );
      case 'addCategory':
        final type = _categoryType(i['type']);
        return PendingFinanceAction(
          call: call,
          title: 'Add category: $name',
          isRecurring: false,
          details: [
            (label: 'Name', value: name),
            (
              label: 'Type',
              value: type == CategoryType.income ? 'Income' : 'Expense',
            ),
            (
              label: 'In totals',
              value: i['excludeFromTotals'] == true
                  ? 'No — left out of totals and budget spend'
                  : 'Yes',
            ),
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
      case 'markBillsPaid':
        final s = _bulkSettlement(i);
        if (s == null) return null;
        final total = s.items.fold(0.0, (t, x) => t + x.amount);
        return PendingFinanceAction(
          call: call,
          title: 'Mark ${s.items.length} bills paid (${_peso(total)})',
          isRecurring: false,
          confirmLabel: 'Mark Paid',
          ledgerChoice: s.choice,
          details: [
            for (final x in s.items)
              (label: 'Bill', value: '${x.bill.name} — ${_peso(x.amount)}'),
            if (s.account case final a?) (label: 'Paid from', value: a.name),
            (label: 'Paid date', value: _day(s.date)),
            // When every bill matched, the ledger choice already says so;
            // otherwise each lookalike is named so the user can remove it.
            if (s.choice.match == null)
              for (final x in s.items)
                if (s.found[x.bill.id] case final found?)
                  (label: 'In ledger?', value: '${x.bill.name}: $found'),
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
      case 'markBillUnpaid':
        final bill =
            _bills.allBills.where((b) => b.id == _str(i['id'])).firstOrNull;
        if (bill == null) return null;
        final gone = _undoneEntries(_bills.billLedgerEntries(bill));
        final paid = bill.paidAmount ?? bill.amount;
        return PendingFinanceAction(
          call: call,
          title: 'Mark bill unpaid: ${bill.name} (${_peso(paid)})',
          isRecurring: false,
          confirmLabel: 'Mark Unpaid',
          isDestructive: gone.isNotEmpty,
          details: [
            (label: 'Bill', value: bill.name),
            (
              label: 'Status',
              value: 'Paid ${_peso(paid)}'
                  '${bill.paidDate == null ? '' : ' on ${_day(bill.paidDate!)}'}'
                  ' → Unpaid',
            ),
            ..._undoRows(gone),
          ],
        );
      case 'markReceivableNotReceived':
        final rec = _bills.allReceivables
            .where((r) => r.id == _str(i['id']))
            .firstOrNull;
        if (rec == null) return null;
        final gone = _undoneEntries(_bills.receivableLedgerEntries(rec));
        final got = rec.receivedAmount ?? rec.amount;
        return PendingFinanceAction(
          call: call,
          title: 'Mark not received: ${rec.name} (${_peso(got)})',
          isRecurring: false,
          confirmLabel: 'Mark Not Received',
          isDestructive: gone.isNotEmpty,
          details: [
            (label: 'Receivable', value: rec.name),
            (
              label: 'Status',
              value: 'Received ${_peso(got)}'
                  '${rec.receivedDate == null ? '' : ' on ${_day(rec.receivedDate!)}'}'
                  ' → Not received',
            ),
            ..._undoRows(gone),
          ],
        );
      case 'editBill':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final billName = bill?.name ?? 'Bill';
        final newCategory = _categoryLabel(_str(i['category']));
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
                value: '${_categoryName(bill?.categoryId)} → $newCategory'
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
      case 'fundSetAside':
        final f = _setAsideFunding(i);
        if (f == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Fund set-aside: ${f.expense.name} (${_peso(f.amount)})',
          isRecurring: false,
          confirmLabel: 'Set Aside',
          details: [
            (label: 'Set-aside', value: f.expense.name),
            (label: 'Amount', value: _peso(f.amount)),
            (label: 'From', value: f.from?.name ?? 'not set'),
            (
              label: 'Into',
              value: f.into?.name ?? 'none — recorded as spending',
            ),
            (label: 'Date', value: _day(f.date)),
            if (f.expense.spentAmount > 0)
              (
                label: 'Funded',
                value: '${_peso(f.expense.spentAmount)} → ${_peso(f.amount)}',
              ),
          ],
        );
      case 'editAccount':
        final e = _accountEdit(i);
        if (e == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Update account: ${e.before.name}',
          isRecurring: false,
          confirmLabel: 'Update Account',
          details: e.rows,
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
            if (_categoryLabel(_str(i['category'])) case final c?)
              (
                label: 'Category',
                value: '${_categoryName(t?.categoryId)} → $c'
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
      case 'setBudget':
        final b = _newBudget(i).plan;
        if (b == null) return null;
        final addsSetAside = b.offersSetAside && b.addSetAside;
        return PendingFinanceAction(
          call: call,
          title: 'Set budget: ${b.label}, ${_peso(b.amount)}',
          isRecurring: false,
          confirmLabel: 'Set Budget',
          option: b.offersSetAside
              ? RowOption(
                  label: 'Also add a monthly set-aside in Bills',
                  hint: 'Nothing in Bills moves money into ${b.label} yet. A '
                      'set-aside gives you something to mark paid; you pick '
                      'the account it comes from when you fund it.',
                  value: b.addSetAside,
                  inputKey: _addSetAsideKey,
                )
              : null,
          details: [
            (label: b.savings ? 'Set aside into' : 'Category', value: b.label),
            (label: 'Amount', value: _peso(b.amount)),
            (label: 'Month', value: b.month),
            (label: 'Group', value: _groupName(b.groupId)),
            (label: 'Repeats', value: 'Every month until removed'),
            if (addsSetAside)
              (
                label: 'Also adds',
                value: 'a monthly ${_peso(b.amount)} set-aside into '
                    '${b.label} in Bills',
              ),
          ],
        );
      case 'editBudget':
        final e = _budgetEdit(i).edit;
        if (e == null) return null;
        final b = e.budget;
        final series = _isSeries(b);
        return PendingFinanceAction(
          call: call,
          title: 'Edit budget: ${_budgetName(b)} (${b.month})',
          isRecurring: false,
          confirmLabel: 'Save Budget',
          // No this-month-only path: an edit is the new going rate for the
          // rest of the series (BudgetPresenter.setBudget).
          tier: series ? ProposalTier.destructive : ProposalTier.change,
          details: [
            (label: 'Budget', value: _budgetName(b)),
            (label: 'Month', value: b.month),
            if (e.amount != b.allocatedAmount)
              (
                label: 'Amount',
                value: '${_peso(b.allocatedAmount)} → ${_peso(e.amount)}',
              ),
            if (e.groupId != b.group)
              (
                label: 'Group',
                value: '${_groupName(b.group)} → ${_groupName(e.groupId)}',
              ),
            if (series)
              (
                label: 'Also changes',
                value: 'every later month of this budget; earlier months '
                    'keep theirs',
              ),
          ],
        );
      case 'removeBudget':
        final b = _budgetById(i);
        if (b == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Remove budget: ${_budgetName(b)} '
              '(${_peso(b.allocatedAmount)})',
          isRecurring: false,
          confirmLabel: 'Remove Budget',
          isDestructive: true,
          details: [
            (label: 'Budget', value: _budgetName(b)),
            (label: 'Amount', value: _peso(b.allocatedAmount)),
            (label: 'Month', value: b.month),
            (
              label: 'Also',
              value: _isSeries(b)
                  ? 'ends it: later months lose it too and it does not come '
                      'back. Earlier months keep theirs.'
                  : 'nothing else: this budget is for ${b.month} only.',
            ),
          ],
        );
      case 'markInstallmentMonthPaid':
        final p = _monthPayment(i);
        if (p == null) return null;
        final total = p.plan.totalMonths;
        return PendingFinanceAction(
          call: call,
          title: 'Mark installment paid: ${p.plan.name} (${_peso(p.amount)})',
          isRecurring: false,
          confirmLabel: 'Mark Paid',
          details: [
            (label: 'Installment', value: p.plan.name),
            (label: 'Month', value: p.month),
            (
              label: 'Paid',
              value: '${p.paid} of $total → ${p.paid + 1} of $total',
            ),
            (label: 'Amount', value: _peso(p.amount)),
            (
              label: 'Charged to',
              value: '${_accountName(p.plan.accountId)} (adds to its balance)',
            ),
            (label: 'Date', value: _day(p.date)),
          ],
        );
      case 'editInstallment':
        final e = _installmentEdit(i).edit;
        if (e == null) return null;
        return PendingFinanceAction(
          call: call,
          title: 'Edit installment: ${e.before.name}',
          isRecurring: false,
          confirmLabel: 'Save Changes',
          tier: e.touchesMore ? ProposalTier.destructive : ProposalTier.change,
          details: _installmentEditRows(e),
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

  // ── Budgets ───────────────────────────────────────────────────────────────

  /// The card's input key for D8's "also add a monthly set-aside" checkbox.
  /// Only the card sets it: [proposeBatch] drops it from a model call.
  static const String _addSetAsideKey = '_addSetAside';

  /// The budget row an id-taking budget call names, or null.
  Budget? _budgetById(Map<String, Object?> i) =>
      _budget?.allBudgets.where((b) => b.id == _str(i['id'])).firstOrNull;

  /// What a budget row is for: the account a savings row funds, else its
  /// category — the same name `find` prints.
  String _budgetName(Budget b) {
    final budget = _budget;
    final savings = budget != null && budget.isSavingsGroup(b.group);
    final name =
        savings ? _accountName(b.categoryId) : _categoryName(b.categoryId);
    return name;
  }

  String _groupName(String id) =>
      _budget?.groupById(id)?.name ?? (id.isEmpty ? 'none' : id);

  /// The budget group [name] names among [pool]: an exact name, else the one
  /// it starts. Null when none or several match.
  static BudgetGroupDef? _groupFor(String name, Iterable<BudgetGroupDef> pool) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return null;
    final exact = pool.where((g) => g.name.toLowerCase() == q).toList();
    if (exact.length == 1) return exact.single;
    final prefix = pool.where((g) => g.name.toLowerCase().startsWith(q));
    return prefix.length == 1 ? prefix.single : null;
  }

  /// The month a new budget lands in: the one named (a slipped year
  /// rebased), else the month the Budget tab shows.
  String _budgetMonth(Map<String, Object?> i) {
    final given = _str(i['month']);
    return RegExp(r'^\d{4}-\d{2}$').hasMatch(given)
        ? rebaseStaleMonthKey(given, DateTime.now())
        : (_budget?.selectedMonth ?? _bills.selectedMonth);
  }

  /// A `setBudget` call bound against the user's categories, savings
  /// accounts and groups, or why it cannot be proposed. The row and the
  /// write both use it.
  ({_NewBudget? plan, String? error}) _newBudget(Map<String, Object?> i) {
    ({_NewBudget? plan, String? error}) fail(String error) =>
        (plan: null, error: error);
    final budget = _budget;
    if (budget == null) return fail('Budgets are not available here.');

    final categoryName = _str(i['category']);
    final accountName = _str(i['savingsAccount']);
    if (categoryName.isEmpty == accountName.isEmpty) {
      return fail('Give either a category (a spending budget) or a '
          'savingsAccount (money to set aside into a savings or goal '
          'account), not both and not neither.');
    }
    final amount = _amountOrNull(i['amount']);
    if (amount == null) {
      return fail('The budget amount must be in pesos, above zero. Ask the '
          'user for it.');
    }

    final savings = accountName.isNotEmpty;
    final String key;
    final String label;
    if (savings) {
      final targets = budget.savingsTargets;
      final account = _matchAccount(accountName, targets);
      if (account == null) {
        final names = targets.map((a) => '"${a.name}"').join(', ');
        return fail('"$accountName" does not match exactly one savings or '
            'goal account. Choices: ${names.isEmpty ? 'none' : names}. Ask '
            'the user which one.');
      }
      key = account.id;
      label = account.name;
    } else {
      final lower = categoryName.toLowerCase();
      final pool = budget.expenseCategories;
      final category = pool
              .where((c) => c.name.toLowerCase() == lower)
              .firstOrNull ??
          pool.where((c) => c.name.toLowerCase().startsWith(lower)).firstOrNull;
      if (category == null) {
        // A budget is keyed by the category's id, which a category this
        // list adds does not have until the user approves it.
        if (_newCategories[lower] case final added?) {
          return fail('"$added" is added in this same list, so it has no '
              'budget yet. Propose the budget after the user approves the '
              'category, in your next reply.');
        }
        final names = pool.map((c) => '"${c.name}"').join(', ');
        return fail('No expense category is named "$categoryName". '
            'Categories: $names. Use one of these names, or add the category '
            'with addCategory first and set its budget after it is saved.');
      }
      key = category.id;
      label = category.name;
    }

    final groups = budget.groups.where((g) => g.isSavings == savings);
    final groupName = _str(i['group']);
    final String groupId;
    if (groupName.isEmpty) {
      groupId = savings
          ? BudgetGroupDef.idSavings
          : BudgetGroupDef.idVariableOptional;
    } else {
      final group = _groupFor(groupName, groups);
      if (group == null) {
        final names = groups.map((g) => '"${g.name}"').join(', ');
        return fail('"$groupName" does not match one '
            '${savings ? 'savings' : 'spending'} group. Groups: $names. Use '
            'one of these, or leave the group out.');
      }
      groupId = group.id;
    }

    final month = _budgetMonth(i);
    final existing = budget.budgetFor(key, month: month);
    if (existing != null) {
      return fail('"$label" already has a budget in $month '
          '(${_peso(existing.allocatedAmount)}, id=${existing.id}). To change '
          'it, call editBudget with that id.');
    }
    return (
      plan: _NewBudget(
        key: key,
        label: label,
        savings: savings,
        amount: amount,
        groupId: groupId,
        month: month,
        // D8: offered only when nothing in Bills funds the account yet — the
        // add-budget sheet's own check.
        offersSetAside:
            savings && budget.setAsideSourcesFor(key, month: month).isEmpty,
        addSetAside: i[_addSetAsideKey] == true,
      ),
      error: null,
    );
  }

  /// A new amount and group for an `editBudget` call, or why it cannot be
  /// proposed.
  ({_BudgetEdit? edit, String? error}) _budgetEdit(Map<String, Object?> i) {
    ({_BudgetEdit? edit, String? error}) fail(String error) =>
        (edit: null, error: error);
    final budget = _budget;
    final b = _budgetById(i);
    if (budget == null || b == null) {
      return fail('Budgets are not available here.');
    }
    var amount = b.allocatedAmount;
    if (i['amount'] != null) {
      final n = _amountOrNull(i['amount']);
      if (n == null) return fail('The budget amount must be above zero.');
      amount = n;
    }
    var groupId = b.group;
    final groupName = _str(i['group']);
    if (groupName.isNotEmpty) {
      // A savings row is keyed by an account, a spending row by a category,
      // so a row can only move to a group of its own kind.
      final savings = budget.isSavingsGroup(b.group);
      final groups = budget.groups.where((g) => g.isSavings == savings);
      final group = _groupFor(groupName, groups);
      if (group == null) {
        final names = groups.map((g) => '"${g.name}"').join(', ');
        return fail('"$groupName" does not match one '
            '${savings ? 'savings' : 'spending'} group. Groups: $names.');
      }
      groupId = group.id;
    }
    if (amount == b.allocatedAmount && groupId == b.group) {
      return fail('That changes nothing on the "${_budgetName(b)}" budget. '
          'Ask the user what to change.');
    }
    return (edit: (budget: b, amount: amount, groupId: groupId), error: null);
  }

  /// True when [b] carries into later months, so an edit or a removal
  /// reaches them too.
  static bool _isSeries(Budget b) => b.isRecurring && b.seriesId != null;

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

    final months = _installmentMonths(i['months']);
    final monthsError = months.error;
    if (monthsError != null) return fail(monthsError);

    final rate = _installmentRate(i['interestRate']);
    final rateError = rate.error;
    if (rateError != null) return fail(rateError);

    final account = _creditAccountFor(_str(i['account']));
    final accountError = account.error;
    if (accountError != null) return fail(accountError);

    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    String? dateNote;
    final rawDate = _str(i['date']);
    if (rawDate.isNotEmpty) {
      final given = _purchaseDate(rawDate);
      final dateError = given.error;
      if (dateError != null) return fail(dateError);
      date = given.date!;
      dateNote = given.note;
    }

    final note = _str(i['note']);
    return (
      plan: _InstallmentPlan(
        name: name,
        amount: amount.toDouble(),
        months: months.months!,
        rate: rate.rate!,
        account: account.account!,
        category: _categoryFor(_str(i['category'])),
        newCategory: _newCategories[_str(i['category']).toLowerCase()],
        requestedCategory: _str(i['category']),
        date: date,
        dateNote: dateNote,
        note: note.isEmpty ? null : note,
      ),
      error: null,
    );
  }

  /// The number of monthly payments in [raw], or why it is not one. Shared
  /// by `addInstallment` and `editInstallment`, so both refuse the same terms.
  static ({int? months, String? error}) _installmentMonths(Object? raw) {
    ({int? months, String? error}) fail(String error) =>
        (months: null, error: error);
    final months = _numOrNull(raw);
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
    return (months: months.toInt(), error: null);
  }

  /// The monthly add-on rate in [raw] (absent is 0%), or why it is not one.
  static ({double? rate, String? error}) _installmentRate(Object? raw) {
    ({double? rate, String? error}) fail(String error) =>
        (rate: null, error: error);
    final double rate;
    if (raw == null || (raw is String && raw.trim().isEmpty)) {
      rate = 0;
    } else {
      final parsed = _numOrNull(raw);
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
    return (rate: rate, error: null);
  }

  /// A purchase date from the model, with a slipped year rebased and a note
  /// saying so — or why it cannot be one (not a date, or in the future).
  static ({DateTime? date, String? note, String? error}) _purchaseDate(
      String raw) {
    final given = DateTime.tryParse(raw);
    if (given == null) {
      return (
        date: null,
        note: null,
        error: 'The purchase date must be YYYY-MM-DD, not "$raw".',
      );
    }
    final now = DateTime.now();
    // The same year-slip guard every other tool applies to a model date.
    final rebased = rebaseStaleDate(given, now);
    final date = DateTime(rebased.year, rebased.month, rebased.day);
    if (date.isAfter(DateTime(now.year, now.month, now.day))) {
      return (
        date: null,
        note: null,
        error: 'The purchase date $raw is in the future. Use the day it was '
            'bought, or leave the date out for today.',
      );
    }
    final moved = date != DateTime(given.year, given.month, given.day);
    return (date: date, note: moved ? 'moved from $raw' : null, error: null);
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
        else if (p.newCategory case final added?)
          (label: 'Category', value: '$added$_newMark')
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

  /// A `markInstallmentMonthPaid` call bound against the live plan: the month
  /// (the one named, else the one the tabs show), the amount (the one named,
  /// else the monthly payment) and the date. The row and the write both use it.
  ({Installment plan, String month, double amount, DateTime date, int paid})?
      _monthPayment(Map<String, Object?> i) {
    final installments = _installments;
    final plan = installments?.findById(_str(i['id']));
    if (installments == null || plan == null) return null;
    final given = _str(i['month']);
    return (
      plan: plan,
      month: RegExp(r'^\d{4}-\d{2}$').hasMatch(given)
          ? rebaseStaleMonthKey(given, DateTime.now())
          : installments.selectedMonth,
      amount: _amountOrNull(i['amount']) ?? plan.monthlyAmount,
      date: _settleDate(i['date']),
      paid: installments.paidCount(plan.id),
    );
  }

  /// Why that month cannot be marked paid — the rules behind the list's
  /// "Mark paid" button ([InstallmentPresenter.canMarkPaid]), each with its
  /// reason — or null.
  String? _monthPaymentProblem(Map<String, Object?> i) {
    final installments = _installments;
    final p = _monthPayment(i);
    if (installments == null || p == null) {
      return 'Installments are not available here.';
    }
    final plan = p.plan;
    if (!plan.isActive) {
      return '"${plan.name}" is cancelled, so it has no payments to mark. '
          'Tell the user.';
    }
    if (installments.billsOnStatement(plan)) {
      return '"${plan.name}" is on ${_accountName(plan.accountId)}, which has '
          'statements: each month is billed when the statement closes and '
          'paid by paying the statement (payCredit). There is nothing to mark '
          'on the plan itself — tell the user.';
    }
    if (plan.chargesDueBy(p.month) == 0) {
      return '"${plan.name}" has no payment due by ${p.month}: its first '
          'payment is in ${plan.startMonth}. Check the month with the user.';
    }
    if (!installments.canMarkPaid(plan, month: p.month)) {
      return 'The ${p.month} payment of "${plan.name}" is already recorded '
          '(${p.paid} of ${plan.totalMonths} paid). Nothing to change — tell '
          'the user.';
    }
    return null;
  }

  /// An `editInstallment` call bound against the live plan, or why it cannot
  /// be proposed. The new plan comes from [LedgerPresenter.editedPlan], the
  /// rule the save uses, so the row shows the monthly payment and schedule
  /// that will be saved.
  ({_PlanEdit? edit, String? error}) _installmentEdit(Map<String, Object?> i) {
    ({_PlanEdit? edit, String? error}) fail(String error) =>
        (edit: null, error: error);
    final ledger = _ledger;
    final installments = _installments;
    final before = installments?.findById(_str(i['id']));
    if (ledger == null || installments == null || before == null) {
      return fail('Installments are not available here.');
    }
    final purchase = ledger.allTransactions
        .where((t) => t.isInstallment && t.installmentId == before.id)
        .firstOrNull;
    final paid = installments.paidCount(before.id);

    var amount = before.totalAmount;
    if (i['amount'] != null) {
      final n = _numOrNull(i['amount']);
      if (n == null || !n.isFinite || n <= 0) {
        return fail('The total price must be in pesos, above zero.');
      }
      amount = n.toDouble();
    }

    var months = before.totalMonths;
    if (i['months'] != null) {
      final m = _installmentMonths(i['months']);
      final error = m.error;
      if (error != null) return fail(error);
      months = m.months!;
      if (months < paid) {
        return fail('$paid payments of "${before.name}" are already recorded, '
            'so the plan cannot be shorter than $paid months. Check with the '
            'user.');
      }
    }

    var rate = before.interestRate;
    if (i['interestRate'] != null) {
      final r = _installmentRate(i['interestRate']);
      final error = r.error;
      if (error != null) return fail(error);
      rate = r.rate!;
    }

    var accountId = before.accountId;
    if (_str(i['account']).isNotEmpty) {
      final a = _creditAccountFor(_str(i['account']));
      final error = a.error;
      if (error != null) return fail(error);
      accountId = a.account!.id;
    }

    // The ledger's edit measures a moved date against the purchase entry; a
    // plan with none, against its own date (the list's form does the same).
    final previousDate = purchase?.date ??
        before.purchaseDate ??
        DateTime.tryParse('${before.startMonth}-01') ??
        DateTime.now();
    var date = previousDate;
    if (_str(i['date']).isNotEmpty) {
      final d = _purchaseDate(_str(i['date']));
      final error = d.error;
      if (error != null) return fail(error);
      date = d.date!;
    }

    final categoryError = _categoryProblem(i);
    if (categoryError != null) return fail(categoryError);
    // The ledger edits the purchase entry's category; a plan with no entry
    // keeps its own.
    final keptCategory = purchase == null
        ? before.categoryId
        : (purchase.categoryId.isEmpty ? null : purchase.categoryId);
    final requested = _str(i['category']);
    final bound = _categoryFor(requested);
    final categoryId = bound?.id ?? keptCategory;
    // A category an earlier row of this list adds is not saved yet: the row
    // names it, and the write binds its id once it is.
    final pendingCategory = bound == null && requested.isNotEmpty
        ? _newCategories[requested.toLowerCase()]
        : null;

    final name = _str(i['name']).isEmpty ? before.name : _str(i['name']);
    final note = i['note'] == null ? before.note : _str(i['note']);

    final after = ledger.editedPlan(
      before,
      previousDate: previousDate,
      account: ledger.accounts.where((a) => a.id == accountId).firstOrNull,
      accountId: accountId,
      amount: amount,
      months: months,
      interestRate: rate,
      date: date,
      name: name,
      note: (note == null || note.isEmpty) ? null : note,
      categoryId: categoryId,
    );
    final edit = _PlanEdit(
      before: before,
      after: after,
      previousDate: previousDate,
      purchase: purchase,
      paid: paid,
      newCategory: pendingCategory,
    );
    if (!edit.changesAnything) {
      return fail('That changes nothing on "${before.name}". Ask the user '
          'what to change.');
    }
    return (edit: edit, error: null);
  }

  /// The row of an installment edit: every field that changes, before →
  /// after, then what else the save changes.
  List<({String label, String value})> _installmentEditRows(_PlanEdit e) {
    final b = e.before;
    final a = e.after;
    String rate(double r) => '${_rateLabel(r)} / mo';
    final purchase = e.purchase;
    return [
      if (a.name != b.name) (label: 'Name', value: '${b.name} → ${a.name}'),
      if (a.totalAmount != b.totalAmount)
        (
          label: 'Total amount',
          value: '${_peso(b.totalAmount)} → ${_peso(a.totalAmount)}',
        ),
      if (a.totalMonths != b.totalMonths)
        (
          label: 'Duration',
          value: '${b.totalMonths} → ${a.totalMonths} months',
        ),
      if (a.interestRate != b.interestRate)
        (
          label: 'Interest rate',
          value: '${rate(b.interestRate)} → ${rate(a.interestRate)}',
        ),
      if (a.monthlyAmount != b.monthlyAmount)
        (
          label: 'Monthly payment',
          value: '${_peso(b.monthlyAmount)} → ${_peso(a.monthlyAmount)}',
        ),
      if (a.accountId != b.accountId)
        (
          label: 'Account',
          value: '${_accountName(b.accountId)} → ${_accountName(a.accountId)}',
        ),
      if (e.dateMoved)
        (
          label: 'Purchase date',
          value: '${_day(e.previousDate)} → ${_day(a.purchaseDate!)}',
        ),
      if (a.startMonth != b.startMonth)
        (label: 'First payment', value: '${b.startMonth} → ${a.startMonth}'),
      if (e.newCategory case final added?)
        (
          label: 'Category',
          value: '${_categoryName(b.categoryId)} → $added$_newMark',
        )
      else if (a.categoryId != b.categoryId)
        (
          label: 'Category',
          value: '${_categoryName(b.categoryId)} → '
              '${_categoryName(a.categoryId)}',
        ),
      if (a.note != b.note)
        (label: 'Note', value: '${b.note ?? 'none'} → ${a.note ?? 'none'}'),
      if (e.schedule)
        (
          label: 'Also changes',
          value: 'every later month of the plan'
              '${e.paid == 0 ? '' : '; the ${e.paid} recorded '
                  '${e.paid == 1 ? 'payment keeps its amount' : 'payments keep their amounts'}'}',
        ),
      if (a.accountId != b.accountId)
        (
          label: 'Also moves',
          value: 'the credit it holds, from ${_accountName(b.accountId)} to '
              '${_accountName(a.accountId)}',
        ),
      if (e.recordChanges && purchase != null)
        (
          label: 'Also changes',
          value: 'its purchase entry in the ledger ("${purchase.description}" '
              '${_peso(purchase.amount)} on ${_day(purchase.date)})',
        ),
    ];
  }

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

      case 'markBillsPaid':
        final s = _bulkSettlement(i);
        if (s == null) throw StateError('markBillsPaid names an unknown bill');
        final record = !alreadyLogged;
        if (record && s.account == null) {
          throw StateError('No account to record the payments in');
        }
        // The Bills tab's batch path: every bill settles in memory, then one
        // save and one fan-out for the lot.
        final result = await _bills.markBillsPaid(
          [for (final x in s.items) x.bill.id],
          accountId: record ? s.account!.id : null,
          paidDate: s.date,
          recordInLedger: record,
          paidAmounts: {for (final x in s.items) x.bill.id: x.amount},
        );
        final lines = [
          for (final x in s.items)
            '${x.bill.name} ${_peso(x.amount)}'
                '${_bulkOutcome(x.bill)}',
        ];
        return 'Marked ${result.applied} of ${s.items.length} bills paid'
            '${record ? ' from ${s.account!.name}' : ', already in the ledger, so no new entries'}'
            ' on ${_day(s.date)}: ${lines.join(', ')}.'
            '${result.skipped == 0 ? '' : ' ${result.skipped} could not be '
                'paid, so nothing changed for them.'}';

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

      case 'markBillUnpaid':
        final id = _str(i['id']);
        final bill = _bills.allBills.where((b) => b.id == id).firstOrNull;
        if (bill == null) throw StateError('Bill "$id" not found');
        final gone = _undoneEntries(_bills.billLedgerEntries(bill));
        // The Bills tab's own undo, with its default: the ledger entry goes
        // too, which is what makes the undo stick.
        await _bills.markBillUnpaid(id);
        final after = _bills.allBills.where((b) => b.id == id).firstOrNull;
        final stillPaid = after?.isPaid ?? false;
        return 'Marked bill "${bill.name}" unpaid${_undoneSummary(gone)}.'
            '${stillPaid ? ' It still reads as paid: payments to the card in '
                'the ledger cover it.' : ''}';

      case 'markReceivableNotReceived':
        final id = _str(i['id']);
        final rec = _bills.allReceivables.where((r) => r.id == id).firstOrNull;
        if (rec == null) throw StateError('Receivable "$id" not found');
        final gone = _undoneEntries(_bills.receivableLedgerEntries(rec));
        await _bills.markReceivableUnreceived(id);
        return 'Marked receivable "${rec.name}" not received'
            '${_undoneSummary(gone)}.';

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
          categoryId: _str(i['category']).isEmpty
              ? null
              : _savedCategoryId(_str(i['category'])),
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

      case 'fundSetAside':
        final f = _setAsideFunding(i);
        final from = f?.from;
        if (f == null || from == null) {
          throw StateError('Set-aside "${_str(i['id'])}" cannot be funded');
        }
        // The Bills tab's own path: a transfer into the destination, or a
        // plain outflow when there is none (a gift really is spent).
        await _bills.markExpensePaid(
          f.expense.id,
          paidAmount: f.amount,
          accountId: from.id,
          toAccountId: f.into?.id,
          paidDate: f.date,
        );
        return 'Set aside ${_peso(f.amount)} for "${f.expense.name}" from '
            '${from.name}${f.into == null ? ' (recorded as spending)' : ' into ${f.into!.name}'}.';

      case 'editAccount':
        final dashboard = _dashboard;
        final e = _accountEdit(i);
        if (dashboard == null || e == null) {
          throw StateError('Account "${_str(i['id'])}" cannot be edited');
        }
        // The account sheet's own save, so a re-planned goal target is
        // reconciled exactly as it is there.
        await dashboard.updateAccount(e.after);
        return 'Updated account "${e.after.name}": '
            '${e.rows.map((r) => '${r.label} ${r.value}').join('; ')}.';

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
        final newCategory = _str(i['category']).isEmpty
            ? null
            : _savedCategoryId(_str(i['category']));
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

      case 'setBudget':
        final budget = _budget;
        final b = _newBudget(i).plan;
        if (budget == null || b == null) {
          throw StateError('setBudget could not be bound');
        }
        // The add-budget sheet's own save, then its set-aside offer (D8).
        await budget.setBudget(b.key, b.amount,
            group: b.groupId, month: b.month);
        if (budget.budgetFor(b.key, month: b.month) == null) {
          throw StateError('setBudget saved nothing for ${b.key}');
        }
        final addsSetAside = b.offersSetAside && b.addSetAside;
        if (addsSetAside) {
          await budget.createRecurringSetAsideFor(b.key, b.amount,
              month: b.month);
        }
        return 'Set a ${_peso(b.amount)} budget for "${b.label}" from '
            '${b.month}, repeating monthly'
            '${addsSetAside ? ', and added a monthly ${_peso(b.amount)} set-aside into ${b.label} in Bills' : ''}.';

      case 'editBudget':
        final budget = _budget;
        final e = _budgetEdit(i).edit;
        if (budget == null || e == null) {
          throw StateError('Budget "${_str(i['id'])}" cannot be edited');
        }
        final b = e.budget;
        await budget.setBudget(b.categoryId, e.amount,
            group: e.groupId, month: b.month);
        return 'Updated the "${_budgetName(b)}" budget to ${_peso(e.amount)} '
            '(${_groupName(e.groupId)}) in ${b.month}'
            '${_isSeries(b) ? ' and every later month' : ''}.';

      case 'removeBudget':
        final budget = _budget;
        final b = _budgetById(i);
        if (budget == null || b == null) {
          throw StateError('Budget "${_str(i['id'])}" not found');
        }
        final name = _budgetName(b);
        final series = _isSeries(b);
        await budget.removeBudget(b.categoryId, month: b.month);
        if (budget.allBudgets.any((x) => x.id == b.id)) {
          throw StateError('removeBudget left ${b.id}');
        }
        return 'Removed the "$name" budget from ${b.month}'
            '${series ? ' and every later month; earlier months keep theirs' : ''}.';

      case 'markInstallmentMonthPaid':
        final installments = _installments;
        final p = _monthPayment(i);
        if (installments == null || p == null) {
          throw StateError('Installment "${_str(i['id'])}" not found');
        }
        // The Installments list's own "Mark paid".
        await installments.markPaid(
          p.plan.id,
          overrideAmount: p.amount,
          date: p.date,
          month: p.month,
        );
        if (installments.paidCount(p.plan.id) <= p.paid) {
          throw StateError('markPaid saved nothing for ${p.plan.id}');
        }
        return 'Marked payment ${p.paid + 1} of ${p.plan.totalMonths} of '
            '"${p.plan.name}" paid for ${p.month}: ${_peso(p.amount)} charged '
            'to ${_accountName(p.plan.accountId)} on ${_day(p.date)}.';

      case 'editInstallment':
        final e = _installmentEdit(i).edit;
        final ledger = _ledger;
        final installments = _installments;
        if (e == null || ledger == null || installments == null) {
          throw StateError('Installment "${_str(i['id'])}" cannot be edited');
        }
        if (e.newCategory != null) {
          // Throws when the category this list adds was not saved, rather
          // than saving the plan without it.
          _savedCategoryId(_str(i['category']));
        }
        final a = e.after;
        final purchase = e.purchase;
        if (purchase != null) {
          // The ledger's own edit of an installment purchase: the plan and
          // its purchase entry change together, recorded payments stay.
          await ledger.saveInstallmentPurchase(
            existing: purchase,
            accountId: a.accountId,
            amount: a.totalAmount,
            months: a.totalMonths,
            interestRate: a.interestRate,
            date: a.purchaseDate!,
            description: a.name,
            note: a.note,
            categoryId: a.categoryId,
          );
        } else {
          // A plan added on the Installments list has no purchase entry: the
          // list's own save.
          await installments.updateInstallment(a);
        }
        final saved = installments.findById(a.id) ?? a;
        return 'Updated installment "${saved.name}": '
            '${_peso(saved.totalAmount)} over ${saved.totalMonths} months at '
            '${_peso(saved.monthlyAmount)}/mo on '
            '${_accountName(saved.accountId)}'
            '${purchase == null ? '' : ', and its purchase entry in the ledger'}.';

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
            categoryId: _str(i['category']).isEmpty
                ? ''
                : _savedCategoryId(_str(i['category'])),
            accountId: _accountFor(_str(i['account']))?.id,
            isRecurring: recurring,
            recurrenceType: recurring ? RecurrenceType.monthly : null,
          ),
          applyToFuture: applyToFuture,
        );
        return 'Added the bill "$name" for ${_peso(amount)} in $month$scope.';

      case 'addCategory':
        final ledger = _ledger;
        if (ledger == null) throw StateError('Ledger is not available');
        final type = _categoryType(i['type']);
        final excluded = i['excludeFromTotals'] == true;
        // The category sheet's own values: the "Auto" icon and the next
        // colour of its type.
        await ledger.addCategory(FinanceCategory(
          id: _id(),
          name: name,
          type: type,
          icon: kAutoCategoryIconKey,
          colorHex: categoryColorAt(
            ledger.categories.where((c) => c.type == type).length,
            isExpense: type == CategoryType.expense,
          ),
          excludeFromTotals: excluded,
        ));
        return 'Added the ${type.name} category "$name"'
            '${excluded ? ', left out of totals and budget spend' : ''}.';

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
          categoryId: p.category?.id ??
              (p.newCategory == null ? null : _savedCategoryId(p.newCategory!)),
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

  /// A `fundSetAside` call bound against the live set-aside and accounts:
  /// the named accounts, else the set-aside's own. The row and the write
  /// both use it, so the accounts the user approved are the ones used.
  ({
    BudgetedExpense expense,
    double amount,
    FinancialAccount? from,
    FinancialAccount? into,
    DateTime date,
  })? _setAsideFunding(Map<String, Object?> i) {
    final e = _bills.allBudgetedExpenses
        .where((e) => e.id == _str(i['id']))
        .firstOrNull;
    if (e == null) return null;
    FinancialAccount? named(String field, String? fallbackId) {
      final name = _str(i[field]);
      if (name.isNotEmpty) return _accountFor(name);
      return _activeAccounts.where((a) => a.id == fallbackId).firstOrNull;
    }

    return (
      expense: e,
      amount: _amountOrNull(i['amount']) ?? e.allocatedAmount,
      from: named('fromAccount', e.accountId),
      into: named('intoAccount', e.destinationAccountId),
      date: _settleDate(i['date']),
    );
  }

  // ── Accounts ──────────────────────────────────────────────────────────────

  /// An `editAccount` call bound against the live account: the account as it
  /// will be saved, and one before → after row for each field that really
  /// changes. The row and the write are both drawn from it, so the user
  /// approves exactly what is saved. A field equal to its current value is no
  /// change and gets no row.
  ({
    FinancialAccount before,
    FinancialAccount after,
    List<({String label, String value})> rows,
  })? _accountEdit(Map<String, Object?> i) {
    final a = (_ledger?.accounts ?? const <FinancialAccount>[])
        .where((a) => a.id == _str(i['id']))
        .firstOrNull;
    if (a == null) return null;
    var after = a;
    final rows = <({String label, String value})>[];
    String was(double? v) => v == null ? 'not set' : _peso(v);

    final name = _str(i['name']);
    if (name.isNotEmpty && name != a.name) {
      after = after.copyWith(name: name);
      rows.add((label: 'Name', value: '${a.name} → $name'));
    }
    final limit = _amountOrNull(i['creditLimit']);
    if (limit != null && limit != a.creditLimit) {
      after = after.copyWith(creditLimit: limit);
      rows.add((
        label: 'Credit limit',
        value: '${was(a.creditLimit)} → ${_peso(limit)}',
      ));
    }
    final statement = _numOrNull(i['statementDay'])?.toInt();
    if (statement != null && statement != a.statementDay) {
      after = after.copyWith(statementDay: statement);
      rows.add((
        label: 'Statement day',
        value: '${_dayOfMonth(a.statementDay)} → day $statement',
      ));
    }
    final due = _numOrNull(i['paymentDueDay'])?.toInt();
    final daysAfter = a.dueDaysAfterStatement;
    if (due != null && (due != a.paymentDueDay || daysAfter != null)) {
      // The sheet stores one due rule: a fixed day replaces "N days after
      // the statement", which would otherwise win over it.
      after = after.copyWith(paymentDueDay: due, dueDaysAfterStatement: null);
      final before = daysAfter != null
          ? '$daysAfter days after the statement'
          : _dayOfMonth(a.paymentDueDay);
      rows.add((label: 'Payment due', value: '$before → day $due'));
    }
    final target = _amountOrNull(i['goalTarget']);
    if (target != null && target != a.goalTarget) {
      after = after.copyWith(goalTarget: target);
      rows.add((
        label: 'Goal target',
        value: '${was(a.goalTarget)} → ${_peso(target)}',
      ));
    }
    final given = DateTime.tryParse(_str(i['maturityDate']));
    final maturity =
        given == null ? null : DateTime(given.year, given.month, given.day);
    final oldMaturity = a.maturityDate;
    if (maturity != null &&
        (oldMaturity == null || _day(oldMaturity) != _day(maturity))) {
      after = after.copyWith(maturityDate: maturity);
      rows.add((
        label: 'Maturity date',
        value: '${oldMaturity == null ? 'not set' : _day(oldMaturity)}'
            ' → ${_day(maturity)}',
      ));
    }
    return (
      before: a,
      after: after.copyWith(updatedAt: DateTime.now()),
      rows: rows,
    );
  }

  static String _dayOfMonth(int? day) => day == null ? 'not set' : 'day $day';

  /// Why an `editAccount` call cannot be shown, or null. Each field is
  /// allowed only where the account sheet shows it: credit details on a
  /// credit card, credit line or BNPL account, a target on a goal, a maturity
  /// on a time deposit. A balance or a type is never edited here.
  String? _accountEditProblem(Map<String, Object?> i) {
    if (_dashboard == null) return 'Editing accounts is not available here.';
    final a = _ledger!.accounts.firstWhere((a) => a.id == _str(i['id']));
    if (i['balance'] != null) {
      return 'A balance never changes by an edit: it moves only through '
          'transactions. If "${a.name}" is off, ask the user what money is '
          'missing and log it with logTransactions (or payCredit for a card '
          'payment).';
    }
    if (i['category'] != null || i['type'] != null) {
      return 'The type of an account cannot change from chat. Ask the user '
          'to change it in Accounts.';
    }
    String notOn(String what, String only) =>
        '"${a.name}" has no $what: only $only has one. Tell the user.';
    const credit = 'a credit card, credit line or BNPL account';
    if (i['creditLimit'] != null) {
      if (!a.isLiability) return notOn('credit limit', credit);
      if (_amountOrNull(i['creditLimit']) == null) {
        return 'The credit limit must be an amount in pesos above zero.';
      }
    }
    for (final (key, what) in const [
      ('statementDay', 'statement day'),
      ('paymentDueDay', 'payment due day'),
    ]) {
      if (i[key] == null) continue;
      if (!a.isLiability) return notOn(what, credit);
      final day = _numOrNull(i[key]);
      if (day == null || day != day.roundToDouble() || day < 1 || day > 28) {
        return 'The $what must be a whole day of the month from 1 to 28, '
            'the days the account sheet offers.';
      }
    }
    if (i['goalTarget'] != null) {
      if (a.category != AccountCategory.goal) {
        return notOn('goal target', 'a goal account');
      }
      if (_amountOrNull(i['goalTarget']) == null) {
        return 'The goal target must be an amount in pesos above zero.';
      }
    }
    if (i['maturityDate'] != null) {
      if (a.category != AccountCategory.timeDeposit) {
        return notOn('maturity date', 'a time deposit');
      }
      final raw = _str(i['maturityDate']);
      final date = DateTime.tryParse(raw);
      if (date == null) {
        return 'The maturity date must be YYYY-MM-DD, not "$raw".';
      }
      final now = DateTime.now();
      if (DateTime(date.year, date.month, date.day)
          .isBefore(DateTime(now.year, now.month, now.day))) {
        return 'The maturity date $raw is in the past. A maturity date is '
            'today or later: check it with the user.';
      }
    }
    if (_accountEdit(i)!.rows.isEmpty) {
      return 'That changes nothing on "${a.name}": no field was given, or '
          'each one already has that value. Tell the user.';
    }
    return null;
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

  /// The `bills` list of a `markBillsPaid` call, in call order: each an id
  /// and the amount the model gave, if any. An item that is a bare string is
  /// read as an id.
  static List<({String id, double? amount})> _bulkBills(
      Map<String, Object?> i) {
    final raw = i['bills'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          (id: _str(e['id']), amount: _amountOrNull(e['paidAmount']))
        else
          (id: _str(e), amount: null),
    ];
  }

  /// A `markBillsPaid` call bound against the live bills and accounts. The
  /// row is drawn from it and the write passes its amounts, account and date
  /// to the presenter, so what the user approved is what is saved. Null when
  /// an id is unknown or no bill is listed.
  _BulkSettlement? _bulkSettlement(Map<String, Object?> i) {
    final items = <({Bill bill, double amount})>[];
    for (final e in _bulkBills(i)) {
      final bill = _bills.allBills.where((b) => b.id == e.id).firstOrNull;
      if (bill == null) return null;
      items.add((
        bill: bill,
        amount: e.amount ?? _bills.unpaidPortionOf(bill),
      ));
    }
    if (items.isEmpty) return null;
    final date = _settleDate(i['paidDate']);
    // One account pays the lot, so it must be one the presenter accepts for
    // every bill: a card statement is never paid from a card.
    final eligible = _bills
        .payerAccountsForAll(items.map((x) => x.bill))
        .map((a) => a.id)
        .toSet();
    final named = _str(i['account']);
    final shared = items.map((x) => x.bill.accountId).toSet();
    final from = named.isNotEmpty
        ? _accountFor(named)
        : shared.length == 1
            ? _activeAccounts
                .where((a) =>
                    a.id == shared.single &&
                    !a.isLiability &&
                    eligible.contains(a.id))
                .firstOrNull
            : null;
    final found = <String, String>{};
    for (final x in items) {
      final match = _ledgerMatch(
        type: TransactionType.outflow,
        amount: x.amount,
        months: {x.bill.month, toMonthKey(date)},
        name: x.bill.name,
      );
      if (match != null) found[x.bill.id] = _matchLabel(match);
    }
    final allFound = found.length == items.length;
    final payable = from != null && eligible.contains(from.id);
    return _BulkSettlement(
      items: items,
      account: from,
      accountPaysAll: payable,
      date: date,
      found: found,
      choice: LedgerEntryChoice(
        alreadyLogged: i['alreadyLogged'] == true || allFound,
        canRecord: payable,
        match: allFound ? found.values.join('; ') : null,
      ),
    );
  }

  /// What became of [before] after a batch payment, for the result: nothing
  /// when it is paid, else whether it moved at all.
  String _bulkOutcome(Bill before) {
    final after = _bills.allBills.where((b) => b.id == before.id).firstOrNull;
    if (after == null) return ' (not found after saving)';
    if (after.isPaid) return '';
    return (after.paidAmount ?? 0) > (before.paidAmount ?? 0)
        ? ' (part paid; still open)'
        : ' (not saved)';
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

  // ── Undoing a settlement ──────────────────────────────────────────────────

  /// Every ledger record an undo deletes: the settlement's own entries and
  /// the other leg of any transfer among them, since
  /// [LedgerPresenter.deleteTransactionOrGroup] takes both legs.
  List<TransactionRecord> _undoneEntries(List<TransactionRecord> entries) {
    final groups = {
      for (final t in entries)
        if (t.transferGroupId != null) t.transferGroupId
    };
    final gone = {for (final t in entries) t.id: t};
    for (final t in _ledger?.allTransactions ?? const <TransactionRecord>[]) {
      if (groups.contains(t.transferGroupId)) gone[t.id] = t;
    }
    return gone.values.toList();
  }

  /// The row's lines for what an undo deletes from the ledger.
  List<({String label, String value})> _undoRows(
          List<TransactionRecord> gone) =>
      gone.isEmpty
          ? const [
              (
                label: 'Ledger',
                value: 'No ledger entry to delete; balances stay as they are',
              ),
            ]
          : [for (final t in gone) (label: 'Deletes', value: _entryLabel(t))];

  String _entryLabel(TransactionRecord t) =>
      '"${t.description}" ${_peso(t.amount)} '
      '${t.type == TransactionType.inflow ? 'into' : 'out of'} '
      '${_accountName(t.accountId)}, ${_day(t.date)}';

  String _undoneSummary(List<TransactionRecord> gone) => gone.isEmpty
      ? '; no ledger entry was deleted'
      : '; deleted from the ledger: ${gone.map(_entryLabel).join('; ')}';

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
      case 'addCategory':
        return _newCategoryProblem(i);
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
      case 'markBillsPaid':
        final listed = _bulkBills(i);
        if (listed.length < 2) {
          return 'markBillsPaid is for two or more bills. For one bill call '
              'markBillPaid with its id.';
        }
        final ids = [for (final e in listed) e.id];
        final targets = [
          for (final id in ids.toSet())
            _bills.allBills.firstWhere((b) => b.id == id)
        ];
        String names(Iterable<Bill> bs) =>
            bs.map((b) => '"${b.name}"').join(', ');
        final twice = targets
            .where((b) => ids.where((id) => id == b.id).length > 1)
            .toList();
        if (twice.isNotEmpty) {
          return '${names(twice)} is listed more than once. List each bill '
              'once, with the amount paid on it.';
        }
        final paid = targets.where((b) => b.isPaid).toList();
        if (paid.isNotEmpty) {
          return '${names(paid)} ${paid.length == 1 ? 'is' : 'are'} already '
              'marked paid. Leave ${paid.length == 1 ? 'it' : 'them'} out and '
              'tell the user.';
        }
        final bad = check('account', active, 'active');
        if (bad != null) return bad;
        final s = _bulkSettlement(i)!;
        final from = s.account;
        if (from != null && !s.accountPaysAll) {
          final cannot = targets.where(
              (b) => !_bills.payerAccountsFor(b).any((a) => a.id == from.id));
          return '${from.name} cannot pay ${names(cannot)}: a card statement '
              'is paid from a bank, e-wallet or cash account. Ask the user '
              'which account paid them.';
        }
        if (s.choice.alreadyLogged || s.choice.canRecord) return null;
        return 'Which account paid these bills? Choices: ${list(active)}. Ask '
            'the user. If they already logged these payments in the Ledger, '
            'call again with alreadyLogged true instead.';
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
      case 'setBudget':
        return _newBudget(i).error;
      case 'editBudget':
        return _budgetEdit(i).error;
      case 'removeBudget':
        return _budget == null ? 'Budgets are not available here.' : null;
      case 'markInstallmentMonthPaid':
        return _monthPaymentProblem(i);
      case 'editInstallment':
        return _installmentEdit(i).error;
      case 'markBillUnpaid':
        final bill = _bills.allBills.firstWhere((b) => b.id == _str(i['id']));
        if (!_bills.billHasPayment(bill)) {
          return 'The bill "${bill.name}" is not paid, so there is no payment '
              'to undo. Nothing to change — tell the user.';
        }
        return null;
      case 'markReceivableNotReceived':
        final rec =
            _bills.allReceivables.firstWhere((r) => r.id == _str(i['id']));
        if (!rec.isReceived) {
          return 'The receivable "${rec.name}" is not marked received, so '
              'there is nothing to undo. Nothing to change — tell the user.';
        }
        return null;
      case 'editBill':
        return _categoryProblem(i);
      case 'editAccount':
        return _accountEditProblem(i);
      case 'editReceivable':
        return check('account', active, 'active');
      case 'editSetAside':
        return check('destinationAccount', active, 'active');
      case 'fundSetAside':
        final e =
            _bills.allBudgetedExpenses.firstWhere((e) => e.id == _str(i['id']));
        if (e.isPaid) {
          return 'The set-aside "${e.name}" is already funded '
              '(${_peso(e.spentAmount)}). Nothing to change — tell the user.';
        }
        final bad = check('fromAccount', active, 'active') ??
            check('intoAccount', active, 'active');
        if (bad != null) return bad;
        final f = _setAsideFunding(i)!;
        if (f.from == null) {
          return 'Which account does the money for "${e.name}" come from? '
              'Choices: ${active.map((a) => '"${a.name}"').join(', ')}. Ask '
              'the user.';
        }
        if (f.into == null &&
            e.budgetedType != SetAsideType.gift &&
            e.budgetedType != SetAsideType.other) {
          return '"${e.name}" is ${e.budgetedType.name} money, so it moves '
              'into a savings or goal account, but none is set. Ask the user '
              'which account it goes into.';
        }
        if (f.into != null && f.into!.id == f.from!.id) {
          return 'The money cannot move from ${f.from!.name} into itself. Ask '
              'the user which account it goes into.';
        }
        return null;
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
    if (call.name == 'markBillsPaid') {
      final missing = [
        for (final e in _bulkBills(call.input))
          if (!_bills.allBills.any((b) => b.id == e.id)) '"${e.id}"'
      ];
      if (missing.isEmpty) return null;
      return 'No bill has the id ${missing.join(', ')}. Call find (entity '
          'bill) and use ids from its result — never ones you made up. If a '
          'bill is not there, tell the user you could not find it.';
    }
    final id = _str(call.input['id']);
    final (String kind, String finder, bool exists) = switch (call.name) {
      'markBillPaid' || 'markBillUnpaid' || 'editBill' || 'deleteBill' => (
          'bill',
          'find (entity bill)',
          _bills.allBills.any((b) => b.id == id),
        ),
      'markReceivableReceived' ||
      'markReceivableNotReceived' ||
      'editReceivable' ||
      'deleteReceivable' =>
        (
          'receivable',
          'find (entity receivable)',
          _bills.allReceivables.any((r) => r.id == id),
        ),
      'editSetAside' || 'deleteSetAside' || 'fundSetAside' => (
          'set-aside',
          'find (entity setAside)',
          _bills.allBudgetedExpenses.any((e) => e.id == id),
        ),
      'editBudget' || 'removeBudget' => (
          'budget',
          'find (entity budget)',
          // No presenter: let the tool say budgets are unavailable.
          _budget == null || _budgetById(call.input) != null,
        ),
      'markInstallmentMonthPaid' || 'editInstallment' => (
          'installment',
          'find (entity installment)',
          // No presenter: let the tool say installments are unavailable.
          _installments?.findById(id) != null || _installments == null,
        ),
      'editAccount' => (
          'account',
          'find (entity account)',
          _ledger?.accounts.any((a) => a.id == id) ?? false,
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
    if (name.isEmpty || _categoryLabel(name) != null) return null;
    final names = _categories.map((c) => '"${c.name}"').join(', ');
    return 'No category is named "$name". Categories: $names. Use one of '
        'these names, or leave the category out. If the user wants a new '
        'category, call addCategory for it in this same reply, BEFORE the '
        'rows that use it: the user approves it in the same list.';
  }

  /// Why an `addCategory` call cannot be shown, or null. A name that already
  /// exists, in any case, is refused and named: two categories the user
  /// cannot tell apart split their spending.
  String? _newCategoryProblem(Map<String, Object?> i) {
    if (_ledger == null) return 'Adding categories is not available here.';
    final name = _str(i['name']);
    if (name.isEmpty) {
      return 'A category needs a name, e.g. "Pets". Ask the user.';
    }
    final type = _str(i['type']);
    if (type != 'expense' && type != 'income') {
      return 'The type must be "expense" or "income". Ask the user which.';
    }
    final lower = name.toLowerCase();
    final same =
        _categories.where((c) => c.name.toLowerCase() == lower).firstOrNull;
    if (same != null) {
      return 'A category named "${same.name}" already exists '
          '(${same.type.name}), so it was not added again. Use "${same.name}" '
          'instead, and tell the user.';
    }
    if (_newCategories[lower] case final earlier?) {
      return '"$earlier" is already added earlier in this list. Add each '
          'category once.';
    }
    return null;
  }

  /// The names of the categories that the `addCategory` rows of [actions]
  /// add, by lower-case name.
  Map<String, String> _addedCategoriesIn(
          Iterable<PendingFinanceAction> actions) =>
      {
        for (final a in actions)
          if (a.call.name == 'addCategory')
            _str(a.call.input['name']).toLowerCase():
                _str(a.call.input['name']),
      };

  static const String _newMark = ' (new, added in this list)';

  /// What a row shows for category [name]: the saved category it binds to,
  /// a category an earlier row of the batch adds (marked new), or null.
  String? _categoryLabel(String name) {
    if (_categoryFor(name) case final c?) return c.name;
    if (_newCategories[name.toLowerCase()] case final added?) {
      return '$added$_newMark';
    }
    return null;
  }

  /// The id of the saved category [name] names, for a write. Throws when it
  /// names none, rather than saving the row with no category: a name was
  /// checked when its row was shown, so a miss here means a category this
  /// batch added was not saved.
  String _savedCategoryId(String name) =>
      _categoryFor(name)?.id ??
      (throw StateError('Category "$name" is not saved'));

  static CategoryType _categoryType(Object? raw) =>
      _str(raw) == 'income' ? CategoryType.income : CategoryType.expense;

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

  FinanceCategory? _categoryFor(String name) {
    if (name.isEmpty) return null;
    final lower = name.toLowerCase();
    final categories = _categories;
    for (final c in categories) {
      if (c.name.toLowerCase() == lower) return c;
    }
    // A category an earlier row adds is that category, even before it is
    // saved: never a longer saved name that merely starts with it.
    if (_newCategories.containsKey(lower)) return null;
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

/// A `markBillsPaid` call bound against the live bills and accounts. Both
/// the row and the write are drawn from one.
class _BulkSettlement {
  const _BulkSettlement({
    required this.items,
    required this.account,
    required this.accountPaysAll,
    required this.date,
    required this.found,
    required this.choice,
  });

  /// Each bill with the amount paid on it, in call order.
  final List<({Bill bill, double amount})> items;

  /// The one account that pays them all. Null when none was named and the
  /// bills share no account that can pay every one of them.
  final FinancialAccount? account;

  /// False when [account] cannot pay one of the bills (a card statement and
  /// a card): the call is then refused before any row.
  final bool accountPaysAll;
  final DateTime date;

  /// A ledger entry that looks like each bill's payment, by bill id.
  final Map<String, String> found;
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
    required this.newCategory,
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

  /// Set when [requestedCategory] is a category an earlier row of the same
  /// batch adds; it is bound by name when the plan is saved, after that row.
  final String? newCategory;
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

/// An `editInstallment` call bound against the live plan: the plan before
/// and as it will be saved, and the ledger purchase entry that changes with
/// it. The row and the write are both drawn from one.
class _PlanEdit {
  const _PlanEdit({
    required this.before,
    required this.after,
    required this.previousDate,
    required this.purchase,
    required this.paid,
    this.newCategory,
  });

  final Installment before;
  final Installment after;

  /// The purchase date the edit is measured from.
  final DateTime previousDate;

  /// The plan's purchase entry in the ledger, or null when the plan was
  /// added on the Installments list and has none.
  final TransactionRecord? purchase;

  /// Payments already recorded. They keep their amounts.
  final int paid;

  /// The name of a category an earlier row of the list adds, when the edit
  /// moves the plan to it. Not saved yet, so [after] does not carry its id.
  final String? newCategory;

  bool get dateMoved {
    final d = after.purchaseDate!;
    return d.year != previousDate.year ||
        d.month != previousDate.month ||
        d.day != previousDate.day;
  }

  /// True when later months change: the monthly payment, the number of
  /// months or the first payment month.
  bool get schedule =>
      after.monthlyAmount != before.monthlyAmount ||
      after.totalMonths != before.totalMonths ||
      after.startMonth != before.startMonth;

  /// True when the purchase entry in the ledger changes with the plan.
  bool get recordChanges =>
      purchase != null &&
      (after.name != before.name ||
          after.totalAmount != before.totalAmount ||
          after.accountId != before.accountId ||
          dateMoved ||
          after.categoryId != before.categoryId ||
          newCategory != null ||
          after.note != before.note);

  /// T3: the edit changes later months, the ledger or the card's hold.
  bool get touchesMore =>
      schedule || recordChanges || after.accountId != before.accountId;

  bool get changesAnything =>
      touchesMore ||
      after.name != before.name ||
      after.totalAmount != before.totalAmount ||
      after.interestRate != before.interestRate ||
      after.categoryId != before.categoryId ||
      newCategory != null ||
      after.note != before.note ||
      dateMoved;
}

/// A `setBudget` call bound against the user's categories, savings accounts
/// and groups. The row and the write are both drawn from one.
class _NewBudget {
  const _NewBudget({
    required this.key,
    required this.label,
    required this.savings,
    required this.amount,
    required this.groupId,
    required this.month,
    required this.offersSetAside,
    required this.addSetAside,
  });

  /// The category id, or for a savings budget the account id it funds.
  final String key;
  final String label;
  final bool savings;
  final double amount;
  final String groupId;
  final String month;

  /// True when the row offers the matching monthly set-aside (design D8).
  final bool offersSetAside;

  /// The user ticked that offer on the row.
  final bool addSetAside;
}

/// An `editBudget` call bound against the live row: its new amount and group.
typedef _BudgetEdit = ({Budget budget, double amount, String groupId});
