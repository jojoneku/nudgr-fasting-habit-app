import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/finance_personal_dictionary.dart';
import 'package:intermittent_fasting/services/storage_service.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';
import 'package:intermittent_fasting/utils/finance_nlp_parser.dart';
import 'package:intermittent_fasting/utils/safe_notifier.dart';

class LedgerPresenter extends ChangeNotifier with SafeNotifier {
  LedgerPresenter(
    StorageService storage,
    StatsPresenter stats, {
    AiCoachService? ai,
    FinancePersonalDictionary? financeDict,
  })  : _storage = storage,
        _stats = stats,
        _ai = ai,
        _financeDict = financeDict ?? FinancePersonalDictionary(storage) {
    load();
  }

  final StorageService _storage;
  final StatsPresenter _stats;
  final AiCoachService? _ai;
  final FinancePersonalDictionary _financeDict;

  bool _isLoading = true;
  String _selectedMonth = toMonthKey(DateTime.now());
  String? _selectedAccountId;
  String? _selectedCategoryId;

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

  @override
  void safeNotify() {
    _rowsForMonthCache = null;
    _spreadsheetCache = null;
    super.safeNotify();
  }

  // ── Chat-logging state (Plan 026 — ephemeral, never persisted) ──────────────
  LedgerChatState _chatState = const LedgerChatState.idle();
  FinanceParseError? _chatHardError;
  String? _lastCommittedSummary;
  ParsedTransaction? _pendingFormPrefill;
  DateTime? _pausedAt;
  static const _staleConversationThreshold = Duration(minutes: 5);

  LedgerChatState get chatState => _chatState;
  FinanceParseError? get chatHardError => _chatHardError;
  String? get lastCommittedSummary => _lastCommittedSummary;
  ParsedTransaction? get pendingFormPrefill => _pendingFormPrefill;

  // --- Public state ---

  bool get isLoading => _isLoading;
  String get selectedMonth => _selectedMonth;
  String? get selectedAccountId => _selectedAccountId;

  /// Optional category filter for the web table view. Null = all categories.
  /// Independent of the chat view, which doesn't filter by category.
  String? get selectedCategoryId => _selectedCategoryId;
  List<FinancialAccount> get accounts => _accounts;
  List<FinanceCategory> get categories => _categories;
  List<TransactionRecord> get allTransactions =>
      List.unmodifiable(_allTransactions);

  // --- Filtered summary ---
  // These month/daily totals exclude internal transfer legs (transferGroupId
  // != null): moving money between your own accounts (incl. paying down a
  // credit card) is neither income nor spending, so it must not inflate the
  // ledger's inflow/outflow figures. Transfer rows still appear in the list.

  double get filteredMonthInflow => _filteredTransactions
      .where(
          (t) => t.type == TransactionType.inflow && t.transferGroupId == null)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredMonthOutflow => _filteredTransactions
      .where(
          (t) => t.type == TransactionType.outflow && t.transferGroupId == null)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredMonthNet => filteredMonthInflow - filteredMonthOutflow;

  /// Map of 'yyyy-MM-dd' → total outflow for that day (respects account filter).
  Map<String, double> get dailyOutflowMap {
    final map = <String, double>{};
    for (final t in _filteredTransactions) {
      if (t.type != TransactionType.outflow || t.transferGroupId != null) {
        continue;
      }
      final key = '${t.date.year.toString().padLeft(4, '0')}-'
          '${t.date.month.toString().padLeft(2, '0')}-'
          '${t.date.day.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + t.amount;
    }
    return map;
  }

