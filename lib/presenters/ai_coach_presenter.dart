import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/advisor_event.dart';
import '../models/advisor_hop_outcome.dart';
import '../models/advisor_reply.dart';
import '../models/advisor_conversation.dart';
import '../models/advisor_route.dart';
import '../models/advisor_profile.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/ai_tool.dart';
import '../models/finance/bill.dart';
import '../models/finance/budget.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/food_db_entry.dart';
import '../models/food_parse_result.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/installment_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/finance_tool_executor.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../presenters/treasury_history_presenter.dart';
import '../services/ai_coach_service.dart';
import '../services/image_compressor.dart';
import '../services/null_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/storage_service.dart';
import '../utils/advisor_routing.dart';
import '../utils/credit_cycle.dart';
import '../utils/finance_format.dart';
import '../utils/finance_tool_catalogue.dart';
import '../utils/planning_intent.dart';
import '../utils/safe_notifier.dart';

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

  /// Runs the tools Nudgy calls. **Nullable**: null means this build offers no
  /// tools at all, and the advisor stays the read-only adviser it was. Tools
  /// are only declared to the model when this is present, so the model can
  /// never propose a change nothing is able to carry out.
  final FinanceToolExecutor? _toolExecutor;

  /// The proposal surface a confirm card binds to, when the injected executor
  /// has one. Resolved here rather than type-tested inside a `build()`.
  /// The cast is explicit because [FinanceProposalHost] is deliberately not a
  /// subtype of [FinanceToolExecutor] — the two describe different audiences —
  /// so Dart cannot promote across them.
  FinanceProposalHost? get financeProposals {
    final executor = _toolExecutor;
    return executor is FinanceProposalHost
        ? executor as FinanceProposalHost
        : null;
  }

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

  /// What Nudgy is doing right now, in the user's own words, or null when
  /// nothing needs saying.
  ///
  /// The empty streaming bubble already carries a "thinking" label, but it
  /// stops the moment the model writes its first word — and a tool-calling
  /// turn writes its prose FIRST ("sure, I can add that") and then goes quiet
  /// for another whole round trip while the tools run and the next hop is
  /// fetched. That silence is what read as a frozen app: a finished-looking
  /// reply, an input bar disabled for reasons nothing explained, and no sign
  /// that a confirm card was still on its way.
  String? _advisorStatus;
  bool _isThinkingEnabled = false;
  bool _isInitializing = true;
  String? _errorMessage;

  /// Reads the time for the idle-gap check. Injected so a test can move it.
  final DateTime Function() _clock;

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
    FinanceToolExecutor? toolExecutor,
    Duration retryHorizon = defaultRetryHorizon,
    DateTime Function()? clock,
  })  : _retryHorizon = retryHorizon,
        _clock = clock ?? DateTime.now,
        _stats = stats,
        _fasting = fasting,
        _nutrition = nutrition,
        _treasury = treasury,
        _budget = budget,
        _installments = installments,
        _history = history,
        _ledger = ledger,
        _storage = storage,
        _cloudFallback = cloudFallback,
        _toolExecutor = toolExecutor,
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

  /// Whether the quick-action chips above the input show: only until the
  /// user says something in this conversation. They are conversation
  /// starters; once a conversation is under way they only take room from it,
  /// and they come back with a new conversation. A restored conversation
  /// that already has the user's words in it starts without them.
  bool get showsQuickActions =>
      !_messages.any((m) => m.role == AiChatRole.user);

  /// Placeholder for the input bar, which is disabled for three quite
  /// different reasons and used to blame all of them on the model not being
  /// ready. Mid-turn that is simply untrue, and it is the reading that made a
  /// working advisor look broken.
  String get inputHint {
    if (_isInitializing) return 'Getting ready…';
    if (_isResponding) return 'Nudgy is working…';
    if (!isModelAvailable) return 'Coach not ready…';
    return 'Ask your coach…';
  }

  /// A line describing work in flight, for the status strip under the chat.
  /// Gated on [isResponding] so it can never outlive the turn that set it.
  ///
  /// A retry outranks whatever else was being said. [isRetryingAdvisor] has
  /// existed since retries were added and nothing ever read it, so a dropped
  /// connection silently restarted the answer with the user watching a spinner
  /// that had, as far as they could tell, been going the whole time.
  String? get advisorStatus {
    if (!_isResponding) return null;
    if (isRetryingAdvisor) return 'Connection hiccup — trying again…';
    return _advisorStatus;
  }

  String? get errorMessage => _errorMessage;
  bool get isThinkingEnabled => _isThinkingEnabled;

  /// True while Nudgy is answering: streaming a hop, running its tools,
  /// waiting on a confirm card, or between hops. For this whole stretch the
  /// send button is a stop button. Only the advisor turn can be stopped; a
  /// ledger hand-off or another coach's reply does not set it.
  bool get isWorking => _advisorRunning;

  /// True when [stop] would do something. False once a stop was asked for,
  /// while the turn unwinds, so a second tap is not taken as a second stop.
  bool get canStop => _advisorRunning && !_stopRequested;

  /// True while a batch of Nudgy's changes waits for the user. The input
  /// takes text then, and a message sent now answers the batch "not
  /// approved" with the user's words (Plan 065 phase 4, decision 3). Stop
  /// still works: it answers the batch "not approved" and ends the turn.
  bool get isAwaitingBatch =>
      _advisorRunning && financeProposals?.batch != null;

  /// Whether the input accepts text now.
  bool get canType =>
      isModelAvailable &&
      !isInitializing &&
      (!_isResponding || isAwaitingBatch);

  // ── Session ───────────────────────────────────────────────────────────────

  /// Open a chat session scoped to [entryPoint].
  ///
  /// The financial advisor restores its persisted history + profile so the user
  /// can keep confiding across sessions; other coaches start fresh.
  void openSession(AiCoachEntryPoint entryPoint) {
    // Reopening the advisor while one of its turns is still running — the
    // mobile sheet calls this every time it opens, and closing it while a
    // suggestion card waits is ordinary — must not reload the thread. Storage
    // does not have the in-flight turn yet, so a reload dropped the prose that
    // introduced the card, and the reply after the user answered it was then
    // written over whatever older message happened to be last.
    if (_isResponding &&
        entryPoint == AiCoachEntryPoint.financeAdvisor &&
        _entryPoint == entryPoint) {
      safeNotify();
      return;
    }
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
    _conversationChosenAt = null;
    _ensureCurrentConversation();
    _messages
      ..clear()
      ..addAll(_currentConversation?.messages ?? const []);
    _advisorProfile = profile ?? AdvisorProfile.empty();
    safeNotify();
    // A batch an app restart interrupted is shown again (Plan 065 phase 4).
    unawaited(resumeOpenBatch());
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  /// Images one advisor message may carry. Each is compressed to a ~1024px
  /// JPEG before send (well under 1 MB, base64 adds a third), so five stay
  /// comfortably inside the 6 MB Lambda request limit with the snapshot and
  /// the legacy single-image mirror on top. The backend enforces the same cap.
  static const int maxAttachments = 5;

  /// Images staged for the next message, in the order they were added. Raw
  /// bytes from the picker or the clipboard; compressed at send.
  final List<Uint8List> _pendingImages = [];

  List<Uint8List> get pendingImages => List.unmodifiable(_pendingImages);
  bool get hasPendingImages => _pendingImages.isNotEmpty;
  int get remainingAttachmentSlots => maxAttachments - _pendingImages.length;
  bool get canAddAttachment => remainingAttachmentSlots > 0;

  /// Shown when an add would pass [maxAttachments].
  String get attachmentLimitMessage =>
      'Up to $maxAttachments images per message.';

  /// Stages [images] for the next message, up to [maxAttachments].
  ///
  /// Returns how many were left out because the cap was reached, so the view
  /// can say so. Empty byte arrays are ignored: they are what a failed read or
  /// an empty clipboard item produces, and sending one fails at the model.
  int addAttachments(Iterable<Uint8List> images) {
    var dropped = 0;
    var added = false;
    for (final image in images) {
      if (image.isEmpty) continue;
      if (!canAddAttachment) {
        dropped++;
        continue;
      }
      _pendingImages.add(image);
      added = true;
    }
    if (added) safeNotify();
    return dropped;
  }

  /// Unstages the image at [index]. Out-of-range indexes are ignored — a
  /// double tap on a remove button must not throw.
  void removeAttachment(int index) {
    if (index < 0 || index >= _pendingImages.length) return;
    _pendingImages.removeAt(index);
    safeNotify();
  }

  void clearAttachments() {
    if (_pendingImages.isEmpty) return;
    _pendingImages.clear();
    safeNotify();
  }

  /// Sends [text] with every staged image, and unstages them.
  ///
  /// The images leave the staging row at once, before the turn runs, so the
  /// row empties the moment the user taps send — like the text field.
  Future<void> sendWithAttachments(String text) async {
    if (_isResponding) return;
    if (text.trim().isEmpty && _pendingImages.isEmpty) return;
    final images = List<Uint8List>.of(_pendingImages);
    if (images.isNotEmpty) {
      _pendingImages.clear();
      safeNotify();
    }
    await send(text, images: images);
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  /// Re-runs the last turn after a failure, without making the user retype it.
  ///
  /// The question is still in the transcript — it always was, which is what
  /// made the old behaviour so annoying: the app was holding the text and still
  /// asked for it again. This drops the failed assistant turn and everything
  /// the tool loop accumulated behind it, then replays from the last real user
  /// message.
  ///
  /// Refuses when the failure was not retryable, so it cannot be used to
  /// re-attempt an expired session or a spent daily cap.
  Future<void> retryLastTurn() async {
    if (_isResponding || !canRetryLastTurn) return;

    final lastUser = _lastUserPromptIndex();
    if (lastUser == null) return;

    final prompt = _messages[lastUser];
    // Drop the user turn too — send() re-adds it, so keeping it would show the
    // question twice.
    _messages.removeRange(lastUser, _messages.length);
    _errorMessage = null;
    _lastTurnRetryable = false;
    safeNotify();

    await send(prompt.text, images: prompt.images);
  }

  /// The message the router last gave to the ledger's quick-log pipeline,
  /// kept so the user can send it to Nudgy instead when the card misread it.
  String? _routedLogText;

  /// Set by [askNudgyInstead] so the next [send] skips the quick-log router.
  bool _bypassRouterOnce = false;

  /// True while the ledger shows a log card for a message this chat routed to
  /// it, so the card can offer "Not a log — ask Nudgy".
  bool get canAskNudgyInstead {
    final ledger = _ledger;
    if (_routedLogText == null || ledger == null || _isResponding) {
      return false;
    }
    final state = ledger.chatState;
    final step = state.lastStep;
    return state.entries.isNotEmpty ||
        step is StepResolved ||
        step is StepClarify;
  }

  /// The quick-log card misread a message: drop the card and let Nudgy answer
  /// the same words instead.
  ///
  /// Nothing is saved — the card is only a review, and cancelling it discards
  /// every row on it. This is the escape hatch for the planning-word veto
  /// (Plan 065, 1d): the veto catches the reported phrasings, the button
  /// catches the rest without sending every message to the model first.
  Future<void> askNudgyInstead() async {
    if (!canAskNudgyInstead) return;
    final text = _routedLogText!;
    _routedLogText = null;
    _ledger!.cancelChat();
    // send() shows the prompt again, so drop the copy the routed turn left —
    // the same move retryLastTurn makes.
    if (_messages.isNotEmpty &&
        _isEditablePrompt(_messages.last) &&
        _messages.last.text == text) {
      _messages.removeLast();
    }
    _bypassRouterOnce = true;
    await send(text);
  }

  /// Replaces a question already asked and answers the new one.
  ///
  /// Everything after the edited message goes: its answer was to a question
  /// that no longer exists, and leaving it would put a reply above a prompt it
  /// does not match. Anything the user wants to keep is above the edit.
  ///
  /// Returns false when the id is not an editable user prompt — a tool-result
  /// turn wears [AiChatRole.user] too, and is not something anyone typed.
  Future<bool> editAndResend(String messageId, String newText) async {
    if (_isResponding) return false;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return false;

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return false;
    final target = _messages[index];
    if (!_isEditablePrompt(target)) return false;
    if (trimmed == target.text.trim()) return false; // nothing changed

    final images = target.images;
    _messages.removeRange(index, _messages.length);
    _errorMessage = null;
    _lastTurnRetryable = false;
    safeNotify();

    await send(trimmed, images: images);
    return true;
  }

  /// True when this message is a prompt the user typed and may edit.
  bool canEdit(AiChatMessage message) =>
      !_isResponding && _isEditablePrompt(message);

  /// A user turn carrying tool results is machinery, not something typed.
  bool _isEditablePrompt(AiChatMessage m) =>
      m.role == AiChatRole.user &&
      m.contentBlocks.isEmpty &&
      m.text.trim().isNotEmpty;

  /// Index of the most recent prompt the user actually typed.
  int? _lastUserPromptIndex() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_isEditablePrompt(_messages[i])) return i;
    }
    return null;
  }

  Future<void> send(
    String text, {
    List<Uint8List> images = const [],
  }) async {
    final bypassRouter = _bypassRouterOnce;
    _bypassRouterOnce = false;
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && isAwaitingBatch) {
      _reviseOpenBatch(trimmed);
      return;
    }
    if ((trimmed.isEmpty && images.isEmpty) || _isResponding) return;
    if (startsFreshAfterIdleGap) startNewConversation();

    // Logging intent — or any reply while the ledger is mid-clarify — goes
    // through the ledger's confirm-before-commit pipeline instead of the advice
    // model. The sheet renders the confirm card. An attached image is always
    // advice, never an expense log, so routing is skipped for a turn with any.
    //
    // Two tests, because they catch different things. [looksLikeExpenseLog]
    // reads the words alone (a spend verb, or a short "coffee 120"), which is
    // all it can do as a pure function. `recognisesLoggableEntry` asks the
    // preparser, which knows the user's actual accounts and categories — so a
    // plainly-stated entry with no spend verb in it, like "207 lunch at alturas
    // maya credit card", is recognised as the log it obviously is instead of
    // being answered as a question. A request only Nudgy's tools can carry out
    // is the exception, and stays with Nudgy — see [isAdvisorToolRequest].
    final ledger = _ledger;
    var promptShown = false;
    if (!bypassRouter &&
        images.isEmpty &&
        _entryPoint == AiCoachEntryPoint.financeAdvisor &&
        ledger != null &&
        _routesToLedger(trimmed, ledger)) {
      // A reply to the ledger's clarifying question is not the message the
      // card is about, so it does not replace the one kept for "ask Nudgy".
      if (ledger.chatState.phase != ChatPhase.clarifying) {
        _routedLogText = trimmed;
      }
      _messages.add(AiChatMessage.user(trimmed));
      _errorMessage = null;
      _isResponding = true;
      safeNotify();
      var handled = true;
      try {
        await ledger.sendChatInput(trimmed);
        handled = !_ledgerFoundNothing(ledger);
      } finally {
        if (handled) {
          _isResponding = false;
          _persistAdvisor();
          safeNotify();
        }
      }
      if (handled || isDisposed) return;
      // The ledger had nothing to put on a card. Nudgy answers instead — it
      // has the whole conversation and every tool, including logging — so the
      // message is never left without a reply. It is already in the thread.
      promptShown = true;
      _routedLogText = null;
    }

    // Compress attached photos off the UI thread before building the turn.
    // Past the cap is a caller bug; the extras are dropped rather than sent
    // into a request the backend would trim anyway.
    var compressed = const <Uint8List>[];
    if (images.isNotEmpty) {
      compressed = await Future.wait(
          images.take(maxAttachments).map(_compressForUpload));
      if (isDisposed) return;
    }

    if (!promptShown) {
      // With an image but no caption, give the model a natural prompt to react
      // to.
      final display = trimmed.isNotEmpty
          ? trimmed
          : compressed.length > 1
              ? 'What do you make of these?'
              : 'What do you make of this?';
      _messages.add(AiChatMessage.user(display, images: compressed));
    }
    _errorMessage = null;
    _isResponding = true;
    safeNotify();

    // Add streaming placeholder for assistant.
    final assistantMsg = AiChatMessage.assistantStreaming();
    _messages.add(assistantMsg);
    safeNotify();

    try {
      final context = _buildContext(images: compressed);
      final buffer = StringBuffer();

      if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
        // Advisor is cloud-only, uses the stronger-model op, and may run a
        // tool loop, so it does not share the token-stream path below.
        final cloud = _advisorService;
        if (cloud == null) {
          throw const AiCoachException(
              'The financial advisor needs Cloud AI. Sign in and enable it in Settings.');
        }
        _activeTier = AiCoachTier.cloud;
        _advisorRunning = true;
        _stopRequested = false;
        safeNotify();
        try {
          await _runAdvisorTurn(cloud, context);
        } finally {
          _advisorRunning = false;
          _cancelHop = null;
        }
      } else {
        // Prefer the primary (on-device) service; fall back to the cloud tier
        // for this response when the primary isn't ready but the cloud is.
        final service = _service.isAvailable
            ? _service
            : (_cloudFallback?.isAvailable ?? false)
                ? _cloudFallback!
                : _service;
        _activeTier = service.tier;
        final stream = service.respond(
          messages: _requestTranscript(),
          context: context,
          isThinking: _isThinkingEnabled,
        );

        await for (final token in stream) {
          if (isDisposed) break; // sheet dismissed mid-stream — stop updating
          buffer.write(token);
          _updateLastMessage(buffer.toString(), isStreaming: true);
          safeNotify();
        }

        _updateLastMessage(buffer.toString(), isStreaming: false);
      }
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
      _advisorStatus = null;
      if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
        _persistAdvisor();
      }
      safeNotify();
    }
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  /// Set from the start of an advisor turn until it has fully unwound.
  bool _advisorRunning = false;

  /// Set by [stop]. Every await in the tool loop checks it on the way back, so
  /// nothing that finishes after the stop can start a hop or change the reply.
  bool _stopRequested = false;

  /// Cancels the latest hop's stream. Null outside an advisor turn. Between
  /// hops it points at a finished hop, where calling it does nothing.
  void Function()? _cancelHop;

  /// True when the turn must not go on: the sheet went away, or the user
  /// stopped it.
  bool get _turnOver => isDisposed || _stopRequested;

  /// Stops the advisor turn now.
  ///
  /// The words already on screen stay, marked as stopped, because they are
  /// real work the user may still want. No further hop starts.
  ///
  /// An open confirm card is answered as a decline, so the change is not
  /// saved and the future the loop waits on completes. The tool_use and its
  /// declined tool_result live only in this turn's transcript, which is thrown
  /// away: the next request carries the stopped prose as plain text and no
  /// tool_use at all, so it can never hold a call without a result.
  ///
  /// Cancelling the subscription ends the service's generator, whose `finally`
  /// closes the HTTP client. The server may still finish the reply on its
  /// side; nobody reads it.
  void stop() {
    if (!canStop) return;
    _stopRequested = true;
    _cancelHop?.call();
    _cancelHop = null;
    final proposals = financeProposals;
    if (proposals?.batch != null) proposals!.decline();
    _advisorStatus = null;
    _advisorAttempt = 1;
    if (_messages.isNotEmpty && _messages.last.role == AiChatRole.assistant) {
      _updateLastMessage(_stoppedText(_messages.last.text), isStreaming: false);
    }
    safeNotify();
  }

  /// The reply as it stood when the user stopped it, marked so it does not
  /// read as a finished answer.
  static String _stoppedText(String shown) =>
      shown.trim().isEmpty ? '_Stopped._' : '$shown\n\n_Stopped._';

  /// Wraps a hop's event stream so [stop] can end it while it waits.
  ///
  /// `await for` only notices a stop when the next event arrives, and the
  /// slowest wait (the model thinking before its first word) has no events at
  /// all. Closing this wrapper ends the loop at once.
  ///
  /// The source is cancelled without awaiting it: a generator still waiting
  /// for response headers only finishes when they arrive, and the turn must
  /// not wait for that. Its errors after the cancel have nobody to tell.
  Stream<AdvisorEvent> _stoppable(Stream<AdvisorEvent> source) {
    StreamSubscription<AdvisorEvent>? sub;
    late final StreamController<AdvisorEvent> out;
    void cancelSource() => sub?.cancel().ignore();
    out = StreamController<AdvisorEvent>(
      onListen: () {
        sub = source.listen(out.add, onError: out.addError, onDone: out.close);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: cancelSource,
    );
    _cancelHop = () {
      cancelSource();
      out.close();
    };
    return out.stream;
  }

  /// Model round trips allowed inside one user turn.
  ///
  /// A runaway loop is the standard failure of this pattern, and the user pays
  /// for it in latency and in daily cap. Five is a starting value, not a
  /// measured one.
  static const int maxToolHops = 5;

  /// Run one advisor turn, including any tool loop it asks for.
  ///
  /// The transcript sent to the model is local to this turn rather than
  /// appended to [_messages]: tool_use and tool_result turns are protocol, not
  /// conversation, and rendering them as chat bubbles would show the user
  /// plumbing. They also must not be persisted — a resumed conversation
  /// replaying a half-finished tool loop would carry tool ids that mean
  /// nothing to a later turn.
  Future<void> _runAdvisorTurn(AiCoachService cloud, AiCoachContext context,
      {List<AiChatMessage>? resumeFrom}) async {
    final historical = context.financeHistoricalSummary();
    // A resumed turn carries on from the protocol transcript saved with its
    // batch, which already ends in that batch's results.
    final transcript = resumeFrom ?? _requestTranscript();
    // Tools are offered only when something can actually run them. Declaring
    // them with no executor would let the model propose changes that silently
    // never happen, which is worse than not offering.
    final tools = _toolExecutor == null ? const <AiTool>[] : kFinanceTools;
    _decideRoute(context);
    // The first hop needs no strip: the bubble is empty, so its own thinking
    // label is on screen. The strip is for after the model has written words.
    _advisorStatus = null;

    // Prose a hop wrote before the time budget cut its tool call. The resume
    // hop is told not to repeat it, so it stays on screen unless that hop
    // writes words of its own.
    var carried = '';
    var resumed = false;
    for (var hop = 1; hop <= maxToolHops; hop++) {
      if (_turnOver) return;
      final reply = await _streamAdvisorHopWithRetries(
        cloud,
        context: context,
        transcript: transcript,
        historical: historical,
        tools: tools,
      );
      if (_turnOver || reply == null) return;
      final text = reply.text.isEmpty ? carried : reply.text;

      if (!reply.wantsTools) {
        final cut = reply.interruptedTools;
        if (cut.isNotEmpty) {
          // The server ran out of time while the model was still writing a
          // tool call, so no card ever appeared. Ask once more, on a fresh
          // hop with a fresh budget, for just that call. Once only: a second
          // cut means the call itself is too large to finish.
          if (!resumed && reply.text.isNotEmpty && hop < maxToolHops) {
            resumed = true;
            carried = reply.text;
            _updateLastMessage(carried, isStreaming: true);
            transcript
              ..add(AiChatMessage.assistantToolUse(
                text: reply.text,
                contentBlocks: reply.assistantContent,
              ))
              ..add(AiChatMessage.user(_resumeCutToolPrompt(cut)));
            _advisorStatus = _workingStatus;
            safeNotify();
            continue;
          }
          _updateLastMessage(
            text.isEmpty ? _cutToolNotice : '$text\n\n_${_cutToolNotice}_',
            isStreaming: false,
          );
          return;
        }
        _updateLastMessage(text, isStreaming: false);
        return;
      }

      // Show any prose the model wrote alongside its tool calls, so the user
      // is not left watching an idle spinner while the tools run.
      if (reply.text.isNotEmpty) {
        _updateLastMessage(reply.text, isStreaming: true);
        safeNotify();
      }

      if (hop == maxToolHops) {
        // Out of hops with a tool call still pending. Say so rather than
        // leaving the last partial thought looking like a finished answer.
        // A routed conversation that runs out of hops goes to Sonnet.
        _escalateRoute();
        _updateLastMessage(
          reply.text.isEmpty
              ? "I couldn't finish that one. Try asking for one change at a time."
              : "${reply.text}\n\n_I couldn't finish that one. Try asking for "
                  "one change at a time._",
          isStreaming: false,
        );
        return;
      }

      transcript.add(AiChatMessage.assistantToolUse(
        text: reply.text,
        contentBlocks: reply.assistantContent,
      ));

      if (!await _runToolStep(reply.toolCalls, transcript)) return;
      // Tools are done; the next hop is another round trip of silence.
      _advisorStatus = _workingStatus;
      safeNotify();
    }
  }

  /// Runs one model step's tool calls and adds their results to [transcript].
  /// Returns false when the turn ended meanwhile.
  ///
  /// Reads run first, one by one, each named while it runs. Every write of
  /// the step then opens as ONE batch the user reviews in one list (Plan 065
  /// phase 4). While it is open the batch is saved, so an app restart finds it
  /// again ([resumeOpenBatch]); every tool_use still gets its tool_result.
  ///
  /// If the user typed instead of answering, their words ride in the same
  /// user turn as the "not approved" results, so Nudgy reads both at once and
  /// proposes a new batch in one hop.
  Future<bool> _runToolStep(
      List<AiToolCall> calls, List<AiChatMessage> transcript) async {
    final results = <String, Map<String, Object?>>{};
    final writes = <AiToolCall>[];
    for (final call in calls) {
      final tool = financeToolNamed(call.name);
      // An unknown tool or an input that breaks the schema means the routing
      // model is not coping: the rest of the conversation goes to Sonnet. The
      // call itself runs as before, and the executor answers it.
      if (tool == null || toolInputProblem(tool, call.input) != null) {
        _escalateRoute();
      }
      if (tool != null && tool.mutates && _toolExecutor != null) {
        writes.add(call);
        continue;
      }
      // Named before the call, not after: this is the stretch with nothing
      // else on screen, and the whole point is to say what is taking time
      // while it takes it.
      _advisorStatus = _statusFor(call);
      safeNotify();
      final result = await _runTool(call);
      if (_turnOver) return false;
      results[call.id] = result.toContentBlock();
    }
    if (writes.isNotEmpty) {
      _advisorStatus = null;
      safeNotify();
      _saveOpenBatch(transcript, writes);
      final answers = await _proposeBatch(writes);
      // A stop while the batch was open declines it, which is what completes
      // this await. The decline is not sent anywhere: no next hop starts.
      _clearOpenBatch();
      if (_turnOver) return false;
      for (final r in answers) {
        results[r.toolUseId] = r.toContentBlock();
      }
    }
    final revision = _revisionText;
    _revisionText = null;
    transcript.add(AiChatMessage.toolResults([
      for (final c in calls) results[c.id]!,
      if (revision != null) {'type': 'text', 'text': revision},
    ]));
    return true;
  }

  Future<List<AiToolResult>> _proposeBatch(List<AiToolCall> writes) async {
    final executor = _toolExecutor;
    if (executor == null) {
      return [
        for (final c in writes)
          AiToolResult.failed(c.id, 'Tools are unavailable in this session.'),
      ];
    }
    try {
      return await executor.proposeBatch(writes);
    } catch (e) {
      debugPrint('AiCoachPresenter batch failed: $e');
      return [
        for (final c in writes)
          AiToolResult.failed(
              c.id, 'That did not go through. Nothing was changed.'),
      ];
    }
  }

  /// Words the user typed while a batch was open, waiting to go to the model
  /// with the batch's "not approved" results.
  String? _revisionText;

  /// The user typed while Nudgy's batch waited: their message answers it.
  /// Nothing in the batch is saved, and the turn goes on to read what they
  /// wrote — no sub-session, and Nudgy keeps the whole context.
  void _reviseOpenBatch(String text) {
    final proposals = financeProposals;
    if (proposals == null) return;
    // The prose that introduced the batch is finished; the next hop writes a
    // new bubble below the user's message.
    if (_messages.isNotEmpty && _messages.last.role == AiChatRole.assistant) {
      final last = _messages.last;
      if (last.text.trim().isEmpty) {
        _messages.removeLast();
      } else {
        _updateLastMessage(last.text, isStreaming: false);
      }
    }
    _messages
      ..add(AiChatMessage.user(text))
      ..add(AiChatMessage.assistantStreaming());
    _revisionText = text;
    proposals.reviseAll(text);
    _persistAdvisor();
    safeNotify();
  }

  // ── An open batch across a restart ─────────────────────────────────────────

  /// How long a saved batch may wait for the user. After this the app does
  /// not show it again; Nudgy is told it was not reviewed.
  static const openBatchLifetime = Duration(hours: 24);

  void _saveOpenBatch(List<AiChatMessage> transcript, List<AiToolCall> writes) {
    final storage = _storage;
    final conversation = _currentConversationId;
    if (storage == null || conversation == null) return;
    storage.saveAdvisorOpenBatch({
      'conversationId': conversation,
      'savedAt': DateTime.now().toIso8601String(),
      'transcript': [for (final m in transcript) m.toJson()],
      'calls': [
        for (final c in writes) {'id': c.id, 'name': c.name, 'input': c.input},
      ],
    });
  }

  void _clearOpenBatch() => _storage?.saveAdvisorOpenBatch(null);

  /// True while [resumeOpenBatch] reads storage. A saved batch belongs to the
  /// current conversation, so no new conversation may start until it is known
  /// whether one waits.
  bool _checkingOpenBatch = false;

  /// Picks up a batch an app restart interrupted, in the conversation it
  /// belongs to. The batch is shown again; the user's answer then finishes
  /// the turn exactly as it would have. A batch that cannot be shown — too
  /// old, no tools in this build, no network to finish the turn — is
  /// answered "not reviewed", so its tool_use never goes without a result.
  Future<void> resumeOpenBatch() async {
    final storage = _storage;
    if (storage == null || _isResponding) return;
    _checkingOpenBatch = true;
    final Map<String, dynamic>? saved;
    try {
      saved = await storage.loadAdvisorOpenBatch();
    } finally {
      _checkingOpenBatch = false;
    }
    if (saved == null || isDisposed) return;
    if (saved['conversationId'] != _currentConversationId) return;
    final List<AiChatMessage> transcript;
    final List<AiToolCall> writes;
    try {
      transcript = [
        for (final m in saved['transcript'] as List)
          AiChatMessage.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      writes = [
        for (final c in saved['calls'] as List)
          AiToolCall(
            id: (c as Map)['id'] as String,
            name: c['name'] as String,
            input: Map<String, Object?>.from(c['input'] as Map),
          ),
      ];
    } catch (e) {
      debugPrint('AiCoachPresenter: unreadable open batch dropped: $e');
      _clearOpenBatch();
      return;
    }
    final savedAt = DateTime.tryParse(saved['savedAt'] as String? ?? '');
    final stale = savedAt == null ||
        DateTime.now().difference(savedAt) > openBatchLifetime;
    final cloud = _advisorService;

    _messages.add(AiChatMessage.assistantStreaming());
    _isResponding = true;
    _advisorRunning = true;
    _stopRequested = false;
    safeNotify();
    try {
      final List<AiToolResult> answers;
      if (stale || cloud == null || _toolExecutor == null) {
        answers = [for (final c in writes) _notReviewed(c.id)];
        _clearOpenBatch();
      } else {
        _saveOpenBatch(transcript, writes);
        answers = await _proposeBatch(writes);
        _clearOpenBatch();
      }
      if (_turnOver) return;
      final revision = _revisionText;
      _revisionText = null;
      transcript.add(AiChatMessage.toolResults([
        for (final r in answers) r.toContentBlock(),
        if (revision != null) {'type': 'text', 'text': revision},
      ]));
      if (cloud == null) {
        _messages.removeLast();
        return;
      }
      await _runAdvisorTurn(cloud, _buildContext(), resumeFrom: transcript);
    } finally {
      _advisorRunning = false;
      _isResponding = false;
      _cancelHop = null;
      if (_messages.isNotEmpty &&
          _messages.last.isStreaming &&
          _messages.last.text.isEmpty) {
        _messages.removeLast();
      }
      _persistAdvisor();
      safeNotify();
    }
  }

  static AiToolResult _notReviewed(String id) => AiToolResult(
        toolUseId: id,
        ok: false,
        summary: 'Not reviewed: the app closed before the user answered, so '
            'nothing was saved. Ask if they still want it.',
      );

  /// Shown between hops, when the model is being asked again and has not yet
  /// started writing.
  static const _workingStatus = 'Working on it…';

  /// Said when a tool call was cut off and asking again did not bring it
  /// back, so the user knows nothing was proposed or saved.
  static const _cutToolNotice =
      "I ran out of time before I could set that up, so nothing was saved. "
      'Ask me again and I will do just that part.';

  /// The protocol turn that asks the model to re-issue the tool calls in
  /// [names] after the server's time budget cut them off. Never shown or
  /// persisted: it lives only in this turn's transcript.
  static String _resumeCutToolPrompt(List<String> names) {
    final list = names.map((n) => '`$n`').join(', ');
    return '(Automatic follow-up from the app, not from the user.) Your '
        'previous reply hit the time limit while you were calling $list, so '
        'that call never arrived and nothing was proposed. Call it again now '
        'with the same details. Do not repeat what you already wrote.';
  }

  /// What to say while [call] runs.
  ///
  /// A mutation says nothing: it puts a confirm card on screen, and the card is
  /// a better answer to "what is happening" than any status line. A read says
  /// which of the user's own lists it is going through, so the wait reads as
  /// work rather than as a hang.
  static String? _statusFor(AiToolCall call) {
    if (financeToolNamed(call.name)?.mutates ?? false) return null;
    switch (call.name) {
      case 'find':
        return switch (call.input['entity']) {
          'bill' => 'Checking your bills…',
          'receivable' => "Checking what you're owed…",
          'setAside' => 'Checking your set-asides…',
          'budget' || 'budgetGroup' => 'Checking your budgets…',
          'installment' => 'Checking your installments…',
          'account' => 'Checking your accounts…',
          _ => 'Looking that up…',
        };
      case 'findTransactions':
        return 'Going through your transactions…';
      case 'checkAffordability':
        return 'Checking affordability…';
      case 'getView':
        return 'Reading your ${call.input['view'] ?? 'finance'} screen…';
    }
    return 'Looking that up…';
  }

  /// How many times a single advisor hop is attempted before giving up.
  ///
  /// Three, not one, because the failures this retries are the ones that had
  /// nothing to do with the request: a dropped connection, a 5xx, a stream that
  /// died mid-answer. Every one of those used to end the turn and leave the
  /// user to retype a question the app was still holding — the worst possible
  /// response to a fault that would have cleared on its own.
  ///
  /// Three is also where it stops. A retry is not free: a streamed turn is
  /// billed for the whole function duration whether or not anyone reads it, so
  /// an unbounded loop would quietly spend real money on an outage. Only
  /// [AiCoachException.retryable] failures are attempted again; an expired
  /// session or a spent daily cap fails once, immediately — and so does
  /// anything that took longer than [defaultRetryHorizon] to fail, which is
  /// the case three attempts made worse rather than better.
  static const maxAdvisorAttempts = 3;

  /// Backoff before each retry. Deliberately short — someone is watching this
  /// happen, and a 5-second pause reads as the app having hung rather than as
  /// patience.
  static const _retryBackoff = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  /// How long an attempt may run, by default, before retrying it stops being
  /// worth doing.
  ///
  /// [maxAdvisorAttempts] assumes the fault was a blip: a dropped connection, a
  /// 5xx, a TLS handshake refused. Those fail in the first second or two, cost
  /// nothing to run again, and usually work on the second go.
  ///
  /// A hop that streamed prose for half a minute and *then* died did not hit a
  /// blip. It hit a ceiling — the advisor's own wall clock — and the next
  /// attempt writes the same long answer into the same ceiling and dies at the
  /// same place. That is what the "connection hiccup" strip was reporting on
  /// long answers: three full re-generations of a reply the user was already
  /// reading, each one wiping the screen first, each one billed in full, and
  /// the same failure at the end of it.
  ///
  /// So past this mark a retryable failure is surfaced instead of retried. The
  /// half-written answer stays on screen (it is the only part that arrived) and
  /// the manual retry affordance stays available — re-spending the turn is then
  /// the user's call, not a loop's.
  ///
  /// Twenty seconds because no blip takes that long to happen, and no advisor
  /// answer that is going to fit finishes that late. It deliberately gives up
  /// on one real case: a genuine mid-stream network drop at second 25 is now
  /// surfaced rather than retried. The partial is kept, which is the better
  /// trade against re-running every long answer three times.
  static const defaultRetryHorizon = Duration(seconds: 20);

  /// Injected so a test can state the horizon instead of waiting out the real
  /// one. [Duration.zero] means no patience at all: every failure counts as
  /// late, which is how the "do not re-generate a long answer" path is
  /// exercised without a twenty-second test.
  final Duration _retryHorizon;

  /// The attempt currently in flight, 1-based. Anything above 1 means a retry
  /// is underway, which the UI says out loud rather than leaving the user
  /// staring at a spinner that restarted for no visible reason.
  int _advisorAttempt = 1;
  int get advisorAttempt => _advisorAttempt;
  bool get isRetryingAdvisor => _advisorAttempt > 1;

  /// Runs one hop, retrying transient failures up to [maxAdvisorAttempts].
  Future<AdvisorReply?> _streamAdvisorHopWithRetries(
    AiCoachService cloud, {
    required AiCoachContext context,
    required List<AiChatMessage> transcript,
    required String historical,
    required List<AiTool> tools,
  }) async {
    for (var attempt = 1; attempt <= maxAdvisorAttempts; attempt++) {
      _advisorAttempt = attempt;
      if (attempt > 1) {
        // Clear the abandoned prose before the next attempt writes over it.
        // Without this the retry's deltas append to half an answer and the user
        // reads two beginnings stitched together.
        _updateLastMessage('', isStreaming: true);
        _errorMessage = null;
        safeNotify();
        await Future<void>.delayed(
            _retryBackoff[(attempt - 2).clamp(0, _retryBackoff.length - 1)]);
        if (_turnOver) return null;
      }

      // Timed, not just counted: how long the attempt lasted is what says
      // whether it hit a blip or a ceiling. See [defaultRetryHorizon].
      final clock = Stopwatch()..start();
      final outcome = await _streamAdvisorHop(
        cloud,
        context: context,
        transcript: transcript,
        historical: historical,
        tools: tools,
      );
      clock.stop();
      if (_turnOver) return null;
      if (outcome.reply != null) {
        _advisorAttempt = 1;
        return outcome.reply;
      }

      final failure = outcome.failure;
      final isLast = attempt == maxAdvisorAttempts;
      final ranTooLong = clock.elapsed >= _retryHorizon;
      if (failure == null || !failure.retryable || isLast || ranTooLong) {
        _advisorAttempt = 1;
        final message = _messageForFailure(
          failure,
          outcome.partial,
          ranTooLong: ranTooLong,
        );
        // Only now does the failure reach the user, so two silent recoveries
        // look like one slightly slow answer rather than three errors.
        _failAdvisorHop(outcome.partial, message,
            retryable: failure?.retryable ?? false);
        return null;
      }
      debugPrint('AiCoachPresenter advisor attempt $attempt failed after '
          '${clock.elapsedMilliseconds}ms, retrying: ${failure.userMessage}');
    }
    return null;
  }

  static const _genericFailure = 'Something went wrong. Try again.';

  /// What to put on screen for a hop that did not produce a reply.
  ///
  /// The service's own message is right for everything except one case: an
  /// answer that streamed for a long time and then stopped. "Try again" is bad
  /// advice there — the same question produces the same long answer and it
  /// stops in the same place. Asking for less, or for the rest of it, is the
  /// thing that actually works, so say that instead.
  static String _messageForFailure(AiCoachException? failure, String partial,
      {required bool ranTooLong}) {
    // Only for a fault we would otherwise have retried. A refused session that
    // happened to take 25 seconds to come back still needs its own message —
    // this copy would send the user to shorten a question that was never the
    // problem.
    if (ranTooLong &&
        (failure?.retryable ?? false) &&
        partial.trim().isNotEmpty) {
      return 'That answer ran long and stopped partway. Ask me to carry on '
          'from where it stopped, or for a shorter version.';
    }
    return failure?.userMessage ?? _genericFailure;
  }

  /// Runs one hop of the advisor, rendering its prose as it arrives.
  ///
  /// Reports the outcome rather than settling the UI, because the caller may
  /// be about to try again — and a failed attempt that has already written an
  /// error to the screen cannot be retried invisibly.
  ///
  /// A failure carries its partial prose back with it. A half-written answer is
  /// real work the user may still want, and the alternative (wiping it for a
  /// red bar) throws away the only part of a slow turn that arrived.
  ///
  /// Mirrors what `respond()` already does for the general coach: accumulate,
  /// update, notify, and stop the moment the sheet goes away.
  Future<AdvisorHopOutcome> _streamAdvisorHop(
    AiCoachService cloud, {
    required AiCoachContext context,
    required List<AiChatMessage> transcript,
    required String historical,
    required List<AiTool> tools,
  }) async {
    final buffer = StringBuffer();
    AdvisorReply? finished;

    try {
      final stream = _stoppable(cloud.adviseFinance(
        messages: transcript,
        context: context,
        profile: _advisorProfile.promptSummary(),
        historical: historical.isEmpty ? null : historical,
        tools: tools,
        // Read on each hop, so an escalation takes effect on the next one.
        route: _currentConversation?.route?.wireName,
      ));

      await for (final event in stream) {
        // Checked per event, not only at the end: events already queued when
        // the user stopped must not write over the stopped reply.
        if (_turnOver) return const AdvisorHopOutcome.abandoned();
        switch (event.kind) {
          case AdvisorEventKind.start:
            break;
          case AdvisorEventKind.delta:
            // Words are arriving, so the strip has nothing left to explain.
            _advisorStatus = null;
            buffer.write(event.text);
            _updateLastMessage(buffer.toString(), isStreaming: true);
            safeNotify();
          case AdvisorEventKind.end:
            finished = event.reply;
          case AdvisorEventKind.error:
            // The server reported its own failure in-band, which it only does
            // for a turn that died in flight — worth another attempt.
            throw AiCoachException(
                event.message ??
                    'The advisor stopped partway through. Try again.',
                retryable: true);
        }
      }
      // A stop closes the stream with no terminal event. That is the user's
      // choice, not a cut-off answer, so it is not reported as a failure.
      if (_turnOver) return const AdvisorHopOutcome.abandoned();
    } on AiCoachException catch (e) {
      return AdvisorHopOutcome.failed(buffer.toString(), e);
    } catch (e) {
      debugPrint('AiCoachPresenter advisor stream error: $e');
      return AdvisorHopOutcome.failed(
          buffer.toString(),
          const AiCoachException(
              'The advisor stopped partway through. Try again.',
              retryable: true));
    }

    if (finished == null) {
      // The stream completed without a terminal event. Never treat this as a
      // short answer: that is precisely how half a reply gets presented as all
      // of it.
      return AdvisorHopOutcome.failed(
          buffer.toString(),
          const AiCoachException(
              'The advisor was cut off mid-answer. Try again.',
              retryable: true));
    }
    return AdvisorHopOutcome.done(finished);
  }

  /// Settles a failed advisor hop: keep whatever prose arrived, mark it
  /// unfinished, and surface why.
  ///
  /// [retryable] is what the retry affordance keys off. A failure the user can
  /// do nothing about (an expired session, a spent cap) should not offer a
  /// button whose only effect is to fail again.
  void _failAdvisorHop(String partial, String message,
      {required bool retryable}) {
    _errorMessage = message;
    _lastTurnRetryable = retryable;
    _updateLastMessage(partial, isStreaming: false);
    safeNotify();
  }

  /// True when the last turn failed in a way that retrying could fix.
  bool _lastTurnRetryable = false;
  bool get canRetryLastTurn =>
      _errorMessage != null && _lastTurnRetryable && !_isResponding;

  /// Dispatch one tool call. Reads run; mutations become proposals.
  Future<AiToolResult> _runTool(AiToolCall call) async {
    final executor = _toolExecutor;
    if (executor == null) {
      return AiToolResult.failed(
          call.id, 'Tools are unavailable in this session.');
    }
    final tool = financeToolNamed(call.name);
    if (tool == null) {
      // The model named something that is not in the catalogue it was given.
      // Say so plainly instead of guessing at an intent.
      return AiToolResult.failed(
          call.id, 'There is no tool called "${call.name}".');
    }
    try {
      return tool.mutates
          ? await executor.propose(call)
          : await executor.runRead(call);
    } catch (e) {
      debugPrint('AiCoachPresenter tool ${call.name} failed: $e');
      return AiToolResult.failed(
          call.id, 'That did not go through. Nothing was changed.');
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

  // ── Memory (Plan 065 phase 5) ─────────────────────────────────────────────

  /// Silence after which the next advisor message starts a new conversation.
  /// The old one stays in [conversations], one tap away.
  static const idleGapForNewConversation = Duration(hours: 6);

  /// A request sends at most this many messages before the oldest are dropped.
  static const int requestTrimThreshold = 50;

  /// How many of the oldest messages one trim drops.
  static const int requestTrimChunk = 20;

  /// True when the next advisor message starts a new conversation: the
  /// current one has messages and has been silent for longer than
  /// [idleGapForNewConversation].
  ///
  /// Never while a turn runs or a batch of changes waits, and never while a
  /// saved batch is being read back: a batch belongs to the conversation it
  /// was proposed in, and a new one would leave it without a home. Never for
  /// the other coaches, whose threads are not saved. Never while the ledger
  /// waits for an answer to its question, because the reply belongs to it.
  bool get startsFreshAfterIdleGap {
    if (_entryPoint != AiCoachEntryPoint.financeAdvisor) return false;
    if (_isResponding || _advisorRunning || _checkingOpenBatch) return false;
    if (financeProposals?.batch != null) return false;
    if (_ledger?.chatState.phase == ChatPhase.clarifying) return false;
    if (_messages.isEmpty) return false;
    var lastActivity = _messages.last.timestamp;
    final chosenAt = _conversationChosenAt;
    if (chosenAt != null && chosenAt.isAfter(lastActivity)) {
      lastActivity = chosenAt;
    }
    return _clock().difference(lastActivity) > idleGapForNewConversation;
  }

  /// When the user last picked the current conversation from the list, or
  /// null when the app picked it. Picking an old chat is a choice to go on
  /// with it, so it counts as activity: the next message stays in it.
  DateTime? _conversationChosenAt;

  /// What a request sends of [transcript].
  ///
  /// Up to [requestTrimThreshold] messages go as they are. Past it, the oldest
  /// messages are dropped in whole chunks of [requestTrimChunk], so the start
  /// of the request stays the same from one trim to the next and the prompt
  /// cache keeps its prefix. A trim on every turn would move the start on
  /// every turn and the cache would never hit.
  ///
  /// The cut never separates a user message from its reply: a cut that lands
  /// on a reply moves forward to the next user message, which also makes the
  /// request start with the user, as the model requires.
  ///
  /// There is no summary of what was dropped. A summary loses numbers, and
  /// the numbers are what the user asks about.
  static List<AiChatMessage> trimForRequest(List<AiChatMessage> transcript) {
    final over = transcript.length - requestTrimThreshold;
    if (over <= 0) return transcript;
    final chunks = (over + requestTrimChunk - 1) ~/ requestTrimChunk;
    final chunkCut = chunks * requestTrimChunk;
    var cut = chunkCut;
    while (cut < transcript.length && transcript[cut].role != AiChatRole.user) {
      cut++;
    }
    return transcript.sublist(cut < transcript.length ? cut : chunkCut);
  }

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
    _conversationChosenAt = null;
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
    _conversationChosenAt = _clock();
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
      _conversationChosenAt = null;
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

  // ── Model route (Plan 065, phase 5) ────────────────────────────────────────

  /// Fixes the current conversation's route when its first advisor message
  /// is sent. A route already set is kept for the conversation's life.
  void _decideRoute(AiCoachContext context) {
    _ensureCurrentConversation();
    final convo = _currentConversation!;
    if (convo.route != null) return;
    final users = _messages.where((m) => m.role == AiChatRole.user).toList();
    // More than one user message: the conversation started before routing
    // existed, so it already ran on Sonnet.
    final route = users.length == 1
        ? routeForFirstMessage(users.single.text,
            hasImages: context.images.isNotEmpty)
        : AdvisorRoute.sonnet;
    _replaceCurrentConversation(convo.copyWith(route: route));
  }

  /// Moves a Haiku conversation to Sonnet for good. Never back: each model
  /// writes its own cache of the history, so going back and forth would pay
  /// for both. The escalation itself costs one cache rewrite, because Sonnet
  /// has no cache of this conversation yet and its first hop writes one.
  void _escalateRoute() {
    final convo = _currentConversation;
    if (convo == null || convo.route != AdvisorRoute.haiku) return;
    _replaceCurrentConversation(convo.copyWith(route: AdvisorRoute.sonnet));
  }

  void _replaceCurrentConversation(AdvisorConversation convo) {
    final idx = _conversations.indexWhere((c) => c.id == convo.id);
    if (idx != -1) _conversations[idx] = convo;
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

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _initOnDevice() async {
    final svc = OnDeviceAiCoachService();
    await svc.init();
    _service = svc;
    _isInitializing = false;
    safeNotify();
  }

  /// One image resized for the vision endpoint, or the original bytes when
  /// the codec fails — a too-large image the server refuses is a clearer
  /// failure than a silently missing one.
  Future<Uint8List> _compressForUpload(Uint8List image) async {
    try {
      return await _imageCompressor.compressForUpload(image);
    } catch (e) {
      debugPrint('AiCoachPresenter.send image compress failed: $e');
      return image;
    }
  }

  static final Random _traceRandom = Random.secure();

  /// A fresh advisor trace id: 16 random hex characters. It names one user
  /// message in the server's cost lines and carries nothing about the user.
  @visibleForTesting
  static String newTraceId() => [
        for (var i = 0; i < 8; i++)
          _traceRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();

  AiCoachContext _buildContext({List<Uint8List> images = const []}) {
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
    var completedGoals = const <AdvisorCompletedGoalLine>[];
    var liquidAccounts = const <AdvisorAccountLine>[];
    var savingsAccounts = const <AdvisorAccountLine>[];
    var investmentAccounts = const <AdvisorAccountLine>[];
    var subAccounts = const <AdvisorSubAccountLine>[];
    var heldLines = const <AdvisorHeldLine>[];
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
      final accountNames = {for (final a in t.accounts) a.id: a.name};
      // Every category with spend, not the dashboard's top 10: the advisor is
      // asked about specific line items, and a category outside the top 10 was
      // simply invisible to it — indistinguishable from one with no spend.
      final trailing = t.categoryTrailingAverage(months: 3);
      // This month's budget per category — not the Budget tab's month, which
      // may be parked anywhere.
      final thisMonth = toMonthKey(DateTime.now());
      final targets = {
        for (final x in b?.allBudgets ?? const <Budget>[])
          if (x.month == thisMonth) x.categoryId: x.allocatedAmount,
      };
      final spent = t.allCategorySpendThisMonth;
      final spentIds = {for (final e in spent) e.$1.id};
      topCategories = [
        for (final e in spent)
          AdvisorCategoryLine(
            name: e.$1.name,
            target: targets[e.$1.id],
            actual: e.$2,
            trailingAverage: trailing.averages[e.$1.id],
            trailingMonths: trailing.months,
          ),
        // Budgeted with nothing spent yet. Built from spending alone, the list
        // left these out, so a ₱2,000 Gifts budget did not exist to Nudgy
        // until the first gift was bought.
        // An income category is a target to earn, not spending: listed here
        // it read as "₱0 of ₱X" spent.
        if (b != null)
          for (final c in b.categoriesByGroup.values.expand((cs) => cs))
            if (!spentIds.contains(c.id) &&
                c.type != CategoryType.income &&
                (targets[c.id] ?? 0) > 0)
              AdvisorCategoryLine(
                name: c.name,
                target: targets[c.id],
                actual: 0,
                trailingAverage: trailing.averages[c.id],
                trailingMonths: trailing.months,
              ),
      ];
      outstandingBills = t.upcomingBills.map((bill) {
        final isStatement = bill.billType == BillType.creditCard;
        // A part-paid statement owes only what is left — the figure the
        // total under these lines already uses.
        final left = isStatement ? creditStatementRemaining(bill) : bill.amount;
        final note = bill.paymentNote?.trim();
        return AdvisorBillLine(
          name: bill.name,
          amount: left,
          dueLabel: _billDueLabel(bill.dueDay),
          fullAmount: left < bill.amount - 0.005 ? bill.amount : null,
          // On a statement the account is the card itself, not where the
          // payment comes from.
          payFrom: isStatement ? null : accountNames[bill.accountId],
          paymentNote: bill.isAutoStatement || note == null || note.isEmpty
              ? null
              : note,
        );
      }).toList();
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
        final s = t.creditStatementBreakdown(a);
        return AdvisorCreditLine(
          name: a.name,
          // Total debt, installments included — the figure the dashboard
          // shows. The billed balance alone told Nudgy a card with ₱5,333 of
          // installments on it owed ₱397.
          owed: a.totalDebt,
          available: a.availableCredit,
          // The when alone: the minimum is its own field, and the dashboard's
          // due line already carries it.
          dueLabel: t.creditDueWhenLabel(a),
          minimumDue: t.creditMinimumDue(a),
          aprMonthly: a.financeChargeRate,
          utilization: a.utilization,
          // The statement balance is what avoids interest. Without it Nudgy
          // had only the total and the minimum, and sent the user to the
          // bank's app for a figure this app already held.
          statementAmount: s?.statementAmount,
          statementPaid: s?.statementPaid,
          statementRemaining: s?.statementRemaining,
          statementCloseLabel: s?.statementClose == null
              ? null
              : DateFormat('MMM d').format(s!.statementClose!),
          sinceClose: s?.sinceClose,
          nextCloseLabel: s?.nextClose == null
              ? null
              : DateFormat('MMM d').format(s!.nextClose!),
          installmentsUnbilled:
              a.unbilledInstallments > 0 ? a.unbilledInstallments : null,
          payInFull: a.effectiveMinimumRule == CreditMinimumRule.payInFull,
        );
      }).toList();
      netWorthTrend = t
          .netWorthTrend(months: 12)
          // With the year: the trend runs 12 months, so a bare "Oct" is
          // both this October and last.
          .map((p) => AdvisorNetWorthPoint(
              label: _monthYearLabel(p.month), value: p.value))
          .toList();
      // A year, so a seasonal month reads as seasonal.
      var cumulative = 0.0;
      incomeExpenseTrend = [
        for (final m in t.incomeExpenseTrend(months: 12))
          AdvisorMonthFlow(
            label: _monthYearLabel(m.month),
            income: m.income,
            expense: m.expense,
            // The history owner's figure, the one closed months are filed
            // with, so the current month is measured the same way.
            savingsContribution: _history?.monthlySavingsContribution(m.month),
            cumulativeNet: cumulative += m.income - m.expense,
          ),
      ];
      // Savings accounts with a target are goals too (the dashboard's goal
      // cards show both); spent goals have their own list below.
      goals = t.activeGoalAccounts.map((a) {
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
      completedGoals = [
        for (final a in t.completedGoalAccounts)
          AdvisorCompletedGoalLine(
            name: a.name,
            target: a.goalTarget,
            spent: a.goalRedeemedAmount,
            dateLabel: DateFormat('MMM yyyy').format(a.goalRedeemedAt!),
          ),
      ];
      final held = t.heldAmountByAccountId;
      liquidAccounts = t.liquidAccounts
          .map((a) => AdvisorAccountLine(
                name: a.name,
                balance: a.balance,
                held: held[a.id],
              ))
          .toList();
      savingsAccounts = [
        for (final a in t.savingsAccounts)
          if ((a.goalTarget ?? 0) <= 0 && a.parentAccountId == null)
            AdvisorAccountLine(name: a.name, balance: a.balance),
      ];
      investmentAccounts = [
        for (final a in t.investmentAccounts)
          AdvisorAccountLine(name: a.name, balance: a.balance),
      ];
      subAccounts = [
        for (final e in t.subAccounts)
          AdvisorSubAccountLine(
            name: e.account.name,
            balance: e.account.balance,
            parentName: e.parentName,
          ),
      ];
      heldLines = [
        for (final h in t.heldForOthersLines)
          AdvisorHeldLine(
            name: h.name,
            amount: h.amount,
            insideAccount: h.insideAccount,
          ),
      ];
      // The dashboard's per-group figures, for this calendar month.
      final allocatedByGroup = t.budgetAllocatedByGroup;
      final spentByGroup = t.budgetSpentByGroup;
      budgetGroups = [
        for (final g in t.budgetGroups)
          if ((allocatedByGroup[g.id] ?? 0) > 0)
            AdvisorBudgetGroupLine(
              name: g.name,
              allocated: allocatedByGroup[g.id]!,
              spent: spentByGroup[g.id] ?? 0,
            ),
      ];
      final inst = _installments;
      if (inst != null) {
        installmentLines = inst.installments
            .where((i) => inst.remainingMonths(i.id) > 0)
            .map((i) => AdvisorInstallmentLine(
                  name: i.name,
                  monthlyAmount: i.monthlyAmount,
                  remainingMonths: inst.remainingMonths(i.id),
                  remainingAmount: inst.remainingAmount(i.id),
                  account: accountNames[i.accountId],
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
                account: r.account,
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
                label: _monthYearLabel(m.month),
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
      today: isAdvisor ? DateTime.now() : null,
      images: isAdvisor ? images : const [],
      imageMimeType: isAdvisor && images.isNotEmpty ? 'image/jpeg' : null,
      // Built once per user message, so every hop and retry of it shares it.
      traceId: isAdvisor ? newTraceId() : null,
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
      expenseBudgetAllocated: isAdvisor && (t?.hasBudget ?? false)
          ? t?.totalExpenseBudgetAllocated
          : null,
      expenseBudgetSpent: isAdvisor && (t?.hasBudget ?? false)
          ? t?.totalExpenseBudgetSpent
          : null,
      allBudgetsAllocated:
          isAdvisor && (t?.hasBudget ?? false) ? t?.totalBudgetAllocated : null,
      allBudgetsUsed:
          isAdvisor && (t?.hasBudget ?? false) ? t?.totalBudgetSpent : null,
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
      heldForOthersLines: heldLines,
      savingsAccounts: savingsAccounts,
      investmentAccounts: investmentAccounts,
      subAccounts: subAccounts,
      completedGoals: completedGoals,
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

  /// Does [text] ask for something only Nudgy's tools can create — an
  /// installment, a bill with a due day, a set-aside, a receivable?
  ///
  /// [looksLikeExpenseLog] treats "add", "pay" and "bill" as spend verbs, so
  /// without this carve-out "add an installment for my phone 24000 over 12
  /// months" went to the ledger's transaction pipeline and came back as a plain
  /// ₱24,000 expense, an error, or nothing at all. Nudgy never saw it, so its
  /// suggestion card could never appear for the very sentence that asks for
  /// one.
  ///
  /// Erring toward Nudgy is cheap: it can still log a plain expense through
  /// `logTransactions`, which lands on the same review card. Erring toward the
  /// ledger is a dead end, because the ledger only knows transactions.
  static bool isAdvisorToolRequest(String text) => _advisorToolIntent.hasMatch(
        text.toLowerCase(),
      );

  static final _advisorToolIntent = RegExp(
    // Installments, by name or by their terms ("12 months", "0%").
    r'\b(instal{1,2}ments?|hulugan|bnpl)\b'
    r'|\b\d+\s*-?\s*(months?|mos?)\b'
    r'|\b0\s*%'
    // Set-asides and sinking funds.
    r'|\bset[\s-]?asides?\b|\bsinking\s+funds?\b'
    // Receivables.
    r'|\breceivables?\b'
    // A bill to track rather than one already paid: it has a due day.
    r'|\bdue\b',
  );

  /// True when [text] should go to the ledger's confirm-before-commit pipeline
  /// rather than to Nudgy.
  bool _routesToLedger(String text, LedgerPresenter ledger) {
    if (ledger.chatState.phase == ChatPhase.clarifying) return true;
    // A request for something only a tool can create belongs to Nudgy — but
    // only when this build has tools to carry it out.
    if (_toolExecutor != null && isAdvisorToolRequest(text)) return false;
    return looksLikeExpenseLog(text) || ledger.recognisesLoggableEntry(text);
  }

  /// True when the ledger read a routed message and found nothing to log.
  ///
  /// The extractor says so by asking a question back, and that question lives
  /// on [LedgerChatState.unclear] — which no chat surface renders. Left alone,
  /// the user's message sat in the thread with no reply, no card and no error.
  static bool _ledgerFoundNothing(LedgerPresenter ledger) {
    final state = ledger.chatState;
    return state.phase == ChatPhase.idle &&
        state.unclear != null &&
        state.entries.isEmpty &&
        state.lastStep == null &&
        ledger.chatHardError == null;
  }

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
    // A plan is advice too: "I want to pay 5000 for the BPI card next month"
    // has an amount and a spend verb, but nothing has been spent yet.
    if (hasPlanningIntent(t)) return false;
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

  /// The conversation as the next request sends it: every settled message,
  /// trimmed by [trimForRequest]. The thread on screen and in storage keeps
  /// all of it.
  List<AiChatMessage> _requestTranscript() =>
      trimForRequest(_userVisibleMessages());

  void _updateLastMessage(String text, {required bool isStreaming}) {
    if (_messages.isEmpty) return;
    _messages[_messages.length - 1] =
        _messages.last.copyWith(text: text, isStreaming: isStreaming);
  }
}
