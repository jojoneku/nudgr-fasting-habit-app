import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_meal_estimate.dart';
import '../models/body_measurement_entry.dart';
import '../models/dashboard_status.dart';
import '../models/chat_message.dart';
import '../models/extracted_food_item.dart';
import '../models/daily_nutrition_log.dart';
import '../models/estimation_source.dart';
import '../models/food_feedback.dart';
import '../models/exercise_entry.dart';
import '../models/food_db_entry.dart';
import '../models/food_entry.dart';
import '../models/food_parse_result.dart';
import '../models/food_search_candidate.dart';
import '../models/food_template.dart';
import '../models/meal_slot.dart';
import '../models/nutrition_goals.dart';
import '../models/tdee_profile.dart';
import '../services/ai_coach_service.dart';
import '../services/cloud_ai_coach_service.dart';
import '../services/food_db_service.dart';
import '../services/food_photo_store.dart';
import '../services/image_compressor.dart';
import '../services/notification_service.dart';
import '../models/personal_food_entry.dart';
import '../models/weight_entry.dart';
import '../services/personal_food_dictionary.dart';
import '../services/storage_service.dart';
import '../utils/body_composition_calculator.dart';
import '../utils/calorie_density_estimator.dart' as cde;
import '../utils/exercise_nlp_parser.dart';
import '../utils/food_match_scorer.dart';
import '../utils/food_nlp_parser.dart';
import 'fasting_presenter.dart';
import 'stats_presenter.dart';
import '../utils/safe_notifier.dart';

/// Resolved (but not yet committed) food items from a chat/composer submission.
typedef _ResolvedChatFood = ({
  List<FoodEntry> entries,
  List<List<ChatFoodAlternative>> alts,
  List<String> rawTexts,
});

class NutritionPresenter extends ChangeNotifier with SafeNotifier {
  final StatsPresenter _statsPresenter;
  final FastingPresenter _fastingPresenter;
  final StorageService _storage;
  final FoodDbService _foodDb;
  final AiCoachService _ai;
  final NotificationService _notifications;

  DailyNutritionLog _todayLog = DailyNutritionLog.empty('');
  NutritionGoals _goals = NutritionGoals.initial();
  List<DailyNutritionLog> _history = [];
  TdeeProfile? _tdeeProfile;
  List<FoodTemplate> _library = [];

  // Memoized getters — cleared automatically on every safeNotify().
  List<FoodTemplate>? _savedTemplatesCache;
  List<FoodTemplate>? _recentFoodsCache;

  int _goalStreak = 0; // consecutive days calorie goal met
  String? _goalMetDate; // last date calorie goal was met
  int _logStreak = 0; // consecutive days with ≥1 entry
  String? _logStreakDate; // latest date an entry was logged

  // Per-day credit ledgers — keep retroactive (backdated) XP idempotent so a
  // backfill → edit → re-backfill can never pay twice. See Plan 037.
  Set<String> _calorieGoalCreditedDates = {};
  Set<String> _proteinGoalCreditedDates = {};
  // Highest log-streak milestone (7/14/30) already paid for the CURRENT run;
  // reset to 0 when the run shrinks below it so a fresh run can earn it again.
  int _streakMilestonePaid = 0;

  bool _calorieGoalNotifiedToday = false;
  bool _overshootPenalizedToday = false;
  bool _isAiEstimating = false;
  AiMealEstimate? _lastEstimate;
  String? _aiEstimateError;

  // ── Weight log ───────────────────────────────────────────────────────────
  List<WeightEntry> _weightLog = const [];

  // ── Body measurements ─────────────────────────────────────────────────────
  List<BodyMeasurementEntry> _measurementLog = const [];
  MeasurementUnit _measurementUnit = MeasurementUnit.metric;
  DateTime? _lastRecompXpDate;

  // ── Personal food dictionary ──────────────────────────────────────────────
  late final PersonalFoodDictionary _personalDict;

  // ── Calorie density estimation — see lib/utils/calorie_density_estimator.dart

  // ── NLP parser state ─────────────────────────────────────────────────────
  bool _isParsing = false;
  FoodParseResult? _lastParseResult;
  // Resolved DB entries matched to each parsed item (null = not found in DB).
  List<FoodDbEntry?> _parsedDbMatches = [];
  String? _parseError;

  // ── Cloud AI (optional upgrade tier for disambiguation) ──────────────────
  final AiCoachService? _cloudAi;

  // ── Photo food logging (Plan 029) ─────────────────────────────────────────
  final ImageCompressor _imageCompressor;
  final FoodPhotoStore _photoStore;
  bool _isPhotoParsing = false;
  String? _photoParseError;

  // ── Chat + exercise state ─────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  List<ChatMessage> _chatMessages = [];
  bool _isChatParsing = false;
  String? _chatParseError;

  // Pending estimate for the composer's review step (Nudgr redesign): resolved
  // by [previewChat] but not yet logged. Committed by [commitPendingChat] or
  // dropped by [discardPendingChat]. Exercise inputs never populate this (they
  // log atomically).
  _ResolvedChatFood? _pendingResolved;
  String? _pendingText;
  // Set when the pending estimate came from a photo — carries the thumbnail so
  // commit can attach it, and discard can delete the orphaned file.
  String? _pendingThumbPath;
  // ── Matcher feedback (telemetry, local-only) ─────────────────────────────
  // Loaded once from storage on init; appended to in-memory and persisted on
  // every event so the curation backlog survives app restarts.
  List<FoodFeedback> _feedback = const [];

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _calFmt = NumberFormat('#,###');

  NutritionPresenter({
    required StatsPresenter statsPresenter,
    required FastingPresenter fastingPresenter,
    required StorageService storage,
    required FoodDbService foodDb,
    required AiCoachService aiCoach,
    AiCoachService? cloudAi,
    NotificationService? notifications,
    ImageCompressor? imageCompressor,
    FoodPhotoStore? photoStore,
  })  : _statsPresenter = statsPresenter,
        _fastingPresenter = fastingPresenter,
        _storage = storage,
        _foodDb = foodDb,
        _ai = aiCoach,
        _cloudAi = cloudAi,
        _imageCompressor = imageCompressor ?? const ImageCompressor(),
        _photoStore = photoStore ?? FoodPhotoStore(),
        _notifications = notifications ?? NotificationService() {
    _personalDict = PersonalFoodDictionary(storage);
    loadState();
  }

  @override
  void safeNotify() {
    _savedTemplatesCache = null;
    _recentFoodsCache = null;
    super.safeNotify();
  }

  // ── Core state ───────────────────────────────────────────────────────────────

  DailyNutritionLog get todayLog => _todayLog;
  NutritionGoals get goals => _goals;
  List<DailyNutritionLog> get history => _history;
  TdeeProfile? get tdeeProfile => _tdeeProfile;

  // ── Weight log ───────────────────────────────────────────────────────────────

  List<WeightEntry> get weightLog => _weightLog;
  WeightEntry? get latestWeight => _weightLog.isEmpty ? null : _weightLog.last;
  double? get weightDelta => BodyCompositionCalculator.weightDelta(_weightLog);

  // ── Body measurement getters ─────────────────────────────────────────────────

  List<BodyMeasurementEntry> get measurementLog => _measurementLog;
  BodyMeasurementEntry? get latestMeasurement =>
      _measurementLog.isEmpty ? null : _measurementLog.last;

  double? get waistDelta =>
      BodyCompositionCalculator.waistDelta(_measurementLog);

  MeasurementTrendDirection get waistTrendDirection =>
      BodyCompositionCalculator.waistTrend(_measurementLog);

  MeasurementUnit get measurementUnit => _measurementUnit;

  String formatMeasurement(double cm) {
    if (_measurementUnit == MeasurementUnit.imperial) {
      return '${(cm / 2.54).toStringAsFixed(1)} in';
    }
    return '${cm.toStringAsFixed(1)} cm';
  }

  double toStorageCm(double displayValue) =>
      _measurementUnit == MeasurementUnit.imperial
          ? displayValue * 2.54
          : displayValue;

  /// Both BF% estimates: US Navy (measurement-based) and BMI (profile-based).
  ({double? navy, double? bmi}) get bodyFatEstimates =>
      BodyCompositionCalculator.bodyFatEstimates(
        profile: _tdeeProfile,
        latest: latestMeasurement,
      );

  /// Average of Navy + BMI estimates; falls back to whichever is available.
  double? get estimatedBodyFatPercent =>
      BodyCompositionCalculator.estimatedBodyFatPercent(
        profile: _tdeeProfile,
        latest: latestMeasurement,
      );

  /// Per-entry Navy BF% history for the trend chart.
  /// Only entries that have both waist and neck measurements are included.
  List<({DateTime date, double bf})> get bodyFatHistory =>
      BodyCompositionCalculator.bodyFatHistory(
        profile: _tdeeProfile,
        measurementLog: _measurementLog,
      );

  bool get hasWaistChartData =>
      BodyCompositionCalculator.hasWaistChartData(_measurementLog);

  bool get hasBodyFatChartData => BodyCompositionCalculator.hasBodyFatChartData(
        profile: _tdeeProfile,
        measurementLog: _measurementLog,
      );

  bool get hasMeasurementExtraSites =>
      BodyCompositionCalculator.hasMeasurementExtraSites(latestMeasurement);

  double? get totalWaistChangeCm =>
      BodyCompositionCalculator.totalWaistChangeCm(_measurementLog);

  /// Formatted total waist change ("−2.3 cm", "+1.0 in", or "—").
  String get waistTotalChangeLabel {
    final delta = totalWaistChangeCm;
    if (delta == null) return '—';
    final sign = delta >= 0 ? '+' : '−';
    return '$sign${formatMeasurement(delta.abs())}';
  }

  /// Formatted body-fat range label ("12–15%", "~14%", or "—").
  String get bodyFatRangeLabel => BodyCompositionCalculator.bodyFatRangeLabel(
        profile: _tdeeProfile,
        latest: latestMeasurement,
      );

  // ── Calorie getters ──────────────────────────────────────────────────────────

  int get todayCalories => _todayLog.totalCalories;

  int get effectiveGoal =>
      _goals.mode == TrackingMode.standard && _tdeeProfile != null
          ? _tdeeProfile!.targetCalories
          : _goals.dailyCalories;

  double get calorieProgress =>
      effectiveGoal > 0 ? (todayCalories / effectiveGoal).clamp(0.0, 1.5) : 0.0;

  /// Net calories (eaten − burned) as a fraction of the goal.
  double get netCalorieProgress =>
      effectiveGoal > 0 ? (netCalories / effectiveGoal).clamp(0.0, 1.0) : 0.0;

  bool get isCalorieGoalMet =>
      effectiveGoal > 0 && todayCalories >= effectiveGoal;
  bool get isOverGoal =>
      effectiveGoal > 0 && todayCalories > effectiveGoal * 1.2;

  String get summaryLabel =>
      '${_calFmt.format(todayCalories)} / ${_calFmt.format(effectiveGoal)} kcal';

  int caloriesForSlot(MealSlot slot) => _todayLog.caloriesForSlot(slot);

  String get hubSubtitle {
    if (todayCalories == 0) return 'Tap to log meals';
    if (isCalorieGoalMet) return 'Goal reached! ✓';
    return summaryLabel;
  }

  // ── Macro getters ────────────────────────────────────────────────────────────

  double get todayProtein => _todayLog.totalProtein;
  double get todayCarbs => _todayLog.totalCarbs;
  double get todayFat => _todayLog.totalFat;

  int? get proteinGoal => _goals.proteinGrams?.round();
  int? get carbsGoal => _goals.carbsGrams?.round();
  int? get fatGoal => _goals.fatGrams?.round();

  // ── Effective macro targets (grams) ──────────────────────────────────────────
  // When the user hasn't set explicit macro targets, derive a sensible default
  // split from the effective calorie goal so the progress bars still track
  // intake (protein 30% @ 4 kcal/g, carbs 40% @ 4 kcal/g, fat 30% @ 9 kcal/g).
  // Explicit targets always win.
  double get effectiveProteinGoalGrams =>
      _goals.proteinGrams != null && _goals.proteinGrams! > 0
          ? _goals.proteinGrams!
          : effectiveGoal * 0.30 / 4;

  double get effectiveCarbsGoalGrams =>
      _goals.carbsGrams != null && _goals.carbsGrams! > 0
          ? _goals.carbsGrams!
          : effectiveGoal * 0.40 / 4;

  double get effectiveFatGoalGrams =>
      _goals.fatGrams != null && _goals.fatGrams! > 0
          ? _goals.fatGrams!
          : effectiveGoal * 0.30 / 9;

  double get proteinProgress => effectiveProteinGoalGrams > 0
      ? (todayProtein / effectiveProteinGoalGrams).clamp(0.0, 1.0)
      : 0.0;

  double get carbsProgress => effectiveCarbsGoalGrams > 0
      ? (todayCarbs / effectiveCarbsGoalGrams).clamp(0.0, 1.0)
      : 0.0;

  double get fatProgress => effectiveFatGoalGrams > 0
      ? (todayFat / effectiveFatGoalGrams).clamp(0.0, 1.0)
      : 0.0;

  bool get isProteinGoalMet =>
      _goals.proteinGrams != null && todayProtein >= _goals.proteinGrams!;

  // ── IF-Sync getters ──────────────────────────────────────────────────────────

  bool get isEatingWindowOpen {
    if (!_goals.ifSyncEnabled) return true;
    return !_fastingPresenter.isFasting;
  }

  String get windowStatusLabel => isEatingWindowOpen
      ? 'Eating window open — log freely'
      : 'Fasting — logging paused';

  // ── Streak getters ───────────────────────────────────────────────────────────

  int get goalStreak => _goalStreak;
  int get logStreak => _logStreak;

  // ── Dashboard analytics ──────────────────────────────────────────────────────

  String? get activeGoal => _tdeeProfile?.goal;

  String? get goalLabel => _tdeeProfile?.goalLabel;

  int get sevenDayAvgCalories =>
      BodyCompositionCalculator.sevenDayAvgCalories(history);

  /// Rolling 7-day average fat intake in grams (Plan 057 — feeds the
  /// `nutrition.fatTrend` insight trigger). See
  /// [BodyCompositionCalculator.sevenDayAvgFatGrams].
  double get sevenDayAvgFatGrams =>
      BodyCompositionCalculator.sevenDayAvgFatGrams(history);

  /// Daily fat-gram target, or null when no fat goal is set. Exposed as a
  /// double (grams) for the Insight Engine's `fatTargetGrams` marker; the
  /// existing [fatGoal] getter rounds to an int for UI display.
  double? get fatTargetGrams => _goals.fatGrams;

  double? get proteinHitRate7d => BodyCompositionCalculator.proteinHitRate7d(
        goals: _goals,
        history: history,
      );

  double get loggingConsistency7d =>
      BodyCompositionCalculator.loggingConsistency7d(history);

