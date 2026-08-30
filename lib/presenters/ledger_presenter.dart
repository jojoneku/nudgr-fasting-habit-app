import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/extracted_entry.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/receipt_parse_result.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_month_scope.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/finance_personal_dictionary.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_flows.dart';
import 'package:intermittent_fasting/utils/finance_entry_extraction.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/finance_nlp_parser.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';

/// Field the ledger list is ordered by (reference "Filter & sort" sheet).
enum LedgerSortField { date, amount }

/// Result of [LedgerPresenter.logReceiptPhoto]. `seeded` means a receipt was
/// read and the confirm-before-commit chat pipeline now holds the draft — the
/// caller closes its sheet and the inline chat panel drives confirm/clarify.
/// Every other value is a failure the caller explains to the user in place.
enum ReceiptScanOutcome {
  seeded,
  notReceipt,
  rateLimited,
  networkError,
  serverError,
  unavailable,
  failed,
}

class LedgerPresenter extends ChangeNotifier with SafeNotifier {
  LedgerPresenter(
    StorageService storage,
    StatsPresenter stats, {
    AiCoachService? ai,
    AiCoachService? cloudAi,
    FinancePersonalDictionary? financeDict,
    TreasuryMonthScope? monthScope,
  })  : _storage = storage,
        _stats = stats,
        _ai = ai,
        _cloudAi = cloudAi,
        _monthScope = monthScope,
        _financeDict = financeDict ?? FinancePersonalDictionary(storage) {
    if (monthScope != null) {
      _selectedMonth = monthScope.month;
      monthScope.addListener(_adoptScopeMonth);
    }
    load();
  }

  /// Shared "month being read" across the Treasury tabs. Null in contexts that
  /// don't share one (tests, standalone views) — then the month is private to
  /// this presenter, exactly as before.
  final TreasuryMonthScope? _monthScope;

  /// Another tab moved the shared month — follow it.
  void _adoptScopeMonth() {
    final month = _monthScope?.month;
    if (month == null || month == _selectedMonth) return;
    setMonth(month);
  }

  @override
  void dispose() {
    _monthScope?.removeListener(_adoptScopeMonth);
    super.dispose();
  }

  final StorageService _storage;
  final StatsPresenter _stats;

  /// On-device classifier (Qwen3 0.6B). Always present; may not be downloaded.
  final AiCoachService? _ai;

  /// Cloud classifier (Bedrock Haiku). Preferred when the user has Cloud AI
  /// enabled and it's reachable; otherwise the on-device tier handles the turn.
  final AiCoachService? _cloudAi;

  final FinancePersonalDictionary _financeDict;

  // Cross-presenter hooks for reimbursable expenses. Receivables are owned by
  // BillsReceivablesPresenter, so the ledger delegates create/delete of the
  // linked reimbursement receivable to it. Wired once at construction (see
  // BillsReceivablesPresenter); null in contexts without a bills presenter
  // (e.g. unit tests) — the reimbursable flag still persists on the txn.
  Future<void> Function(TransactionRecord outflow, DateTime? expectedDate)?
      onSpawnReimbursementReceivable;
  Future<void> Function(String receivableId)? onDeleteReimbursementReceivable;
  Future<void> Function(
    TransactionRecord outflow, {
    bool updateExpectedDate,
    DateTime? expectedDate,
  })? onUpdateReimbursementReceivable;

  /// Resolves the expected payback date of the receivable linked to a
  /// reimbursable expense — the date lives on the receivable, not the txn, so
  /// the edit form reads it back through here to pre-fill the picker.
  DateTime? Function(String receivableId)?
      reimbursementReceivableExpectedDateResolver;