  /// Map of 'yyyy-MM-dd' → total inflow for that day (respects account filter).
  Map<String, double> get dailyInflowMap {
    final map = <String, double>{};
    for (final t in _filteredTransactions) {
      if (t.type != TransactionType.inflow || t.transferGroupId != null) {
        continue;
      }
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
    safeNotify();
  }

  double get filteredAccountBalance {
    if (_selectedAccountId == null) return 0.0;
    final account =
        _accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    return account?.balance ?? 0.0;
  }

  /// Transactions in [selectedMonth] filtered by [selectedAccountId].
  /// In "All" view: deduplicates transfers — keeps only the outflow leg.
  /// In single-account view: shows both legs belonging to that account.
  Map<DateTime, List<TransactionRecord>> get groupedTransactions {
    var txns = _filteredTransactions;

    // Apply optional single-day filter (from calendar tap)
    if (_selectedDate != null) {
      txns = txns
          .where((t) =>
              t.date.year == _selectedDate!.year &&
              t.date.month == _selectedDate!.month &&
              t.date.day == _selectedDate!.day)
          .toList();
    }

    final grouped = <DateTime, List<TransactionRecord>>{};
    for (final txn in txns) {
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      grouped.putIfAbsent(day, () => []).add(txn);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => b.date.compareTo(a.date));
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in sortedKeys) k: grouped[k]!};
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
    if (_selectedCategoryId != null) {
      txns = txns.where((t) => t.categoryId == _selectedCategoryId).toList();
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
  /// Excludes transfer legs — a transfer is neither income nor spending.
  double get tableInflow => ledgerRowsForMonth
      .where((r) =>
          r.txn.type == TransactionType.inflow && r.txn.transferGroupId == null)
      .fold(0.0, (sum, r) => sum + r.txn.amount);

  /// Outflow subtotal for the current table filter (month/account/category).
  /// Excludes transfer legs — a transfer is neither income nor spending.
  double get tableOutflow => ledgerRowsForMonth
      .where((r) =>
          r.txn.type == TransactionType.outflow &&
          r.txn.transferGroupId == null)
      .fold(0.0, (sum, r) => sum + r.txn.amount);

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

  // --- Filter controls ---

  void setMonth(String month) {
    _selectedMonth = month;
    _selectedDate = null; // clear day filter when navigating months
    safeNotify();
  }

  void setAccount(String? id) {
    _selectedAccountId = id;
    safeNotify();
  }

  /// Sets the table-view category filter. Null clears it (all categories).
  void setCategoryFilter(String? id) {
    _selectedCategoryId = id;
    safeNotify();
  }

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

  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String description,
    required DateTime date,
    String? note,
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
      transferGroupId: groupId,
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
  }

  Future<void> deleteTransaction(String id) async {
    final txn = _allTransactions.where((t) => t.id == id).firstOrNull;
    if (txn == null) return; // already gone — no-op (C9)
    _reverseBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = _allTransactions.where((t) => t.id != id).toList();
    safeNotify();
    await _saveAll();
  }

  /// Deletes a transaction; if it belongs to a transfer pair, removes BOTH legs
  /// so the two accounts unwind cleanly and neither side is left orphaned.
  Future<void> deleteTransactionOrGroup(String id) async {
    final txn = _allTransactions.where((t) => t.id == id).firstOrNull;
    if (txn == null) return;
    final groupId = txn.transferGroupId;
    if (groupId == null) {
      await deleteTransaction(id);
      return;
    }
    for (final leg
        in _allTransactions.where((t) => t.transferGroupId == groupId)) {
      _reverseBalanceDelta(leg.accountId, leg.amount, leg.type);
    }
    _allTransactions =
        _allTransactions.where((t) => t.transferGroupId != groupId).toList();
    safeNotify();
    await _saveAll();
  }

  /// Bulk-deletes the given transaction ids in ONE mutation + ONE persist,
  /// instead of N fire-and-forget calls each doing a full-list write. Transfer
  /// pairs are expanded so both legs go (matches [deleteTransactionOrGroup]).
  /// (Plan 052 C8)
  Future<void> deleteTransactions(Set<String> ids) async {
    if (ids.isEmpty) return;
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
    if (toRemove.isEmpty) return;
    for (final t in toRemove) {
      _reverseBalanceDelta(t.accountId, t.amount, t.type);
    }
    final removeIds = toRemove.map((t) => t.id).toSet();
    _allTransactions =
        _allTransactions.where((t) => !removeIds.contains(t.id)).toList();
    safeNotify();
    await _saveAll();
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
    _categories = [..._categories, category];
    safeNotify();
    await _storage.saveFinanceCategories(_categories);
  }

