import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/advisor_conversation.dart';
import '../models/advisor_profile.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/food_db_entry.dart';
import '../models/food_parse_result.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../services/ai_coach_service.dart';
import '../services/image_compressor.dart';
import '../services/null_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/storage_service.dart';
import '../utils/safe_notifier.dart';

const int _maxHistoryMessages = 50;

/// How many months of month-by-month detail the advisor snapshot carries.
///
/// 18 rather than 12 so a year-over-year comparison has both endpoints: at 12
/// the oldest column is the same month being asked about, which is exactly the
/// comparison that cannot then be made.
const int _historyWindowMonths = 18;

/// Row caps on the historical grids. The snapshot is budgeted, and a grid is
/// the one section that grows in two dimensions at once — rows are pre-sorted
/// by total, so a cap drops the least material lines first.
const int _historyMaxCategoryRows = 18;
const int _historyMaxSavingsRows = 12;

/// Biggest expenses listed per past month. Enough to explain a month without
/// re-sending it in full; each month also reports its total and item count so
/// the sample is never mistaken for the whole.
const int _historyItemsPerMonth = 6;

/// How many named advisor conversations stay browsable. Older ones fold into a
/// single archive thread ("Earlier messages") once this is exceeded.
const int _maxConversations = 10;

/// Cap on the archive thread so folded-away history stays bounded.
const int _maxArchiveMessages = 100;

class AiCoachPresenter extends ChangeNotifier with SafeNotifier {
  final StatsPresenter _stats;

  /// Fasting state for the fasting/nutrition/stats coaches. **Nullable**: the
  /// web companion is finance-only and has no `FastingPresenter` — constructing
  /// one there would init `NotificationService`, a platform channel with no web
  /// implementation. The advisor entry point never reads it.
  final FastingPresenter? _fasting;
  final NutritionPresenter? _nutrition;
  final TreasuryDashboardPresenter? _treasury;
  final BudgetPresenter? _budget;

  /// Active installment / BNPL plans — a fixed monthly commitment the advisor
  /// must account for when judging affordability. Null when finance isn't wired.
  final InstallmentPresenter? _installments;

  /// Month-by-month history: the category x month spend grid, per-pocket
  /// savings contributions, and each month's biggest expenses.
  ///
  /// Null when finance isn't wired, in which case the advisor keeps the
  /// aggregate trends it always had and simply has no detail grid — the
  /// snapshot omits those sections rather than sending empty ones.
  final TreasuryHistoryPresenter? _history;

  /// Ledger used by the financial-advisor mode to log expenses in-conversation
  /// through the existing confirm-before-commit pipeline. Null when finance
  /// isn't wired (advisor logging simply unavailable).
  final LedgerPresenter? _ledger;

  /// Persists advisor chat history + the learned profile (local-only for now).
  final StorageService? _storage;

  /// Resizes attached photos before upload (same codec the food photo flow
  /// uses). Injected so tests can substitute a fake that skips the platform
  /// channel.
  final ImageCompressor _imageCompressor;

  /// The user-curated advisor memory, injected into every advisor turn.
  AdvisorProfile _advisorProfile = AdvisorProfile.empty();

  AiCoachService _service;

  /// Optional cloud tier used only when the primary [_service] is unavailable
  /// (e.g. the on-device model isn't downloaded). Chat falls back to this for
  /// that response; the primary service is preferred whenever it's ready.
  final AiCoachService? _cloudFallback;

  AiCoachTier _activeTier = AiCoachTier.onDevice;

  AiCoachEntryPoint _entryPoint = AiCoachEntryPoint.general;
  final List<AiChatMessage> _messages = [];

  /// Saved advisor conversations (ChatGPT-style). `_messages` is the live copy
  /// of whichever one is [_currentConversationId]; the two are reconciled on
  /// every persist.
  final List<AdvisorConversation> _conversations = [];
  String? _currentConversationId;
  bool _isResponding = false;
  bool _isThinkingEnabled = false;
  bool _isInitializing = true;
  String? _errorMessage;

