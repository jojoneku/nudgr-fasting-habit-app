import 'package:flutter/foundation.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_coach_context.dart';
import '../models/insight.dart';
import '../models/insight_snapshot.dart';
import '../services/ai_coach_service.dart';
import '../services/storage_service.dart';
import '../utils/insight_snapshot_builder.dart';
import '../utils/insight_triggers.dart';
import '../utils/safe_notifier.dart';
import 'activity_presenter.dart';
import 'budget_presenter.dart';
import 'fasting_presenter.dart';
import 'nutrition_presenter.dart';
import 'quest_presenter.dart';
import 'stats_presenter.dart';
import 'treasury_dashboard_presenter.dart';

/// The Insight Engine (Plan 057 Phase 3).
///
/// Cross-module "System Analysis": reduces every feature presenter to a
/// compact [InsightSnapshot], detects signals with the pure rule engine in
/// `insight_triggers.dart`, and phrases what the rules found into [Insight]s
/// for the Hub coach line + daily brief. Cost is near-zero: a per-section
/// hash gate skips all work when nothing changed, the LLM is only ever asked
/// to *phrase* a line the rules already produced, and template fallbacks keep
/// the feature fully functional with zero AI availability.
///
/// This presenter is the ONLY place source presenters are read (in
/// [buildSnapshotInputs]); everything downstream operates on the immutable
/// snapshot. Constructor injection only — no globals.
class InsightsPresenter extends ChangeNotifier with SafeNotifier {
  InsightsPresenter({
    required StorageService storage,
    required FastingPresenter fasting,
    required StatsPresenter stats,
    required QuestPresenter quests,
    NutritionPresenter? nutrition,
    TreasuryDashboardPresenter? treasury,
    BudgetPresenter? budget,
    ActivityPresenter? activity,
    AiCoachService? onDeviceAi,
    AiCoachService? cloudAi,
    DateTime Function()? clock,
  })  : _storage = storage,
        _fasting = fasting,
        _stats = stats,
        _quests = quests,
        _nutrition = nutrition,
        _treasury = treasury,
        _budget = budget,
        _activity = activity,
        _onDeviceAi = onDeviceAi,
        _cloudAi = cloudAi,
        _clock = clock ?? DateTime.now {
    for (final source in _sources) {
      source.addListener(_onSourceChanged);
    }
  }

  final StorageService _storage;
  final FastingPresenter _fasting;
  final StatsPresenter _stats;
  final QuestPresenter _quests;
  final NutritionPresenter? _nutrition;
  final TreasuryDashboardPresenter? _treasury;
  final BudgetPresenter? _budget;
  final ActivityPresenter? _activity;
  final AiCoachService? _onDeviceAi;
  final AiCoachService? _cloudAi;
  final DateTime Function() _clock;

  Iterable<ChangeNotifier> get _sources => <ChangeNotifier?>[
        _fasting,
        _stats,
        _quests,
        _nutrition,
        _treasury,
        _budget,
        _activity,
      ].whereType<ChangeNotifier>();

  // ── Tunables ──────────────────────────────────────────────────────────────

  /// Ring-buffer cap for persisted insights.
  static const int _kMaxInsights = 30;

  /// Hard cap on nudges *surfaced* per local calendar day (nag-fatigue guard,
  /// Plan 057). Briefs don't count.
  static const int _kMaxNudgesPerDay = 2;

  /// Hard cap on cloud phrasing calls per local calendar day (cost runaway
  /// guard). Derived from the count of today's cloud-sourced insights.
  static const int _kMaxCloudCallsPerDay = 6;

  /// Timeout for a single one-shot phrasing call.
  static const Duration _kPhraseTimeout = Duration(seconds: 20);

  /// Reserved cooldown-map key that persists the "last read" watermark
  /// alongside the per-trigger cooldown timestamps. It never collides with a
  /// trigger id (all trigger ids are `domain.name`), and `evaluateTriggers`
  /// ignores any key that isn't a trigger id, so it rides along harmlessly.
  static const String _kLastReadKey = '_lastRead';

  static const String _kBriefInstruction =
      'You are The System, an RPG-style coach. Given this player status '
      'digest, write a 2-3 sentence morning briefing: one observation about a '
      'trend or change, one concrete directive for today. No preamble.';

