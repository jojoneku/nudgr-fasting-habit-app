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

  List<FinancialAccount> _accounts = [];
  List<FinanceCategory> _categories = [];
  List<TransactionRecord> _allTransactions = [];

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
  List<FinancialAccount> get accounts => _accounts;
  List<FinanceCategory> get categories => _categories;
  List<TransactionRecord> get allTransactions =>
      List.unmodifiable(_allTransactions);

  // --- Filtered summary ---

  double get filteredMonthInflow => _filteredTransactions
      .where((t) => t.type == TransactionType.inflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredMonthOutflow => _filteredTransactions
      .where((t) => t.type == TransactionType.outflow)
      .fold(0.0, (sum, t) => sum + t.amount);

  double get filteredMonthNet => filteredMonthInflow - filteredMonthOutflow;

  /// Map of 'yyyy-MM-dd' → total outflow for that day (respects account filter).
  Map<String, double> get dailyOutflowMap {
    final map = <String, double>{};
    for (final t in _filteredTransactions) {
      if (t.type != TransactionType.outflow) continue;
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
      if (t.type != TransactionType.inflow) continue;
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
    if (values.isEmpty) return 1.0; // avoid division by zero
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

  /// Refreshes the account list from storage. Call this before showing any
  /// sheet that needs accounts — TreasuryDashboardPresenter may have added
  /// or removed accounts since LedgerPresenter last loaded.
  Future<void> reloadAccounts() async {
    _accounts = await _storage.loadAccounts();
    safeNotify();
  }

  // --- Load ---

  Future<void> load() async {
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

    _isLoading = false;
    safeNotify();
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
    required String categoryId,
    required String description,
    required DateTime date,
    String? note,
  }) async {
    final groupId = _generateId();
    final monthKey = toMonthKey(date);

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
    final old = _allTransactions.firstWhere((t) => t.id == txn.id);
    _reverseBalanceDelta(old.accountId, old.amount, old.type);
    _applyBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = [
      for (final t in _allTransactions) t.id == txn.id ? txn : t,
    ];
    safeNotify();
    await _saveAll();
  }

  Future<void> deleteTransaction(String id) async {
    final txn = _allTransactions.firstWhere((t) => t.id == id);
    _reverseBalanceDelta(txn.accountId, txn.amount, txn.type);
    _allTransactions = _allTransactions.where((t) => t.id != id).toList();
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
      if (preparse.isFullyResolved && _ai == null || preparse.isFullyResolved) {
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
        categoryId: _firstCategoryIdForTransfer(),
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

  /// Transfers still need a categoryId per the data model. Picks the first
  /// expense category; if none exists, picks any category. Caller has already
  /// validated that at least one category exists for the transfer path.
  String _firstCategoryIdForTransfer() {
    final expense = _categories.where((c) => c.type == CategoryType.expense);
    return (expense.isNotEmpty ? expense : _categories).first.id;
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
