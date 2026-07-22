import 'package:flutter/material.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/food_db_entry.dart';
import '../models/food_parse_result.dart';
import '../presenters/budget_presenter.dart';
import '../presenters/fasting_presenter.dart';
import '../presenters/ledger_presenter.dart';
import '../presenters/nutrition_presenter.dart';
import '../presenters/stats_presenter.dart';
import '../presenters/treasury_dashboard_presenter.dart';
import '../services/ai_coach_service.dart';
import '../services/null_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../utils/safe_notifier.dart';

const int _maxHistoryMessages = 50;

class AiCoachPresenter extends ChangeNotifier with SafeNotifier {
  final StatsPresenter _stats;
  final FastingPresenter _fasting;
  final NutritionPresenter? _nutrition;
  final TreasuryDashboardPresenter? _treasury;
  final BudgetPresenter? _budget;

  /// Ledger used by the financial-advisor mode to log expenses in-conversation
  /// through the existing confirm-before-commit pipeline. Null when finance
  /// isn't wired (advisor logging simply unavailable).
  final LedgerPresenter? _ledger;

  AiCoachService _service;

  /// Optional cloud tier used only when the primary [_service] is unavailable
  /// (e.g. the on-device model isn't downloaded). Chat falls back to this for
  /// that response; the primary service is preferred whenever it's ready.
  final AiCoachService? _cloudFallback;

  AiCoachTier _activeTier = AiCoachTier.onDevice;

  AiCoachEntryPoint _entryPoint = AiCoachEntryPoint.general;
  final List<AiChatMessage> _messages = [];
  bool _isResponding = false;
  bool _isThinkingEnabled = false;
  bool _isInitializing = true;
  String? _errorMessage;

  AiCoachPresenter({
    required StatsPresenter stats,
    required FastingPresenter fasting,
    NutritionPresenter? nutrition,
    AiCoachService? service,
    TreasuryDashboardPresenter? treasury,
    BudgetPresenter? budget,
    LedgerPresenter? ledger,
    AiCoachService? cloudFallback,
  })  : _stats = stats,
        _fasting = fasting,
        _nutrition = nutrition,
        _treasury = treasury,
        _budget = budget,
        _ledger = ledger,
        _cloudFallback = cloudFallback,
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

  /// Open a new chat session scoped to [entryPoint].
  void openSession(AiCoachEntryPoint entryPoint) {
    _entryPoint = entryPoint;
    _messages.clear();
    _errorMessage = null;
    safeNotify();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    if (text.trim().isEmpty || _isResponding) return;

    final userMsg = AiChatMessage.user(text.trim());
    _messages.add(userMsg);
    _errorMessage = null;
    _isResponding = true;
    safeNotify();

    // Add streaming placeholder for assistant.
    final assistantMsg = AiChatMessage.assistantStreaming();
    _messages.add(assistantMsg);
    safeNotify();

    try {
      final context = _buildContext();
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
        stream = cloud.adviseFinance(
          messages: _userVisibleMessages(),
          context: context,
          // Learned profile + historical benchmark are wired in a later task.
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

  void clearHistory() {
    _messages.clear();
    _errorMessage = null;
    safeNotify();
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

  AiCoachContext _buildContext() {
    final stats = _stats.stats;
    final n = _nutrition;
    final t = _treasury;
    final b = _budget;

    // The rich finance snapshot is only assembled for the advisor — it keeps
    // the RPG coach's prompt lean and avoids extra per-message computation.
    final isAdvisor = _entryPoint == AiCoachEntryPoint.financeAdvisor;
    var topCategories = const <AdvisorCategoryLine>[];
    var outstandingBills = const <AdvisorBillLine>[];
    if (isAdvisor && t != null) {
      topCategories = t.categorySpendThisMonth
          .map((e) => AdvisorCategoryLine(
                name: e.$1.name,
                target: b?.budgetFor(e.$1.id)?.allocatedAmount,
                actual: e.$2,
              ))
          .toList();
      outstandingBills = t.upcomingBills
          .map((bill) => AdvisorBillLine(name: bill.name, amount: bill.amount))
          .toList();
    }
    final savingsRate = t?.savingsRate;

    return AiCoachContext(
      entryPoint: _entryPoint,
      isFasting: _fasting.isFasting,
      elapsedFastMinutes:
          _fasting.isFasting ? _fasting.elapsedSeconds ~/ 60 : null,
      fastingGoalHours: _fasting.fastingGoalHours,
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
    );
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

  /// Heuristic: does [text] read as an expense to log (an amount plus a spend
  /// verb/keyword) rather than an advisory question? Used by the advisor mode
  /// to route logging intents into the confirm-before-commit ledger pipeline.
  /// Deliberately conservative — anything ambiguous stays as advice.
  static bool looksLikeExpenseLog(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;
    // A question is advice, never a log.
    if (t.contains('?')) return false;
    final hasAmount = RegExp(r'(₱|php|p)?\s?\d[\d,]*(\.\d+)?').hasMatch(t);
    if (!hasAmount) return false;
    final hasLogVerb = RegExp(
      r'\b(log|spent|spend|paid|pay|bought|buy|add|record|got|grabbed|bill)\b',
    ).hasMatch(t);
    // Short "coffee 120"-style entries (2–4 tokens with an amount) are logs too.
    final tokens = t.split(RegExp(r'\s+'));
    final terse = tokens.length <= 4;
    return hasLogVerb || terse;
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