  static const String _kNudgeInstruction =
      'You are The System, an RPG-style coach. Rewrite the following directive '
      'as one short, specific, motivating line (max 22 words) using the '
      "player's status digest for context. No preamble, no quotes.";

  // ── State ─────────────────────────────────────────────────────────────────

  final List<Insight> _insights = []; // most-recent-first ring buffer
  Map<String, DateTime> _cooldowns = {}; // trigger id → last fired
  Map<String, String> _baselineHashes = {}; // section name → hash
  DateTime? _lastBriefDate;
  DateTime? _lastRead;

  bool _initialized = false;
  bool _isGenerating = false;
  bool _pendingRecompute = false;
  bool _refreshRequestedBeforeInit = false;
  // Re-entrancy guards. Both [refresh] and [generateDailyBriefIfDue] await
  // slow AI phrasing calls; the Hub mount, home-screen lifecycle-resume, and
  // source-change microtask can all invoke them while a previous call is still
  // in flight. Without these, two overlapping calls each pass their once-a-day
  // / hash gate (which isn't updated until after the await) and both generate —
  // producing duplicate briefs/nudges. [_refreshPending] re-runs a single
  // coalesced refresh for any change that landed mid-flight.
  bool _refreshInFlight = false;
  bool _refreshPending = false;
  bool _briefInFlight = false;
  int _idCounter = 0;

  // ── Read surface (Hub) ──────────────────────────────────────────────────

  /// What the Hub coach line shows: the most recent nudge from today if any,
  /// else today's brief, else the most recent insight of any age, else null.
  Insight? get current {
    final now = _clock();
    final todayNudge = _firstWhere((i) =>
        i.kind == InsightKind.nudge && _isSameLocalDay(i.createdAt, now));
    if (todayNudge != null) return todayNudge;
    final brief = dailyBrief;
    if (brief != null) return brief;
    return _insights.isEmpty ? null : _insights.first;
  }

  /// Today's daily brief, or null before it has been generated today.
  Insight? get dailyBrief {
    final now = _clock();
    return _firstWhere((i) =>
        i.kind == InsightKind.dailyBrief && _isSameLocalDay(i.createdAt, now));
  }

  /// The persisted ring buffer, most-recent-first (for the brief sheet).
  List<Insight> get recent => List.unmodifiable(_insights);

  /// Whether there is at least one insight newer than the last-read watermark.
  bool get hasUnread {
    if (_insights.isEmpty) return false;
    final watermark = _lastRead;
    if (watermark == null) return true;
    return _insights.first.createdAt.isAfter(watermark);
  }

  bool get isGenerating => _isGenerating;

  bool get isInitialized => _initialized;