  WeightTrendDirection get weightTrendDirection =>
      BodyCompositionCalculator.weightTrend(_weightLog);

  DashboardStatus get dashboardStatus =>
      BodyCompositionCalculator.dashboardStatus(
        history: history,
        profile: _tdeeProfile,
        goals: _goals,
        weightLog: _weightLog,
        measurementLog: _measurementLog,
      );

  String get primaryKpiLabel =>
      BodyCompositionCalculator.primaryKpiLabel(activeGoal);

  String get secondaryKpiLabel =>
      BodyCompositionCalculator.secondaryKpiLabel(activeGoal);

  String weightTrendLabel(WeightTrendDirection direction) =>
      BodyCompositionCalculator.weightTrendLabel(activeGoal, direction);

  // ── Food library getters ─────────────────────────────────────────────────────

  List<FoodTemplate> get savedTemplates =>
      _savedTemplatesCache ??= _computeSavedTemplates();

  List<FoodTemplate> _computeSavedTemplates() {
    final sorted = List<FoodTemplate>.from(_library);
    sorted.sort((a, b) {
      if (a.isPinned == b.isPinned) return 0;
      return a.isPinned ? -1 : 1;
    });
    return List.unmodifiable(sorted);
  }

  List<FoodTemplate> get recentFoods =>
      _recentFoodsCache ??= _computeRecentFoods();

  List<FoodTemplate> _computeRecentFoods() {
    final seen = <String>{};
    final recent = <FoodTemplate>[];
    for (final slot in MealSlot.values) {
      for (final entry in _todayLog.entriesForSlot(slot).reversed) {
        if (seen.add(entry.name) && recent.length < 10) {
          recent.add(FoodTemplate(
            id: entry.id,
            name: entry.name,
            isMeal: false,
            entries: [entry],
          ));
        }
      }
    }
    for (final log in _history) {
      if (recent.length >= 10) break;
      for (final entry in log.allEntries.reversed) {
        if (seen.add(entry.name) && recent.length < 10) {
          recent.add(FoodTemplate(
            id: entry.id,
            name: entry.name,
            isMeal: false,
            entries: [entry],
          ));
        }
      }
    }
    return recent;
  }

  // ── AI getters ───────────────────────────────────────────────────────────────

  FoodDbService get foodDb => _foodDb;

  /// Typeahead for the chat input. Returns food names ranked by
  /// personal-dict recency first, then FTS5 matches from the bundled food DB.
  /// Deduped case-insensitively, capped at [limit]. Returns empty for queries
  /// shorter than 2 chars.
  Future<List<String>> suggestFoodNames(String query, {int limit = 6}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final dictHits = _personalDict.prefixSearch(q, limit: limit);
    final result = <String>[];
    final seen = <String>{};
    for (final e in dictHits) {
      if (seen.add(e.name.toLowerCase())) result.add(e.name);
      if (result.length >= limit) return result;
    }
    final dbHits = await _foodDb.search(q);
    for (final e in dbHits) {
      if (result.length >= limit) break;
      if (seen.add(e.name.toLowerCase())) result.add(e.name);
    }
    return result;
  }

  bool get isAiAvailable => _ai.isAvailable;
  bool get isAiEstimating => _isAiEstimating;
  bool get isAiDownloading => _ai.downloadProgress != null;

  /// True when the cloud tier is wired in (constructor passed cloudAi) AND
  /// the user has flipped it on AND a valid auth token is present. Used by
  /// the UI to surface a status chip so the user knows logs will go through
  /// Bedrock Haiku.
  bool get isCloudAiAvailable => _cloudAi?.isAvailable ?? false;

  /// True when the cloud service is wired in but currently not available —
  /// usually means signed out or settings toggle off. Distinct from "not
  /// wired in at all" so the chip can show a muted state.
  bool get isCloudAiConfigured => _cloudAi != null;

  // ── First-run AI prompt (Plan 027 §3.2) ──────────────────────────────────

  static const Duration _aiPromptCooldown = Duration(days: 7);

  /// True when neither cloud (signed in + toggle on) nor on-device AI is
  /// usable AND the user hasn't skipped the prompt within the cool-down
  /// window. Drives the "Set up smart food logging" modal.
  Future<bool> shouldShowAiPrompt() async {
    if (isCloudAiAvailable || isAiAvailable) return false;
    final skippedAt = await _storage.loadAiPromptSkippedAt();
    if (skippedAt == null) return true;
    final since = DateTime.fromMillisecondsSinceEpoch(skippedAt);
    return DateTime.now().difference(since) >= _aiPromptCooldown;
  }

  /// Persist the skip timestamp so we don't nag for [_aiPromptCooldown].
  Future<void> skipAiPrompt() async {
    await _storage.saveAiPromptSkippedAt(DateTime.now().millisecondsSinceEpoch);
  }

  /// Clear the skip timestamp — used after sign-in / download succeeds so
  /// future "no AI" sessions show the prompt again.
  Future<void> resetAiPromptCooldown() async {
    await _storage.saveAiPromptSkippedAt(null);
  }

  // ── Personal dict access (Plan 027 §2) ───────────────────────────────────

  int get learnedFoodCount => _personalDict.count;
  List<PersonalFoodEntry> get learnedFoods => _personalDict.all();

  Future<void> clearLearnedFoods() async {
    await _personalDict.clearAll();
    safeNotify();
  }

  Future<void> removeLearnedFood(String name) async {
    await _personalDict.remove(name);
    safeNotify();
  }

  /// Plan 027 — let the user correct a learned food's per-100g macros when
  /// the auto-promoted estimate was wrong. Reuses [PersonalFoodDictionary.upsert]
  /// which overwrites the existing entry by normalized key.
  Future<void> updateLearnedFood({
    required String name,
    required double kcalPer100g,
    double? proteinPer100g,
    double? carbsPer100g,
    double? fatPer100g,
  }) async {
    await _personalDict.upsert(
      name: name,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    );
    safeNotify();
  }

  /// User-authored custom food (Phase 1 of the "add a food" feature). Writes
  /// straight into the personal dictionary as a per-100g density, so it
  /// resolves *before* the bundled food DB on every future log and surfaces in
  /// typeahead. Callers pass already-normalized per-100g values — the
  /// AddCustomFoodSheet converts a per-serving entry (e.g. 90 kcal / 15 g) to
  /// per-100g before calling. Reuses the same upsert as [updateLearnedFood], so
  /// adding a name that already exists overwrites it with the user's values.
  Future<void> addCustomFood({
    required String name,
    required double kcalPer100g,
    double? proteinPer100g,
    double? carbsPer100g,
    double? fatPer100g,
  }) async {
    await _personalDict.upsert(
      name: name,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    );
    safeNotify();
  }

  int get aiDownloadProgress => _ai.downloadProgress ?? 0;
  String get aiSizeLabel => '~586 MB';
  AiMealEstimate? get lastEstimate => _lastEstimate;
  String? get aiEstimateError => _aiEstimateError;

  // ── NLP parser getters ───────────────────────────────────────────────────────

  bool get isParsing => _isParsing;
  FoodParseResult? get lastParseResult => _lastParseResult;
  List<FoodDbEntry?> get parsedDbMatches => List.unmodifiable(_parsedDbMatches);
  String? get parseError => _parseError;

  // ── Chat + exercise getters ───────────────────────────────────────────────────

  DateTime get selectedDate => _selectedDate;
  bool get isSelectedDateToday =>
      _dateFmt.format(_selectedDate) == _dateFmt.format(DateTime.now());