  AiCoachPresenter({
    required StatsPresenter stats,
    FastingPresenter? fasting,
    NutritionPresenter? nutrition,
    AiCoachService? service,
    TreasuryDashboardPresenter? treasury,
    BudgetPresenter? budget,
    InstallmentPresenter? installments,
    TreasuryHistoryPresenter? history,
    LedgerPresenter? ledger,
    StorageService? storage,
    AiCoachService? cloudFallback,
    ImageCompressor? imageCompressor,
  })  : _stats = stats,
        _fasting = fasting,
        _nutrition = nutrition,
        _treasury = treasury,
        _budget = budget,
        _installments = installments,
        _history = history,
        _ledger = ledger,
        _storage = storage,
        _cloudFallback = cloudFallback,
        _imageCompressor = imageCompressor ?? const ImageCompressor(),
        _service = service ?? NullAiCoachService() {
    // If a real service was injected (already initialised externally), skip
    // the internal init. Only auto-init when no service is provided.
    if (service == null) {
      _initOnDevice();
    } else {
      _isInitializing = false;
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  bool get isResponding => _isResponding;
  bool get isModelAvailable =>
      _service.isAvailable || (_cloudFallback?.isAvailable ?? false);
  int? get downloadProgress => _service.downloadProgress;
  bool get isDownloading => downloadProgress != null;
  bool get isInitializing => _isInitializing;
  AiCoachTier get activeTier => _activeTier;
  AiCoachEntryPoint get entryPoint => _entryPoint;
  String? get errorMessage => _errorMessage;
  bool get isThinkingEnabled => _isThinkingEnabled;

  // ── Session ───────────────────────────────────────────────────────────────

  /// Open a chat session scoped to [entryPoint].
  ///
  /// The financial advisor restores its persisted history + profile so the user
  /// can keep confiding across sessions; other coaches start fresh.
  void openSession(AiCoachEntryPoint entryPoint) {
    _entryPoint = entryPoint;
    _errorMessage = null;
    if (entryPoint == AiCoachEntryPoint.financeAdvisor) {
      _loadAdvisorState();
    } else {
      _messages.clear();
    }
    safeNotify();
  }

  /// The user-curated advisor memory (goals, risk tolerance, notes).
  AdvisorProfile get advisorProfile => _advisorProfile;

  Future<void> _loadAdvisorState() async {
    final storage = _storage;
    if (storage == null) {
      // No persistence (e.g. unit tests): still give the advisor a live
      // conversation to write into.
      _ensureCurrentConversation();
      return;
    }
    final saved = await storage.loadAdvisorConversations();
    final profile = await storage.loadAdvisorProfile();
    if (isDisposed) return;

    _conversations
      ..clear()
      ..addAll(saved);

    // Migration: older installs only have the flat history list. Wrap it into
    // a single conversation the first time so nothing is lost.
    if (_conversations.isEmpty) {
      final history = await storage.loadAdvisorHistory();
      if (isDisposed) return;
      if (history.isNotEmpty) {
        final now = DateTime.now();
        _conversations.add(AdvisorConversation(
          id: _newConversationId(),
          title: AdvisorConversation.titleFrom(history),
          createdAt: now,
          updatedAt: now,
          messages: history,
        ));
      }
    }

    // Open the most recently updated non-archive chat, else create a fresh one.
    final active = _activeConversations();
    _currentConversationId = active.isNotEmpty ? active.first.id : null;
    _ensureCurrentConversation();
    _messages
      ..clear()
      ..addAll(_currentConversation?.messages ?? const []);
    _advisorProfile = profile ?? AdvisorProfile.empty();
    safeNotify();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> send(String text, {Uint8List? image}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && image == null) || _isResponding) return;

    // Logging intent — or any reply while the ledger is mid-clarify — goes
    // through the ledger's confirm-before-commit pipeline instead of the advice
    // model. The sheet renders the confirm card. An attached image is always
    // advice, never an expense log, so routing is skipped for one.
    //
    // Two tests, because they catch different things. [looksLikeExpenseLog]
    // reads the words alone (a spend verb, or a short "coffee 120"), which is
    // all it can do as a pure function. `recognisesLoggableEntry` asks the
    // preparser, which knows the user's actual accounts and categories — so a
    // plainly-stated entry with no spend verb in it, like "207 lunch at alturas
    // maya credit card", is recognised as the log it obviously is instead of
    // being answered as a question.
    final ledger = _ledger;
    if (image == null &&
        _entryPoint == AiCoachEntryPoint.financeAdvisor &&
        ledger != null &&
        (ledger.chatState.phase == ChatPhase.clarifying ||
            looksLikeExpenseLog(trimmed) ||
            ledger.recognisesLoggableEntry(trimmed))) {
      _messages.add(AiChatMessage.user(trimmed));
      _errorMessage = null;
      _isResponding = true;
      safeNotify();
      try {
        await ledger.sendChatInput(trimmed);
      } finally {
        _isResponding = false;
        _persistAdvisor();
        safeNotify();
      }
      return;
    }

    // Compress an attached photo off the UI thread before building the turn.
    Uint8List? compressed;
    if (image != null) {
      try {
        compressed = await _imageCompressor.compressForUpload(image);
      } catch (e) {
        compressed = image; // fall back to the original bytes
        debugPrint('AiCoachPresenter.send image compress failed: $e');
      }
      if (isDisposed) return;
    }

    // With an image but no caption, give the model a natural prompt to react to.
    final display = trimmed.isEmpty ? 'What do you make of this?' : trimmed;
    final userMsg = AiChatMessage.user(display, imageBytes: compressed);
    _messages.add(userMsg);
    _errorMessage = null;
    _isResponding = true;
    safeNotify();

    // Add streaming placeholder for assistant.
    final assistantMsg = AiChatMessage.assistantStreaming();
    _messages.add(assistantMsg);
    safeNotify();

    try {
      final context = _buildContext(image: compressed);
      final buffer = StringBuffer();

      final Stream<String> stream;
      if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
        // Advisor is cloud-only and uses the stronger-model op.
        final cloud = _advisorService;
        if (cloud == null) {
          throw const AiCoachException(
              'The financial advisor needs Cloud AI. Sign in and enable it in Settings.');
        }
        _activeTier = AiCoachTier.cloud;
        final historical = context.financeHistoricalSummary();
        stream = cloud.adviseFinance(
          messages: _userVisibleMessages(),
          context: context,
          profile: _advisorProfile.promptSummary(),
          historical: historical.isEmpty ? null : historical,
        );
      } else {
        // Prefer the primary (on-device) service; fall back to the cloud tier
        // for this response when the primary isn't ready but the cloud is.
        final service = _service.isAvailable
            ? _service
            : (_cloudFallback?.isAvailable ?? false)
                ? _cloudFallback!
                : _service;
        _activeTier = service.tier;
        stream = service.respond(
          messages: _userVisibleMessages(),
          context: context,
          isThinking: _isThinkingEnabled,
        );
      }

      await for (final token in stream) {
        if (isDisposed) break; // sheet dismissed mid-stream — stop updating
        buffer.write(token);
        _updateLastMessage(buffer.toString(), isStreaming: true);
        safeNotify();
      }

      _updateLastMessage(buffer.toString(), isStreaming: false);
    } on AiCoachException catch (e) {
      // Typed failure from the service — the message already says exactly
      // what went wrong (connection vs auth vs rate-limit vs server error).
      _errorMessage = e.userMessage;
      _updateLastMessage('', isStreaming: false);
      debugPrint('AiCoachPresenter.send coach error: $e');
    } catch (e) {
      _errorMessage = 'Something went wrong. Try again.';
      _updateLastMessage('', isStreaming: false);
      debugPrint('AiCoachPresenter.send error: $e');
    } finally {
      _isResponding = false;
      _trimHistory();
      if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
        _persistAdvisor();
      }
      safeNotify();
    }
  }

  // ── Food parse ────────────────────────────────────────────────────────────

  /// Parse a food description and return matched DB entries for confirmation.
  /// Sends a chat message showing what was found.
  Future<List<(ParsedFoodItem, FoodDbEntry?)>> parseAndPreview(
    String description,
  ) async {
    final result = await _service.parseFood(description);
    if (result == null || result.isEmpty) return [];

    final nutrition = _nutrition;
    if (nutrition == null) return [];

    await nutrition.parseMeal(description);
    final matches = nutrition.parsedDbMatches;

    return List.generate(
      result.items.length,
      (i) => (result.items[i], i < matches.length ? matches[i] : null),
    );
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<void> downloadModel() async {
    if (_service is! OnDeviceAiCoachService) {
      _service = OnDeviceAiCoachService();
    }
    safeNotify();
    try {
      await _service.downloadModel(onProgress: (_) => notifyListeners());
    } catch (e) {
      _errorMessage = 'Download failed. Check your connection and try again.';
      debugPrint('AiCoachPresenter.downloadModel error: $e');
    }
    safeNotify();
  }

  // ── Tier ─────────────────────────────────────────────────────────────────

  void setTier(AiCoachTier tier) {
    if (_activeTier == tier) return;
    _activeTier = tier;
    safeNotify();
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  /// Clears the CURRENT conversation's messages (the visible thread), leaving
  /// other saved chats and the archive intact.
  void clearHistory() {
    _messages.clear();
    _errorMessage = null;
    if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
      _persistAdvisor();
    }
    safeNotify();
  }

  /// Append a settled assistant line to the advisor conversation (e.g. a
  /// "✓ Logged …" acknowledgment after an in-chat expense commit). Persisted.
  void appendAssistantNote(String text) {
    _messages.add(
      AiChatMessage.assistantStreaming()
          .copyWith(text: text, isStreaming: false),
    );
    _trimHistory();
    if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
      _persistAdvisor();
    }
    safeNotify();
  }

  // ── Conversations (ChatGPT-style history) ────────────────────────────────

  /// Saved conversations for the history browser: active chats newest-first,
  /// with the archive thread (if any) pinned last.
  List<AdvisorConversation> get conversations {
    final active = _activeConversations();
    final archive =
        _conversations.where((c) => c.isArchive && c.messages.isNotEmpty);
    return [...active, ...archive];
  }

  String? get currentConversationId => _currentConversationId;

  /// Start a fresh chat, saving the current one first.
  void startNewConversation() {
    _persistAdvisor();
    final now = DateTime.now();
    final convo = AdvisorConversation(
      id: _newConversationId(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    _conversations.add(convo);
    _currentConversationId = convo.id;
    _messages.clear();
    _errorMessage = null;
    _enforceConversationCap();
    _storage?.saveAdvisorConversations(_conversations);
    safeNotify();
  }

  /// Reopen a saved conversation as the live thread.
  void openConversation(String id) {
    if (id == _currentConversationId) return;
    _persistAdvisor();
    final convo = _conversations.where((c) => c.id == id).firstOrNull;
    if (convo == null) return;
    _currentConversationId = id;
    _messages
      ..clear()
      ..addAll(convo.messages);
    _errorMessage = null;
    safeNotify();
  }

  /// Delete a saved conversation. If it was the current one, fall back to the
  /// newest remaining chat (or a fresh empty one).
  void deleteConversation(String id) {
    _conversations.removeWhere((c) => c.id == id);
    if (id == _currentConversationId) {
      _currentConversationId = null;
      _messages.clear();
      final active = _activeConversations();
      if (active.isNotEmpty) {
        _currentConversationId = active.first.id;
        _messages.addAll(active.first.messages);
      } else {
        _ensureCurrentConversation();
      }
    }
    _storage?.saveAdvisorConversations(_conversations);
    safeNotify();
  }

  // ── Conversation internals ────────────────────────────────────────────────

  AdvisorConversation? get _currentConversation =>
      _conversations.where((c) => c.id == _currentConversationId).firstOrNull;

  /// Active (non-archive) conversations, most-recently-updated first.
  List<AdvisorConversation> _activeConversations() {
    final active = _conversations.where((c) => !c.isArchive).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return active;
  }

  void _ensureCurrentConversation() {
    if (_currentConversation != null) return;
    final now = DateTime.now();
    final convo = AdvisorConversation(
      id: _newConversationId(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    _conversations.add(convo);
    _currentConversationId = convo.id;
  }

  /// Fold the live [_messages] into the current conversation and persist the
  /// whole set (plus the legacy flat history, which mirrors the current chat so
  /// older clients and the sync empty-check keep working).
  void _persistAdvisor() {
    if (_entryPoint != AiCoachEntryPoint.financeAdvisor) return;
    _ensureCurrentConversation();
    final settled =
        _messages.where((m) => !m.isStreaming && m.text.isNotEmpty).toList();
    final idx =
        _conversations.indexWhere((c) => c.id == _currentConversationId);
    if (idx != -1) {
      final cur = _conversations[idx];
      _conversations[idx] = cur.copyWith(
        messages: settled,
        updatedAt: DateTime.now(),
        title:
            cur.isArchive ? cur.title : AdvisorConversation.titleFrom(settled),
      );
    }
    _enforceConversationCap();
    _storage?.saveAdvisorConversations(_conversations);
    _storage?.saveAdvisorHistory(_messages);
  }

  /// Keep at most [_maxConversations] active chats; fold the oldest overflow
  /// into a single archive thread ("Earlier messages"), capped in size.
  void _enforceConversationCap() {
    var active = _conversations.where((c) => !c.isArchive).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)); // oldest first
    while (active.length > _maxConversations) {
      final evicted = active.removeAt(0);
      _conversations.remove(evicted);
      if (evicted.messages.isEmpty) continue;
      final archiveIdx = _conversations
          .indexWhere((c) => c.id == AdvisorConversation.archiveId);
      if (archiveIdx == -1) {
        _conversations.add(AdvisorConversation(
          id: AdvisorConversation.archiveId,
          title: 'Earlier messages',
          createdAt: evicted.createdAt,
          updatedAt: DateTime.now(),
          messages: _capArchive(evicted.messages),
        ));
      } else {
        final archive = _conversations[archiveIdx];
        _conversations[archiveIdx] = archive.copyWith(
          messages: _capArchive([...archive.messages, ...evicted.messages]),
          updatedAt: DateTime.now(),
        );
      }
    }
  }

  List<AiChatMessage> _capArchive(List<AiChatMessage> msgs) =>
      msgs.length > _maxArchiveMessages
          ? msgs.sublist(msgs.length - _maxArchiveMessages)
          : msgs;

  String _newConversationId() =>
      'c_${DateTime.now().microsecondsSinceEpoch}_${_conversations.length}';

  // ── Advisor profile (user-curated memory) ───────────────────────────────────

  void _updateProfile(AdvisorProfile next) {
    _advisorProfile = next;
    _storage?.saveAdvisorProfile(next);
    safeNotify();
  }

  void addAdvisorGoal(String goal) {
    final g = goal.trim();
    if (g.isEmpty || _advisorProfile.goals.contains(g)) return;
    _updateProfile(_advisorProfile.copyWith(
      goals: [..._advisorProfile.goals, g],
      updatedAt: DateTime.now(),
    ));
  }

  void removeAdvisorGoal(String goal) {
    _updateProfile(_advisorProfile.copyWith(
      goals: _advisorProfile.goals.where((g) => g != goal).toList(),
      updatedAt: DateTime.now(),
    ));
  }

  void setAdvisorRiskTolerance(String? value) {
    _updateProfile(_advisorProfile.copyWith(
      riskTolerance: value?.trim(),
      updatedAt: DateTime.now(),
    ));
  }

  void addAdvisorFact(String fact) {
    final f = fact.trim();
    if (f.isEmpty || _advisorProfile.facts.contains(f)) return;
    _updateProfile(_advisorProfile.copyWith(
      facts: [..._advisorProfile.facts, f],
      updatedAt: DateTime.now(),
    ));
  }

  void removeAdvisorFact(String fact) {
    _updateProfile(_advisorProfile.copyWith(
      facts: _advisorProfile.facts.where((f) => f != fact).toList(),
      updatedAt: DateTime.now(),
    ));
  }

  void clearAdvisorProfile() {
    _updateProfile(AdvisorProfile(updatedAt: DateTime.now()));
  }

  void clearError() {
    _errorMessage = null;
    safeNotify();
  }

  void toggleThinking() {
    _isThinkingEnabled = !_isThinkingEnabled;
    safeNotify();
  }

  @override
  void dispose() {
    super.dispose(); // SafeNotifier.dispose() → _disposed = true
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _initOnDevice() async {
    final svc = OnDeviceAiCoachService();
    await svc.init();
    _service = svc;
    _isInitializing = false;
    safeNotify();
  }

  AiCoachContext _buildContext({Uint8List? image}) {
    final stats = _stats.stats;
    final n = _nutrition;
    final t = _treasury;
    final b = _budget;

    // The rich finance snapshot is only assembled for the advisor — it keeps
    // the RPG coach's prompt lean and avoids extra per-message computation.
    final isAdvisor = _entryPoint == AiCoachEntryPoint.financeAdvisor;
    var topCategories = const <AdvisorCategoryLine>[];
    var outstandingBills = const <AdvisorBillLine>[];
    var pendingReceivables = const <AdvisorReceivableLine>[];
    var creditLines = const <AdvisorCreditLine>[];
    var netWorthTrend = const <AdvisorNetWorthPoint>[];
    var incomeExpenseTrend = const <AdvisorMonthFlow>[];
    var goals = const <AdvisorGoalLine>[];
    var liquidAccounts = const <AdvisorAccountLine>[];
    var budgetGroups = const <AdvisorBudgetGroupLine>[];
    var installmentLines = const <AdvisorInstallmentLine>[];
    var maturities = const <AdvisorMaturityLine>[];
    var recentTransactions = const <AdvisorTxnLine>[];
    var recurringCommitments = const <AdvisorRecurringLine>[];
    var scheduledFuture = const <AdvisorScheduledLine>[];
    var paidBills = const <AdvisorBillLine>[];
    var receivedThisMonth = const <AdvisorReceivableLine>[];
    var setAsides = const <AdvisorSetAsideLine>[];
    var monthlyLedger = const <AdvisorMonthLedger>[];
    var historyMonthLabels = const <String>[];
    var categoryHistory = const <AdvisorCategoryHistoryRow>[];
    var savingsHistory = const <AdvisorSavingsHistoryRow>[];
    var spendingByMonth = const <AdvisorMonthSpendingDigest>[];
    if (isAdvisor && t != null) {
      // Every category with spend, not the dashboard's top 10: the advisor is
      // asked about specific line items, and a category outside the top 10 was
      // simply invisible to it — indistinguishable from one with no spend.
      final trailing = t.categoryTrailingAverage(months: 3);
      topCategories = t.allCategorySpendThisMonth
          .map((e) => AdvisorCategoryLine(
                name: e.$1.name,
                target: b?.budgetFor(e.$1.id)?.allocatedAmount,
                actual: e.$2,
                trailingAverage: trailing.averages[e.$1.id],
                trailingMonths: trailing.months,
              ))
          .toList();
      outstandingBills = t.upcomingBills
          .map((bill) => AdvisorBillLine(
                name: bill.name,
                amount: bill.amount,
                dueLabel: _billDueLabel(bill.dueDay),
              ))
          .toList();
      pendingReceivables = t.outstandingReceivables
          .map((r) => AdvisorReceivableLine(
                name: r.name,
                amount: r.amount,
                expectedLabel: r.expectedDate == null
                    ? 'ASAP'
                    : DateFormat('MMM d').format(r.expectedDate!),
              ))
          .toList();
      creditLines = t.creditAccounts.map((a) {
        final due = t.creditDueInfo(a);
        return AdvisorCreditLine(
          name: a.name,
          owed: a.currentPayable,
          available: a.availableCredit,
          dueLabel: due?.label,
          minimumDue: t.creditMinimumDue(a),
          aprMonthly: a.financeChargeRate,
          utilization: a.utilization,
        );
      }).toList();
      netWorthTrend = t
          .netWorthTrend(months: 12)
          .map((p) => AdvisorNetWorthPoint(label: p.label, value: p.value))
          .toList();
      incomeExpenseTrend = t
          // A year, so a seasonal month reads as seasonal.
          .incomeExpenseTrend(months: 12)
          .map((m) => AdvisorMonthFlow(
                label: m.label,
                income: m.income,
                expense: m.expense,
              ))
          .toList();
      goals = t.goalAccounts.map((a) {
        // A savings budget on the goal account IS its recurring monthly plan
        // (e.g. ₱2,500/mo into "Braces") — lets the advisor project a timeline.
        final plan =
            b?.savingsBudgets.where((e) => e.account.id == a.id).firstOrNull;
        return AdvisorGoalLine(
          name: a.name,
          saved: a.balance,
          target: a.goalTarget,
          monthlyContribution: plan?.budget.allocatedAmount,
        );
      }).toList();
      liquidAccounts = t.liquidAccounts
          .map((a) => AdvisorAccountLine(name: a.name, balance: a.balance))
          .toList();
      budgetGroups = b == null
          ? const []
          : b.groupBars
              .map((g) => AdvisorBudgetGroupLine(
                    name: g.label,
                    allocated: g.allocated,
                    spent: g.spent,
                  ))
              .toList();
      final inst = _installments;
      if (inst != null) {
        installmentLines = inst.installments
            .where((i) => inst.remainingMonths(i.id) > 0)
            .map((i) => AdvisorInstallmentLine(
                  name: i.name,
                  monthlyAmount: i.monthlyAmount,
                  remainingMonths: inst.remainingMonths(i.id),
                  remainingAmount: inst.remainingAmount(i.id),
                ))
            .toList();
      }
      maturities = t.timeDepositAccounts
          .map((a) => AdvisorMaturityLine(
                name: a.name,
                amount: a.balance,
                dateLabel: a.maturityDate == null
                    ? null
                    : DateFormat('MMM d, yyyy').format(a.maturityDate!),
              ))
          .toList();
      recentTransactions = t
          // 8 was too few to explain anything: a single busy week filled the
          // list, so the advisor could see a category was over budget but not
          // which purchases put it there. This is the recency view — the
          // month-by-month digests below cover the past by size instead, so
          // this one no longer has to stretch to reach last month.
          .recentSpending(limit: 60)
          .map((r) => AdvisorTxnLine(
                dateLabel: DateFormat('MMM d').format(r.date),
                description: r.description,
                amount: r.amount,
                category: r.category,
              ))
          .toList();
      recurringCommitments = t.recurringCommitments
          .map((c) => AdvisorRecurringLine(
                name: c.name,
                amount: c.amount,
                dueDay: c.dueDay,
                isInflow: c.isInflow,
              ))
          .toList();
      scheduledFuture = t.scheduledFutureObligations.map((s) {
        final p = s.month.split('-');
        final y = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
        final mo = int.tryParse(p.length > 1 ? p[1] : '') ?? 1;
        return AdvisorScheduledLine(
          name: s.name,
          amount: s.amount,
          monthLabel: DateFormat('MMM yyyy').format(DateTime(y, mo)),
          dateLabel: s.day == null
              ? null
              : DateFormat('MMM d').format(DateTime(y, mo, s.day!)),
          isInflow: s.isInflow,
        );
      }).toList();
      paidBills = t.paidBillsThisMonth
          .map((b) => AdvisorBillLine(name: b.name, amount: b.amount))
          .toList();
      receivedThisMonth = t.receivedThisMonth
          .map((r) => AdvisorReceivableLine(name: r.name, amount: r.amount))
          .toList();
      setAsides = t.setAsidesThisMonth
          .map((s) => AdvisorSetAsideLine(
                name: s.name,
                allocated: s.allocated,
                funded: s.funded,
                remaining: s.remaining,
                isFunded: s.isPaid || s.remaining <= 0,
              ))
          .toList();
      monthlyLedger = t
          .historicalLedger(months: 12)
          .map((m) => AdvisorMonthLedger(
                label: m.label,
                billed: m.billed,
                billsPaid: m.billsPaid,
                receivablesExpected: m.receivablesExpected,
                received: m.received,
                netSavings: m.netSavings,
              ))
          .toList();
    }
    final h = _history;
    if (isAdvisor && h != null) {
      // The grids are keyed by month, so they need one shared, ordered spine.
      // Take it from the tail of the ledger's own active months rather than
      // generating a calendar range: a month with no transactions contributes
      // nothing but an empty column to every row below it.
      final months = h.activeMonths;
      final window = months.length <= _historyWindowMonths
          ? months
          : months.sublist(months.length - _historyWindowMonths);
      if (window.isNotEmpty) {
        historyMonthLabels =
            window.map((m) => _monthYearLabel(m)).toList(growable: false);
        // Rows are already sorted by total spend descending, so the cap keeps
        // the categories that actually move the needle. Capped at all because
        // a long tail of one-off categories would crowd out the months.
        categoryHistory = h.categoryMatrix
            .take(_historyMaxCategoryRows)
            .map((r) => AdvisorCategoryHistoryRow(
                  name: r.name,
                  amounts: [for (final m in window) r.byMonth[m]],
                  total: r.total,
                ))
            .toList();
        savingsHistory = h.savingsPocketMatrix
            .take(_historyMaxSavingsRows)
            .map((r) => AdvisorSavingsHistoryRow(
                  name: r.name,
                  amounts: [for (final m in window) r.byMonth[m]],
                  total: r.total,
                ))
            .toList();
      }
      spendingByMonth = h
          .largestSpendingByMonth(
            months: _historyWindowMonths,
            perMonth: _historyItemsPerMonth,
          )
          .map((d) => AdvisorMonthSpendingDigest(
                monthLabel: _monthYearLabel(d.month),
                monthTotal: d.monthTotal,
                itemCount: d.itemCount,
                items: [
                  for (final tx in d.items)
                    AdvisorTxnLine(
                      dateLabel: DateFormat('MMM d').format(tx.date),
                      description: tx.description,
                      amount: tx.amount,
                      category: tx.category,
                    ),
                ],
              ))
          .toList();
    }
    final savingsRate = t?.savingsRate;
    final peakDay = t?.peakSpendDay;

    return AiCoachContext(
      entryPoint: _entryPoint,
      imageBytes: isAdvisor ? image : null,
      imageMimeType: isAdvisor && image != null ? 'image/jpeg' : null,
      // Absent on finance-only surfaces (web): report "not fasting" rather than
      // inventing a fast, and omit the goal entirely.
      isFasting: _fasting?.isFasting ?? false,
      elapsedFastMinutes: (_fasting?.isFasting ?? false)
          ? _fasting!.elapsedSeconds ~/ 60
          : null,
      fastingGoalHours: _fasting?.fastingGoalHours,
      fastingStreak: stats.streak,
      playerLevel: stats.level,
      playerXp: stats.currentXp,
      playerHp: stats.currentHp,
      todayCalories: n?.todayCalories,
      calorieGoal: n?.effectiveGoal,
      todayProtein: n?.todayProtein,
      todayCarbs: n?.todayCarbs,
      todayFat: n?.todayFat,
      monthBudget: _budget?.totalAllocated,
      monthSpent: _treasury?.monthTotalOutflow,
      // Advisor-only rich snapshot (source of numeric truth for adviseFinance).
      forecastedNetBalance: isAdvisor ? t?.forecastedNetBalance : null,
      netWorth: isAdvisor ? t?.netWorth : null,
      totalLiquidCash: isAdvisor ? t?.totalLiquidCash : null,
      monthNetCashFlow: isAdvisor ? t?.monthNetCashFlow : null,
      savingsRatePct:
          isAdvisor && savingsRate != null ? savingsRate * 100 : null,
      totalCreditAvailable: isAdvisor ? t?.totalCreditAvailable : null,
      totalCreditOwed: isAdvisor ? t?.totalCreditOwed : null,
      outstandingBillsTotal: isAdvisor ? t?.monthUnpaidBills : null,
      daysLeftInMonth: isAdvisor ? t?.daysLeftInMonth : null,
      topCategories: topCategories,
      outstandingBills: outstandingBills,
      monthIncome: isAdvisor ? t?.monthTotalInflow : null,
      pendingReceivablesTotal: isAdvisor ? t?.pendingReceivables : null,
      totalSavingsAndGoals: isAdvisor ? t?.totalSavingsAndGoals : null,
      creditLines: creditLines,
      pendingReceivables: pendingReceivables,
      nextMonthBillsTotal: isAdvisor && (t?.nextMonthUnpaidBills ?? 0) > 0
          ? t?.nextMonthUnpaidBills
          : null,
      nextMonthReceivablesTotal:
          isAdvisor && (t?.nextMonthPendingReceivables ?? 0) > 0
              ? t?.nextMonthPendingReceivables
              : null,
      recurringCommitments: recurringCommitments,
      scheduledFuture: scheduledFuture,
      paidBillsThisMonth: paidBills,
      receivedThisMonth: receivedThisMonth,
      setAsides: setAsides,
      monthlyLedger: monthlyLedger,
      netWorthTrend: netWorthTrend,
      incomeExpenseTrend: incomeExpenseTrend,
      goals: goals,
      liquidAccounts: liquidAccounts,
      heldForOthers: isAdvisor ? t?.totalHeldForOthers : null,
      budgetGroups: budgetGroups,
      setAsidesRemaining: isAdvisor ? t?.budgetedExpensesRemaining : null,
      installments: installmentLines,
      installmentsMonthlyLoad: isAdvisor && installmentLines.isNotEmpty
          ? _installments?.totalDueThisMonth
          : null,
      avgDailySpend: isAdvisor ? t?.avgDailySpend7 : null,
      peakDaySpend: isAdvisor ? t?.peakDaySpend7 : null,
      peakDayLabel: isAdvisor && peakDay != null
          ? DateFormat('MMM d').format(peakDay)
          : null,
      todaySpend: isAdvisor ? t?.todayOutflow : null,
      netWorthMonthDelta: isAdvisor ? t?.netWorthMonthDelta : null,
      netWorthMonthDeltaPct: isAdvisor ? t?.netWorthMonthDeltaPct : null,
      maturities: maturities,
      recentTransactions: recentTransactions,
      historyMonthLabels: historyMonthLabels,
      categoryHistory: categoryHistory,
      savingsHistory: savingsHistory,
      spendingByMonth: spendingByMonth,
    );
  }

  /// 'YYYY-MM' → 'Sep 2026'. The year is load-bearing: the History grids run
  /// long enough that a bare 'Sep' would collide with the same month a year
  /// earlier, and a collision here is a wrong answer, not a cosmetic one.
  static String _monthYearLabel(String monthKey) {
    final parsed = DateTime.tryParse('$monthKey-01');
    return parsed == null ? monthKey : DateFormat('MMM yyyy').format(parsed);
  }

  /// Due label for a current-month bill given its [dueDay], relative to today
  /// ("Due today", "Due in 3 days", "Overdue by 2 days"). Kept here so the
  /// snapshot the advisor sees carries the same urgency the Bills tab shows.
  static String _billDueLabel(int dueDay) {
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final diff = dueDay.clamp(1, lastDay) - now.day;
    if (diff < 0) {
      final n = -diff;
      return n == 1 ? 'Overdue by 1 day' : 'Overdue by $n days';
    }
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    return 'Due in $diff days';
  }

  /// The cloud-tier service the advisor uses (it is cloud-only). Prefers the
  /// dedicated cloud fallback, else the primary service if it happens to be cloud.
  AiCoachService? get _advisorService {
    final fallback = _cloudFallback;
    if (fallback != null && fallback.tier == AiCoachTier.cloud) return fallback;
    if (_service.tier == AiCoachTier.cloud) return _service;
    return null;
  }

  /// Ledger presenter available to the advisor for in-conversation logging.
  LedgerPresenter? get advisorLedger => _ledger;

  /// A second-person request to log something ("can you add…", "please log…").
  ///
  /// This is the one shape allowed past the question-mark veto. It turns on the
  /// subject: *you* doing something is an instruction, *I* wondering about
  /// something is a question, and only the first should reach the ledger.
  static bool isPoliteLogRequest(String text) => RegExp(
        r"\b(can|could|would|will|pls|please)\s+(you\s+)?"
        r"(pls\s+|please\s+|just\s+)?"
        r"(add|log|record|enter|put|note|save)\b",
      ).hasMatch(text.toLowerCase());

  /// Heuristic: does [text] read as an expense to log (an amount plus a spend
  /// verb/keyword) rather than an advisory question? Used by the advisor mode
  /// to route logging intents into the confirm-before-commit ledger pipeline.
  /// Deliberately conservative — anything ambiguous stays as advice.
  static bool looksLikeExpenseLog(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;
    // A question is advice, never a log — unless it is a request wearing a
    // question mark. "can I afford 4000 food gcash?" is deliberating and stays
    // with the advice model; "can you add 175 maribank?" is an instruction, and
    // answering it conversationally is how the assistant ended up describing
    // entries it had not logged.
    if (t.contains('?') && !isPoliteLogRequest(t)) return false;
    final hasAmount = RegExp(r'(₱|php|p)?\s?\d[\d,]*(\.\d+)?').hasMatch(t);
    if (!hasAmount) return false;
    final hasLogVerb = RegExp(
      r'\b(log|spent|spend|paid|pay|bought|buy|add|record|got|grabbed|bill)\b',
    ).hasMatch(t);
    if (hasLogVerb) return true;
    // Short "coffee 120"-style entries are logs too — but only when a describing
    // token (the *what*) sits beside the amount. A bare number the user typed in
    // conversation ("12k", "₱5,000", "i have 12k") has nothing to log and is
    // almost always advice input, so it must stay with the model rather than
    // getting hijacked into the ledger's confirm-before-commit pipeline.
    final tokens = t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (tokens.length > 4) return false;
    // A standalone amount token, incl. currency prefix and k/m shorthand.
    final amountToken = RegExp(r'^(₱|php|p)?\d[\d,]*(\.\d+)?(k|m)?$');
    // Conversational filler carries no logging intent; ignore it when deciding
    // whether a describing word is actually present.
    const filler = {
      'i',
      'im',
      "i'm",
      'my',
      'me',
      'we',
      'us',
      'you',
      'have',
      'has',
      'had',
      'a',
      'an',
      'the',
      'is',
      'am',
      'are',
      'was',
      'about',
      'around',
      'roughly',
      'only',
      'just',
      'some',
      'and',
      'or',
      'to',
      'of',
      'in',
      'on',
      'at',
      'so',
      'ok',
      'okay',
      'yes',
      'no',
      'yeah',
      'nah',
      'maybe',
      'left',
      'total',
      'saved',
      'save',
      'php',
      'peso',
      'pesos',
    };
    final hasDescriptor = tokens.any(
      (tok) => !amountToken.hasMatch(tok) && !filler.contains(tok),
    );
    return hasDescriptor;
  }

  List<AiChatMessage> _userVisibleMessages() =>
      _messages.where((m) => !m.isStreaming && m.text.isNotEmpty).toList();

  void _updateLastMessage(String text, {required bool isStreaming}) {
    if (_messages.isEmpty) return;
    _messages[_messages.length - 1] =
        _messages.last.copyWith(text: text, isStreaming: isStreaming);
  }

  void _trimHistory() {
    if (_messages.length > _maxHistoryMessages) {
      _messages.removeRange(0, _messages.length - _maxHistoryMessages);
    }
  }
}
