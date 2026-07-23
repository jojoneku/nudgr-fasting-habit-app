import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
import '../services/ai_coach_service.dart';
import '../services/null_ai_coach_service.dart';
import '../services/on_device_ai_coach_service.dart';
import '../services/storage_service.dart';
import '../utils/safe_notifier.dart';

const int _maxHistoryMessages = 50;

class AiCoachPresenter extends ChangeNotifier with SafeNotifier {
  final StatsPresenter _stats;
  final FastingPresenter _fasting;
  final NutritionPresenter? _nutrition;
  final TreasuryDashboardPresenter? _treasury;
  final BudgetPresenter? _budget;

  /// Active installment / BNPL plans — a fixed monthly commitment the advisor
  /// must account for when judging affordability. Null when finance isn't wired.
  final InstallmentPresenter? _installments;

  /// Ledger used by the financial-advisor mode to log expenses in-conversation
  /// through the existing confirm-before-commit pipeline. Null when finance
  /// isn't wired (advisor logging simply unavailable).
  final LedgerPresenter? _ledger;

  /// Persists advisor chat history + the learned profile (local-only for now).
  final StorageService? _storage;

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
    InstallmentPresenter? installments,
    LedgerPresenter? ledger,
    StorageService? storage,
    AiCoachService? cloudFallback,
  })  : _stats = stats,
        _fasting = fasting,
        _nutrition = nutrition,
        _treasury = treasury,
        _budget = budget,
        _installments = installments,
        _ledger = ledger,
        _storage = storage,
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
    if (storage == null) return;
    final history = await storage.loadAdvisorHistory();
    final profile = await storage.loadAdvisorProfile();
    if (isDisposed) return;
    _messages
      ..clear()
      ..addAll(history);
    _advisorProfile = profile ?? AdvisorProfile.empty();
    safeNotify();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isResponding) return;

    // Advisor logging: a clear expense-log intent — or any reply while the
    // ledger is mid-clarify — goes through the ledger's confirm-before-commit
    // pipeline instead of the advice model. The sheet renders the confirm card.
    final ledger = _ledger;
    if (_entryPoint == AiCoachEntryPoint.financeAdvisor &&
        ledger != null &&
        (ledger.chatState.phase == ChatPhase.clarifying ||
            looksLikeExpenseLog(trimmed))) {
      _messages.add(AiChatMessage.user(trimmed));
      _errorMessage = null;
      _isResponding = true;
      safeNotify();
      try {
        await ledger.sendChatInput(trimmed);
      } finally {
        _isResponding = false;
        _storage?.saveAdvisorHistory(_messages);
        safeNotify();
      }
      return;
    }

    final userMsg = AiChatMessage.user(trimmed);
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
        _storage?.saveAdvisorHistory(_messages);
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

  void clearHistory() {
    _messages.clear();
    _errorMessage = null;
    if (_entryPoint == AiCoachEntryPoint.financeAdvisor) {
      _storage?.clearAdvisorHistory();
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
      _storage?.saveAdvisorHistory(_messages);
    }
    safeNotify();
  }

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
    if (isAdvisor && t != null) {
      topCategories = t.categorySpendThisMonth
          .map((e) => AdvisorCategoryLine(
                name: e.$1.name,
                target: b?.budgetFor(e.$1.id)?.allocatedAmount,
                actual: e.$2,
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
          .netWorthTrend(months: 6)
          .map((p) => AdvisorNetWorthPoint(label: p.label, value: p.value))
          .toList();
      incomeExpenseTrend = t
          .incomeExpenseTrend(months: 6)
          .map((m) => AdvisorMonthFlow(
                label: m.label,
                income: m.income,
                expense: m.expense,
              ))
          .toList();
      goals = t.goalAccounts
          .map((a) => AdvisorGoalLine(
                name: a.name,
                saved: a.balance,
                target: a.goalTarget,
              ))
          .toList();
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
          .recentSpending(limit: 8)
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
    }
    final savingsRate = t?.savingsRate;
    final peakDay = t?.peakSpendDay;

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
    );
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