  /// True when committing a log right now would be blocked by the IF-Sync gate
  /// (today only, eating window closed). Callers should check this before
  /// committing a pending estimate so they can explain the block and keep the
  /// estimate on screen, rather than silently dropping it (`isEatingWindowOpen`
  /// already returns true when IF-Sync is disabled).
  bool get isLoggingBlockedNow => isSelectedDateToday && !isEatingWindowOpen;
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);

  /// The selected day's log entries ordered newest-first — the source for the
  /// redesigned "Today's log" list (Nudgr nutrition redesign). Each message is
  /// one logged food entry/meal or exercise; ordering is display-only.
  List<ChatMessage> get logEntriesNewestFirst =>
      _chatMessages.reversed.toList(growable: false);

  bool get isChatParsing => _isChatParsing;
  String? get chatParseError => _chatParseError;

  /// Dismiss the last chat-parse error (e.g. after the user acknowledges it in
  /// the hub quick-log bar). No-op when there is nothing to clear.
  void clearChatParseError() {
    if (_chatParseError == null) return;
    _chatParseError = null;
    safeNotify();
  }

  /// Sum of exercise calories burned from chat messages on [_selectedDate].
  int get selectedDateCaloriesBurned => _chatMessages
      .where((m) => m.kind == ChatMessageKind.exercise)
      .fold(0, (sum, m) => sum + (m.exerciseEntry?.caloriesBurned ?? 0));

  /// Remaining = goal − eaten + burned. Never negative.
  int get remainingCalories =>
      (effectiveGoal - todayCalories + selectedDateCaloriesBurned)
          .clamp(0, 99999);

  /// Net = eaten − burned.
  int get netCalories => todayCalories - selectedDateCaloriesBurned;

  // ── Actions — entries ────────────────────────────────────────────────────────

  Future<void> addFoodEntry(FoodEntry entry, MealSlot slot) async {
    // IF-Sync gate is a "now" concept — only blocks logging on TODAY. Past-day
    // backfills are always allowed even while currently fasting (Plan 037).
    if (isSelectedDateToday && _goals.ifSyncEnabled && !isEatingWindowOpen) {
      return;
    }
    await _ensureTodayLogFresh();
    _todayLog = _todayLog.addEntry(entry, slot);
    safeNotify();
    await _storage.saveNutritionLog(_todayLog);
    await _applyLogSideEffects(_todayLog.date);
  }

  /// Log a food entry created from manual user input and add it to the chat feed.
  Future<void> addManualFoodEntry(FoodEntry entry) async {
    // IF-Sync gate is a "now" concept — only blocks logging on TODAY. Past-day
    // backfills are always allowed even while currently fasting (Plan 037).
    if (isSelectedDateToday && _goals.ifSyncEnabled && !isEatingWindowOpen) {
      return;
    }
    await _ensureTodayLogFresh();
    _todayLog = _todayLog.addEntry(entry, MealSlot.meal);
    final msg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: entry.name,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.food,
      foodItems: [
        ChatFoodItem.fromFoodEntry(entry, amountText: '${entry.calories} kcal'),
      ],
      mealSlot: MealSlot.meal,
    );
    _chatMessages.add(msg);
    safeNotify();
    // Save log + chat atomically so a crash between them can't desync.
    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _applyLogSideEffects(_todayLog.date);
  }

  Future<void> removeFoodEntry(String entryId, MealSlot slot) async {
    _todayLog = _todayLog.removeEntry(entryId, slot);
    safeNotify();
    await _storage.saveNutritionLog(_todayLog);
  }

  Future<void> addMealFromTemplate(FoodTemplate meal, MealSlot slot) async {
    if (_isChatParsing) return; // avoid racing with an in-flight parse
    // IF-Sync gate is a "now" concept — only blocks logging on TODAY. Past-day
    // backfills are always allowed even while currently fasting (Plan 037).
    if (isSelectedDateToday && _goals.ifSyncEnabled && !isEatingWindowOpen) {
      return;
    }
    await _ensureTodayLogFresh();
    final entries = meal.entries
        .map((e) => e.copyWith())
        .map((e) => FoodEntry(
              id: FoodEntry.generateId(),
              name: e.name,
              calories: e.calories,
              protein: e.protein,
              carbs: e.carbs,
              fat: e.fat,
              grams: e.grams,
              estimationSource: e.estimationSource,
              loggedAt: DateTime.now(),
            ))
        .toList();
    _todayLog = _todayLog.addEntries(entries, slot);
    // Increment useCount on template
    final idx = _library.indexWhere((t) => t.id == meal.id);
    if (idx != -1) {
      _library[idx] =
          _library[idx].copyWith(useCount: _library[idx].useCount + 1);
      await _storage.saveFoodLibrary(_library);
    }

    // Add a chat message so the log appears in the nutrition chat feed.
    final chatMsg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: meal.name,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.food,
      mealSlot: slot,
      foodItems: entries.map((e) => ChatFoodItem.fromFoodEntry(e)).toList(),
    );
    _chatMessages.add(chatMsg);
    safeNotify();

    // Persist log + chat together so a crash between them can't desync.
    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _applyLogSideEffects(_todayLog.date);
  }

  // ── Actions — weight log ─────────────────────────────────────────────────────

  /// Log the user's weight now. Persists the entry and resets today's
  /// weight reminder (recurring schedule fires again tomorrow).
  Future<void> logWeight(double kg) async {
    await logWeightOnDate(kg, DateTime.now());
  }

  /// Log the user's weight for a specific [date]. Persists the entry and
  /// cancels today's pending weight-reminder notification; re-schedules
  /// if still enabled so tomorrow's reminder is set.
  Future<void> logWeightOnDate(double kg, DateTime date) async {
    final entry = WeightEntry(
      id: WeightEntry.generateId(),
      weightKg: kg,
      loggedAt: date,
    );
    _weightLog = [..._weightLog, entry];
    await _storage.saveWeightLog(_weightLog);
    safeNotify();

    // Cancel today's pending reminder; the recurring schedule fires again tomorrow.
    await _notifications.cancelWeightReminder();
    // Re-schedule if still enabled so tomorrow's alarm is set.
    final prefs = await _storage.loadNotificationPreferences();
    if (prefs.weightReminderEnabled) {
      await _notifications.scheduleWeightReminder(prefs.weightReminderTime);
    }
  }

  // ── Actions — goals / TDEE ───────────────────────────────────────────────────

  Future<void> updateGoals(NutritionGoals newGoals) async {
    _goals = newGoals;
    _calorieGoalNotifiedToday = false;
    _overshootPenalizedToday = false;
    safeNotify();
    await _storage.saveNutritionGoals(newGoals);
    await _awardCalorieGoalIfUncredited(_dateFmt.format(DateTime.now()),
        isToday: true);
  }

  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    _tdeeProfile = profile;
    safeNotify();
    await _storage.saveTdeeProfile(profile);
    await _awardCalorieGoalIfUncredited(_dateFmt.format(DateTime.now()),
        isToday: true);
  }

  // ── Actions — food library ────────────────────────────────────────────────────

  /// Parses [text] using NLP + DB lookup and returns FoodEntry objects
  /// WITHOUT adding them to the daily log. Used by the template builder.
  Future<List<FoodEntry>> parseFoodItemsForTemplate(String text) async {
    final result = FoodNlpParser.parse(text.trim());
    if (result.isEmpty) return [];
    final dbMatches = await _resolveDbMatches(result);
    return [
      for (var i = 0; i < result.items.length; i++)
        _buildEntry(result.items[i], dbMatches[i]),
    ];
  }

  Future<void> saveFoodTemplate(FoodTemplate template) async {
    if (_library.length >= 50) return; // cap at 50
    final idx = _library.indexWhere((t) => t.id == template.id);
    if (idx != -1) {
      _library[idx] = template;
    } else {
      _library.add(template);
    }
    safeNotify();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> deleteFoodTemplate(String templateId) async {
    _library.removeWhere((t) => t.id == templateId);
    safeNotify();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> renameTemplate(String templateId, String newName) async {
    final idx = _library.indexWhere((t) => t.id == templateId);
    if (idx == -1 || newName.trim().isEmpty) return;
    _library[idx] = _library[idx].copyWith(name: newName.trim());
    safeNotify();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> togglePinTemplate(String templateId) async {
    final idx = _library.indexWhere((t) => t.id == templateId);
    if (idx == -1) return;
    _library[idx] = _library[idx].copyWith(isPinned: !_library[idx].isPinned);
    safeNotify();
    await _storage.saveFoodLibrary(_library);
  }

  // ── Actions — AI estimation ───────────────────────────────────────────────────

  /// No-op — kept for API compatibility. The shared Qwen model is initialised
  /// by [OnDeviceAiCoachService.init] in [AiCoachPresenter].
  Future<void> initAi() async {
    safeNotify();
  }

  Future<void> estimateMeal(String description) async {
    if (!isAiAvailable) return;
    _isAiEstimating = true;
    _lastEstimate = null;
    _aiEstimateError = null;
    safeNotify();
    try {
      _lastEstimate = await _ai.estimateMacros(description);
      if (_lastEstimate == null) {
        _aiEstimateError = 'Model returned no usable data. Try again.';
      }
    } catch (e) {
      _lastEstimate = null;
      _aiEstimateError = _errorMessage(e);
    } finally {
      _isAiEstimating = false;
      safeNotify();
    }
  }

  String _errorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('timeout') || msg.contains('timeoutexception')) {
      return 'Analysis timed out. Try a shorter description.';
    }
    if (msg.contains('json') || msg.contains('format')) {
      return 'Model output unreadable. Please try again.';
    }
    return 'Analysis failed. Please try again.';
  }

  Future<void> confirmAiEstimate(
      List<AiItemEstimate> items, MealSlot slot) async {
    final entries = items.map((i) => i.toFoodEntry()).toList();
    for (final entry in entries) {
      await addFoodEntry(entry, slot);
    }
    _lastEstimate = null;
    safeNotify();
  }

  void clearEstimate() {
    _lastEstimate = null;
    _aiEstimateError = null;
    safeNotify();
  }

  // ── Actions — NLP food parser ─────────────────────────────────────────────

  /// Parse [description] using the rule-based [FoodNlpParser], then look up
  /// each item in the food DB. Notifies listeners when done.
  Future<void> parseMeal(String description) async {
    _isParsing = true;
    _lastParseResult = null;
    _parsedDbMatches = [];
    _parseError = null;
    safeNotify();

    try {
      final result = FoodNlpParser.parse(description);
      if (result.isEmpty) {
        _parseError =
            'Could not identify any food items. Try being more specific.';
        return;
      }
      _lastParseResult = result;
      _parsedDbMatches = await _resolveDbMatches(result);
    } catch (e) {
      _parseError = 'Failed to parse meal description.';
    } finally {
      _isParsing = false;
      safeNotify();
    }
  }

  /// Confirm and log the parsed items to [slot].
  /// [overrides] optionally replaces a DB match at index with a custom entry.
  Future<void> confirmParsedMeal(
    MealSlot slot, {
    Map<int, FoodEntry> overrides = const {},
  }) async {
    final result = _lastParseResult;
    if (result == null) return;
    // IF-Sync gate is a "now" concept — only blocks logging on TODAY. Past-day
    // backfills are always allowed even while currently fasting (Plan 037).
    if (isSelectedDateToday && _goals.ifSyncEnabled && !isEatingWindowOpen) {
      return;
    }

    await _ensureTodayLogFresh();

    final entries = [
      for (var i = 0; i < result.items.length; i++)
        overrides[i] ?? _buildEntry(result.items[i], _parsedDbMatches[i]),
    ];
    _todayLog = _todayLog.addEntries(entries, slot);
    safeNotify();

    await _storage.saveNutritionLog(_todayLog);
    await _applyLogSideEffects(_todayLog.date);

    _lastParseResult = null;
    _parsedDbMatches = [];
    safeNotify();
  }

  void clearParseResult() {
    _lastParseResult = null;
    _parsedDbMatches = [];
    _parseError = null;
    safeNotify();
  }

  Future<List<FoodDbEntry?>> _resolveDbMatches(FoodParseResult result) async {
    return Future.wait(result.items.map(_resolveOneDbItem));
  }

  /// Resolves one parsed item to a [FoodDbEntry] using a layered pipeline.
  ///
  /// Order:
  ///   1. Semantic top-k via [_semanticSearch] (RAG; injected, optional)
  ///   2. LLM rerank for ambiguous semantic results
  ///   3. Existing FTS5 + best-match scoring (always available)
  ///
  /// [altName] is searched alongside [item.name] in the FTS5 step, e.g. the
  /// original NLP name before AI normalisation. This catches cases where AI
  /// renamed "adobo" to "braised chicken" — both searches run, best score wins.
  /// Hybrid retrieval: parallel FTS5 (lexical) and semantic (vector) searches
  /// fused via Reciprocal Rank Fusion. Returns the top-1 entry plus runner-up
  /// alternatives and a confidence score derived from the gap between top-1
  /// and top-2 RRF scores. (Plan 022 §2.3 — replaces the old layered
  /// _resolveOneDbItem confidence-band logic.)
  Future<_HybridMatch?> _hybridResolveItem({required String name}) async {
    final ftsHits = await _foodDb.search(name);
    if (ftsHits.isEmpty) return null;

    const rrfK = 60;
    final scores = <String, double>{};
    final byId = <String, FoodDbEntry>{};
    for (var i = 0; i < ftsHits.length; i++) {
      final id = ftsHits[i].id;
      scores[id] = (scores[id] ?? 0) + 1.0 / (rrfK + i + 1);
      byId.putIfAbsent(id, () => ftsHits[i]);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pick = byId[ranked.first.key]!;
    final runnerUps = ranked.skip(1).take(4).map((e) => byId[e.key]!).toList();

    final top1 = ranked.first.value;
    final top2 = ranked.length > 1 ? ranked[1].value : 0.0;
    double confidence = top2 == 0 ? 0.55 : top1 / (top1 + top2);

    final qWords = SearchNormalize.wordTokens(name);
    final entryWords = SearchNormalize.wordTokens(pick.name);
    if (qWords.isNotEmpty && qWords.every(entryWords.contains)) {
      confidence += 0.10;
    }

    confidence = confidence.clamp(0.05, 0.95);

    return _HybridMatch(
      pick: pick,
      alternatives: runnerUps,
      confidence: confidence,
    );
  }

  Future<FoodDbEntry?> _resolveOneDbItem(
    ParsedFoodItem item, {
    String? altName,
  }) async {
    // Use the same hybrid RRF pipeline as the chat path for consistent quality.
    final hybrid = await _hybridResolveItem(name: item.name);
    if (hybrid != null) return hybrid.pick;
    // altName secondary FTS5 pass when hybrid found nothing (e.g. AI-normalised
    // form like "milk powder" vs raw "bearbrand").
    if (altName != null && altName.toLowerCase() != item.name.toLowerCase()) {
      return _resolveViaFts5(item.name, altName: altName);
    }
    return null;
  }

  Future<FoodDbEntry?> _resolveViaFts5(String name, {String? altName}) async {
    // Run primary + alt-name searches in parallel. FTS5's multi-token prefix
    // match already handles per-token coverage, so no extra fallback needed.
    final results = await Future.wait([
      _foodDb.search(name),
      if (altName != null && altName.toLowerCase() != name.toLowerCase())
        _foodDb.search(altName),
    ]);

    final allHits = <String, FoodDbEntry>{};
    for (final hits in results) {
      for (final h in hits) {
        allHits.putIfAbsent(h.id, () => h);
      }
    }

    if (allHits.isEmpty) return null;
    final best = FoodMatchScorer.pickBest(allHits.values.toList(), name);
    if (best == null) return null;

    // Confidence gate: only return when the match is strong enough to log
    // without review. Otherwise fall through (return null) so the caller
    // hands off to AI macro estimation rather than logging a confident-wrong
    // DB hit (e.g. "red rice" → "Sapin-sapin (rice cake)").
    //
    // We accept a match if it's learnable against either the primary name or
    // the alt name (AI-normalised name often passes when the raw NLP name
    // doesn't, e.g. "bearbrand" raw vs "milk powder" normalised).
    if (FoodMatchScorer.isLearnableMatch(best, name)) return best;
    if (altName != null &&
        altName.toLowerCase() != name.toLowerCase() &&
        FoodMatchScorer.isLearnableMatch(best, altName)) {
      return best;
    }
    return null;
  }

  FoodEntry _buildEntry(ParsedFoodItem parsed, FoodDbEntry? dbEntry) {
    if (dbEntry != null) {
      final base = dbEntry.toFoodEntry(parsed.grams);
      final isLexical = FoodMatchScorer.isLearnableMatch(dbEntry, parsed.name);
      final name = isLexical ? dbEntry.name : parsed.name;
      return base.copyWith(name: _formatDisplayName(name));
    }

    final estimatedKcal = cde.estimateKcal(parsed.name, parsed.grams);
    final (pR, cR, fR) = cde.bucketMacroRatios(parsed.name);
    final (estProtein, estCarbs, estFat) =
        cde.macrosFromCalories(estimatedKcal, pR: pR, cR: cR, fR: fR);
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: _formatDisplayName(parsed.name),
      calories: estimatedKcal,
      protein: estProtein,
      carbs: estCarbs,
      fat: estFat,
      grams: parsed.grams,
      estimationSource: EstimationSource.keywordDensity,
      confidence: 0.3,
      loggedAt: DateTime.now(),
    );
  }

  /// Coarse macro split (15% P / 50% C / 35% F) used when neither the food DB
  /// Title-cases food names so they render nicely in the chat feed.
  ///
  /// "red rice"                   → "Red Rice"
  /// "rice, red, cooked"          → "Rice, Red, Cooked"
  /// "buko (young coconut)"       → "Buko (Young Coconut)"
  /// "BEEF, GROUND, 80% LEAN"     → "Beef, Ground, 80% Lean"
  ///
  /// Punctuation, spacing, parentheses, and digits are preserved exactly.
  /// Each alphabetic run is title-cased independently.
  static final RegExp _alphaRun = RegExp(r'[a-zA-Z]+');
  String _formatDisplayName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.toLowerCase().splitMapJoin(
          _alphaRun,
          onMatch: (m) {
            final w = m.group(0)!;
            return w[0].toUpperCase() + w.substring(1);
          },
          onNonMatch: (s) => s,
        );
  }

  FoodEntry _buildEntryFromDict(
    ParsedFoodItem parsed,
    PersonalFoodEntry dict,
  ) {
    final factor = parsed.grams / 100;
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: _formatDisplayName(parsed.name),
      calories: (dict.kcalPer100g * factor).round().clamp(1, 9999),
      protein:
          dict.proteinPer100g != null ? dict.proteinPer100g! * factor : null,
      carbs: dict.carbsPer100g != null ? dict.carbsPer100g! * factor : null,
      fat: dict.fatPer100g != null ? dict.fatPer100g! * factor : null,
      grams: parsed.grams,
      estimationSource: EstimationSource.personalDict,
      loggedAt: DateTime.now(),
    );
  }

  Future<void> downloadAiModel() async {
    if (isAiDownloading) return;
    safeNotify();
    try {
      await _ai.downloadModel(onProgress: (_) => notifyListeners());
    } catch (_) {
      // Download failed — model remains unavailable; banner will stay visible.
    }
    safeNotify();
  }

  // ── Actions — chat feed ───────────────────────────────────────────────────────

  /// Switch the viewed day. Loads that day's chat messages and nutrition log.
  Future<void> setSelectedDate(DateTime date) async {
    if (_isChatParsing) return; // avoid desyncing log vs chat mid-parse
    _selectedDate = date;
    final dateKey = _dateFmt.format(date);
    final raw = await _storage.loadChatMessagesRaw(dateKey);
    _chatMessages = raw.map(ChatMessage.fromJson).toList();
    _todayLog = await _storage.loadNutritionLogForDate(dateKey);
    _reconcileChatWithLog();
    safeNotify();
  }

  // ── Weight log mutations ──────────────────────────────────────────────────

  Future<void> deleteWeight(String id) async {
    _weightLog = _weightLog.where((e) => e.id != id).toList();
    await _storage.saveWeightLog(_weightLog);
    safeNotify();
  }

  // ── Body measurement mutations ────────────────────────────────────────────

  Future<void> logMeasurement(BodyMeasurementEntry entry) async {
    _measurementLog = [..._measurementLog, entry]
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    await _storage.saveBodyMeasurements(_measurementLog);
    await _checkRecompXp();
    safeNotify();
  }

  Future<void> updateMeasurement(BodyMeasurementEntry updated) async {
    _measurementLog = [
      for (final e in _measurementLog)
        if (e.id == updated.id) updated else e,
    ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    await _storage.saveBodyMeasurements(_measurementLog);
    safeNotify();
  }

  Future<void> deleteMeasurement(String id) async {
    _measurementLog = _measurementLog.where((e) => e.id != id).toList();
    await _storage.saveBodyMeasurements(_measurementLog);
    safeNotify();
  }

  Future<void> setMeasurementUnit(MeasurementUnit unit) async {
    _measurementUnit = unit;
    await _storage.saveMeasurementUnit(unit);
    safeNotify();
  }

  Future<void> _checkRecompXp() async {
    if (activeGoal != 'cut') return;
    if (waistTrendDirection != MeasurementTrendDirection.down) return;
    if (weightTrendDirection != WeightTrendDirection.stable) return;
    final now = DateTime.now();
    if (_lastRecompXpDate != null &&
        now.difference(_lastRecompXpDate!).inDays < 7) {
      return;
    }
    _lastRecompXpDate = now;
    await _storage.saveLastRecompXpDate(now);
    await _statsPresenter.addXp(300);
    await _notifications.showSimpleNotification(
      title: 'Recomp confirmed',
      body:
          'Your waist is shrinking while weight holds steady. Keep going. +300 XP',
    );
  }

  /// Maximum chat input length. Above this we reject — long pastes can blow
  /// up AI prompt budgets and stall parsing for tens of seconds.
  static const int _maxChatInputLength = 500;

  // ── Debug / dev tools ────────────────────────────────────────────────────
  // REMOVE before any production audit — only called from kDebugMode tiles.

  /// Fires a minimal cloud-parse call and returns a human-readable summary
  /// of what came back (tier hit, items, latency). Safe to call standalone —
  /// does not mutate any presenter state.
  Future<String> debugTestCloudAi() async {
    final cloud = _cloudAi;
    if (cloud == null) return 'cloudAi not injected';
    if (!cloud.isAvailable) {
      return 'isAvailable=false  '
          '(endpoint=${cloud.runtimeType}, enabled=${cloud.isAvailable})';
    }
    final sw = Stopwatch()..start();
    try {
      final candidates = await _buildCandidatePool('1 cup of rice');
      final result =
          await cloud.parseFoodWithCandidates('1 cup of rice', candidates);
      sw.stop();
      if (result == null) {
        // High-signal diagnostic: show the raw HTTP response so we can
        // tell whether this is auth (401), rate-limit (429), or server error.
        String ping = '';
        if (cloud is CloudAiCoachService) {
          ping = await cloud.debugPing('parseFoodWithCandidates', {
            'text': '1 cup of rice',
            'candidates': candidates
                .take(3)
                .map((c) => {'food_id': c.entry.id, 'name': c.entry.name})
                .toList(),
          });
        }
        return 'null (${sw.elapsedMilliseconds}ms)\n$ping';
      }
      final items =
          result.items.map((i) => '${i.name} (${i.grams}g)').join(', ');
      return '✓ ${sw.elapsedMilliseconds}ms\n$items';
    } catch (e) {
      sw.stop();
      return 'error after ${sw.elapsedMilliseconds}ms:\n$e';
    }
  }

  /// Parse [text] as food or exercise, add to the chat feed, and persist.
  Future<void> parseChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isChatParsing) return;
    if (trimmed.length > _maxChatInputLength) {
      _chatParseError =
          'Input too long ($_maxChatInputLength char limit). Split into smaller messages.';
      safeNotify();
      return;
    }
    _isChatParsing = true;
    _chatParseError = null;
    safeNotify();

    try {
      if (ExerciseNlpParser.looksLikeExercise(trimmed)) {
        await _parseChatAsExercise(trimmed);
      } else {
        await _parseChatAsFood(trimmed);
      }
    } catch (e) {
      _chatParseError = 'Something went wrong. Please try again.';
      debugPrint('NutritionPresenter: parseChat error: $e');
    } finally {
      _isChatParsing = false;
      safeNotify();
    }
  }

  // ── Composer review flow (resolve → preview → commit) ──────────────────────

  /// True when a resolved-but-unlogged estimate is awaiting review.
  bool get hasPendingChat => _pendingResolved != null;

  /// The pending estimate's entries (for the composer to render); empty if none.
  List<FoodEntry> get pendingChatEntries =>
      _pendingResolved?.entries ?? const [];

  /// Per-item alternatives for the pending estimate (parallel to entries).
  List<List<ChatFoodAlternative>> get pendingChatAlternatives =>
      _pendingResolved?.alts ?? const [];

  /// Total calories of the pending estimate (0 when none). Keeps the estimate
  /// card's totals out of `build()` (architecture rule 1).
  int get pendingChatTotalCalories =>
      pendingChatEntries.fold(0, (s, e) => s + e.calories);

  /// Summed macros (grams) of the pending estimate; zeros when none.
  ({double protein, double carbs, double fat}) get pendingChatMacros {
    var p = 0.0, c = 0.0, f = 0.0;
    for (final e in pendingChatEntries) {
      p += e.protein ?? 0;
      c += e.carbs ?? 0;
      f += e.fat ?? 0;
    }
    return (protein: p, carbs: c, fat: f);
  }

  /// Clears all three pending-estimate fields together — the single source of
  /// truth so previewChat/commit/discard can't desync them.
  void _clearPending() {
    _pendingResolved = null;
    _pendingText = null;
    _pendingThumbPath = null;
  }

  /// Resolve [text] into a pending estimate for review WITHOUT logging it.
  /// Food → populates [pendingChatEntries] (caller shows the estimate card).
  /// Exercise → logged atomically (no estimate step). On failure sets
  /// [chatParseError]. Nothing is committed to the log for food until
  /// [commitPendingChat] is called.
  Future<void> previewChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isChatParsing) return;
    if (trimmed.length > _maxChatInputLength) {
      _chatParseError =
          'Input too long ($_maxChatInputLength char limit). Split into smaller messages.';
      safeNotify();
      return;
    }
    _isChatParsing = true;
    _chatParseError = null;
    // NOTE: we intentionally do NOT clear the pending estimate here. A second
    // food submission while an estimate is on screen ACCUMULATES into it (the
    // composer hint says "Add another item…"). A fresh composer already has no
    // pending (dispose/Edit call discardPendingChat), so the first item still
    // starts clean. Exercise still logs atomically without touching pending.
    safeNotify();

    try {
      if (ExerciseNlpParser.looksLikeExercise(trimmed)) {
        await _parseChatAsExercise(trimmed); // atomic — no review step
      } else {
        final resolved = await _resolveChatFood(trimmed);
        if (resolved != null) {
          final existing = _pendingResolved;
          if (existing != null) {
            // Merge into the existing estimate so both items are reviewed and
            // logged together.
            _pendingResolved = (
              entries: [...existing.entries, ...resolved.entries],
              alts: [...existing.alts, ...resolved.alts],
              rawTexts: [...existing.rawTexts, ...resolved.rawTexts],
            );
            _pendingText = [
              if (_pendingText != null && _pendingText!.isNotEmpty)
                _pendingText!,
              trimmed,
            ].join('; ');
          } else {
            _pendingResolved = resolved;
            _pendingText = trimmed;
          }
        }
      }
    } catch (e) {
      _chatParseError = 'Something went wrong. Please try again.';
      debugPrint('NutritionPresenter: previewChat error: $e');
    } finally {
      _isChatParsing = false;
      safeNotify();
    }
  }

  /// Re-resolve a pending item after an inline rename so its calories/macros
  /// reflect the new name (runs the same resolver as chat food). Keeps the
  /// user's typed [newName] as the label but swaps in the freshly-resolved
  /// nutrition. On resolver failure the name still updates (macros unchanged).
  /// No-op for empty name / bad index / no pending estimate.
  Future<void> recomputePendingChatEntry(int index, String newName) async {
    final resolved = _pendingResolved;
    final name = newName.trim();
    if (resolved == null || name.isEmpty) return;
    if (index < 0 || index >= resolved.entries.length) return;
    if (_isChatParsing) return;

    _isChatParsing = true;
    final priorError = _chatParseError;
    safeNotify();
    try {
      final r = await _resolveChatFood(name);
      // Recompute must never surface a chat error to the composer.
      _chatParseError = priorError;
      final cur = _pendingResolved;
      if (cur == null || index >= cur.entries.length) return;
      final base = cur.entries[index];
      final src = (r != null && r.entries.isNotEmpty) ? r.entries.first : null;
      final updated = src == null
          ? base.copyWith(name: name)
          : base.copyWith(
              name: name,
              calories: src.calories,
              protein: src.protein,
              carbs: src.carbs,
              fat: src.fat,
              grams: src.grams,
              estimationSource: src.estimationSource,
              confidence: src.confidence,
            );
      final entries = [...cur.entries];
      entries[index] = updated;
      _pendingResolved = (
        entries: entries,
        alts: cur.alts,
        rawTexts: cur.rawTexts,
      );
    } catch (e) {
      _chatParseError = priorError;
      debugPrint('NutritionPresenter: recomputePendingChatEntry error: $e');
    } finally {
      _isChatParsing = false;
      safeNotify();
    }
  }

  /// Commit the pending estimate to today's log (creates the log entry).
  /// Returns the new entry's id for undo, or null when there was nothing pending
  /// or logging was gated. No-op when there is no pending estimate.
  Future<String?> commitPendingChat() async {
    final resolved = _pendingResolved;
    final text = _pendingText;
    if (resolved == null || text == null) return null;
    final thumb = _pendingThumbPath;
    _clearPending();
    safeNotify();
    return _commitFoodChat(
      text,
      resolved.entries,
      resolved.alts,
      resolved.rawTexts,
      photoThumbnailPath: thumb,
    );
  }

  /// Drop the pending estimate without logging it (Edit / Cancel). Deletes an
  /// un-committed photo thumbnail so retakes don't leak files.
  void discardPendingChat() {
    if (_pendingResolved == null &&
        _pendingText == null &&
        _pendingThumbPath == null) {
      return;
    }
    final thumb = _pendingThumbPath;
    _clearPending();
    if (thumb != null) {
      // ignore: unawaited_futures
      _photoStore.delete(thumb);
    }
    safeNotify();
  }

  // ── Photo food logging (Plan 029) ─────────────────────────────────────────

  /// True while a photo is being compressed + analysed by the vision endpoint.
  bool get isPhotoParsing => _isPhotoParsing;

  /// User-facing error from the last photo parse, or null. Cleared on the next
  /// [resolvePhotoPreview] call.
  String? get photoParseError => _photoParseError;

  void clearPhotoParseError() {
    if (_photoParseError == null) return;
    _photoParseError = null;
    safeNotify();
  }

  /// Resolve a stored thumbnail's docs-relative path to an absolute file path
  /// for display, or null if missing. Exposed for the chat-row widget.
  Future<String?> resolvePhotoThumbnail(String relativePath) =>
      _photoStore.absolutePath(relativePath);

  /// Resolve a meal from a photo (+ optional [caption]) into a pending estimate
  /// for review — WITHOUT logging. Compresses the image, sends it to the cloud
  /// vision endpoint, and stages the detected items (+ thumbnail) as the pending
  /// estimate. The caller shows the estimate and calls [commitPendingChat] to
  /// log or [discardPendingChat] to drop it.
  ///
  /// Photo items are tagged [EstimationSource.photoAi] and are NEVER promoted
  /// into the personal dictionary (§0.2) — vision estimates are the least
  /// verified input, so they must not silently bypass the DB. The whole flow
  /// is disposal-safe (§0.4): dismissing the sheet mid-call must not notify a
  /// disposed presenter.
  Future<void> resolvePhotoPreview(Uint8List imageBytes,
      {String? caption}) async {
    if (_isPhotoParsing) return;
    final cloud = _cloudAi;
    if (cloud == null || !cloud.isAvailable) {
      _photoParseError =
          'Photo logging needs Cloud AI. Enable it in Settings and sign in.';
      safeNotify();
      return;
    }

    _isPhotoParsing = true;
    _photoParseError = null;
    _clearPending(); // don't inherit a stale text/photo estimate
    safeNotify();

    try {
      final upload = await _imageCompressor.compressForUpload(imageBytes);
      if (isDisposed) return;

      final result = await cloud
          .parseFoodFromImage(upload, 'image/jpeg', caption)
          .timeout(const Duration(seconds: 35));
      if (isDisposed) return;

      // Log the real outcome before mapping to a user message — the detail
      // (HTTP code / body snippet / exception) is the only breadcrumb we get
      // from a release build that has no attached console.
      if (result.status != PhotoParseStatus.ok) {
        debugPrint(
            'NutritionPresenter: resolvePhotoPreview status=${result.status.name}'
            '${result.httpStatus != null ? ' http=${result.httpStatus}' : ''}'
            '${result.detail != null ? ' detail=${result.detail}' : ''}');
      }

      switch (result.status) {
        case PhotoParseStatus.unavailable:
          _photoParseError =
              'Photo logging needs Cloud AI. Enable it in Settings and sign in.';
          return;
        case PhotoParseStatus.rateLimited:
          _photoParseError =
              'Daily AI limit reached. Photo logging resets tomorrow.';
          return;
        case PhotoParseStatus.noFood:
          _photoParseError = "Couldn't spot any food in that photo. "
              'Try another shot or describe it in text.';
          return;
        case PhotoParseStatus.networkError:
          // The only case where the connection is actually suspect.
          _photoParseError = "Couldn't reach the photo analyser. "
              'Check your connection and try again.';
          return;
        case PhotoParseStatus.serverError:
          // Connection is fine; the backend failed. Be honest, and include the
          // code so a report is actionable.
          _photoParseError = 'Photo analysis is temporarily unavailable'
              '${result.httpStatus != null ? ' (error ${result.httpStatus})' : ''}'
              '. Please try again in a bit.';
          return;
        case PhotoParseStatus.failed:
          _photoParseError = "Couldn't read the photo analysis. "
              'Please try again.';
          return;
        case PhotoParseStatus.ok:
          break;
      }

      // Build a log entry per detected item. food_id is always null for photo,
      // so macros come from the vision estimate. Tagged photoAi → shown as an
      // estimate and excluded from personal-dict auto-learn.
      final entries = <FoodEntry>[];
      final altsList = <List<ChatFoodAlternative>>[];
      final rawTexts = <String>[];
      for (final item in result.items) {
        final m = item.estimatedMacros;
        final photoEntry = FoodEntry(
          id: FoodEntry.generateId(),
          name: _formatDisplayName(item.name),
          calories:
              m?.calories.round() ?? cde.estimateKcal(item.name, item.grams),
          protein: m?.proteinG,
          carbs: m?.carbsG,
          fat: m?.fatG,
          grams: item.grams,
          estimationSource: EstimationSource.photoAi,
          confidence:
              item.resolverConfidence > 0 ? item.resolverConfidence : 0.6,
          loggedAt: DateTime.now(),
        );
        entries.add(photoEntry);
        // Photo estimates aren't cached on first sight, but repetition earns it
        // a spot in the personal dict (see the cloud path / _kLearnAfterLogs).
        if (m != null &&
            _priorLogCount(photoEntry.name) + 1 >= _kLearnAfterLogs) {
          // ignore: unawaited_futures
          _learnFromEntry(item.name, photoEntry, allowLowConfidence: true);
        }
        altsList.add(const []);
        rawTexts.add(item.name);
      }
      if (entries.isEmpty) {
        _photoParseError = "Couldn't spot any food in that photo. "
            'Try another shot or describe it in text.';
        return;
      }

      final captionLabel = (caption != null && caption.trim().isNotEmpty)
          ? caption.trim()
          : 'Photo meal';

      var commitEntries = entries;
      var commitAlts = altsList;
      var commitRaw = rawTexts;
      if (result.intent == ParseIntent.singleDish && entries.length > 1) {
        final combined = _combineEntriesAsOneDish(entries, captionLabel);
        commitEntries = [combined];
        commitAlts = const [[]];
        commitRaw = [captionLabel];
      }

      // Persist a thumbnail for the chat row. Best-effort — a failed thumbnail
      // must not block logging the meal.
      String? thumbPath;
      try {
        final thumbBytes = await _imageCompressor.makeThumbnail(imageBytes);
        if (isDisposed) return;
        thumbPath = await _photoStore.saveThumbnail(
            thumbBytes, ChatMessage.generateId());
      } catch (e) {
        debugPrint('NutritionPresenter: thumbnail save failed: $e');
      }
      if (isDisposed) return;

      // Stage as the pending estimate for review — commit happens on "Log it".
      _pendingResolved = (
        entries: commitEntries,
        alts: commitAlts,
        rawTexts: commitRaw,
      );
      _pendingText = captionLabel;
      _pendingThumbPath = thumbPath;
    } on TimeoutException {
      if (isDisposed) return;
      _photoParseError = 'Photo analysis timed out. Please try again.';
    } catch (e) {
      if (isDisposed) return;
      _photoParseError = "Couldn't analyse this photo. Please try again.";
      debugPrint('NutritionPresenter: resolvePhotoPreview error: $e');
    } finally {
      if (!isDisposed) {
        _isPhotoParsing = false;
        safeNotify();
      }
    }
  }

  /// Resolve [text] into food entries WITHOUT committing — shared by the atomic
  /// [_parseChatAsFood] (used by [parseChat]) and the review flow [previewChat].
  /// Returns null and sets [_chatParseError] when nothing could be identified.
  Future<_ResolvedChatFood?> _resolveChatFood(String text) async {
    // Plan 026/027 — tiered single-call pipeline.
    //   Path A (cloud, Plan 026): Bedrock single call extracts + resolves +
    //     estimates macros for off-DB foods. Highest quality.
    //   Path B (on-device single-call, Plan 027 §2.1): Qwen extracts +
    //     picks from candidates. No macro estimation — falls through to
    //     keyword bucket for unmatched items.
    //   Path C (on-device legacy, Plan 022): extractFoodItems + per-item
    //     personal dict → hybrid FTS+semantic → keyword fallback. Reached
    //     when paths A and B both return null/fail.

    // Path A: cloud-primary single call.
    if ((_cloudAi?.isAvailable ?? false)) {
      final cloudResult = await _tryCloudParseFood(text);
      if (cloudResult != null) {
        return (
          entries: cloudResult.entries,
          alts: cloudResult.alts,
          rawTexts: cloudResult.rawTexts,
        );
      }
    }

    // Path B: on-device single-call (Plan 027 §2.1).
    if (_ai.isAvailable) {
      final localResult = await _tryLocalParseFood(text);
      if (localResult != null) {
        return (
          entries: localResult.entries,
          alts: localResult.alts,
          rawTexts: localResult.rawTexts,
        );
      }
    }

    // Path C: on-device extraction → per-item local resolution.
    List<ExtractedFoodItem> items = const [];
    if (_ai.isAvailable) {
      try {
        final extracted = await _ai
            .extractFoodItems(text)
            .timeout(const Duration(seconds: 25));
        if (extracted != null && extracted.isNotEmpty) {
          items = extracted;
        }
      } catch (e) {
        debugPrint('NutritionPresenter: extractFoodItems failed: $e');
      }
    }

    if (items.isEmpty) {
      // No-AI fallback (Plan 022 §2.4): rule-based parser, no HyDE.
      final nlpResult = FoodNlpParser.parse(text);
      if (nlpResult.isEmpty) {
        _chatParseError = 'Could not identify any food items.';
        return null;
      }
      items = nlpResult.items
          .map((p) => ExtractedFoodItem(
                name: p.name,
                grams: p.grams,
                hydeDescription: p.name, // reuse name when HyDE unavailable
                rawText: p.rawText,
              ))
          .toList();
    }

    // ── Layer 2 + 3: resolve each item, commit, build chat row ────────────
    final entries = <FoodEntry>[];
    final altsList = <List<ChatFoodAlternative>>[];

    for (final item in items) {
      // Personal dict — instant, always trusted, max confidence.
      final dictHit = _personalDict.lookup(item.name);
      if (dictHit != null) {
        entries.add(_buildEntryFromDict(
          ParsedFoodItem(
              rawText: item.rawText,
              name: item.name,
              grams: item.grams,
              isEstimated: false),
          dictHit,
        ));
        altsList.add(const []);
        continue;
      }

      final hybrid = await _hybridResolveItem(name: item.name);

      if (hybrid != null) {
        final entry = hybrid.pick.toFoodEntry(item.grams).copyWith(
              estimationSource: EstimationSource.db,
              confidence: hybrid.confidence,
            );
        entries.add(entry);
        // Plan 027 §2.1 — local hybrid resolve no longer auto-promotes to the
        // personal dict on a single log (too risky for false positives).
        // Cloud-confirmed picks still do, the user can save manually via the
        // chat row, and repeat-learning caches it once the same food is logged
        // [_kLearnAfterLogs] times (repetition is the trust signal).
        _maybeRepeatLearn(item.name, entry);
        // Stash up to 2 alternatives when the auto-pick was uncertain so
        // the chat row can render swap chips (ChatFoodItem.needsConfirmation
        // gates the rendering at the < 0.6 threshold).
        if (hybrid.confidence < 0.6 && hybrid.alternatives.isNotEmpty) {
          altsList.add(hybrid.alternatives.take(2).map((e) {
            final alt = e.toFoodEntry(item.grams);
            return ChatFoodAlternative(
              name: alt.name,
              calories: alt.calories,
              protein: alt.protein,
              carbs: alt.carbs,
              fat: alt.fat,
              grams: alt.grams,
              estimationSource: EstimationSource.db,
            );
          }).toList());
        } else {
          altsList.add(const []);
        }
        continue;
      }

      // Last-ditch: keyword-density estimate with macro split-from-calories.
      final estKcal = cde.estimateKcal(item.name, item.grams);
      final (bpR, bcR, bfR) = cde.bucketMacroRatios(item.name);
      final (estProtein, estCarbs, estFat) =
          cde.macrosFromCalories(estKcal, pR: bpR, cR: bcR, fR: bfR);
      entries.add(FoodEntry(
        id: FoodEntry.generateId(),
        name: _formatDisplayName(item.name),
        calories: estKcal,
        protein: estProtein,
        carbs: estCarbs,
        fat: estFat,
        grams: item.grams,
        estimationSource: EstimationSource.keywordDensity,
        confidence: 0.3,
        loggedAt: DateTime.now(),
      ));
      altsList.add(const []);
      // Telemetry: this is a DB miss — record the query so it shows up in the
      // curation backlog. Fire-and-forget; storage failure shouldn't block the
      // user's log.
      // ignore: unawaited_futures
      _logFeedback(
        kind: FoodFeedbackKind.fallbackMiss,
        userQuery: item.name,
        pickedName: item.name,
        pickedDbId: null,
        estimationSource: EstimationSource.keywordDensity,
        confidence: 0.3,
      );
    }

    return (
      entries: entries,
      alts: altsList,
      rawTexts: [for (final item in items) item.rawText],
    );
  }

  /// Atomic food logging (type → log in one step) — used by [parseChat] and the
  /// Hub quick-log. Resolves then immediately commits.
  Future<void> _parseChatAsFood(String text) async {
    final resolved = await _resolveChatFood(text);
    if (resolved != null) {
      await _commitFoodChat(
          text, resolved.entries, resolved.alts, resolved.rawTexts);
    }
  }

  // ── On-device single-call path (Plan 027 §2.1) ───────────────────────────

  /// On-device parallel to [_tryCloudParseFood]. Qwen extracts items and
  /// picks from candidates; unmatched items get null food_id and we fall
  /// through to keyword-bucket synthesis here so the user still gets *some*
  /// entry logged. Returns null on total failure so caller falls through to
  /// the legacy hybrid path.
  Future<_CloudParseResult?> _tryLocalParseFood(String text) async {
    try {
      final candidates = await _buildCandidatePool(text);
      final extracted = await _ai
          .parseFoodWithCandidates(text, candidates)
          .timeout(const Duration(seconds: 30));
      if (extracted == null || extracted.items.isEmpty) return null;

      final entries = <FoodEntry>[];
      final altsList = <List<ChatFoodAlternative>>[];
      final rawTexts = <String>[];

      for (final item in extracted.items) {
        rawTexts.add(item.rawText);
        FoodEntry? entry;

        // Personal dict precedence.
        final dictHit = _personalDict.lookup(item.name);
        if (dictHit != null) {
          entry = _buildEntryFromDict(
            ParsedFoodItem(
                rawText: item.rawText,
                name: item.name,
                grams: item.grams,
                isEstimated: false),
            dictHit,
          );
        } else if (item.resolvedFoodId != null &&
            item.resolverConfidence >= 0.70) {
          final hit = await _foodDb.getById(item.resolvedFoodId!);
          if (hit != null) {
            entry = hit.toFoodEntry(item.grams).copyWith(
                  name: _formatDisplayName(item.name),
                  estimationSource: EstimationSource.localAi,
                  confidence: item.resolverConfidence,
                );
          }
        }

        // AI didn't resolve confidently — try hybrid RRF before keyword bucket.
        // HyDE description improves semantic recall over the raw name alone.
        List<ChatFoodAlternative> alts = const [];
        if (entry == null) {
          final hybrid = await _hybridResolveItem(name: item.name);
          if (hybrid != null) {
            entry = hybrid.pick.toFoodEntry(item.grams).copyWith(
                  name: _formatDisplayName(item.name),
                  estimationSource: EstimationSource.localAi,
                  confidence: hybrid.confidence,
                );
            if (hybrid.confidence < 0.6 && hybrid.alternatives.isNotEmpty) {
              alts = hybrid.alternatives.take(2).map((e) {
                final alt = e.toFoodEntry(item.grams);
                return ChatFoodAlternative(
                  name: alt.name,
                  calories: alt.calories,
                  protein: alt.protein,
                  carbs: alt.carbs,
                  fat: alt.fat,
                  grams: alt.grams,
                  estimationSource: EstimationSource.db,
                );
              }).toList();
            }
          }
        }

        // Last-ditch: keyword-bucket fallback when both AI and hybrid failed.
        if (entry == null) {
          final estKcal = cde.estimateKcal(item.name, item.grams);
          final (estProtein, estCarbs, estFat) =
              cde.macrosFromCalories(estKcal);
          entry = FoodEntry(
            id: FoodEntry.generateId(),
            name: _formatDisplayName(item.name),
            calories: estKcal,
            protein: estProtein,
            carbs: estCarbs,
            fat: estFat,
            grams: item.grams,
            estimationSource: EstimationSource.keywordDensity,
            confidence: 0.3,
            loggedAt: DateTime.now(),
          );
          // Stale or missing food_id — record for curation backlog.
          // ignore: unawaited_futures
          _logFeedback(
            kind: FoodFeedbackKind.fallbackMiss,
            userQuery: item.name,
            pickedName: item.name,
            pickedDbId: item.resolvedFoodId,
            estimationSource: EstimationSource.keywordDensity,
            confidence: 0.3,
          );
        }

        entries.add(entry);
        altsList.add(alts);
        // Repeat-learning: cache foods logged 3+ times so the dict fills even
        // without Cloud AI (on-device resolves don't auto-promote otherwise).
        _maybeRepeatLearn(item.name, entry);
      }

      // Plan 027 — collapse into one entry when AI flagged the input as a
      // single composite dish (e.g. "egg with sardines"). Keeps the log
      // tidy without losing macro accuracy.
      if (extracted.intent == ParseIntent.singleDish && entries.length > 1) {
        final combined = _combineEntriesAsOneDish(entries, text);
        return _CloudParseResult(
          entries: [combined],
          alts: const [[]],
          rawTexts: [text],
        );
      }

      return _CloudParseResult(
        entries: entries,
        alts: altsList,
        rawTexts: rawTexts,
      );
    } catch (e) {
      debugPrint('NutritionPresenter: local parse failed: $e');
      return null;
    }
  }

  // ── Cloud-primary path (Plan 026) ───────────────────────────────────────

  /// Single Bedrock call that extracts items, picks `food_id` from a
  /// pre-fetched candidate pool, and estimates macros for unmatched items.
  /// Returns null on any failure so the caller can fall back to on-device.
  Future<_CloudParseResult?> _tryCloudParseFood(String text) async {
    final cloud = _cloudAi;
    if (cloud == null || !cloud.isAvailable) return null;

    try {
      // Build candidate pool from alias-aware FTS over the whole text plus
      // each NLP-detected fragment. Total budget: <100ms.
      final candidates = await _buildCandidatePool(text);

      final extracted = await cloud
          .parseFoodWithCandidates(text, candidates)
          .timeout(const Duration(seconds: 25));
      if (extracted == null || extracted.items.isEmpty) return null;

      // Mirror the on-device guards that live in OnDeviceAiCoachService.
      // Cloud returns raw items; apply the same post-parse fixups here.
      var items = extracted.items;

      // Canonical-USDA guard: "Egg, Whole, Cooked, Scrambled" is one ingredient,
      // not four. Cloud sometimes decomposes on commas despite prompt instructions.
      if (items.length > 1 && FoodNlpParser.looksLikeUsdaCanonical(text)) {
        final g = _cloudSingleItemExplicitGrams(text) ?? items.first.grams;
        items = [
          ExtractedFoodItem(
            name: text.trim(),
            grams: g,
            hydeDescription: items.first.hydeDescription,
            rawText: text,
            resolvedFoodId: items.first.resolvedFoodId,
            resolverConfidence: items.first.resolverConfidence,
            estimatedMacros: items.first.estimatedMacros,
            macroFallback: items.first.macroFallback,
          ),
        ];
      }

      // Single-item explicit-gram reconciliation: user wrote "12g chocolate crinkle"
      // but cloud returned 40g. Trust the user's gram count and scale macros.
      if (items.length == 1) {
        final userGrams = _cloudSingleItemExplicitGrams(text);
        if (userGrams != null && userGrams > 0) {
          final i = items.first;
          if ((i.grams - userGrams).abs() / userGrams > 0.05) {
            final ratio = userGrams / i.grams;
            EstimatedMacros? scaledMacros;
            if (i.estimatedMacros != null) {
              final m = i.estimatedMacros!;
              scaledMacros = EstimatedMacros(
                calories: m.calories * ratio,
                proteinG: m.proteinG * ratio,
                carbsG: m.carbsG * ratio,
                fatG: m.fatG * ratio,
              );
            }
            items = [
              ExtractedFoodItem(
                name: i.name,
                grams: userGrams,
                hydeDescription: i.hydeDescription,
                rawText: i.rawText,
                resolvedFoodId: i.resolvedFoodId,
                resolverConfidence: i.resolverConfidence,
                estimatedMacros: scaledMacros,
                macroFallback: i.macroFallback,
              ),
            ];
          }
        }
      }

      // IF-Sync gate runs at commit time, not here.
      final entries = <FoodEntry>[];
      final altsList = <List<ChatFoodAlternative>>[];
      final rawTexts = <String>[];

      for (final item in items) {
        rawTexts.add(item.rawText);
        FoodEntry? entry;

        // Personal dict precedence — saves a round-trip the next time.
        final dictHit = _personalDict.lookup(item.name);
        if (dictHit != null) {
          entry = _buildEntryFromDict(
            ParsedFoodItem(
                rawText: item.rawText,
                name: item.name,
                grams: item.grams,
                isEstimated: false),
            dictHit,
          );
        } else if (item.resolvedFoodId != null &&
            item.resolverConfidence >= 0.70) {
          // Cloud picked a DB candidate. Hydrate from DB for fresh macros.
          // Tag as cloudAi so the badge shows "Cloud" — the resolution was
          // cloud-driven even though the macros came from the DB row.
          final hit = await _foodDb.getById(item.resolvedFoodId!);
          if (hit != null) {
            entry = hit.toFoodEntry(item.grams).copyWith(
                  // Preserve the user's phrasing, not the DB canonical name.
                  name: _formatDisplayName(item.name),
                  estimationSource: EstimationSource.cloudAi,
                  confidence: item.resolverConfidence,
                );
            // Auto-promote confident cloud-resolved picks to personal dict.
            if (item.resolverConfidence >= 0.8) {
              // ignore: unawaited_futures
              _learnFromEntry(item.name, entry);
            }
          }
        } else if (item.estimatedMacros != null) {
          // Cloud couldn't pick a DB candidate; use its open-ended estimate.
          final m = item.estimatedMacros!;
          // Plan 034 SEV-3: when macroFallback is true the Lambda synthesised
          // a generic ~2 kcal/g ratio (model forgot to return macros). Use the
          // cloudAiFallback source so the UI shows 'Cloud~' in error colour,
          // signalling the user that this figure is a rough approximation.
          final source = item.macroFallback
              ? EstimationSource.cloudAiFallback
              : EstimationSource.cloudAi;
          entry = FoodEntry(
            id: FoodEntry.generateId(),
            name: _formatDisplayName(item.name),
            calories: m.calories.round(),
            protein: m.proteinG,
            carbs: m.carbsG,
            fat: m.fatG,
            grams: item.grams,
            estimationSource: source,
            confidence: item.macroFallback
                ? 0.1
                : (item.resolverConfidence > 0 ? item.resolverConfidence : 0.6),
            loggedAt: DateTime.now(),
          );
          // H2: a SINGLE open cloud estimate is not auto-learned (a one-off
          // hallucination would bypass the DB permanently). But once the user
          // has logged this same food [_kLearnAfterLogs] times, repetition is a
          // trustworthy enough signal to cache it. The generic ~2 kcal/g
          // fallback (cloudAiFallback) is excluded — it's a guess, not an
          // estimate.
          if (source == EstimationSource.cloudAi &&
              _priorLogCount(entry.name) + 1 >= _kLearnAfterLogs) {
            // ignore: unawaited_futures
            _learnFromEntry(item.name, entry, allowLowConfidence: true);
          }
        }

        if (entry == null) {
          // DB lookup failed for the resolved food_id and no macro estimate
          // was provided. Don't abort the whole parse — fall to keyword bucket
          // so other items in a multi-item meal still commit correctly.
          final estKcal = cde.estimateKcal(item.name, item.grams);
          final (estProtein, estCarbs, estFat) =
              cde.macrosFromCalories(estKcal);
          entry = FoodEntry(
            id: FoodEntry.generateId(),
            name: _formatDisplayName(item.name),
            calories: estKcal,
            protein: estProtein,
            carbs: estCarbs,
            fat: estFat,
            grams: item.grams,
            estimationSource: EstimationSource.keywordDensity,
            confidence: 0.3,
            loggedAt: DateTime.now(),
          );
          // Stale or missing food_id — record for curation backlog.
          // ignore: unawaited_futures
          _logFeedback(
            kind: FoodFeedbackKind.fallbackMiss,
            userQuery: item.name,
            pickedName: item.name,
            pickedDbId: item.resolvedFoodId,
            estimationSource: EstimationSource.keywordDensity,
            confidence: 0.3,
          );
        }

        entries.add(entry);
        altsList.add(const []);
      }

      // Plan 027 — collapse into one entry when AI flagged the input as a
      // single composite dish (e.g. "egg with sardines"). Keeps the log
      // tidy without losing macro accuracy.
      if (extracted.intent == ParseIntent.singleDish && entries.length > 1) {
        final combined = _combineEntriesAsOneDish(entries, text);
        return _CloudParseResult(
          entries: [combined],
          alts: const [[]],
          rawTexts: [text],
        );
      }

      return _CloudParseResult(
        entries: entries,
        alts: altsList,
        rawTexts: rawTexts,
      );
    } catch (e) {
      debugPrint('NutritionPresenter: cloud parse failed: $e');
      return null;
    }
  }

  /// Plan 027 — sum a list of [FoodEntry] into a single combined entry whose
  /// name is the user's original input. Used when the AI flags a multi-item
  /// extraction as a single composite dish. The resulting `estimationSource`
  /// is the worst-quality (most-degraded) source among constituents so the
  /// badge accurately reflects the lowest-confidence ingredient.
  FoodEntry _combineEntriesAsOneDish(
      List<FoodEntry> parts, String originalText) {
    int cal = 0;
    double? p = 0, c = 0, f = 0;
    double grams = 0;
    double minConfidence = 1.0;
    EstimationSource worstSource = EstimationSource.db;
    const sourceRank = {
      EstimationSource.db: 0,
      EstimationSource.personalDict: 0,
      EstimationSource.userManual: 0,
      EstimationSource.cloudAi: 1,
      EstimationSource.photoAi: 2,
      EstimationSource.localAi: 2,
      EstimationSource.aiPerItem: 2,
      EstimationSource.keywordDensity: 3,
    };
    for (final e in parts) {
      cal += e.calories;
      if (e.protein != null) p = (p ?? 0) + e.protein!;
      if (e.carbs != null) c = (c ?? 0) + e.carbs!;
      if (e.fat != null) f = (f ?? 0) + e.fat!;
      if (e.grams != null) grams += e.grams!;
      if ((e.confidence ?? 1.0) < minConfidence) minConfidence = e.confidence!;
      if ((sourceRank[e.estimationSource] ?? 0) >
          (sourceRank[worstSource] ?? 0)) {
        worstSource = e.estimationSource;
      }
    }
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: _formatDisplayName(originalText),
      calories: cal,
      protein: p,
      carbs: c,
      fat: f,
      grams: grams > 0 ? grams : null,
      estimationSource: worstSource,
      confidence: minConfidence,
      loggedAt: DateTime.now(),
    );
  }

  /// Builds a deduped candidate pool from alias-aware FTS. Searches:
  ///   (a) the whole text — catches the dominant food
  ///   (b) each NLP-detected fragment — catches multi-item meals
  /// Top-15 final, ordered by combined FTS rank.
  /// Aggressive splitter for retrieval — broader than [FoodNlpParser]'s
  /// splitter because for candidate retrieval we want a hit per ingredient
  /// even when the user uses connectors the NLP parser keeps glued
  /// ("egg with sardines", "ulam at kanin", "pork into talong").
  ///
  /// Splits on: , and + plus with at na o in into. Drops 1–2 char tokens.
  static final _candidateSplitter = RegExp(
    r'\s*(?:,|\band\b|\bplus\b|\+|\bwith\b|\bat\b|\bna\b|\bo\b|\bin\b|\binto\b)\s*',
    caseSensitive: false,
  );

  List<String> _splitForCandidateRetrieval(String text) {
    return text
        .split(_candidateSplitter)
        .map((f) => f.trim())
        .where((f) => f.length >= 3)
        .toList();
  }

  // Short brand tokens that FTS5 won't match because the DB uses the full name.
  static const _brandAliases = <String, String>{
    'mcdo': "mcdonald's",
    'mcdonald': "mcdonald's",
    'mcds': "mcdonald's",
    'jbc': 'jollibee',
    'jollibee': 'jollibee',
    'bk': 'burger king',
    'kfc': 'kfc',
    'greenwich': 'greenwich',
    'chowking': 'chowking',
    'shakeys': "shakey's",
    'shakey': "shakey's",
    'mang inasal': 'mang inasal',
    'manginasal': 'mang inasal',
    'popeyes': "popeye's",
    'popeye': "popeye's",
  };

  /// Returns [text] with short brand abbreviations expanded to their full name
  /// so FTS can match the DB's canonical brand entries.
  static String _expandBrandTokens(String text) {
    var result = text.toLowerCase();
    for (final entry in _brandAliases.entries) {
      result = result.replaceAll(
        RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
        entry.value,
      );
    }
    // Preserve original casing for non-alias words by returning the replaced
    // lower-case version — FTS is case-insensitive so this is fine.
    return result;
  }

  /// Builds a deduped candidate pool by querying FTS over the whole text
  /// AND each ingredient fragment, then **round-robin** filling the final
  /// pool so multi-ingredient queries get representation from every
  /// fragment instead of being dominated by the first one.
  Future<List<FoodSearchCandidate>> _buildCandidatePool(String text) async {
    final expanded = _expandBrandTokens(text);
    final fragments = _splitForCandidateRetrieval(expanded);
    // Always include both original and brand-expanded forms so nothing is lost.
    final queries = <String>{text, expanded, ...fragments}.toList();
    final hitLists = await Future.wait(queries.map(_foodDb.search));

    // Re-sort each per-query result by specificity excess so generic entries
    // (fewer extra words vs. the query) float above branded/regional variants
    // before the round-robin interleave. Stable sort — BM25 order is preserved
    // among candidates with the same excess score.
    final sorted = [
      for (var i = 0; i < hitLists.length; i++)
        (List<FoodDbEntry>.from(hitLists[i])
          ..sort((a, b) => _specificityExcess(a, queries[i])
              .compareTo(_specificityExcess(b, queries[i])))),
    ];

    // Round-robin: take position 0 from each list, then position 1, etc.
    // This guarantees fragment hits aren't squeezed out by a dominant
    // whole-text hit list.
    final seen = <String, FoodSearchCandidate>{};
    const maxTotal = 15;
    final maxDepth =
        sorted.fold<int>(0, (m, list) => list.length > m ? list.length : m);
    for (var depth = 0; depth < maxDepth; depth++) {
      for (final list in sorted) {
        if (depth >= list.length) continue;
        final hit = list[depth];
        seen.putIfAbsent(
          hit.id,
          () => FoodSearchCandidate(
            entry: hit,
            score: 1.0,
            source: SearchSource.fts5,
          ),
        );
        if (seen.length >= maxTotal) break;
      }
      if (seen.length >= maxTotal) break;
    }
    return seen.values.toList();
  }

  /// Ratio of words in [entry.name] that are NOT in [query], as a fraction of
  /// total name words. 0.0 = all name words are in the query (generic match).
  /// Rising toward 1.0 as extra content words dominate (over-specific).
  static double _specificityExcess(FoodDbEntry entry, String query) {
    final queryWords = _contentWords(query);
    if (queryWords.isEmpty) return 0.0;
    final nameWords = _contentWords(entry.name);
    if (nameWords.isEmpty) return 0.0;
    return nameWords.difference(queryWords).length / nameWords.length;
  }

  static Set<String> _contentWords(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(' ')
      .where((w) => w.length > 2)
      .toSet();

  // ── Cloud post-parse guards (mirrors on_device_ai_coach_service.dart) ────

  static double? _cloudSingleItemExplicitGrams(String text) {
    final matches = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:g|gm|gms|gram|grams)\b',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.length != 1) return null;
    return double.tryParse(matches.first.group(1)!);
  }

  /// Shared commit path for both cloud and on-device branches. Adds
  /// entries to today's log, builds the chat message, persists, and runs
  /// streak/goal checks.
  /// Commits [entries] to today's log and appends the chat/log-entry row.
  /// Returns the created message's id (for undo), or null if the IF-Sync gate
  /// blocked logging.
  Future<String?> _commitFoodChat(
    String text,
    List<FoodEntry> entries,
    List<List<ChatFoodAlternative>> altsList,
    List<String> rawTexts, {
    String? photoThumbnailPath,
  }) async {
    // IF-Sync gate is a "now" concept — only blocks logging on TODAY. Past-day
    // backfills are always allowed even while currently fasting (Plan 037).
    if (isSelectedDateToday && _goals.ifSyncEnabled && !isEatingWindowOpen) {
      // The thumbnail was saved before the gate; don't leak it.
      if (photoThumbnailPath != null) {
        // ignore: unawaited_futures
        _photoStore.delete(photoThumbnailPath);
      }
      return null;
    }

    // Refresh today's log if midnight crossed mid-parse.
    await _ensureTodayLogFresh();

    _todayLog = _todayLog.addEntries(entries, MealSlot.meal);

    final msg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.food,
      foodItems: [
        for (var i = 0; i < entries.length; i++)
          ChatFoodItem.fromFoodEntry(
            entries[i],
            amountText: i < rawTexts.length ? rawTexts[i] : entries[i].name,
            alternatives: i < altsList.length ? altsList[i] : const [],
          ),
      ],
      mealSlot: MealSlot.meal,
      photoThumbnailPath: photoThumbnailPath,
    );
    _chatMessages.add(msg);
    safeNotify();

    // Persist log + chat together so a crash between them can't desync.
    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _applyLogSideEffects(_todayLog.date);
    return msg.id;
  }

  Future<void> _parseChatAsExercise(String text) async {
    final weightKg = _tdeeProfile?.weightKg ?? 70.0;
    final result = ExerciseNlpParser.parse(text, weightKg: weightKg);
    if (result == null) {
      _chatParseError = 'Could not identify the exercise. Try: "walked 3km".';
      return;
    }
    final entry = ExerciseEntry(
      id: ExerciseEntry.generateId(),
      name: result.activityName,
      rawText: text,
      distanceKm: result.distanceKm,
      durationMinutes: result.durationMinutes,
      caloriesBurned: result.caloriesBurned,
      isEstimated: result.isEstimated,
      loggedAt: DateTime.now(),
    );
    final msg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.exercise,
      exerciseEntry: entry,
    );
    _chatMessages.add(msg);
    await _persistChatMessages();
  }

  /// Swap the auto-picked food item with one of its alternatives. Triggered
  /// when the user taps an alternative chip on a low-confidence chat row.
  /// Updates today's log, replaces the chat row, learns the swap into the
  /// personal dictionary so the same input next time auto-resolves correctly.
  Future<void> swapChatFoodAlternative(
    String messageId,
    int itemIndex,
    int alternativeIndex,
  ) async {
    if (_isChatParsing) return; // avoid racing with an in-flight parse
    final msgIdx = _chatMessages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = _chatMessages[msgIdx];
    if (msg.kind != ChatMessageKind.food) return;
    if (itemIndex < 0 || itemIndex >= msg.foodItems.length) return;

    final item = msg.foodItems[itemIndex];
    if (alternativeIndex < 0 || alternativeIndex >= item.alternatives.length) {
      return;
    }
    final alt = item.alternatives[alternativeIndex];

    // Replace the existing FoodEntry in today's log with one built from the
    // chosen alternative, keeping the same id so other indexes stay valid.
    final newEntry = FoodEntry(
      id: item.entryId,
      name: alt.name,
      calories: alt.calories,
      protein: alt.protein,
      carbs: alt.carbs,
      fat: alt.fat,
      grams: alt.grams,
      estimationSource: alt.estimationSource,
      // Tap-to-swap is an explicit user choice — mark it confidently logged.
      confidence: 0.95,
      loggedAt: DateTime.now(),
    );
    _todayLog = _todayLog.replaceEntry(newEntry, msg.mealSlot);

    // Build the updated chat row. The picked alternative becomes the primary;
    // the previous primary moves into the alternatives list so the user can
    // swap back if they tapped the wrong chip.
    final previousAsAlt = ChatFoodAlternative(
      name: item.name,
      calories: item.calories,
      protein: item.protein,
      carbs: item.carbs,
      fat: item.fat,
      grams: item.grams,
      estimationSource: item.estimationSource,
    );
    final newAlts = [
      for (var i = 0; i < item.alternatives.length; i++)
        if (i != alternativeIndex) item.alternatives[i],
      previousAsAlt,
    ];
    final updatedItem = ChatFoodItem.fromFoodEntry(
      newEntry,
      amountText: item.amountText,
      alternatives: newAlts.take(2).toList(),
    );

    final updatedItems = List<ChatFoodItem>.from(msg.foodItems);
    updatedItems[itemIndex] = updatedItem;
    _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
    safeNotify();

    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _applyLogSideEffects(_todayLog.date);

    // Learn the swap so the same query next time goes straight to this entry.
    // ignore: unawaited_futures
    _learnFromEntry(item.amountText ?? alt.name, newEntry);

    // Telemetry: implicit negative on the original pick + explicit positive on
    // the alternative. Useful for both "what was wrong" and "what's frequently
    // chosen as a swap target".
    // ignore: unawaited_futures
    _logFeedback(
      kind: FoodFeedbackKind.swap,
      userQuery: item.amountText ?? item.name,
      pickedName: item.name,
      pickedDbId: null,
      estimationSource: item.estimationSource,
      confidence: item.confidence,
      swappedToName: alt.name,
    );
  }

  /// Mark every item in a chat food message as a bad match. Captures one
  /// [FoodFeedbackKind.userDislike] entry per item so a curator sees both the
  /// raw query and what the matcher picked. The log entries themselves stay —
  /// the user already ate the food; this only flags the parse for review.
  Future<void> markChatMessageDisliked(String messageId) async {
    final msg = _chatMessages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => ChatMessage(
        id: '',
        rawText: '',
        timestamp: DateTime.now(),
        kind: ChatMessageKind.food,
      ),
    );
    if (msg.id.isEmpty || msg.kind != ChatMessageKind.food) return;
    if (msg.foodItems.isEmpty) return;

    for (final item in msg.foodItems) {
      // ignore: unawaited_futures
      _logFeedback(
        kind: FoodFeedbackKind.userDislike,
        userQuery: msg.rawText,
        pickedName: item.name,
        pickedDbId: null,
        estimationSource: item.estimationSource,
        confidence: item.confidence,
      );
    }
  }

  /// Read-only view of stored feedback. Used by future curation/debug UIs.
  List<FoodFeedback> get foodFeedback => List.unmodifiable(_feedback);

  /// Append [entry] to the in-memory list and persist (capped). Append-only —
  /// older entries are evicted from storage in [LocalStorageService].
  Future<void> _logFeedback({
    required FoodFeedbackKind kind,
    required String userQuery,
    required String pickedName,
    required String? pickedDbId,
    required EstimationSource estimationSource,
    double? confidence,
    String? swappedToName,
  }) async {
    final entry = FoodFeedback(
      id: FoodFeedback.generateId(),
      timestamp: DateTime.now(),
      kind: kind,
      userQuery: userQuery,
      pickedName: pickedName,
      pickedDbId: pickedDbId,
      estimationSource: estimationSource.name,
      confidence: confidence,
      swappedToName: swappedToName,
    );
    _feedback = [..._feedback, entry];
    if (_feedback.length > FoodFeedback.maxStoredEntries) {
      _feedback =
          _feedback.sublist(_feedback.length - FoodFeedback.maxStoredEntries);
    }
    try {
      await _storage.saveFoodFeedback(_feedback);
    } catch (e) {
      debugPrint('NutritionPresenter: saveFoodFeedback failed: $e');
    }
  }

  /// Remove a single food item at [itemIndex] from [messageId]. Used by the
  /// per-row × button in edit mode. If removing would leave the message empty,
  /// the whole message is removed instead. The corresponding [FoodEntry] is
  /// also removed from today's log.
  Future<void> removeChatFoodItemAt(String messageId, int itemIndex) async {
    if (_isChatParsing) return;
    final msgIdx = _chatMessages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = _chatMessages[msgIdx];
    if (msg.kind != ChatMessageKind.food) return;
    if (itemIndex < 0 || itemIndex >= msg.foodItems.length) return;

    // Last item — drop the whole message to keep the UI consistent.
    if (msg.foodItems.length == 1) {
      await removeChatMessage(messageId);
      return;
    }

    final item = msg.foodItems[itemIndex];
    _todayLog = _todayLog.removeEntry(item.entryId, msg.mealSlot);

    final updated = List<ChatFoodItem>.from(msg.foodItems)..removeAt(itemIndex);
    _chatMessages[msgIdx] = msg.copyWithFoodItems(updated);
    safeNotify();

    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
  }

  /// Remove a chat message. Food items are also removed from [_todayLog].
  Future<void> removeChatMessage(String messageId) async {
    if (_isChatParsing) return; // avoid racing with an in-flight parse
    final msg = _chatMessages.cast<ChatMessage?>().firstWhere(
          (m) => m!.id == messageId,
          orElse: () => null,
        );
    if (msg == null) return;

    // Remove all food entries from today's log in a single mutation, save
    // once. Avoids N storage writes for an N-item meal.
    if (msg.kind == ChatMessageKind.food) {
      for (final item in msg.foodItems) {
        _todayLog = _todayLog.removeEntry(item.entryId, msg.mealSlot);
      }
    }
    _chatMessages.removeWhere((m) => m.id == messageId);
    safeNotify();

    // Delete the photo thumbnail file alongside the row (§0.4).
    if (msg.photoThumbnailPath != null) {
      // ignore: unawaited_futures
      _photoStore.delete(msg.photoThumbnailPath!);
    }

    await Future.wait([
      if (msg.kind == ChatMessageKind.food)
        _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
  }

  /// Undo counterpart to [removeChatMessage] — re-inserts a previously removed
  /// chat message and re-adds its food entries to [_todayLog]. Used by the
  /// "Undo" affordance on delete (Nudgr nutrition redesign). Ordering is
  /// restored by timestamp, so the exact prior index is not required. The
  /// photo thumbnail file was deleted on removal, so a restored photo entry
  /// falls back to the camera placeholder (its nutrition data is intact).
  Future<void> restoreChatMessage(ChatMessage msg) async {
    if (_chatMessages.any((m) => m.id == msg.id)) return; // already present
    if (msg.kind == ChatMessageKind.food && msg.foodItems.isNotEmpty) {
      await _ensureTodayLogFresh();
      final entries = [
        for (final item in msg.foodItems)
          FoodEntry(
            id: item.entryId,
            name: item.name,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            grams: item.grams,
            estimationSource: item.estimationSource,
            confidence: item.confidence,
            loggedAt: msg.timestamp,
          ),
      ];
      _todayLog = _todayLog.addEntries(entries, msg.mealSlot);
    }
    _chatMessages
      ..add(msg)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    safeNotify();
    await Future.wait([
      if (msg.kind == ChatMessageKind.food)
        _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
  }

  /// Re-parse [newText] for item at [itemIndex] in [messageId], update in-place.
  /// If [newText] parses to multiple items, the single item is replaced by all of them.
  Future<void> editChatFoodItem(
      String messageId, int itemIndex, String newText) async {
    if (_isChatParsing) return; // avoid racing with an in-flight parse
    final msgIdx = _chatMessages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = _chatMessages[msgIdx];
    if (itemIndex >= msg.foodItems.length) return;
    final oldItem = msg.foodItems[itemIndex];
    final trimmed = newText.trim();

    _isChatParsing = true;
    _chatParseError = null;
    safeNotify();
    try {
      // In-memory remove only — save is deferred until we have the replacement,
      // so a cloud timeout or crash can't permanently drop the old entry.
      _todayLog = _todayLog.removeEntry(oldItem.entryId, msg.mealSlot);

      // Cloud-first (same pipeline as initial logging), then legacy fallback.
      final List<FoodEntry> newEntries;
      final List<String> amountTexts;
      List<List<ChatFoodAlternative>> altsList = const [];

      final cloudResult = await _tryCloudParseFood(trimmed);
      if (cloudResult != null && cloudResult.entries.isNotEmpty) {
        newEntries = cloudResult.entries;
        altsList = cloudResult.alts;
        amountTexts = cloudResult.rawTexts.isNotEmpty
            ? cloudResult.rawTexts
            : newEntries.map((e) => e.name).toList();
      } else {
        // Legacy fallback: on-device NLP + resolver.
        final result = FoodNlpParser.parse(trimmed);
        if (result.isNotEmpty) {
          final dbMatches = await _resolveDbMatches(result);
          newEntries = [
            for (var i = 0; i < result.items.length; i++)
              _buildEntry(result.items[i], dbMatches[i]),
          ];
          for (var i = 0; i < newEntries.length; i++) {
            if (dbMatches[i] != null) {
              await _learnFromEntry(result.items[i].name, newEntries[i]);
            }
          }
          amountTexts = result.items.map((it) => it.rawText).toList();
        } else {
          // Nothing parseable — preserve old macros under the new name.
          newEntries = [
            FoodEntry(
              id: FoodEntry.generateId(),
              name: _formatDisplayName(trimmed),
              calories: oldItem.calories,
              protein: oldItem.protein,
              carbs: oldItem.carbs,
              fat: oldItem.fat,
              grams: oldItem.grams,
              estimationSource: EstimationSource.userManual,
              loggedAt: DateTime.now(),
            ),
          ];
          amountTexts = [trimmed];
        }
      }

      // In-memory add all replacements. Bypasses the IF-Sync gate intentionally
      // — editing an already-logged item should not be blocked by the eating window.
      for (final e in newEntries) {
        _todayLog = _todayLog.addEntry(e, msg.mealSlot);
      }

      // Atomic save: both removal and addition land together.
      await _storage.saveNutritionLog(_todayLog);

      final updatedItems = List<ChatFoodItem>.from(msg.foodItems);
      final replacementItems = [
        for (var i = 0; i < newEntries.length; i++)
          ChatFoodItem.fromFoodEntry(
            newEntries[i],
            amountText:
                i < amountTexts.length ? amountTexts[i] : newEntries[i].name,
            alternatives: i < altsList.length ? altsList[i] : const [],
          ),
      ];
      updatedItems.replaceRange(itemIndex, itemIndex + 1, replacementItems);
      _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
      await _persistChatMessages();
      await _applyLogSideEffects(_todayLog.date);
    } finally {
      _isChatParsing = false;
      safeNotify();
    }
  }

  /// Persist a confirmed name → per-100g mapping to the personal dictionary.
  /// Skips entries that are not confident enough to cache:
  ///   • missing/zero grams (can't compute per-100g)
  ///   • low confidence (`< 0.70`) — weak DB matches and AI estimates set this,
  ///     so the dict only ever caches reliable mappings.
  ///
  /// [allowLowConfidence] bypasses the confidence floor — used by the
  /// repeat-learning path, where the trust signal is that the user has logged
  /// the same food several times, not the per-estimate confidence.
  Future<void> _learnFromEntry(String name, FoodEntry e,
      {bool allowLowConfidence = false}) async {
    if (e.grams == null || e.grams! <= 0) return;
    if (!allowLowConfidence && (e.confidence ?? 1.0) < 0.70) return;
    await _personalDict.upsert(
      name: name,
      kcalPer100g: e.calories * 100 / e.grams!,
      proteinPer100g: e.protein != null ? e.protein! * 100 / e.grams! : null,
      carbsPer100g: e.carbs != null ? e.carbs! * 100 / e.grams! : null,
      fatPer100g: e.fat != null ? e.fat! * 100 / e.grams! : null,
    );
  }

  /// Open cloud/photo AI estimates are normally never auto-learned (a one-off
  /// hallucinated estimate would bypass the bundled DB permanently). But once
  /// the user has logged the same food name this many times, repetition is a
  /// strong enough signal to cache the latest estimate into the personal dict.
  static const int _kLearnAfterLogs = 3;

  /// Sources whose entries are trustworthy enough to repeat-learn. A DB or
  /// on-device-AI resolution points at a real food row; a keyword-density or
  /// cloud-fallback figure is a rough guess and must never be cached, even
  /// after repetition.
  static const Set<EstimationSource> _repeatLearnableSources = {
    EstimationSource.db,
    EstimationSource.localAi,
  };

  /// Repeat-learning for the **non-Cloud** paths (on-device AI + rule-based
  /// hybrid). Local resolves don't auto-promote on a single log — too risky
  /// for false positives (Plan 027 §2.1) — but once the user has logged the
  /// same food [_kLearnAfterLogs] times, repetition is a tier-independent trust
  /// signal, so we cache it just like the Cloud fallback path does. Skips rough
  /// guesses via [_repeatLearnableSources] and no-gram entries via
  /// [_learnFromEntry].
  void _maybeRepeatLearn(String queryName, FoodEntry entry) {
    if (!_repeatLearnableSources.contains(entry.estimationSource)) return;
    if (_priorLogCount(entry.name) + 1 < _kLearnAfterLogs) return;
    // ignore: unawaited_futures
    _learnFromEntry(queryName, entry, allowLowConfidence: true);
  }

  /// Count of prior logged entries (across history) whose name matches [name],
  /// case-insensitively. Drives [_kLearnAfterLogs] repeat-learning.
  int _priorLogCount(String name) {
    final norm = name.trim().toLowerCase();
    var n = 0;
    for (final log in _history) {
      for (final e in log.allEntries) {
        if (e.name.trim().toLowerCase() == norm) n++;
      }
    }
    return n;
  }

  /// Batch-edit all food items in a message at once.
  /// [newTexts] must match [message.foodItems] by index.
  Future<void> editAllChatFoodItems(
      String messageId, List<String> newTexts) async {
    if (_isChatParsing) return; // avoid racing with parseChat or another edit
    final msgIdx = _chatMessages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = _chatMessages[msgIdx];

    _isChatParsing = true;
    _chatParseError = null;
    safeNotify();

    try {
      final updatedItems = <ChatFoodItem>[];
      for (var i = 0; i < min(newTexts.length, msg.foodItems.length); i++) {
        final oldItem = msg.foodItems[i];
        final newText = newTexts[i].trim();

        // Swap in today's log: remove old, add new.
        _todayLog = _todayLog.removeEntry(oldItem.entryId, msg.mealSlot);

        // Cloud-first (same pipeline as initial logging), then legacy fallback.
        FoodEntry newEntry;
        String amountText = newText;

        final cloudResult = await _tryCloudParseFood(newText);
        if (cloudResult != null && cloudResult.entries.isNotEmpty) {
          newEntry = cloudResult.entries.first;
          amountText = cloudResult.rawTexts.isNotEmpty
              ? cloudResult.rawTexts.first
              : newEntry.name;
        } else {
          final result = FoodNlpParser.parse(newText);
          if (result.isNotEmpty) {
            final dbMatches = await _resolveDbMatches(result);
            newEntry = _buildEntry(result.items.first, dbMatches.first);
            if (dbMatches.first != null) {
              await _learnFromEntry(result.items.first.name, newEntry);
            }
          } else {
            // Nothing parseable — preserve old macros under the new name.
            newEntry = FoodEntry(
              id: FoodEntry.generateId(),
              name: _formatDisplayName(newText),
              calories: oldItem.calories,
              protein: oldItem.protein,
              carbs: oldItem.carbs,
              fat: oldItem.fat,
              grams: oldItem.grams,
              estimationSource: EstimationSource.userManual,
              loggedAt: DateTime.now(),
            );
          }
        }
        _todayLog = _todayLog.addEntry(newEntry, msg.mealSlot);
        updatedItems.add(ChatFoodItem.fromFoodEntry(
          newEntry,
          amountText: amountText,
          alternatives: cloudResult != null && cloudResult.alts.isNotEmpty
              ? cloudResult.alts[0]
              : const [],
        ));
      }

      // Items beyond newTexts.length have no replacement — preserve them in
      // both the chat and the log so they don't become orphaned entries.
      for (var i = updatedItems.length; i < msg.foodItems.length; i++) {
        updatedItems.add(msg.foodItems[i]);
      }

      await _storage.saveNutritionLog(_todayLog);
      _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
      await _persistChatMessages();
      await _applyLogSideEffects(_todayLog.date);
    } finally {
      _isChatParsing = false;
      safeNotify();
    }
  }

  Future<void> _persistChatMessages() async {
    final dateKey = _dateFmt.format(_selectedDate);
    await _storage.saveChatMessages(dateKey, _chatMessages);
  }

  /// Before any log-mutating action, check if the calendar day has rolled
  /// over since [_todayLog] was loaded. If the user was logging toward what
  /// they thought was "today" (i.e. [_selectedDate] matches [_todayLog.date]),
  /// advance to the actual current day so new entries land where the user
  /// will look for them. If the user explicitly selected a past date,
  /// preserve that view.
  Future<void> _ensureTodayLogFresh() async {
    final now = DateTime.now();
    final today = _dateFmt.format(now);
    if (_todayLog.date == today) return;
    if (_dateFmt.format(_selectedDate) != today) {
      return; // user is on a past day
    }
    _todayLog = await _storage.loadNutritionLogForDate(today);
    _selectedDate = now;
    final raw = await _storage.loadChatMessagesRaw(today);
    _chatMessages = raw.map(ChatMessage.fromJson).toList();
    _reconcileChatWithLog();
  }

  /// Defensive reconciliation between the nutrition log (source of truth for
  /// what was eaten) and the chat feed (the rendered list). The feed reads
  /// only from [_chatMessages], so any [FoodEntry] in [_todayLog] that lacks a
  /// matching chat row is invisible in the UI even though it still counts in
  /// the calorie/macro totals. That happens when food is logged via a non-chat
  /// path (quick-add / log-meal sheets call [addFoodEntry], which never builds
  /// a [ChatMessage]) or when a sync restores the log with an empty messages
  /// array. Rebuild the missing rows from the log so "consumed kcal but no
  /// list item" can't happen.
  ///
  /// In-memory only — not persisted on load, so it never churns the sync queue.
  /// Idempotent: matches by [FoodEntry.id], so re-running (or persisting later
  /// via a normal chat action) can't duplicate rows.
  void _reconcileChatWithLog() {
    final shown = <String>{
      for (final m in _chatMessages)
        for (final item in m.foodItems) item.entryId,
    };

    final orphans = <ChatMessage>[];
    for (final slot in _todayLog.meals.keys) {
      for (final entry in _todayLog.entriesForSlot(slot)) {
        if (shown.contains(entry.id)) continue;
        orphans.add(ChatMessage(
          id: ChatMessage.generateId(),
          rawText: entry.name,
          timestamp: entry.loggedAt,
          kind: ChatMessageKind.food,
          foodItems: [ChatFoodItem.fromFoodEntry(entry)],
          mealSlot: slot,
        ));
      }
    }
    if (orphans.isEmpty) return;

    _chatMessages = [..._chatMessages, ...orphans]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  // ── Load state ───────────────────────────────────────────────────────────────

  Future<void> loadState() async {
    await Future.wait([
      _storage.loadTodayNutritionLog().then((v) => _todayLog = v),
      _storage.loadNutritionGoals().then((v) => _goals = v),
      _storage.loadNutritionHistory().then((v) => _history = v),
      _storage.loadTdeeProfile().then((v) => _tdeeProfile = v),
      _storage.loadFoodLibrary().then((v) => _library = v),
      _storage.loadNutritionStreak().then((v) => _goalStreak = v),
      _storage.loadNutritionGoalMetDate().then((v) => _goalMetDate = v),
      _storage.loadLogStreak().then((v) => _logStreak = v),
      _storage.loadLogStreakDate().then((v) => _logStreakDate = v),
      _storage
          .loadCalorieGoalCreditedDates()
          .then((v) => _calorieGoalCreditedDates = v),
      _storage
          .loadProteinGoalCreditedDates()
          .then((v) => _proteinGoalCreditedDates = v),
      _storage.loadStreakMilestonePaid().then((v) => _streakMilestonePaid = v),
      _storage.loadFoodFeedback().then((v) => _feedback = v),
      _storage.loadWeightLog().then((v) => _weightLog = v),
      _storage.loadBodyMeasurements().then((v) => _measurementLog = v),
      _storage.loadMeasurementUnit().then((v) => _measurementUnit = v),
      _storage.loadLastRecompXpDate().then((v) => _lastRecompXpDate = v),
      _personalDict.init(),
    ]);
    final todayKey = _dateFmt.format(DateTime.now());
    final rawChat = await _storage.loadChatMessagesRaw(todayKey);
    _chatMessages = rawChat.map(ChatMessage.fromJson).toList();
    _reconcileChatWithLog();
    if (isDisposed) return; // presenter was disposed during async load

    // Restore same-day dedup flags from loaded state so app restarts mid-day
    // don't re-fire notifications or re-apply HP penalties.
    _calorieGoalNotifiedToday = _goalMetDate == todayKey;
    _overshootPenalizedToday = isOverGoal;

    // Seed retro-credit guards on first run after this feature ships (the
    // ledger keys are brand new → empty for existing installs). Without this,
    // the first commit could re-pay XP already earned before the upgrade.
    if (_calorieGoalCreditedDates.isEmpty && _goalMetDate != null) {
      _calorieGoalCreditedDates = {_goalMetDate!};
      await _storage.saveCalorieGoalCreditedDates(_calorieGoalCreditedDates);
    }
    if (_proteinGoalCreditedDates.isEmpty && isProteinGoalMet) {
      _proteinGoalCreditedDates = {todayKey};
      await _storage.saveProteinGoalCreditedDates(_proteinGoalCreditedDates);
    }
    if (_streakMilestonePaid == 0 && _logStreak > 0) {
      _streakMilestonePaid = _logStreak >= 30
          ? 30
          : _logStreak >= 14
              ? 14
              : _logStreak >= 7
                  ? 7
                  : 0;
      if (_streakMilestonePaid > 0) {
        await _storage.saveStreakMilestonePaid(_streakMilestonePaid);
      }
    }

    // Apply notification preferences: schedule or cancel weight reminder.
    final notifPrefs = await _storage.loadNotificationPreferences();
    if (notifPrefs.weightReminderEnabled) {
      await _notifications
          .scheduleWeightReminder(notifPrefs.weightReminderTime);
    } else {
      await _notifications.cancelWeightReminder();
    }

    safeNotify();
  }

  // ── Internal RPG hooks ────────────────────────────────────────────────────────

  /// Single date-aware entry point for all commit side effects. [dateKey] is
  /// the day the entry was logged to (today or a backfilled past day). For
  /// past days we grant retroactive XP + streak credit but never fire toasts,
  /// notifications, or HP penalties (those are "now" concepts). See Plan 037.
  Future<void> _applyLogSideEffects(String dateKey) async {
    final isToday = dateKey == _dateFmt.format(DateTime.now());
    await _recomputeLogStreak();
    await _awardCalorieGoalIfUncredited(dateKey, isToday: isToday);
    await _awardProteinGoalIfUncredited(dateKey, isToday: isToday);
    if (isToday) await _checkOvershoot();
  }

  /// Awards the +30 calorie-goal XP once per day (idempotent via the ledger),
  /// for today or a backfilled past day. The IF-Sync bonus, goal streak, VIT
  /// stat, and notification are today-only.
  Future<void> _awardCalorieGoalIfUncredited(String dateKey,
      {required bool isToday}) async {
    if (!isCalorieGoalMet) return;

    if (!_calorieGoalCreditedDates.contains(dateKey)) {
      await _statsPresenter.addXp(30);
      // IF-Sync bonus is an eating-window reward — today only (Plan 037 §2).
      if (isToday && _goals.ifSyncEnabled) {
        await _statsPresenter.addXp(10);
      }
      _calorieGoalCreditedDates = {..._calorieGoalCreditedDates, dateKey};
      await _storage.saveCalorieGoalCreditedDates(_calorieGoalCreditedDates);
    }

    if (!isToday) {
      safeNotify();
      return;
    }

    // Goal streak + VIT stat: today only, once per day.
    if (_goalMetDate != dateKey) {
      final yesterday =
          _dateFmt.format(DateTime.now().subtract(const Duration(days: 1)));
      _goalStreak = (_goalMetDate == yesterday) ? _goalStreak + 1 : 1;
      _goalMetDate = dateKey;
      if (_goalStreak % 7 == 0) await _statsPresenter.awardStat('vit');
      await _storage.saveNutritionStreak(_goalStreak);
      await _storage.saveNutritionGoalMetDate(dateKey);
    }
    // Fire calorie-goal notification once per day on first hit.
    if (!_calorieGoalNotifiedToday) {
      final prefs = await _storage.loadNotificationPreferences();
      if (prefs.calorieGoalEnabled) {
        _calorieGoalNotifiedToday = true;
        await _notifications.showCalorieGoalNotification(
            todayCalories, effectiveGoal);
      }
    }
    safeNotify();
  }

  /// Awards the +15 protein-goal XP once per day (idempotent via the ledger).
  /// The permanent STR stat point is today-only to keep the stat economy tied
  /// to live actions.
  Future<void> _awardProteinGoalIfUncredited(String dateKey,
      {required bool isToday}) async {
    if (_goals.proteinGrams == null || !isProteinGoalMet) return;
    if (_proteinGoalCreditedDates.contains(dateKey)) return;
    await _statsPresenter.addXp(15);
    if (isToday) await _statsPresenter.awardStat('str');
    _proteinGoalCreditedDates = {..._proteinGoalCreditedDates, dateKey};
    await _storage.saveProteinGoalCreditedDates(_proteinGoalCreditedDates);
  }

  Future<void> _checkOvershoot() async {
    if (!_goals.overshootPenaltyEnabled) return;
    if (_overshootPenalizedToday || !isOverGoal) return;
    _overshootPenalizedToday = true;
    await _statsPresenter.modifyHp(-5);
  }

  /// Recomputes the log streak as the longest consecutive run of days with at
  /// least one entry, ending at the most recent logged day (Plan 037 §3) — so
  /// backfilling a forgotten day can repair/extend a broken streak. Milestone
  /// XP (7/14/30) is paid once per run via [_streakMilestonePaid].
  Future<void> _recomputeLogStreak() async {
    // loadNutritionHistory() is authoritative (reads the persisted blob) and
    // excludes today, so add today's log explicitly. The just-committed day is
    // already persisted, so it's reflected here.
    final history = await _storage.loadNutritionHistory();
    final logged = <String>{
      for (final log in history)
        if (log.allEntries.isNotEmpty) log.date,
    };
    final todayKey = _dateFmt.format(DateTime.now());
    final todayLog = _todayLog.date == todayKey
        ? _todayLog
        : await _storage.loadNutritionLogForDate(todayKey);
    if (todayLog.allEntries.isNotEmpty) logged.add(todayKey);
    if (_todayLog.allEntries.isNotEmpty) logged.add(_todayLog.date);

    if (logged.isEmpty) {
      _logStreak = 0;
      _logStreakDate = null;
      await _storage.saveLogStreak(0);
      safeNotify();
      return;
    }

    final latest =
        logged.map(DateTime.parse).reduce((a, b) => a.isAfter(b) ? a : b);
    var run = 0;
    var cursor = latest;
    while (logged.contains(_dateFmt.format(cursor))) {
      run++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    _logStreak = run;
    _logStreakDate = _dateFmt.format(latest);

    // Reset the milestone marker when a new (shorter) run starts, so the next
    // run can earn the milestone again; never re-pay within the same run.
    if (_logStreak < _streakMilestonePaid) {
      _streakMilestonePaid = 0;
      await _storage.saveStreakMilestonePaid(0);
    }
    for (final m in const [7, 14, 30]) {
      if (_logStreak >= m && _streakMilestonePaid < m) {
        await _statsPresenter.addXp(m == 7
            ? 20
            : m == 14
                ? 40
                : 80);
        _streakMilestonePaid = m;
        await _storage.saveStreakMilestonePaid(m);
      }
    }

    await _storage.saveLogStreak(_logStreak);
    await _storage.saveLogStreakDate(_logStreakDate!);
    safeNotify();
  }
}

/// Result of [NutritionPresenter._hybridResolveItem]: the top-1 DB entry,
/// up to 4 runner-up alternatives (for chip rendering), and a 0..1 confidence
/// score derived from the RRF fusion gap between top-1 and top-2.
class _HybridMatch {
  final FoodDbEntry pick;
  final List<FoodDbEntry> alternatives;
  final double confidence;

  const _HybridMatch({
    required this.pick,
    required this.alternatives,
    required this.confidence,
  });
}

/// Plan 026 — result bundle for the cloud-primary food parse path.
class _CloudParseResult {
  final List<FoodEntry> entries;
  final List<List<ChatFoodAlternative>> alts;
  final List<String> rawTexts;

  const _CloudParseResult({
    required this.entries,
    required this.alts,
    required this.rawTexts,
  });
}