  /// Replaces the stored category that shares [category]'s id — used by the web
  /// Setup categories table for inline rename / recolor / type change. A no-op
  /// if the id isn't present.
  Future<void> updateCategory(FinanceCategory category) async {
    _categories = [
      for (final c in _categories)
        if (c.id == category.id) category else c
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

  /// Handles every user message in the chat input row — whether starting a
  /// new conversation or replying to a clarifying question.
  ///
  /// Flow:
  /// 1. Preprocess the input (regex + dict). If hard-errored → set
  ///    [chatHardError], no AI call, no state change.
  /// 2. If fully resolved AND no live conversation → commit + snackbar.
  /// 3. Otherwise enter `classifying` phase and invoke the AI for one turn.
  /// 4. Map the [ClassifierStep] to the next [LedgerChatState] phase.
  Future<void> sendChatInput(String text) async {
    final isReply = _chatState.phase == ChatPhase.clarifying;
    final viewingPast = !isSelectedDateToday;

    if (!isReply) {
      // Fresh input — preprocess.
      final preparse = preparseFinanceInput(
        input: text,
        categories: _categories,
        accounts: _accounts,
        learnedDict: _financeDict.snapshot(),
        viewingPastDate: viewingPast,
      );
      if (preparse.hardError != null) {
        _chatHardError = preparse.hardError;
        safeNotify();
        return;
      }
      _chatHardError = null;
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
      await _runClassifier(preparse);
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
      await _runClassifier(preparse);
    }
  }

  Future<void> _runClassifier(PreparseResult preparse) async {
    final ai = _ai;
    if (ai == null || !ai.isAvailable) {
      _fallbackToForm(preparse.toDraft(), 'AI unavailable.');
      return;
    }
    final step = await ai.runFinanceClassifierStep(
      conversation: _chatState.turns,
      preparse: preparse,
      categories: _categories,
      accounts: _accounts,
      learnedMappings: _financeDict.snapshot(),
      turnCount: _chatState.turnCount,
    );
    if (step == null) {
      _fallbackToForm(_chatState.draft, 'Couldn\'t reach the model.');
      return;
    }
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
    safeNotify();
  }

  /// User tapped "Yes" on the resolving turn — commit + learn + reset.
  Future<void> confirmResolved() async {
    final step = _chatState.lastStep;
    if (step is! StepResolved) return;
    await _commitParsed(step.transaction);
    if (step.learnedToken != null && step.transaction.categoryId != null) {
      await _financeDict.learn(
          step.learnedToken!, step.transaction.categoryId!);
    }
  }

  /// User tapped "Edit" — close drawer and surface a draft for the form to
  /// read on its next open. [pendingFormPrefill] is consumed by the view.
  void editResolved() {
    final step = _chatState.lastStep;
    final draft = step is StepResolved ? step.transaction : _chatState.draft;
    _pendingFormPrefill = draft;
    _chatState = const LedgerChatState.idle();
    safeNotify();
  }

  /// User tapped Cancel — drop conversation, clear input. No commit, no learn.
  void cancelChat() {
    _chatState = const LedgerChatState.idle();
    _chatHardError = null;
    _pendingFormPrefill = null;
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
      safeNotify();
    }
  }

  bool get isSelectedDateToday {
    final d = _selectedDate;
    if (d == null) return true;
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<void> _commitParsed(ParsedTransaction draft) async {
    if (!draft.isComplete) {
      _fallbackToForm(draft, 'Missing required fields.');
      return;
    }
    final now = DateTime.now();
    final description = _truncateDescription(_cleanDescription(draft));
    if (draft.type == TransactionType.transfer) {
      await addTransfer(
        fromAccountId: draft.accountId!,
        toAccountId: draft.transferToAccountId!,
        amount: draft.amount!,
        description: description,
        date: now,
      );
    } else {
      await addTransaction(TransactionRecord(
        id: _generateId(),
        date: now,
        accountId: draft.accountId!,
        categoryId: draft.categoryId!,
        amount: draft.amount!,
        type: draft.type!,
        description: description,
        month: toMonthKey(now),
      ));
    }
    _lastCommittedSummary = _summaryFor(draft);
    _chatState = const LedgerChatState.idle();
    _chatHardError = null;
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

  /// Falls back to the form prefilled with the partial draft, clears chat.
  void _fallbackToForm(ParsedTransaction draft, String reason) {
    _pendingFormPrefill = draft;
    _chatState = const LedgerChatState.idle();
    safeNotify();
  }

  /// Plan 026 §4 — description captured from raw input, capped at 60.
  String _truncateDescription(String raw) {
    final trimmed = raw.trim();
    return trimmed.length <= 60 ? trimmed : trimmed.substring(0, 60);
  }

  /// Strips the parsed amount, account name(s), and parser connector/verb words
  /// out of the raw input so the stored description is just what the user
  /// actually described (e.g. "-500 jollibee gcash" → "jollibee"). Falls back to
  /// the category name when nothing descriptive remains.
  String _cleanDescription(ParsedTransaction draft) {
    var s = draft.description.trim();
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

    // Parser connector / verb words that carry no description meaning.
    s = s.replaceAll(
      RegExp(r'\b(?:from|to|transfer|paid|pay|settle)\b', caseSensitive: false),
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

    if (_selectedAccountId != null) {
      return inMonth.where((t) => t.accountId == _selectedAccountId).toList();
    }

    // All-accounts view: deduplicate transfers — keep only outflow leg.
    return inMonth
        .where((t) =>
            t.transferGroupId == null || t.type == TransactionType.outflow)
        .toList();
  }
}