  bool _isLoading = true;
  String _selectedMonth = toMonthKey(DateTime.now());
  // Multi-select filters — the "Filter & sort" sheet lets the user pick any
  // combination of categories and accounts. Empty set = no constraint (all).
  final Set<String> _selectedAccountIds = {};
  final Set<String> _selectedCategoryIds = {};
  // Sort applied to the transaction list (date newest/oldest, amount high/low).
  LedgerSortField _sortField = LedgerSortField.date;
  bool _sortDescending = true;
  // When true, the feed shows only outstanding reimbursable expenses — money
  // you've spent and are still owed back.
  bool _owedOnly = false;

  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];

  // ── Derived-row caches (Plan 052 P1) ────────────────────────────────────────
  // `ledgerSpreadsheetRows` reconstructs every account's balance history by
  // sorting all transactions per account — expensive, and the web grid reads it
  // on every build (the search box filters view-side via setState, so the page
  // rebuilds per keystroke without any presenter change). Cache the result and
  // clear it in [safeNotify], i.e. only when presenter state actually mutates —
  // so per-keystroke rebuilds reuse the cached rows instead of re-sorting all
  // history each character.
  List<({TransactionRecord txn, double runningBalance})>? _rowsForMonthCache;
  List<
      ({
        TransactionRecord txn,
        double runningBalance,
        double accountBalance,
      })>? _spreadsheetCache;
  List<
      ({
        TransactionRecord txn,
        double runningBalance,
        double accountBalance,
      })>? _spreadsheetAllCache;

  @override
  void safeNotify() {
    _rowsForMonthCache = null;
    _spreadsheetCache = null;
    _spreadsheetAllCache = null;
    super.safeNotify();
  }

  // ── Chat-logging state (Plan 026 — ephemeral, never persisted) ──────────────
  LedgerChatState _chatState = const LedgerChatState.idle();
  FinanceParseError? _chatHardError;
  String? _lastCommittedSummary;
  String? _lastCommitSnappedFromMonth;
  ParsedTransaction? _pendingFormPrefill;
  DateTime? _pausedAt;
  static const _staleConversationThreshold = Duration(minutes: 5);

  /// Segments of a multi-transaction message that still need a clarify turn,
  /// in written order. Filled when a batch confirm card is built and drained
  /// one at a time after the confirmed transactions are committed. Cleared
  /// whenever the user cancels or a fresh message arrives — a queue that
  /// outlived its conversation would ambush the next entry.
  List<PreparseResult> _deferredSegments = const [];

  /// Leftovers waiting for the *form*, on surfaces that have no clarify UI (the
  /// web Quick Add). [_deferredSegments] can't serve these: it drives a clarify
  /// conversation, which is exactly what those surfaces lack. Drained one at a
  /// time by [takeNextFormPrefill] as each prefilled form closes, and cleared
  /// alongside [_deferredSegments] so a queue never outlives its message.
  List<ParsedTransaction> _queuedFormPrefills = const [];

  LedgerChatState get chatState => _chatState;
  FinanceParseError? get chatHardError => _chatHardError;
  String? get lastCommittedSummary => _lastCommittedSummary;

  /// Set when the last Quick-Add commit moved the view out of the month the
  /// user was reading (Quick Add always dates "today"). Holds the month they
  /// were on, so the view can explain the jump instead of just doing it.
  String? get lastCommitSnappedFromMonth => _lastCommitSnappedFromMonth;
  ParsedTransaction? get pendingFormPrefill => _pendingFormPrefill;

  /// How many leftovers are still queued behind [pendingFormPrefill]. Lets a
  /// one-shot surface say "2 more need details" instead of springing a second
  /// form on the user unannounced.
  int get queuedFormPrefillCount => _queuedFormPrefills.length;

  // --- Public state ---

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;

  /// Backward-compatible single-selection accessors (web table view + tests).
  /// Return the sole selected id, or null when zero or many are selected.
  String? get selectedAccountId =>
      _selectedAccountIds.length == 1 ? _selectedAccountIds.first : null;

  /// Optional category filter applied to both the mobile transaction list
  /// ([groupedTransactions]) and the web table view. Null = all categories.
  /// Independent of the chat view, which doesn't filter by category.
  String? get selectedCategoryId =>
      _selectedCategoryIds.length == 1 ? _selectedCategoryIds.first : null;

  // Multi-select filter + sort state for the "Filter & sort" sheet.
  Set<String> get selectedAccountIds => Set.unmodifiable(_selectedAccountIds);
  Set<String> get selectedCategoryIds => Set.unmodifiable(_selectedCategoryIds);
  LedgerSortField get sortField => _sortField;
  bool get sortDescending => _sortDescending;

  /// Number of active filters (each selected category/account, the owed flag,
  /// and a single-day filter) — drives the count badge on the Filter & sort
  /// button.
  int get activeFilterCount =>
      _selectedCategoryIds.length +
      _selectedAccountIds.length +
      (_owedOnly ? 1 : 0) +
      (_selectedDate != null ? 1 : 0);

  /// True when the sort is anything other than the default newest-first date.
  bool get isCustomSort =>
      _sortField != LedgerSortField.date || !_sortDescending;
  List<FinancialAccount> get accounts => _accounts;
  List<FinanceCategory> get categories => _categories;
  List<TransactionRecord> get allTransactions =>
      List.unmodifiable(_allTransactions);

  // --- Filtered summary ---
  // These month/daily totals exclude internal transfer legs AND reimbursables/
  // loans: moving money between your own accounts (incl. paying down a credit
  // card), and money you front or lend and will get back, are neither income
  // nor spending — so they must not inflate the ledger's inflow/outflow figures.
  // A reimbursable's repayment inflow is likewise excluded from income (it's
  // your own money returning). Both still appear as rows in the list.
  // See [isSpendingOutflow] / [isIncomeInflow] in utils/finance_flows.dart.

  /// Receivable ids spawned by reimbursable/loan outflows — used to recognise
  /// (and exclude) their repayment inflows from income.
  Set<String> get _reimbursementIds =>
      reimbursementReceivableIds(_allTransactions);

  /// Category ids the user flagged to exclude from cash-flow totals.
  Set<String> get _excludedCategoryIds =>
      excludedCashFlowCategoryIds(_categories);

  double get filteredMonthInflow {
    final reimb = _reimbursementIds;
    final excluded = _excludedCategoryIds;
    return _filteredTransactions
        .where((t) => isIncomeInflow(t, reimb, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get filteredMonthOutflow {
    final excluded = _excludedCategoryIds;
    return _filteredTransactions
        .where((t) => isSpendingOutflow(t, excluded))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double get filteredMonthNet => filteredMonthInflow - filteredMonthOutflow;

  /// Map of 'yyyy-MM-dd' → total outflow for that day (respects account filter).
  Map<String, double> get dailyOutflowMap {
    final excluded = _excludedCategoryIds;
    final map = <String, double>{};
    for (final t in _filteredTransactions) {
      if (!isSpendingOutflow(t, excluded)) continue;
      final key = '${t.date.year.toString().padLeft(4, '0')}-'
          '${t.date.month.toString().padLeft(2, '0')}-'
          '${t.date.day.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + t.amount;
    }
    return map;
  }

  /// Map of 'yyyy-MM-dd' → total inflow for that day (respects account filter).
  Map<String, double> get dailyInflowMap {
    final reimb = _reimbursementIds;
    final excluded = _excludedCategoryIds;
    final map = <String, double>{};
    for (final t in _filteredTransactions) {
      if (!isIncomeInflow(t, reimb, excluded)) continue;
      final key = '${t.date.year.toString().padLeft(4, '0')}-'
          '${t.date.month.toString().padLeft(2, '0')}-'
          '${t.date.day.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + t.amount;
    }
    return map;
  }

  /// Average daily outflow for the selected month (excludes zero-spend days).
  double get averageDailyOutflow {
    final values = dailyOutflowMap.values;
    if (values.isEmpty) return 0.0; // no spend this month → genuinely ₱0
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Optional date filter — when set, [groupedTransactions] shows only that day.
  DateTime? _selectedDate;
  DateTime? get selectedDate => _selectedDate;

  void setSelectedDate(DateTime? d) {
    _selectedDate = d;
    safeNotify();
  }

  /// Steps the selected date by [delta] days. If no date is selected, anchors
  /// at today (or the 1st of the selected month if today is in a different month).
  void stepDay(int delta) {
    final anchor = _selectedDate ??
        (() {
          final now = DateTime.now();
          final monthParts = _selectedMonth.split('-');
          final y = int.parse(monthParts[0]);
          final m = int.parse(monthParts[1]);
          return (now.year == y && now.month == m) ? now : DateTime(y, m, 1);
        })();
    final next = anchor.add(Duration(days: delta));
    _selectedDate = next;
    _selectedMonth =
        '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}';
    _monthScope?.setMonth(_selectedMonth);
    safeNotify();
  }

  double get filteredAccountBalance => _accounts
      .where((a) => _selectedAccountIds.contains(a.id))
      .fold(0.0, (sum, a) => sum + a.balance);

  /// Transactions in [selectedMonth] after every active filter — accounts and
  /// categories (multi-select), the owed flag, and an optional single day. The
  /// shared base for both the grouped and flat list views.
  ///
  /// Transfers are NOT deduplicated: both legs are listed (see
  /// [_filteredTransactions]), so the destination account's increase is
  /// visible. Deleting one leg must therefore remove its partner too — that's
  /// what [deleteTransactionOrGroup] is for.
  List<TransactionRecord> get _visibleTransactions {
    var txns = _filteredTransactions;

    // Multi-select category filter (mirrors the web table view).
    if (_selectedCategoryIds.isNotEmpty) {
      txns = txns
          .where((t) => _selectedCategoryIds.contains(t.categoryId))
          .toList();
    }

    // Optional "money I'm owed" filter.
    if (_owedOnly) {
      txns = txns.where(isOutstandingReimbursable).toList();
    }

    // Optional single-day filter (from calendar tap).
    if (_selectedDate != null) {
      txns = txns
          .where((t) =>
              t.date.year == _selectedDate!.year &&
              t.date.month == _selectedDate!.month &&
              t.date.day == _selectedDate!.day)
          .toList();
    }
    return txns;
  }

  /// Day-grouped transactions honouring the date sort direction. Used when
  /// [sortField] is [LedgerSortField.date].
  Map<DateTime, List<TransactionRecord>> get groupedTransactions {
    final asc = !_sortDescending;
    final grouped = <DateTime, List<TransactionRecord>>{};
    for (final txn in _visibleTransactions) {
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      grouped.putIfAbsent(day, () => []).add(txn);
    }
    for (final list in grouped.values) {
      list.sort(
          (a, b) => asc ? a.date.compareTo(b.date) : b.date.compareTo(a.date));
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => asc ? a.compareTo(b) : b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  /// Flat transaction list sorted by the active [sortField]/[sortDescending].
  /// Used when sorting by amount (day grouping doesn't apply).
  List<TransactionRecord> get sortedTransactions {
    int cmp(TransactionRecord a, TransactionRecord b) {
      final c = switch (_sortField) {
        LedgerSortField.amount => a.amount.compareTo(b.amount),
        LedgerSortField.date => a.date.compareTo(b.date),
      };
      // Stable tiebreak on id so equal keys keep a deterministic order.
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    return [..._visibleTransactions]
      ..sort((a, b) => _sortDescending ? cmp(b, a) : cmp(a, b));
  }

  // --- Web table view (Plan 050-B) ---

  /// Detailed-records rows for the web table, scoped to [selectedMonth],
  /// [selectedAccountId], and [selectedCategoryId]. Each row carries a running
  /// balance accumulated chronologically (oldest → newest) within the current
  /// filter, then the list is returned newest-first for display.
  ///
  /// The running balance is signed by transaction direction (inflow adds,
  /// outflow subtracts) and reflects the order transactions occurred within the
  /// filtered scope — it is purely derived, never persisted.
  List<({TransactionRecord txn, double runningBalance})>
      get ledgerRowsForMonth {
    final cached = _rowsForMonthCache;
    if (cached != null) return cached;
    var txns = _filteredTransactions;
    if (_selectedCategoryIds.isNotEmpty) {
      txns = txns
          .where((t) => _selectedCategoryIds.contains(t.categoryId))
          .toList();
    }

    // Accumulate chronologically (oldest first) so the running balance reads as
    // a true ledger; stable on date then id to keep same-day order deterministic.
    final chronological = [...txns]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    final rows = <({TransactionRecord txn, double runningBalance})>[];
    var balance = 0.0;
    for (final t in chronological) {
      balance += t.type == TransactionType.inflow ? t.amount : -t.amount;
      rows.add((txn: t, runningBalance: balance));
    }

    // Display newest-first.
    return _rowsForMonthCache = rows.reversed.toList();
  }

  /// Inflow subtotal for the current table filter (month/account/category).
  /// Excludes transfer legs and reimbursable/loan repayments — neither is income.
  double get tableInflow {
    final reimb = _reimbursementIds;
    final excluded = _excludedCategoryIds;
    return ledgerRowsForMonth
        .where((r) => isIncomeInflow(r.txn, reimb, excluded))
        .fold(0.0, (sum, r) => sum + r.txn.amount);
  }

  /// Outflow subtotal for the current table filter (month/account/category).
  /// Excludes transfer legs and reimbursables/loans — neither is spending.
  double get tableOutflow {
    final excluded = _excludedCategoryIds;
    return ledgerRowsForMonth
        .where((r) => isSpendingOutflow(r.txn, excluded))
        .fold(0.0, (sum, r) => sum + r.txn.amount);
  }

  /// What was owed on liability [accountId] at the END of [asOf] (that day
  /// included), floored at zero like [FinancialAccount.currentPayable]. Zero for
  /// a missing or non-liability account.
  ///
  /// A credit statement bills the balance as of its close date, but the
  /// generator only runs when the app is next opened — which can be days later,
  /// with fresh charges already on the card. Reading the live balance then
  /// billed those charges into a cycle that had already closed.
  ///
  /// Derived by unwinding the account's CURRENT balance back across every
  /// transaction dated after [asOf] — the same technique as
  /// [_accountBalanceByTxnId], under the same sign rule as
  /// [_applyBalanceDelta], so spending on a card raises what is owed. Both legs
  /// of a card payment are separate records carrying the card's own
  /// `accountId`, so filtering on it captures payments as well as charges.
  double payableAsOf(String accountId, DateTime asOf) {
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null || !account.isLiability) return 0;
    // Start of the day after [asOf]: a transaction dated ON the close date is
    // part of the cycle that closed, not the next one.
    final cutoff = DateTime(asOf.year, asOf.month, asOf.day + 1);
    var owed = account.balance;
    for (final t in _allTransactions) {
      if (t.accountId != accountId || t.date.isBefore(cutoff)) continue;
      final base = t.type == TransactionType.inflow ? t.amount : -t.amount;
      final delta = -base; // liability: spending raises what is owed
      owed -= delta; // unwind → the balance before this transaction
    }
    return owed > 0 ? owed : 0;
  }

  /// Per-transaction account balance: the involved account's balance
  /// immediately *after* that transaction. Reconstructed by unwinding each
  /// account's CURRENT [FinancialAccount.balance] backward (newest → oldest)
  /// across every one of its transactions, so the value is correct for any
  /// month without needing a stored historical opening balance.
  ///
  /// Liability-aware: mirrors the sign rule in [_applyBalanceDelta] (spending on
  /// a card raises the owed balance). Keyed by transaction id. Purely derived,
  /// never persisted.
  Map<String, double> get _accountBalanceByTxnId {
    final byAccount = <String, List<TransactionRecord>>{};
    for (final t in _allTransactions) {
      byAccount.putIfAbsent(t.accountId, () => []).add(t);
    }
    final map = <String, double>{};
    for (final entry in byAccount.entries) {
      final account = _accounts.where((a) => a.id == entry.key).firstOrNull;
      final isLiability = account?.isLiability ?? false;
      // Newest first; stable on id for deterministic same-instant ordering.
      final txns = [...entry.value]..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate != 0 ? byDate : b.id.compareTo(a.id);
        });
      var running = account?.balance ?? 0.0;
      for (final t in txns) {
        map[t.id] = running; // balance AFTER this transaction
        final base = t.type == TransactionType.inflow ? t.amount : -t.amount;
        final delta = isLiability ? -base : base;
        running -= delta; // unwind → balance before, for the next older txn
      }
    }
    return map;
  }

  /// Rows for the web spreadsheet view: every [ledgerRowsForMonth] row enriched
  /// with the involved account's post-transaction balance. The View applies
  /// transient filters/sorts on top — running balances stay stable regardless,
  /// matching the reference design.
  List<
      ({
        TransactionRecord txn,
        double runningBalance,
        double accountBalance,
      })> get ledgerSpreadsheetRows {
    final cached = _spreadsheetCache;
    if (cached != null) return cached;
    final acctMap = _accountBalanceByTxnId;
    return _spreadsheetCache = [
      for (final r in ledgerRowsForMonth)
        (
          txn: r.txn,
          runningBalance: r.runningBalance,
          accountBalance: acctMap[r.txn.id] ?? 0.0,
        ),
    ];
  }

  /// The same rows as [ledgerSpreadsheetRows] but over ALL history rather than
  /// the selected month.
  ///
  /// The web grid reads this whenever a cross-month filter is active (a search
  /// term, or a date range). Searching "Netflix" or asking for May→July while
  /// scoped to one month returned an empty grid, which read as "you have no
  /// such transactions" rather than "your filter can't see them".
  List<
      ({
        TransactionRecord txn,
        double runningBalance,
        double accountBalance,
      })> get ledgerSpreadsheetRowsAllMonths {
    final cached = _spreadsheetAllCache;
    if (cached != null) return cached;
    final acctMap = _accountBalanceByTxnId;

    // Same accumulation rule as ledgerRowsForMonth: chronological for the
    // running balance, displayed newest-first.
    final chronological = [..._allTransactions]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final rows = <({
      TransactionRecord txn,
      double runningBalance,
      double accountBalance,
    })>[];
    var balance = 0.0;
    for (final t in chronological) {
      balance += t.type == TransactionType.inflow ? t.amount : -t.amount;
      rows.add((
        txn: t,
        runningBalance: balance,
        accountBalance: acctMap[t.id] ?? 0.0,
      ));
    }
    return _spreadsheetAllCache = rows.reversed.toList();
  }

  // --- Filter controls ---

  void setMonth(String month) {
    _selectedMonth = month;
    _selectedDate = null; // clear day filter when navigating months
    _monthScope?.setMonth(month); // keep Bills/Budget/Installments in step
    safeNotify();
  }

  /// Backward-compatible single setter (web + tests): selects exactly [id], or
  /// clears the account filter when null.
  void setAccount(String? id) {
    _selectedAccountIds.clear();
    if (id != null) _selectedAccountIds.add(id);
    safeNotify();
  }

  /// Sets the active category filter to exactly [id]. Null clears it.
  void setCategoryFilter(String? id) {
    _selectedCategoryIds.clear();
    if (id != null) _selectedCategoryIds.add(id);
    safeNotify();
  }

  /// Toggles a category in the multi-select filter.
  void toggleCategoryFilter(String id) {
    if (!_selectedCategoryIds.remove(id)) _selectedCategoryIds.add(id);
    safeNotify();
  }

  /// Toggles an account in the multi-select filter.
  void toggleAccountFilter(String id) {
    if (!_selectedAccountIds.remove(id)) _selectedAccountIds.add(id);
    safeNotify();
  }

  /// Sets the list sort field and direction.
  void setSort(LedgerSortField field, {required bool descending}) {
    _sortField = field;
    _sortDescending = descending;
    safeNotify();
  }

  /// Clears all filters (categories, accounts, owed, day); leaves sort untouched.
  void clearAllFilters() {
    _selectedCategoryIds.clear();
    _selectedAccountIds.clear();
    _owedOnly = false;
    _selectedDate = null;
    safeNotify();
  }

  bool get owedOnly => _owedOnly;

  /// Toggles the "money I'm owed" filter — shows only outstanding reimbursable
  /// expenses (spent, not yet paid back).
  void setOwedFilter(bool value) {
    _owedOnly = value;
    safeNotify();
  }

  /// Reimbursement receivable ids that already have a settling inflow leg, i.e.
  /// the payback has landed. Derived purely from the transaction list.
  Set<String> get _settledReimbursementIds => {
        for (final t in _allTransactions)
          if (t.type == TransactionType.inflow && t.receivableId != null)
            t.receivableId!,
      };

  /// Authoritative set of reimbursement-receivable ids that are still
  /// outstanding (the linked receivable exists and hasn't been received).
  /// Pushed by [BillsReceivablesPresenter] via [setOutstandingReimbursementIds]
  /// whenever receivable state changes. Null until first pushed — in that state
  /// (no bills presenter, e.g. tests or a standalone ledger) the ledger falls
  /// back to inferring settlement from payback inflow legs.
  Set<String>? _outstandingReimbursementIds;

  /// Wired by [BillsReceivablesPresenter] so "owed to you" reflects the real
  /// receivable state (received, partially paid back, deleted, or never
  /// created) instead of guessing from transaction inflow legs.
  void setOutstandingReimbursementIds(Set<String> ids) {
    _outstandingReimbursementIds = ids;
    safeNotify();
  }

  /// A reimbursable outflow still awaiting payback.
  ///
  /// When the authoritative receivable set is available, an expense counts as
  /// owed only while a linked, unreceived receivable exists for it — so an
  /// expense with no receivable (never created, or since deleted) reads as
  /// already settled, and one whose receivable was marked received drops off
  /// even if the payback was recorded outside the ledger. Without that set
  /// (no bills presenter) it falls back to inferring settlement from the
  /// presence of a payback inflow leg.
  bool isOutstandingReimbursable(TransactionRecord t) {
    if (!t.reimbursable || t.type != TransactionType.outflow) return false;
    if (t.transferGroupId != null) return false;
    final receivableId = t.reimbursementReceivableId;
    final outstanding = _outstandingReimbursementIds;
    if (outstanding != null) {
      return receivableId != null && outstanding.contains(receivableId);
    }
    return receivableId == null ||
        !_settledReimbursementIds.contains(receivableId);
  }

  /// Total still owed to you this month across outstanding reimbursables.
  double get outstandingOwedTotal => _allTransactions
      .where((t) => t.month == _selectedMonth && isOutstandingReimbursable(t))
      .fold(0.0, (sum, t) => sum + t.amount);

  bool get hasOutstandingOwed => outstandingOwedTotal > 0;

  /// Refreshes the account list from storage. Call this before showing any
  /// sheet that needs accounts — TreasuryDashboardPresenter may have added
  /// or removed accounts since LedgerPresenter last loaded.
  Future<void> reloadAccounts() async {
    _accounts = await _storage.loadAccounts();
    safeNotify();
  }

  // --- Load ---

  bool _hasLoaded = false;

  Future<void> load() async {
    // After the first load this presenter is long-lived and already holds the
    // data. Re-entrant calls (e.g. switching back to the Ledger tab) do a silent
    // background refresh — no loading spinner, and skip the one-time dictionary
    // init + category migration — so the page stays on screen and just updates
    // in place. Flipping `_isLoading` here is what made tab-switching feel slow.
    if (_hasLoaded) {
      _accounts = await _storage.loadAccounts();
      _categories = await _storage.loadFinanceCategories();
      _allTransactions = await _storage.loadTransactions();
      safeNotify();
      return;
    }

    _isLoading = true;
    safeNotify();

    _accounts = await _storage.loadAccounts();
    _categories = await _storage.loadFinanceCategories();
    _allTransactions = await _storage.loadTransactions();
    await _financeDict.init();

    // One-time migration: reassign any category that still has the old
    // white default (#FFFFFF / near-white luminance > 0.65) to a palette color.
    final migrated = _migrateCategories(_categories);
    if (migrated != null) {
      _categories = migrated;
      await _storage.saveFinanceCategories(_categories);
    }

    await _migrateTransferLegCategories();
    await _migrateTransferInflowPartners();

    _isLoading = false;
    _hasLoaded = true;
    safeNotify();
  }

  /// One-time backfill for the dedicated-transfer-category change. Earlier
  /// builds stamped transfer legs with the first expense category (or an empty
  /// id); re-point every transfer leg at the reserved transfer category so the
  /// stored data is semantically correct and no longer depends on the
  /// `transferGroupId` guard to stay out of spend totals. Idempotent: once every
  /// leg references the transfer id there is nothing left to change.
  Future<void> _migrateTransferLegCategories() async {
    final hasStrayLeg = _allTransactions.any((t) =>
        t.transferGroupId != null &&
        t.categoryId != FinanceCategory.transferCategoryId);
    if (!hasStrayLeg) return;

    final transferId = await _ensureTransferCategory();
    _allTransactions = [
      for (final t in _allTransactions)
        if (t.transferGroupId != null && t.categoryId != transferId)
          t.copyWith(categoryId: transferId)
        else
          t,
    ];
    await _saveAll();
  }

  /// Back-fills transferToAccountId on inflow legs that were created before the
  /// fix that stores it symmetrically. Without this, legacy inflow rows in the
  /// web ledger display "— → AccountB" instead of "AccountA → AccountB".
  /// Idempotent: stops as soon as no stray legs remain.
  Future<void> _migrateTransferInflowPartners() async {
    final hasStrayInflow = _allTransactions.any((t) =>
        t.transferGroupId != null &&
        t.type == TransactionType.inflow &&
        t.transferToAccountId == null);
    if (!hasStrayInflow) return;

    // Build a groupId → outflow-accountId lookup in one pass.
    final fromById = <String, String>{};
    for (final t in _allTransactions) {
      if (t.transferGroupId != null && t.type == TransactionType.outflow) {
        fromById[t.transferGroupId!] = t.accountId;
      }
    }

    _allTransactions = [
      for (final t in _allTransactions)
        if (t.transferGroupId != null &&
            t.type == TransactionType.inflow &&
            t.transferToAccountId == null &&
            fromById.containsKey(t.transferGroupId))
          t.copyWith(transferToAccountId: fromById[t.transferGroupId!])
        else
          t,
    ];
    await _saveAll();
  }

  /// Returns a new list with corrected colors if any category needed migration,
  /// or null if everything was already fine.
  List<FinanceCategory>? _migrateCategories(List<FinanceCategory> cats) {
    bool anyChanged = false;
    int expenseIdx = 0;
    int incomeIdx = 0;

    final result = cats.map((cat) {
      if (!isDefaultWhite(cat.colorHex)) return cat;

      anyChanged = true;
      final isExpense = cat.type == CategoryType.expense;
      final idx = isExpense ? expenseIdx++ : incomeIdx++;
      return cat.copyWith(colorHex: categoryColorAt(idx, isExpense: isExpense));
    }).toList();

    return anyChanged ? result : null;
  }

  // --- Transaction CRUD ---

  Future<void> addTransaction(TransactionRecord txn) async {
    final isFirstEver = _allTransactions.isEmpty;
    final isFirstToday = !_hasTransactionToday();

    _allTransactions = [..._allTransactions, txn];
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    // Optimistic: repaint with the new transaction before the encode+write.
    safeNotify();
    await _saveAll();

    if (isFirstEver) await _stats.addXp(25);
    if (isFirstToday) await _stats.addXp(10);
  }

  /// Re-adds a [txn] that was just removed via [deleteTransaction] (an Undo),
  /// restoring its linked reimbursement receivable too — otherwise undoing a
  /// reimbursable-expense delete brings the expense back but silently drops the
  /// "owed to you" tracking. Awards no XP: restoring isn't a fresh log.
  Future<void> restoreTransaction(TransactionRecord txn) async {
    _allTransactions = [..._allTransactions, txn];
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    safeNotify();
    await _saveAll();
    if (txn.reimbursable &&
        txn.type == TransactionType.outflow &&
        txn.reimbursementReceivableId != null) {
      // Re-spawn with no set date so it resurfaces immediately (the original
      // expected date didn't survive the delete); the id is reused, keeping
      // the expense↔receivable link intact.
      await spawnReimbursementReceivable(txn, null);
    }
  }

  /// Re-adds every record in [txns] — the Undo counterpart of
  /// [deleteTransactionOrGroup], which may have removed both legs of a
  /// transfer. Restoring the legs one at a time through [restoreTransaction]
  /// would work too, but this persists once instead of per leg.
  Future<void> restoreTransactions(List<TransactionRecord> txns) async {
    if (txns.isEmpty) return;
    if (txns.length == 1) return restoreTransaction(txns.first);
    _allTransactions = [..._allTransactions, ...txns];
    for (final txn in txns) {
      _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    }
    safeNotify();
    await _saveAll();
    for (final txn in txns) {
      if (txn.reimbursable &&
          txn.type == TransactionType.outflow &&
          txn.reimbursementReceivableId != null) {
        await spawnReimbursementReceivable(txn, null);
      }
    }
  }

  /// Logs a reimbursable outflow — money you spent but expect to recover (e.g.
  /// a work expense). [outflow] must already carry `reimbursable: true` and a
  /// pre-generated `reimbursementReceivableId`. The outflow is persisted as a
  /// normal expense (so it still counts in headline Expenses) and, when a bills
  /// presenter is wired, a linked ReceivableType.reimbursement is spawned for
  /// the expected payback.
  Future<void> addReimbursableExpense(
    TransactionRecord outflow, {
    required DateTime? expectedReimbursementDate,
  }) async {
    await addTransaction(outflow);
    await spawnReimbursementReceivable(outflow, expectedReimbursementDate);
  }

  /// Spawns the reimbursement receivable for an already-persisted [outflow].
  /// [expectedDate] is null for "ASAP / no set date". No-op when no bills
  /// presenter is wired.
  Future<void> spawnReimbursementReceivable(
    TransactionRecord outflow,
    DateTime? expectedDate,
  ) async {
    final spawn = onSpawnReimbursementReceivable;
    if (spawn != null) await spawn(outflow, expectedDate);
  }

  /// Deletes a reimbursement receivable by id (used when a reimbursable expense
  /// is un-flagged or removed). No-op when no bills presenter is wired.
  Future<void> deleteReimbursementReceivable(String receivableId) async {
    final remove = onDeleteReimbursementReceivable;
    if (remove != null) await remove(receivableId);
  }

  /// Re-syncs the linked receivable's amount/name after a reimbursable [outflow]
  /// is edited. No-op when no bills presenter is wired.
  ///
  /// Pass [updateExpectedDate] true (from the edit form) to also write the
  /// user's chosen [expectedDate] — null meaning "ASAP" — so the payback date
  /// can be changed. Amount-only callers (e.g. inline grid edits) leave it
  /// false so the existing schedule is untouched.
  Future<void> syncReimbursementReceivable(
    TransactionRecord outflow, {
    bool updateExpectedDate = false,
    DateTime? expectedDate,
  }) async {
    final sync = onUpdateReimbursementReceivable;
    if (sync != null) {
      await sync(outflow,
          updateExpectedDate: updateExpectedDate, expectedDate: expectedDate);
    }
  }

  /// Expected payback date of the receivable linked to a reimbursable expense,
  /// or null when unset ("ASAP") / no bills presenter is wired. The edit form
  /// uses this to pre-fill the date the transaction record itself doesn't store.
  DateTime? reimbursementReceivableExpectedDate(String receivableId) =>
      reimbursementReceivableExpectedDateResolver?.call(receivableId);

  /// Books a transfer as two linked legs. [billId] stamps both legs with the
  /// bill they settle — a liability statement is paid via transfer, so without
  /// the back-link the payment was untraceable from the bill and undoing one
  /// could not find the ledger entries to unwind.
  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String description,
    required DateTime date,
    String? note,
    String? billId,
  }) async {
    final groupId = _generateId();
    final monthKey = toMonthKey(date);
    // Both legs carry the reserved transfer category — a transfer is neither an
    // expense nor income, so it must never be stamped with a real category.
    final categoryId = await _ensureTransferCategory();

    final outflow = TransactionRecord(
      id: _generateId(),
      date: date,
      accountId: fromAccountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.outflow,
      description: description,
      note: note,
      month: monthKey,
      transferToAccountId: toAccountId,
      transferGroupId: groupId,
      billId: billId,
    );
    final inflow = TransactionRecord(
      id: _generateId(),
      date: date,
      accountId: toAccountId,
      categoryId: categoryId,
      amount: amount,
      type: TransactionType.inflow,
      description: description,
      note: note,
      month: monthKey,
      transferToAccountId: fromAccountId,
      transferGroupId: groupId,
      billId: billId,
    );

    _allTransactions = [..._allTransactions, outflow, inflow];
    _applyBalanceDelta(fromAccountId, amount, TransactionType.outflow);
    _applyBalanceDelta(toAccountId, amount, TransactionType.inflow);
    safeNotify();
    await _saveAll();
  }

  Future<void> updateTransaction(TransactionRecord txn) async {
    // Guard against a vanished id (reachable via fast successive inline edits
    // or an interleaved delete) — `firstWhere` would otherwise throw. (C9)
    final old = _allTransactions.where((t) => t.id == txn.id).firstOrNull;
    if (old == null) return;
    _reverseBalanceDelta(old.accountId, old.amount, old.type);
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = [
      for (final t in _allTransactions) t.id == txn.id ? txn : t,
    ];
    safeNotify();
    await _saveAll();
    // Keep a linked reimbursement receivable in step with edits that bypass the
    // add/edit form — notably the web grid's inline cell edits, which call
    // updateTransaction directly. Without this, correcting a reimbursable's
    // amount inline leaves "owed to you" stuck at the old figure. Form paths
    // also call syncReimbursementReceivable themselves; a double-sync is
    // idempotent. If the edit flipped it away from a reimbursable outflow,
    // retire the now-orphaned receivable instead.
    if (txn.reimbursable &&
        txn.type == TransactionType.outflow &&
        txn.reimbursementReceivableId != null) {
      await syncReimbursementReceivable(txn);
    } else if (old.reimbursable && old.reimbursementReceivableId != null) {
      await deleteReimbursementReceivable(old.reimbursementReceivableId!);
    }
  }

  Future<void> deleteTransaction(String id) async {
    final txn = _allTransactions.where((t) => t.id == id).firstOrNull;
    if (txn == null) return; // already gone — no-op (C9)
    _reverseBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = _allTransactions.where((t) => t.id != id).toList();
    safeNotify();
    await _saveAll();
    // Tidy up the linked reimbursement receivable so deleting the expense
    // doesn't leave an orphaned "you're owed" entry behind.
    final receivableId = txn.reimbursementReceivableId;
    if (receivableId != null) {
      await deleteReimbursementReceivable(receivableId);
    }
  }

  /// Deletes a transaction; if it belongs to a transfer pair, removes BOTH legs
  /// so the two accounts unwind cleanly and neither side is left orphaned.
  ///
  /// Returns every record actually removed, so an Undo can put the whole set
  /// back via [restoreTransactions] — restoring only the swiped leg would leave
  /// the partner missing and the two account balances out of step.
  Future<List<TransactionRecord>> deleteTransactionOrGroup(String id) async {
    final txn = _allTransactions.where((t) => t.id == id).firstOrNull;
    if (txn == null) return const [];
    final groupId = txn.transferGroupId;
    if (groupId == null) {
      await deleteTransaction(id);
      return [txn];
    }
    final legs = _allTransactions
        .where((t) => t.transferGroupId == groupId)
        .toList(growable: false);
    for (final leg in legs) {
      _reverseBalanceDelta(leg.accountId, leg.amount, leg.type);
    }
    _allTransactions =
        _allTransactions.where((t) => t.transferGroupId != groupId).toList();
    safeNotify();
    await _saveAll();
    return legs;
  }

  /// Bulk-deletes the given transaction ids in ONE mutation + ONE persist,
  /// instead of N fire-and-forget calls each doing a full-list write. Transfer
  /// pairs are expanded so both legs go (matches [deleteTransactionOrGroup]).
  /// (Plan 052 C8)
  ///
  /// Returns every record removed so an Undo can restore the exact set via
  /// [restoreTransactions] — including transfer partners the caller never
  /// selected.
  Future<List<TransactionRecord>> deleteTransactions(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    // Expand any transfer legs whose partner is in the selection set.
    final groupIds = _allTransactions
        .where((t) => ids.contains(t.id) && t.transferGroupId != null)
        .map((t) => t.transferGroupId)
        .toSet();
    final toRemove = _allTransactions
        .where((t) =>
            ids.contains(t.id) ||
            (t.transferGroupId != null && groupIds.contains(t.transferGroupId)))
        .toList();
    if (toRemove.isEmpty) return const [];
    for (final t in toRemove) {
      _reverseBalanceDelta(t.accountId, t.amount, t.type);
    }
    final removeIds = toRemove.map((t) => t.id).toSet();
    _allTransactions =
        _allTransactions.where((t) => !removeIds.contains(t.id)).toList();
    safeNotify();
    await _saveAll();
    return toRemove;
  }

  /// Upserts an account (used for filter chips and add-sheet in ledger view).
  Future<void> saveAccount(FinancialAccount account) async {
    final exists = _accounts.any((a) => a.id == account.id);
    _accounts = exists
        ? [for (final a in _accounts) a.id == account.id ? account : a]
        : [..._accounts, account];
    safeNotify();
    await _storage.saveAccounts(_accounts);
  }

  // --- Category CRUD ---

  Future<void> addCategory(FinanceCategory category) async {
    // Stamp a real creation time so the row syncs up (categories default to
    // epoch-0 updatedAt otherwise, which loses to any remote copy under
    // last-write-wins).
    _categories = [
      ..._categories,
      category.copyWith(updatedAt: DateTime.now())
    ];
    safeNotify();
    await _storage.saveFinanceCategories(_categories);
  }

  /// Replaces the stored category that shares [category]'s id — used by the web
  /// Setup categories table for inline rename / recolor / type change. A no-op
  /// if the id isn't present.
  Future<void> updateCategory(FinanceCategory category) async {
    // Bump updatedAt on every edit (rename, recolor, type, icon, exclude-toggle)
    // so the change wins under last-write-wins sync — the call sites use
    // copyWith without touching the timestamp.
    final stamped = category.copyWith(updatedAt: DateTime.now());
    _categories = [
      for (final c in _categories)
        if (c.id == stamped.id) stamped else c
    ];
    safeNotify();
    await _storage.saveFinanceCategories(_categories);
  }

  /// Throws [StateError('has_transactions')] if any transaction still
  /// references this category — refusing to delete prevents broken category
  /// references in the ledger feed and pie chart.
  ///
  /// Cascade-clears any personal-dict entries that pointed at this category,
  /// so re-typing a learned token after delete won't resolve to a dead id.
  Future<void> deleteCategory(String id) async {
    final inUse = _allTransactions.any((t) => t.categoryId == id);
    if (inUse) throw StateError('has_transactions');
    _categories = _categories.where((c) => c.id != id).toList();
    safeNotify();
    await _storage.saveFinanceCategories(_categories);
    await _financeDict.removeForCategory(id);
  }

  // ── Chat-logging state machine (Plan 026 §7) ────────────────────────────────

  /// Whether the rule-based preparser can already see a transaction in [text] —
  /// an amount together with an account or a category it recognises.
  ///
  /// Used to decide whether a message typed into the assistant is something to
  /// log or something to answer. It is far stronger evidence than a keyword
  /// list, because it is the very layer that would do the logging: it knows the
  /// user's real account and category names. "207 lunch at alturas maya credit
  /// card" reads as a log with no spend verb anywhere in it, while "i have 12k
  /// saved" does not, because nothing in it names an account or a category.
  ///
  /// A question is never a log, however much of one the parser can see in it:
  /// "can I afford a ₱4000 dinner?" is asking, not reporting.
  bool recognisesLoggableEntry(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains('?')) return false;
    // `viewingPastDate` is deliberately false: whether the ledger is parked on
    // an old day changes whether a log is ALLOWED, not whether the words are
    // one. sendChatInput re-parses with the real value and reports that error.
    final batch = preparseFinanceBatch(
      input: trimmed,
      categories: _categories,
      accounts: _accounts,
      learnedDict: _financeDict.snapshot(),
    );
    if (batch.hardError != null) return false;
    return batch.segments.any((s) =>
        s.amount != null && (s.accountId != null || s.categoryId != null));
  }

  /// Handles every user message in the chat input row — whether starting a
  /// new conversation or replying to a clarifying question.
  ///
  /// Flow:
  /// 1. Preprocess the input (regex + dict). If hard-errored → set
  ///    [chatHardError], no AI call, no state change.
  /// 2. If fully resolved AND no live conversation → commit + snackbar.
  /// 3. Otherwise enter `classifying` phase and invoke the AI for one turn.
  /// 4. Map the [ClassifierStep] to the next [LedgerChatState] phase.
  ///
  /// [autoResolve] is for surfaces without a multi-turn clarify UI (the web
  /// Quick Add box): a confident `resolved` step is committed immediately and
  /// anything ambiguous opens the prefilled form, all in one shot — no chat
  /// drawer. Mobile leaves it false and drives the clarify conversation.
  /// Scan a receipt photo into a pending expense.
  ///
  /// Vision is cloud-only, so this uses the cloud tier directly. On a
  /// successful read it seeds the SAME confirm-before-commit chat pipeline the
  /// typed quick-log uses — the merchant becomes the description, the grand
  /// total the amount, and the classifier resolves the category (from the
  /// receipt's hint) and asks for the account if it can't be inferred. The
  /// transaction is stamped today, like the typed quick-log; edit the date in
  /// the form if the receipt is for another day.
  ///
  /// Returns [ReceiptScanOutcome.seeded] when the confirm card is ready (caller
  /// dismisses its sheet); any other value is a failure to surface in place.
  Future<ReceiptScanOutcome> logReceiptPhoto(
    Uint8List bytes,
    String mimeType, {
    String? note,
  }) async {
    // Prefer whichever tier can actually do vision (cloud). The on-device tier
    // returns `unavailable`, so trying it too costs nothing and future-proofs.
    final service = _cloudAi ?? _ai;
    if (service == null) return ReceiptScanOutcome.unavailable;

    final result = await service.parseReceiptFromImage(bytes, mimeType, note);
    switch (result.status) {
      case ReceiptParseStatus.rateLimited:
        return ReceiptScanOutcome.rateLimited;
      case ReceiptParseStatus.networkError:
        return ReceiptScanOutcome.networkError;
      case ReceiptParseStatus.serverError:
        return ReceiptScanOutcome.serverError;
      case ReceiptParseStatus.unavailable:
        return ReceiptScanOutcome.unavailable;
      case ReceiptParseStatus.failed:
        return ReceiptScanOutcome.failed;
      case ReceiptParseStatus.notReceipt:
        return ReceiptScanOutcome.notReceipt;
      case ReceiptParseStatus.ok:
        break;
    }

    final total = result.total;
    if (total == null || total <= 0) return ReceiptScanOutcome.notReceipt;

    // Auto-fill the account only when there's exactly one loggable one (same
    // filter the classifier uses); otherwise let it ask.
    final loggable = _accounts
        .where((a) => a.isActive && !a.isSubAccount && !a.isCustodian)
        .toList();
    final soleAccountId = loggable.length == 1 ? loggable.first.id : null;

    final merchant = result.merchant?.trim() ?? '';
    final draft = ParsedTransaction(
      amount: total,
      type: TransactionType.outflow,
      accountId: soleAccountId,
      description: merchant,
      descriptionIsClean: merchant.isNotEmpty,
    );

    // A human-readable seed turn so the classifier can categorise from the
    // merchant + hint. The amount/type are passed authoritatively via preparse,
    // so digits in a merchant name ("7-Eleven") never confuse extraction.
    final seedParts = <String>[
      if (merchant.isNotEmpty) merchant,
      total.toStringAsFixed(2),
      if (result.categoryHint != null) result.categoryHint!,
    ];
    _chatHardError = null;
    _chatState = LedgerChatState(
      phase: ChatPhase.classifying,
      turns: [
        LedgerChatTurn(
          text: 'Receipt — ${seedParts.join(' · ')}',
          isUser: true,
          at: DateTime.now(),
        ),
      ],
      draft: draft,
      turnCount: 0,
    );
    safeNotify();

    final preparse = PreparseResult(
      rawInput: merchant.isEmpty ? seedParts.join(' ') : merchant,
      amount: draft.amount,
      type: draft.type,
      accountId: draft.accountId,
      categoryId: draft.categoryId,
    );
    await _runClassifier(preparse);
    return ReceiptScanOutcome.seeded;
  }

  /// Handles a message the user typed at the assistant.
  ///
  /// Plan 058: the cloud extractor reads the WHOLE message in one call and
  /// returns every transaction in it. That is the primary path. The regex
  /// pipeline below it is the fallback for when the extractor has no transport
  /// (offline, over the daily cap) or its response can't be parsed — it is no
  /// longer allowed to split the message before the model reads it, which is
  /// what dropped context stated once across a list.
  Future<void> sendChatInput(String text, {bool autoResolve = false}) async {
    final isReply = _chatState.phase == ChatPhase.clarifying;

    if (!isReply) {
      // Viewing a past month is a whole-message error that doesn't depend on
      // how the text parses, so it is answered before either path runs.
      if (!isSelectedDateToday) {
        _chatHardError = FinanceParseError.viewingPastDate;
        safeNotify();
        return;
      }
      final extracted = await _extractEntries(text);
      if (extracted != null) {
        await _presentExtraction(extracted, text, autoResolve: autoResolve);
        return;
      }
    }
    await _legacyChatInput(text, autoResolve: autoResolve);
  }

  /// One extraction call. Returns null when the tier is unavailable or the
  /// response was unreadable — the caller then falls back to the regex path.
  Future<ExtractionResult?> _extractEntries(String text) async {
    final cloud = _cloudAi;
    if (cloud == null) return null;
    _chatHardError = null;
    _chatState = LedgerChatState(
      phase: ChatPhase.classifying,
      turns: [LedgerChatTurn(text: text, isUser: true, at: DateTime.now())],
      turnCount: 0,
    );
    safeNotify();
    try {
      return await cloud.extractFinanceEntries(
        message: text,
        categories: _categories,
        accounts: _accounts,
        learnedMappings: _financeDict.snapshot(),
        categoryNameFor: _categoryNameFor,
      );
    } catch (_) {
      // A transport blow-up is the fallback's cue, not an error to show.
      return null;
    }
  }

  String _categoryNameFor(String categoryId) {
    for (final c in _categories) {
      if (c.id == categoryId) return c.name;
    }
    return '';
  }

  /// Puts the extracted rows on the confirm card.
  ///
  /// Nothing commits here. Even a set of rows with no gaps waits for the user,
  /// because the card is the honesty surface: it is where they see what the
  /// model understood before it becomes money in the ledger.
  Future<void> _presentExtraction(
    ExtractionResult result,
    String rawText, {
    bool autoResolve = false,
  }) async {
    if (result.entries.isEmpty) {
      // Nothing to log. If the model asked something, put that in the
      // conversation; otherwise let the regex path have a try — it may still
      // recognise a shape the model didn't.
      final question = result.unclear;
      if (question == null || question.isEmpty) {
        await _legacyChatInput(rawText, autoResolve: autoResolve);
        return;
      }
      _chatState = _chatState.copyWith(
        phase: ChatPhase.idle,
        unclear: question,
        turns: [
          ..._chatState.turns,
          LedgerChatTurn(text: question, isUser: false, at: DateTime.now()),
        ],
      );
      safeNotify();
      return;
    }

    // One-shot surfaces with no review UI commit what is ready and send the
    // first gap to the prefilled form, as they always have.
    if (autoResolve) {
      await _commitEntries(result.entries.where((e) => e.isReady).toList());
      final leftover = result.entries.where((e) => !e.isReady).toList();
      if (leftover.isNotEmpty) {
        _fallbackToForm(leftover.first.txn, 'Needs more detail.');
      }
      return;
    }

    _chatState = _chatState.copyWith(
      phase: ChatPhase.reviewing,
      entries: result.entries,
      draft: result.entries.first.txn,
      clearLastStep: true,
      clearUnclear: true,
    );
    safeNotify();
  }

  // ── Inline resolution (Plan 058) ──────────────────────────────────────────
  //
  // A missing account or category is answered with a picker, not a question.
  // The old clarify loop spent a Bedrock call and a user turn asking "which
  // account?" on a three-turn budget that dead-ended at the form; a dropdown
  // answers it instantly and for free. These setters are what the card's chips
  // call.

  /// Seeds the review card without a round trip through the extractor, so a
  /// widget test can drive the real presenter rather than a stand-in.
  @visibleForTesting
  void debugSeedReview(List<ExtractedEntry> entries) {
    _chatState = _chatState.copyWith(
      phase: ChatPhase.reviewing,
      entries: entries,
      draft: entries.isEmpty ? const ParsedTransaction() : entries.first.txn,
    );
    safeNotify();
  }

  void _updateEntry(int index, ExtractedEntry Function(ExtractedEntry) f) {
    final entries = _chatState.entries;
    if (index < 0 || index >= entries.length) return;
    final next = [...entries];
    next[index] = f(entries[index]);
    _chatState = _chatState.copyWith(entries: next, draft: next.first.txn);
    safeNotify();
  }

  void setEntryAccount(int index, String accountId) => _updateEntry(
        index,
        (e) =>
            e.resolve(EntryField.account, e.txn.copyWith(accountId: accountId)),
      );

  void setEntryTransferTo(int index, String accountId) => _updateEntry(
        index,
        (e) => e.resolve(EntryField.transferTo,
            e.txn.copyWith(transferToAccountId: accountId)),
      );

  /// Setting a category also settles the direction, since an income category
  /// can only be an inflow and an expense category an outflow.
  void setEntryCategory(int index, String categoryId) =>
      _updateEntry(index, (e) {
        final cat = _categories.where((c) => c.id == categoryId).firstOrNull;
        final type = cat == null
            ? e.txn.type
            : (cat.type == CategoryType.income
                ? TransactionType.inflow
                : TransactionType.outflow);
        return e.copyWith(
          txn: e.txn.copyWith(categoryId: categoryId, type: type),
          missing: {...e.missing}
            ..remove(EntryField.category)
            ..remove(EntryField.type),
        );
      });

  void setEntryAmount(int index, double amount) => _updateEntry(
        index,
        (e) => amount <= 0
            ? e
            : e.resolve(EntryField.amount, e.txn.copyWith(amount: amount)),
      );

  void setEntryDate(int index, DateTime date) =>
      _updateEntry(index, (e) => e.copyWith(txn: e.txn.copyWith(date: date)));

  /// Dropping one row of a multi-entry message. Clearing the last row ends the
  /// review rather than leaving an empty card on screen.
  void removeEntry(int index) {
    final entries = _chatState.entries;
    if (index < 0 || index >= entries.length) return;
    final next = [...entries]..removeAt(index);
    if (next.isEmpty) {
      cancelChat();
      return;
    }
    _chatState = _chatState.copyWith(entries: next, draft: next.first.txn);
    safeNotify();
  }

  /// User tapped "Log all" on the review card.
  ///
  /// Commits every ready row. Rows still holding a gap stay on the card rather
  /// than being dropped, so confirming the good ones never silently loses the
  /// rest — the button is disabled while any gap remains, so in practice this
  /// commits the lot.
  Future<void> confirmEntries() async {
    final entries = _chatState.entries;
    if (entries.isEmpty) return;
    final ready = entries.where((e) => e.isReady).toList();
    if (ready.isEmpty) return;

    final leftover = entries.where((e) => !e.isReady).toList();
    await _commitEntries(ready);

    if (leftover.isNotEmpty) {
      _chatState = _chatState.copyWith(
        phase: ChatPhase.reviewing,
        entries: leftover,
        draft: leftover.first.txn,
      );
      safeNotify();
    }
  }

  /// Commits rows as one user action, then learns from them.
  ///
  /// Each token is learned against ITS OWN row's category — pairing one row's
  /// description with another row's category would persist a mapping the user
  /// never confirmed. Only single-word descriptions are learned: a phrase is a
  /// label for one purchase, not a token worth matching later.
  Future<void> _commitEntries(List<ExtractedEntry> entries) async {
    if (entries.isEmpty) return;
    for (final e in entries) {
      await _commitParsed(e.txn, announce: false);
    }
    for (final e in entries) {
      final categoryId = e.txn.categoryId;
      if (categoryId == null || !e.txn.descriptionIsClean) continue;
      final token = e.txn.description.trim().toLowerCase();
      if (token.isEmpty || token.contains(' ')) continue;
      await _financeDict.learn(token, categoryId);
    }
    _lastCommittedSummary = entries.length == 1
        ? _summaryFor(entries.first.txn)
        : 'Logged ${entries.length} transactions';
    safeNotify();
  }

  /// The pre-058 pipeline: regex split, then one classifier call per fragment.
  /// Reached only when the extractor is unavailable or unreadable, and for
  /// replies inside a clarify conversation it started.
  Future<void> _legacyChatInput(String text, {bool autoResolve = false}) async {
    final isReply = _chatState.phase == ChatPhase.clarifying;
    final viewingPast = !isSelectedDateToday;

    if (!isReply) {
      // Fresh input — preprocess. One message may describe several
      // transactions; a single one is just the length-1 batch.
      final batch = preparseFinanceBatch(
        input: text,
        categories: _categories,
        accounts: _accounts,
        learnedDict: _financeDict.snapshot(),
        viewingPastDate: viewingPast,
      );
      // A brand-new message supersedes any leftovers still queued from a
      // previous one — whether they were waiting on a question or on a form.
      // The pending prefill goes too: left standing, an entry the user walked
      // away from would open its form on top of the next thing they typed.
      _deferredSegments = const [];
      _queuedFormPrefills = const [];
      _pendingFormPrefill = null;
      if (batch.hardError != null) {
        _chatHardError = batch.hardError;
        safeNotify();
        return;
      }
      _chatHardError = null;

      if (batch.isMulti) {
        await _startBatch(batch, text, autoResolve: autoResolve);
        return;
      }

      final preparse = batch.segments.first;
      if (preparse.hardError != null) {
        _chatHardError = preparse.hardError;
        safeNotify();
        return;
      }
      // A fully-resolved parse commits directly (the AI is only consulted for
      // ambiguous input). The old `a && b || a` clause collapsed to this. (C12)
      if (preparse.isFullyResolved) {
        await _commitParsed(preparse.toDraft());
        return;
      }
      _chatState = _chatState.copyWith(
        phase: ChatPhase.classifying,
        turns: [
          LedgerChatTurn(text: text, isUser: true, at: DateTime.now()),
        ],
        draft: preparse.toDraft(),
        turnCount: 0,
      );
      safeNotify();
      await _runClassifier(preparse, autoResolve: autoResolve);
    } else {
      // Reply turn — append, advance the AI.
      final updatedTurns = [
        ..._chatState.turns,
        LedgerChatTurn(text: text, isUser: true, at: DateTime.now()),
      ];
      _chatState = _chatState.copyWith(
        phase: ChatPhase.classifying,
        turns: updatedTurns,
        turnCount: _chatState.turnCount + 1,
        clearLastStep: true,
      );
      safeNotify();
      // Rebuild a preparse summary from the current draft for the prompt.
      final preparse = PreparseResult(
        rawInput: text,
        amount: _chatState.draft.amount,
        type: _chatState.draft.type,
        accountId: _chatState.draft.accountId,
        transferToAccountId: _chatState.draft.transferToAccountId,
        categoryId: _chatState.draft.categoryId,
      );
      await _runClassifier(preparse, autoResolve: autoResolve);
    }
  }

  /// Handles a message that described more than one transaction.
  ///
  /// Segments the regex+dictionary layer already resolved cost nothing, so when
  /// *every* segment resolved the whole lot commits straight away — the same
  /// rule the single-entry path uses, applied to the list.
  ///
  /// Otherwise each unresolved segment gets its own classifier turn, run
  /// concurrently. One call per segment rather than one call describing the
  /// whole list is deliberate: it reuses the single-transaction prompt and its
  /// entity validation unchanged, so a batch can't degrade into a shape the
  /// response parser has to guess at. Segments the AI couldn't pin down are
  /// carried on [StepResolved.deferred] and handed to the ordinary clarify loop
  /// once the confirmed ones are logged — a batch never blocks on its worst
  /// segment.
  Future<void> _startBatch(
    PreparseBatch batch,
    String rawText, {
    bool autoResolve = false,
  }) async {
    if (batch.allResolved) {
      await _commitBatch([for (final s in batch.segments) s.toDraft()]);
      return;
    }

    _chatState = LedgerChatState(
      phase: ChatPhase.classifying,
      turns: [LedgerChatTurn(text: rawText, isUser: true, at: DateTime.now())],
      draft: batch.segments.first.toDraft(),
      turnCount: 0,
    );
    safeNotify();

    // A segment with its own hard error (two amounts, a sign that contradicts
    // its category) can't be fixed by asking a question — it needs a retype —
    // so it never reaches the AI and never joins the clarify queue. It is
    // reported on the confirm card instead, where the user can see it and
    // retype just that entry.
    final askable = batch.unresolved.where((s) => s.hardError == null).toList();
    final malformed =
        batch.unresolved.where((s) => s.hardError != null).toList();
    final steps = await Future.wait(
      askable.map((s) => _classifyOnce(s, rawText)),
    );

    final drafts = <ParsedTransaction>[];
    final deferred = <PreparseResult>[];
    final learnedPairs = <String, String>{};

    // Walk the segments in written order so the confirm card reads like the
    // message, rather than grouping by which layer answered.
    for (final segment in batch.segments) {
      if (segment.hardError != null) continue;
      // Identity lookup: `askable` holds the very instances from
      // `batch.segments`, and PreparseResult has no value equality.
      final i = askable.indexOf(segment);
      if (i < 0) {
        drafts.add(segment.toDraft()); // resolved by the parser alone
        continue;
      }
      final step = steps[i];
      if (step is StepResolved) {
        // Merged onto this segment's own draft, for the same reason the
        // single-entry path merges: the preparser's date/note/debtor/
        // reimbursable findings are not restated by the model.
        final merged = segment.toDraft().mergeWith(step.transaction);
        drafts.add(merged);
        final token = step.learnedToken;
        final categoryId = merged.categoryId;
        // Pair each token with ITS OWN segment's category. Collecting bare
        // tokens and pairing them with the batch's first category would teach
        // the dictionary a mapping the user never confirmed.
        if (token != null && categoryId != null) {
          learnedPairs[token] = categoryId;
        }
      } else {
        deferred.add(segment);
      }
    }

    if (drafts.isEmpty) {
      // Nothing survived. Treat it as the single-entry ambiguous case so the
      // user gets the normal clarify conversation rather than a dead end.
      final first = batch.segments.first;
      _chatState = _chatState.copyWith(draft: first.toDraft());
      await _runClassifier(first, autoResolve: autoResolve);
      // On a one-shot surface _runClassifier has just sent `first` to the form.
      // The rest of the message would otherwise end here, unlogged and unsaid.
      if (autoResolve) {
        _queuedFormPrefills = [
          for (final s in batch.segments.skip(1))
            _withCleanDescription(s.toDraft()),
        ];
        safeNotify();
      }
      return;
    }

    final step = StepResolved.batch(
      transactions: drafts,
      summaryText: _batchSummaryFor(drafts, deferred.length, malformed.length),
      deferred: deferred,
      learnedPairs: learnedPairs,
    );

    // One-shot surfaces (web Quick Add) have no clarify UI, so an unresolved
    // leftover would vanish. Commit what's confirmed, then hand the leftovers
    // to the prefilled form — all of them, in written order. Only the first
    // used to be kept, so "coffee 150 gcash, taxi, lunch" logged the coffee and
    // dropped the lunch without a word.
    if (autoResolve) {
      await _commitBatch(drafts);
      _queueForForm([...deferred, ...malformed]);
      return;
    }

    _chatState = _chatState.copyWith(
      phase: ChatPhase.clarifying,
      lastStep: step,
      draft: drafts.first,
      turns: [
        ..._chatState.turns,
        LedgerChatTurn(
            text: step.summaryText, isUser: false, at: DateTime.now()),
      ],
    );
    safeNotify();
  }

  /// One classifier turn for [segment], independent of the chat transcript.
  /// Used only by the batch path, where segments are resolved side by side.
  Future<ClassifierStep?> _classifyOnce(
      PreparseResult segment, String rawText) async {
    Future<ClassifierStep?> run(AiCoachService svc) =>
        svc.runFinanceClassifierStep(
          conversation: [
            LedgerChatTurn(
                text: segment.rawInput, isUser: true, at: DateTime.now()),
          ],
          preparse: segment,
          categories: _categories,
          accounts: _accounts,
          learnedMappings: _financeDict.snapshot(),
          turnCount: 0,
        );

    final cloud = _cloudAi;
    final onDevice = _ai;
    ClassifierStep? step;
    if (cloud != null) step = await run(cloud);
    if (step == null && onDevice != null && onDevice.isAvailable) {
      step = await run(onDevice);
    }
    return step;
  }

  /// Commits several drafts as one user action, then reports them as one line.
  Future<void> _commitBatch(List<ParsedTransaction> drafts) async {
    final complete = drafts.where((d) => d.isComplete).toList();
    if (complete.isEmpty) {
      if (drafts.isNotEmpty) {
        _fallbackToForm(drafts.first, 'Missing required fields.');
      }
      return;
    }
    for (final draft in complete) {
      await _commitParsed(draft, announce: false);
    }
    _lastCommittedSummary = complete.length == 1
        ? _summaryFor(complete.first)
        : 'Logged ${complete.length} transactions';
    safeNotify();
  }

  String _batchSummaryFor(
    List<ParsedTransaction> drafts,
    int deferredCount,
    int malformedCount,
  ) {
    final lines = [for (final d in drafts) '\u2022 ${_summaryFor(d)}'];
    final parts = <String>['Log these ${drafts.length}?', ...lines];
    if (deferredCount > 0) {
      parts.add('$deferredCount more need${deferredCount == 1 ? 's' : ''} '
          'a detail \u2014 I\'ll ask after.');
    }
    // Malformed entries can't be asked about, so say so here: this is the only
    // place the user learns they didn't log, and it names how many to retype.
    if (malformedCount > 0) {
      parts.add(malformedCount == 1
          ? "1 entry I couldn't read \u2014 retype that one."
          : "$malformedCount entries I couldn't read \u2014 retype those.");
    }
    return parts.join('\n');
  }

  Future<void> _runClassifier(
    PreparseResult preparse, {
    bool autoResolve = false,
  }) async {
    Future<ClassifierStep?> run(AiCoachService svc) =>
        svc.runFinanceClassifierStep(
          conversation: _chatState.turns,
          preparse: preparse,
          categories: _categories,
          accounts: _accounts,
          learnedMappings: _financeDict.snapshot(),
          turnCount: _chatState.turnCount,
        );

    // Tier cascade (per product decision): Bedrock is the default classifier
    // (on by default, no Cloud AI toggle required) whenever it has transport;
    // else the on-device model (which may not be downloaded yet); else the
    // manual form. A null result from a tier — transport error, model not
    // loaded, unparseable output — falls through to the next tier.
    final cloud = _cloudAi;
    final onDevice = _ai;
    ClassifierStep? step;
    if (cloud != null) step = await run(cloud);
    if (step == null && onDevice != null && onDevice.isAvailable) {
      step = await run(onDevice);
    }
    if (step == null) {
      _fallbackToForm(_chatState.draft, 'AI unavailable.');
      return;
    }
    // A resolved step refines the draft; it does not replace it. The clarify and
    // give-up branches already merged, and taking the resolved one wholesale was
    // the odd one out: fields the preparser derived deterministically — the
    // reimbursable flag, a parsed date, a note, the debtor — are not things the
    // model is asked to restate, so overwriting the draft with its answer
    // silently dropped them.
    step = switch (step) {
      StepResolved s when !s.isBatch => StepResolved(
          transaction: _chatState.draft.mergeWith(s.transaction),
          learnedToken: s.learnedToken,
          summaryText: s.summaryText,
        ),
      _ => step,
    };
    _chatState = _chatState.copyWith(
      phase: ChatPhase.clarifying,
      lastStep: step,
      draft: switch (step) {
        StepResolved s => s.transaction,
        StepClarify s => _chatState.draft.mergeWith(s.partialDraft),
        StepGiveUp s => _chatState.draft.mergeWith(s.partialDraft),
      },
      turns: [
        ..._chatState.turns,
        LedgerChatTurn(
          text: switch (step) {
            StepResolved s => s.summaryText,
            StepClarify s => s.question,
            StepGiveUp s => s.reason,
          },
          isUser: false,
          quickReplies: step is StepClarify ? step.quickReplies : null,
          at: DateTime.now(),
        ),
      ],
    );
    if (step is StepGiveUp) {
      _fallbackToForm(_chatState.draft, step.reason);
      return;
    }
    // One-shot surfaces (web Quick Add) have no clarify UI: commit a confident
    // resolve straight away, and hand an ambiguous one to the prefilled form.
    if (autoResolve) {
      if (step is StepResolved) {
        await confirmResolved();
      } else {
        _fallbackToForm(_chatState.draft, 'Needs more detail.');
      }
      return;
    }
    safeNotify();
  }

  /// User tapped "Yes" on the resolving turn — commit + learn + reset.
  ///
  /// Commits every transaction the step carries, which is one in the ordinary
  /// case and several when the message described a list. Any segment the AI
  /// couldn't resolve is then handed to the clarify loop, so confirming the
  /// good ones never silently drops the rest.
  Future<void> confirmResolved() async {
    final step = _chatState.lastStep;
    if (step is! StepResolved) return;

    final deferred = step.deferred;
    if (step.isBatch) {
      await _commitBatch(step.transactions);
    } else {
      await _commitParsed(step.transaction);
    }
    for (final pair in step.learnedPairs.entries) {
      await _financeDict.learn(pair.key, pair.value);
    }
    // Queue this step's leftovers behind anything already waiting, then take
    // the next one. _commitBatch/_commitParsed reset the chat to idle, so each
    // leftover gets a clean conversation of its own.
    if (deferred.isNotEmpty) {
      _deferredSegments = [..._deferredSegments, ...deferred];
    }
    await _advanceDeferred();
  }

  /// Starts a clarify conversation for the next queued segment of a
  /// multi-transaction message, if any. No-op when the queue is empty.
  Future<bool> _advanceDeferred() async {
    // Only clarifiable segments are ever queued (malformed ones are reported on
    // the confirm card instead), but skip any that slipped through rather than
    // stalling the queue on one that can't be asked about.
    final queue = _deferredSegments.where((s) => s.hardError == null).toList();
    if (queue.isEmpty) {
      _deferredSegments = const [];
      return false;
    }
    final next = queue.first;
    _deferredSegments = queue.skip(1).toList();
    _chatHardError = null;
    _chatState = LedgerChatState(
      phase: ChatPhase.classifying,
      turns: [
        LedgerChatTurn(text: next.rawInput, isUser: true, at: DateTime.now()),
      ],
      draft: next.toDraft(),
      turnCount: 0,
    );
    safeNotify();
    await _runClassifier(next);
    return true;
  }

  /// User tapped "Edit" — close drawer and surface a draft for the form to
  /// read on its next open. [pendingFormPrefill] is consumed by the view.
  void editResolved() {
    final step = _chatState.lastStep;
    final draft = step is StepResolved ? step.transaction : _chatState.draft;
    _pendingFormPrefill = draft;
    _chatState = const LedgerChatState.idle();
    // Editing takes the user into the form, away from the conversation, so any
    // queued leftovers are abandoned rather than fired at an absent chat.
    _deferredSegments = const [];
    _queuedFormPrefills = const [];
    safeNotify();
  }

  /// User tapped Cancel — drop conversation, clear input. No commit, no learn.
  /// Also drops any queued leftovers from a multi-transaction message: cancel
  /// means cancel the message, not just the segment on screen.
  void cancelChat() {
    _chatState = const LedgerChatState.idle();
    _chatHardError = null;
    _pendingFormPrefill = null;
    _deferredSegments = const [];
    _queuedFormPrefills = const [];
    safeNotify();
  }

  /// Called by the view after it consumes [pendingFormPrefill].
  void consumeFormPrefill() {
    if (_pendingFormPrefill == null) return;
    _pendingFormPrefill = null;
    safeNotify();
  }

  void clearChatHardError() {
    if (_chatHardError == null) return;
    _chatHardError = null;
    safeNotify();
  }

  void clearLastCommittedSummary() {
    if (_lastCommittedSummary == null) return;
    _lastCommittedSummary = null;
    _lastCommitSnappedFromMonth = null;
    safeNotify();
  }

  /// View calls this when the app backgrounds. We record the timestamp so
  /// [notifyAppResumed] can decide whether to reset the in-flight conversation.
  void notifyAppPaused() {
    _pausedAt = DateTime.now();
  }

  /// Resets the chat state when the app has been backgrounded longer than
  /// [_staleConversationThreshold]. Ledger entries should be deliberate —
  /// resuming a half-typed conversation an hour later is worse than starting
  /// fresh.
  void notifyAppResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    if (_chatState.phase == ChatPhase.idle) return;
    if (DateTime.now().difference(pausedAt) > _staleConversationThreshold) {
      _chatState = const LedgerChatState.idle();
      _deferredSegments = const [];
      _queuedFormPrefills = const [];
      safeNotify();
    }
  }

  /// Same calendar day, ignoring time of day.
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get isSelectedDateToday {
    final d = _selectedDate;
    if (d == null) return true;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// [announce] false suppresses the per-transaction toast summary so a batch
  /// commit can report once ("Logged 3 transactions") instead of flashing a
  /// separate confirmation for every entry.
  Future<void> _commitParsed(ParsedTransaction draft,
      {bool announce = true}) async {
    if (!draft.isComplete) {
      _fallbackToForm(draft, 'Missing required fields.');
      return;
    }
    // A date named in the message wins; otherwise "now", as chat always did.
    // The time-of-day is kept for today's entries so same-day ordering still
    // reflects when you logged; a back-dated entry lands at midday, which keeps
    // it clear of both day boundaries whatever the reader's timezone.
    final now = DateTime.now();
    final parsed = draft.date;
    final date = parsed == null
        ? now
        : (_isSameDay(parsed, now)
            ? now
            : DateTime(parsed.year, parsed.month, parsed.day, 12));
    final note = draft.note?.trim();
    // The AI classifier writes a clean, meaningful label — use it as-is. Only
    // raw chat input needs the extraction tokens (amount/account/…) stripped.
    final description = draft.descriptionIsClean
        ? _truncateDescription(draft.description)
        : _truncateDescription(_cleanDescription(draft));
    if (draft.type == TransactionType.transfer) {
      await addTransfer(
        fromAccountId: draft.accountId!,
        toAccountId: draft.transferToAccountId!,
        amount: draft.amount!,
        description: description,
        date: date,
        note: (note == null || note.isEmpty) ? null : note,
      );
    } else if (draft.reimbursable && draft.type == TransactionType.outflow) {
      // Chat suggested a reimbursable expense — log it as one (spawns the
      // linked receivable). A payback date is only set when the message named
      // one behind a payback cue; otherwise null keeps the form's "ASAP"
      // default. Reversible via edit either way.
      final owedBy = draft.owedBy?.trim();
      await addReimbursableExpense(
        TransactionRecord(
          id: _generateId(),
          date: date,
          accountId: draft.accountId!,
          categoryId: draft.categoryId!,
          amount: draft.amount!,
          type: TransactionType.outflow,
          description: description,
          note: (note == null || note.isEmpty) ? null : note,
          month: toMonthKey(date),
          reimbursable: true,
          reimbursementReceivableId: _generateId(),
          owedBy: (owedBy == null || owedBy.isEmpty) ? null : owedBy,
        ),
        expectedReimbursementDate: draft.expectedReimbursementDate,
      );
    } else {
      await addTransaction(TransactionRecord(
        id: _generateId(),
        date: date,
        accountId: draft.accountId!,
        categoryId: draft.categoryId!,
        amount: draft.amount!,
        type: draft.type!,
        description: description,
        note: (note == null || note.isEmpty) ? null : note,
        month: toMonthKey(date),
      ));
    }
    if (announce) _lastCommittedSummary = _summaryFor(draft);
    _chatState = const LedgerChatState.idle();
    _chatHardError = null;
    // Snap the ledger to the month the entry actually landed in, if the user is
    // reading a different one, so the new row is visible instead of silently
    // landing off-screen (the toast fired but no row appeared). With dates now
    // parseable from the text, that month is the entry's — not necessarily this
    // one: "500 food gcash yesterday" on the 1st belongs to last month.
    final nowKey = toMonthKey(date);
    final snappedFrom = _selectedMonth;
    _lastCommitSnappedFromMonth = null;
    if (_selectedMonth != nowKey) {
      _selectedMonth = nowKey;
      _selectedDate = null; // clear any day filter so the new row isn't hidden
      _monthScope?.setMonth(nowKey);
      // Record the jump so the view can say so. Moving the user's reading
      // position without a word is what made this feel like a glitch.
      _lastCommitSnappedFromMonth = snappedFrom;
    }
    safeNotify();
  }

  String _summaryFor(ParsedTransaction draft) {
    final accountName = _accounts
        .where((a) => a.id == draft.accountId)
        .map((a) => a.name)
        .firstOrNull;
    final categoryName = _categories
        .where((c) => c.id == draft.categoryId)
        .map((c) => c.name)
        .firstOrNull;
    if (draft.type == TransactionType.transfer) {
      final toName = _accounts
          .where((a) => a.id == draft.transferToAccountId)
          .map((a) => a.name)
          .firstOrNull;
      return 'Transferred ₱${draft.amount!.toStringAsFixed(0)} '
          '${accountName ?? '?'} → ${toName ?? '?'}';
    }
    final verb = draft.type == TransactionType.inflow ? 'Received' : 'Logged';
    return '$verb ₱${draft.amount!.toStringAsFixed(0)} → '
        '${categoryName ?? '?'} (${accountName ?? '?'})';
  }

  /// Hands [leftovers] to the form: the first becomes [pendingFormPrefill], the
  /// rest wait their turn. No-op on an empty list, so the caller needn't guard.
  void _queueForForm(List<PreparseResult> leftovers) {
    if (leftovers.isEmpty) return;
    _queuedFormPrefills = [
      for (final s in leftovers.skip(1)) _withCleanDescription(s.toDraft()),
    ];
    _fallbackToForm(leftovers.first.toDraft(), 'Needs more detail.');
  }

  /// Pops the next queued leftover for a one-shot surface to open the form
  /// with, or null when the queue is empty. The view calls this after each
  /// prefilled form closes; abandoning the flow means simply not calling it,
  /// and the next message clears whatever is left.
  ParsedTransaction? takeNextFormPrefill() {
    if (_queuedFormPrefills.isEmpty) return null;
    final next = _queuedFormPrefills.first;
    _queuedFormPrefills = _queuedFormPrefills.skip(1).toList();
    safeNotify();
    return next;
  }

  /// Falls back to the form prefilled with the partial draft, clears chat.
  ///
  /// The draft's description is still the raw message at this point — that is
  /// what `PreparseResult.toDraft` puts there — so it is cleaned on the way in.
  /// Only the commit path used to clean it, which left the form showing
  /// "207 lunch at alturas maya credit card" in a Description field sitting
  /// right beside the Amount and Account fields holding those very values.
  void _fallbackToForm(ParsedTransaction draft, String reason) {
    _pendingFormPrefill = _withCleanDescription(draft);
    _chatState = const LedgerChatState.idle();
    safeNotify();
  }

  /// [draft] with its description reduced to what the user actually described.
  /// A draft the AI wrote already carries a clean label, so it is left alone.
  ParsedTransaction _withCleanDescription(ParsedTransaction draft) {
    if (draft.descriptionIsClean || draft.description.isEmpty) return draft;
    return draft.copyWith(
      description: _truncateDescription(_cleanDescription(draft)),
      descriptionIsClean: true,
    );
  }

  /// Longest description chat will store. The manual form is uncapped, but a
  /// chat description is derived from free text that can run to 500 characters,
  /// so some ceiling is needed. 120 fits every realistic entry.
  static const _maxDescriptionLength = 120;

  /// Caps the description, cutting on a word boundary and marking the cut.
  ///
  /// The old 60-character hard slice was silent and mid-word: a long entry lost
  /// its tail with nothing to say so had happened. An ellipsis makes the
  /// truncation visible in the ledger row, which is the difference between a
  /// shortened label and a corrupted one.
  String _truncateDescription(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= _maxDescriptionLength) return trimmed;
    final cut = trimmed.substring(0, _maxDescriptionLength);
    final lastSpace = cut.lastIndexOf(' ');
    // Only honour a word boundary that isn't hacking the label in half.
    final body = lastSpace > _maxDescriptionLength * 0.6
        ? cut.substring(0, lastSpace)
        : cut;
    return '${body.trimRight()}…';
  }

  /// Strips the parsed amount, account name(s), and parser connector/verb words
  /// out of the raw input so the stored description is just what the user
  /// actually described (e.g. "-500 jollibee gcash" → "jollibee"). Falls back to
  /// the category name when nothing descriptive remains.
  String _cleanDescription(ParsedTransaction draft) {
    // Drop the spans the preparser already turned into a note and a date, so
    // the label doesn't repeat fields the transaction now carries structurally.
    var s = chatDescriptionSource(
      rawInput: draft.description.trim(),
      accounts: _accounts,
    );
    if (s.isEmpty) return s;

    // Amount token (optional ₱/p prefix, optional sign, thousands commas).
    s = s.replaceAll(
      RegExp(r'(?<=^|\s)[₱p]?[+-]?\d[\d,]*(?:\.\d+)?(?=\s|$)',
          caseSensitive: false),
      ' ',
    );

    // Account names for both legs (case-insensitive, handles multi-word names).
    for (final id in [draft.accountId, draft.transferToAccountId]) {
      if (id == null) continue;
      final name =
          _accounts.where((a) => a.id == id).map((a) => a.name).firstOrNull;
      if (name != null && name.trim().isNotEmpty) {
        s = s.replaceAll(
            RegExp(RegExp.escape(name), caseSensitive: false), ' ');
      }
    }

    // Parser connector / verb words that carry no description meaning. The
    // payback phrasing goes too: it is why the entry is reimbursable, which the
    // toggle already records, so leaving it in made labels like
    // "jana she'll pay me back".
    s = s.replaceAll(
      RegExp(r'\b(?:from|to|transfer|paid|pay|settle)\b', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(
      RegExp(
        r"(?:i'?ll\s+|she'?ll\s+|he'?ll\s+|they'?ll\s+|will\s+|gonna\s+)?"
        r'(?:pay|pays|paying)\s+(?:me\s+)?back'
        r'|paid\s+(?:me\s+)?back|payback|owes?\s+me'
        r'|reimbursable|reimbursement|reimbursed?',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (s.isEmpty) {
      final cat = _categories
          .where((c) => c.id == draft.categoryId)
          .map((c) => c.name)
          .firstOrNull;
      return cat ?? '';
    }
    return s;
  }

  /// Returns the id of the reserved transfer category, lazily creating and
  /// persisting it the first time a transfer is recorded. The category is
  /// system-owned: hidden from every picker/breakdown (it is neither expense
  /// nor income) and protected from deletion while transfers reference it.
  Future<String> _ensureTransferCategory() async {
    final existing =
        _categories.where((c) => c.type == CategoryType.transfer).firstOrNull;
    if (existing != null) return existing.id;
    final category = FinanceCategory.transfer();
    _categories = [..._categories, category];
    await _storage.saveFinanceCategories(_categories);
    return category.id;
  }

  // --- Private helpers ---

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';

  bool _hasTransactionToday() {
    final today = DateTime.now();
    return _allTransactions.any((t) =>
        t.date.year == today.year &&
        t.date.month == today.month &&
        t.date.day == today.day);
  }

  void _applyBalanceDelta(
      String accountId, double amount, TransactionType type) {
    // Sub-accounts share the same real-world money as their parent, so any
    // transaction-driven delta on a sub also moves the parent. Transfers
    // between a parent and its own sub net to zero on the parent (re-tagging),
    // while external inflows/outflows on a sub correctly hit both accounts.
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    final parentId = account?.parentAccountId;
    // Asset accounts: inflow raises the balance, outflow lowers it.
    // Liability accounts (credit card / credit line / BNPL): balance = debt
    // owed, so the sign inverts — spending (outflow) raises the debt and paying
    // it down (inflow) lowers it. This matches the user's mental model and keeps
    // net-worth math correct. Liabilities are always top-level (no parent) and
    // sub-accounts are always assets, so deriving the sign from this account
    // also yields the right delta for its parent leg.
    final base = type == TransactionType.inflow ? amount : -amount;
    final delta = (account?.isLiability ?? false) ? -base : base;

    _accounts = [
      for (final a in _accounts)
        if (a.id == accountId)
          a.copyWith(balance: a.balance + delta)
        else if (parentId != null && a.id == parentId)
          a.copyWith(balance: a.balance + delta)
        else
          a,
    ];
  }

  void _reverseBalanceDelta(
      String accountId, double amount, TransactionType type) {
    _applyBalanceDelta(
      accountId,
      amount,
      type == TransactionType.inflow
          ? TransactionType.outflow
          : TransactionType.inflow,
    );
  }

  Future<void> _saveAll() async {
    await Future.wait([
      _storage.saveTransactions(_allTransactions),
      _storage.saveAccounts(_accounts),
    ]);
  }

  List<TransactionRecord> get _filteredTransactions {
    final inMonth =
        _allTransactions.where((t) => t.month == _selectedMonth).toList();

    if (_selectedAccountIds.isNotEmpty) {
      return inMonth
          .where((t) => _selectedAccountIds.contains(t.accountId))
          .toList();
    }

    // All-accounts view: show every transaction, including BOTH transfer legs
    // (outflow on the source account and inflow on the destination account) so
    // the destination's increase is visible. Income/expense totals still
    // exclude transfer legs via transferGroupId == null guards in the summary
    // getters, so this does not affect those figures.
    return inMonth;
  }
}