  /// Mark everything currently in the buffer as read. Persists the watermark
  /// so the "new" badge stays cleared across restarts.
  void markRead() {
    final latest = _insights.isEmpty ? _clock() : _insights.first.createdAt;
    if (_lastRead != null && !latest.isAfter(_lastRead!)) return;
    _lastRead = latest;
    // ignore: unawaited_futures
    _persistCooldowns();
    safeNotify();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Load persisted state (insights, baseline hashes, cooldowns, brief date)
  /// before the first refresh. Safe to call once; subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    final results = await Future.wait([
      _storage.loadInsights(),
      _storage.loadInsightBaselineHashes(),
      _storage.loadInsightCooldowns(),
      _storage.loadLastDailyBriefDate(),
    ]);
    if (isDisposed) return;

    _insights
      ..clear()
      ..addAll((results[0] as List<Insight>?) ?? const <Insight>[]);
    _baselineHashes = (results[1] as Map<String, String>?) ?? {};
    final cooldowns = (results[2] as Map<String, DateTime>?) ?? {};
    _lastRead = cooldowns.remove(_kLastReadKey);
    _cooldowns = cooldowns;
    _lastBriefDate = results[3] as DateTime?;

    _initialized = true;
    if (_refreshRequestedBeforeInit) {
      _refreshRequestedBeforeInit = false;
      await refresh();
    } else {
      safeNotify();
    }
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.removeListener(_onSourceChanged);
    }
    super.dispose();
  }

  // ── Refresh (cheap path) ────────────────────────────────────────────────

  /// Test seam: simulate a source presenter firing `notifyListeners`. Drives
  /// the exact debounced-microtask path the real source listeners use.
  @visibleForTesting
  void debugSimulateSourceChange() => _onSourceChanged();

  void _onSourceChanged() {
    if (_pendingRecompute) return;
    _pendingRecompute = true;
    Future.microtask(() {
      _pendingRecompute = false;
      if (isDisposed) return;
      // ignore: unawaited_futures
      refresh();
    });
  }

  /// Rebuild the snapshot and compare per-section hashes to the stored
  /// baseline. Unchanged → return immediately (no trigger eval, no LLM, no
  /// writes). Changed → evaluate triggers (honouring cooldowns + the daily
  /// surface cap), phrase and persist any surfaced nudges, and persist the
  /// new baseline. Never throws.
  Future<void> refresh() async {
    if (!_initialized) {
      _refreshRequestedBeforeInit = true;
      return;
    }
    // Coalesce overlapping calls: if one is already running, ask it to run once
    // more when it finishes (so a change that landed mid-flight isn't missed)
    // instead of racing a second concurrent pass that would double-fire nudges.
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }
    _refreshInFlight = true;
    try {
      await _refreshOnce();
      while (_refreshPending && !isDisposed) {
        _refreshPending = false;
        await _refreshOnce();
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshOnce() async {
    final now = _clock();
    final snapshot = InsightSnapshotBuilder.build(buildSnapshotInputs(), now);
    final newHashes = snapshot.sectionHashes;
    if (_mapEquals(newHashes, _baselineHashes)) return; // hash gate

    final changedSections = _changedSectionNames(snapshot);
    final fired = evaluateTriggers(snapshot, _cooldowns, now);

    var surfacedAny = false;
    if (fired.isNotEmpty) {
      var remaining = _kMaxNudgesPerDay - _todaysNudgeCount(now);
      if (remaining > 0) {
        final ranked = [...fired]
          ..sort((a, b) => _moodRank(a.mood).compareTo(_moodRank(b.mood)));
        _isGenerating = true;
        safeNotify();
        try {
          for (final trigger in ranked) {
            if (remaining <= 0) break;
            final (text, source) = await _phrase(
              _kNudgeInstruction,
              snapshot,
              trigger.fallbackText(snapshot),
              changedSections: changedSections,
              directive: trigger.fallbackText(snapshot),
            );
            if (isDisposed) return;
            _prepend(Insight(
              id: _nextId(trigger.id),
              kind: InsightKind.nudge,
              mood: trigger.mood,
              text: text,
              triggerId: trigger.id,
              createdAt: now,
              source: source,
            ));
            _cooldowns[trigger.id] = now;
            remaining--;
            surfacedAny = true;
          }
        } finally {
          _isGenerating = false;
        }
      }
    }

    _baselineHashes = newHashes;
    await _persistBaseline();
    if (surfacedAny) {
      await _persistInsights();
      await _persistCooldowns();
    }
    safeNotify();
  }

  // ── Daily brief ───────────────────────────────────────────────────────────

  /// Generate the morning brief at most once per local calendar day. No-op if
  /// one was already generated today. Uses the tiered phrasing chain
  /// (on-device → cloud → template). Never throws.
  Future<void> generateDailyBriefIfDue() async {
    if (!_initialized) return;
    // Guard against overlapping callers (hub mount + lifecycle resume + the
    // once-per-day home-screen call). `_lastBriefDate` is only set after the
    // phrasing await, so without this two concurrent calls would both pass the
    // once-a-day check and generate a duplicate brief (and a duplicate LLM
    // call).
    if (_briefInFlight) return;
    final now = _clock();
    if (_lastBriefDate != null && _isSameLocalDay(_lastBriefDate!, now)) return;

    _briefInFlight = true;
    _isGenerating = true;
    safeNotify();
    try {
      final snapshot = InsightSnapshotBuilder.build(buildSnapshotInputs(), now);
      final changedSections = _changedSectionNames(snapshot);
      final (text, source) = await _phrase(
        _kBriefInstruction,
        snapshot,
        _templateBrief(snapshot),
        changedSections: changedSections,
      );
      if (isDisposed) return;
      _prepend(Insight(
        id: _nextId('brief'),
        kind: InsightKind.dailyBrief,
        mood: InsightMood.neutral,
        text: text,
        createdAt: now,
        source: source,
      ));
      _lastBriefDate = now;
      await _persistInsights();
      await _storage.saveLastDailyBriefDate(now);
    } finally {
      _briefInFlight = false;
      _isGenerating = false;
      safeNotify();
    }
  }

  /// Assemble a template brief from the sections' own fallback lines — used
  /// when no AI phrased the brief. Leads with the most urgent holding
  /// condition and appends a positive note when one applies.
  String _templateBrief(InsightSnapshot snapshot) {
    final holding = allInsightTriggers.where((t) => t.test(snapshot)).toList()
      ..sort((a, b) => _moodRank(a.mood).compareTo(_moodRank(b.mood)));
    final buffer = StringBuffer('System analysis complete. ');
    if (holding.isEmpty) {
      buffer.write('All fronts are holding — keep your lines steady today.');
      return buffer.toString();
    }
    final lead = holding.first;
    buffer.write(lead.fallbackText(snapshot));
    // Append a positive note if one holds and wasn't already the lead line.
    final positive = holding.firstWhere(
      (t) => t.mood == InsightMood.positive && t.id != lead.id,
      orElse: () => lead,
    );
    if (positive.id != lead.id) {
      buffer.write(' ${positive.fallbackText(snapshot)}');
    }
    return buffer.toString();
  }

  // ── Tier routing (phrasing only) ──────────────────────────────────────────

  /// Try on-device → cloud → template fallback. Returns the phrased text and
  /// the tier that produced it. Never throws; any failure/empty result falls
  /// through to the next tier, ending at [fallback] with [InsightSource.rules].
  Future<(String, InsightSource)> _phrase(
    String instruction,
    InsightSnapshot snapshot,
    String fallback, {
    Set<String> changedSections = const {},
    String? directive,
  }) async {
    final onDevice = _onDeviceAi;
    if (onDevice != null && onDevice.isAvailable) {
      final text = await _collect(
          onDevice, instruction, snapshot, changedSections, directive);
      if (text != null && text.isNotEmpty) {
        return (text, InsightSource.onDevice);
      }
    }

    final cloud = _cloudAi;
    if (cloud != null &&
        cloud.isAvailable &&
        _cloudCallsToday(_clock()) < _kMaxCloudCallsPerDay) {
      final text = await _collect(
          cloud, instruction, snapshot, changedSections, directive);
      if (text != null && text.isNotEmpty) return (text, InsightSource.cloud);
    }

    return (fallback, InsightSource.rules);
  }

  /// One-shot, empty-history phrasing call. Collects the token stream with a
  /// timeout and returns the trimmed text, or null on error/empty/disposal.
  Future<String?> _collect(
    AiCoachService service,
    String instruction,
    InsightSnapshot snapshot,
    Set<String> changedSections,
    String? directive,
  ) async {
    try {
      final digest = snapshot.toPromptDigest(changedSections: changedSections);
      final prompt = StringBuffer(instruction);
      if (directive != null) {
        prompt.writeln();
        prompt.writeln();
        prompt.write('Directive to rewrite: $directive');
      }
      prompt.writeln();
      prompt.writeln();
      prompt.write('Player status digest:');
      prompt.writeln();
      prompt.write(digest);

      final buffer = StringBuffer();
      final stream = service.respond(
        messages: [AiChatMessage.user(prompt.toString())],
        context: const AiCoachContext(entryPoint: AiCoachEntryPoint.general),
      ).timeout(_kPhraseTimeout);
      await for (final token in stream) {
        if (isDisposed) return null;
        buffer.write(token);
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    } catch (e) {
      debugPrint('InsightsPresenter._collect error: $e');
      return null;
    }
  }

  // ── Snapshot mapping — the only place source presenters are read ─────────

  /// Build the pure [InsightSnapshotInputs] from the injected source
  /// presenters. Overridable in tests so the whole refresh/brief/tier flow
  /// can be exercised against a controlled snapshot without constructing real
  /// feature presenters.
  @visibleForTesting
  InsightSnapshotInputs buildSnapshotInputs() {
    final now = _clock();
    final stats = _stats.stats;
    final n = _nutrition;
    final t = _treasury;
    final b = _budget;
    final a = _activity;

    double? latestWeightKg;
    int? daysSinceWeight;
    final latest = n?.latestWeight;
    if (latest != null) {
      latestWeightKg = latest.weightKg;
      daysSinceWeight = _daysBetween(latest.loggedAt, now);
    }

    int? steps7dAvg;
    if (a != null) {
      final logs = a.weeklyLogs;
      if (logs.isNotEmpty) {
        steps7dAvg =
            (logs.fold<int>(0, (s, l) => s + l.steps) / logs.length).round();
      }
    }

    final historyEmpty = n == null || n.history.isEmpty;

    return InsightSnapshotInputs(
      // Fasting
      isFasting: _fasting.isFasting,
      fastingStreak: _fasting.currentStreak,
      fastingGoalHours: _fasting.fastingGoalHours,
      // Nutrition
      todayCalories: n?.todayCalories,
      effectiveGoal: n?.effectiveGoal,
      sevenDayAvgCalories: historyEmpty ? null : n.sevenDayAvgCalories,
      sevenDayAvgFatGrams: historyEmpty ? null : n.sevenDayAvgFatGrams,
      fatTargetGrams: n?.fatTargetGrams,
      proteinHitRate7d: n?.proteinHitRate7d,
      loggingConsistency7d: n?.loggingConsistency7d,
      logStreak: n?.logStreak,
      goalStreak: n?.goalStreak,
      // Finance
      monthSpent: t?.monthTotalOutflow,
      monthBudget: b?.totalAllocated,
      billImminent: t?.hasBillImminent,
      anyCategoryOverBudget: b?.budgetRows.any((r) => r.isOver),
      netCashFlow: t?.monthNetCashFlow,
      // Quests
      questsDueTodayCount:
          _quests.todayActiveQuests.length + _quests.todayOverdueQuests.length,
      hasUrgentQuest: _quests.hasUrgentQuest,
      // Activity
      stepsToday: a?.todaySteps,
      steps7dAvg: steps7dAvg,
      // Body
      latestWeightKg: latestWeightKg,
      daysSinceLastWeightLog: daysSinceWeight,
      // RPG
      level: stats.level,
      xp: stats.currentXp,
      hp: stats.currentHp,
    );
  }

  // ── Persistence helpers ────────────────────────────────────────────────

  Future<void> _persistInsights() => _storage.saveInsights(List.of(_insights));

  Future<void> _persistBaseline() =>
      _storage.saveInsightBaselineHashes(Map.of(_baselineHashes));

  Future<void> _persistCooldowns() {
    final merged = Map<String, DateTime>.of(_cooldowns);
    if (_lastRead != null) merged[_kLastReadKey] = _lastRead!;
    return _storage.saveInsightCooldowns(merged);
  }

  // ── Small internals ───────────────────────────────────────────────────────

  void _prepend(Insight insight) {
    _insights.insert(0, insight);
    if (_insights.length > _kMaxInsights) {
      _insights.removeRange(_kMaxInsights, _insights.length);
    }
  }

  String _nextId(String suffix) =>
      '${_clock().microsecondsSinceEpoch}-${_idCounter++}-$suffix';

  int _todaysNudgeCount(DateTime now) => _insights
      .where((i) =>
          i.kind == InsightKind.nudge && _isSameLocalDay(i.createdAt, now))
      .length;

  int _cloudCallsToday(DateTime now) => _insights
      .where((i) =>
          i.source == InsightSource.cloud && _isSameLocalDay(i.createdAt, now))
      .length;

  Set<String> _changedSectionNames(InsightSnapshot snapshot) {
    final changed = <String>{};
    snapshot.sectionHashes.forEach((name, hash) {
      if (_baselineHashes[name] != hash) changed.add(name);
    });
    return changed;
  }

  Insight? _firstWhere(bool Function(Insight) test) {
    for (final i in _insights) {
      if (test(i)) return i;
    }
    return null;
  }

  static int _moodRank(InsightMood mood) => switch (mood) {
        InsightMood.urgent => 0,
        InsightMood.positive => 1,
        InsightMood.neutral => 2,
      };

  static bool _isSameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _daysBetween(DateTime from, DateTime to) =>
      DateTime(to.year, to.month, to.day)
          .difference(DateTime(from.year, from.month, from.day))
          .inDays;

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
