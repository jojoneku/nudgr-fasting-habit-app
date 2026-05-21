import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_meal_estimate.dart';
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
import '../models/index_progress.dart';
import '../models/meal_slot.dart';
import '../models/nutrition_goals.dart';
import '../models/tdee_profile.dart';
import '../services/ai_coach_service.dart';
import '../services/embedding_service.dart';
import '../services/food_db_service.dart';
import '../services/food_semantic_search_service.dart';
import '../services/notification_service.dart';
import '../services/open_food_facts_service.dart';
import '../models/personal_food_entry.dart';
import '../models/weight_entry.dart';
import '../services/personal_food_dictionary.dart';
import '../services/storage_service.dart';
import '../utils/exercise_nlp_parser.dart';
import '../utils/food_match_scorer.dart';
import '../utils/food_nlp_parser.dart';
import 'fasting_presenter.dart';
import 'stats_presenter.dart';

class NutritionPresenter extends ChangeNotifier {
  final StatsPresenter _statsPresenter;
  final FastingPresenter _fastingPresenter;
  final StorageService _storage;
  final FoodDbService _foodDb;
  final AiCoachService _ai;
  final FoodSemanticSearchService? _semanticSearch;
  final EmbeddingService? _embedder;
  final OpenFoodFactsService _barcodeLookup;
  final NotificationService _notifications;
  StreamSubscription<IndexProgress>? _indexProgressSub;

  // Confidence thresholds — see docs/rag_food_search_spec.md for tuning notes.
  static const double _semanticHighConfidence = 0.80;
  static const double _semanticAcceptable = 0.55;
  static const double _llmRerankConfidence = 0.70;
  static const int _semanticTopK = 5;

  DailyNutritionLog _todayLog = DailyNutritionLog.empty('');
  NutritionGoals _goals = NutritionGoals.initial();
  List<DailyNutritionLog> _history = [];
  TdeeProfile? _tdeeProfile;
  List<FoodTemplate> _library = [];

  int _goalStreak = 0; // consecutive days calorie goal met
  String? _goalMetDate; // last date calorie goal was met
  int _logStreak = 0; // consecutive days with ≥1 entry
  String? _logStreakDate; // last date an entry was logged

  bool _proteinGoalMetToday = false;
  bool _calorieGoalNotifiedToday = false;
  bool _isAiEstimating = false;
  AiMealEstimate? _lastEstimate;
  String? _aiEstimateError;

  // ── Weight log ───────────────────────────────────────────────────────────
  List<WeightEntry> _weightLog = const [];

  // ── Personal food dictionary ──────────────────────────────────────────────
  late final PersonalFoodDictionary _personalDict;

  // ── Calorie density buckets (keyword fallback for unknown foods) ─────────
  static const _calorieBuckets = [
    (
      kcalPerG: 7.5,
      keywords: ['oil', 'butter', 'ghee', 'lard', 'margarine', 'mantika']
    ),
    (
      kcalPerG: 5.5,
      keywords: [
        'nut',
        'almond',
        'peanut',
        'cashew',
        'pistachio',
        'walnut',
        'seed',
        'buto'
      ]
    ),
    (
      kcalPerG: 3.5,
      keywords: ['sugar', 'syrup', 'honey', 'jam', 'jelly', 'asukal']
    ),
    (
      kcalPerG: 4.5,
      keywords: [
        'cake',
        'cookie',
        'biscuit',
        'pastry',
        'donut',
        'chocolate',
        'candy',
        'chips',
        'cracker'
      ]
    ),
    (
      kcalPerG: 1.3,
      keywords: [
        'rice',
        'pasta',
        'noodle',
        'spaghetti',
        'bread',
        'flour',
        'oat',
        'cereal',
        'kanin',
        'bigas'
      ]
    ),
    (
      kcalPerG: 2.0,
      keywords: [
        'beef',
        'pork',
        'chicken',
        'turkey',
        'lamb',
        'meat',
        'manok',
        'baboy',
        'baka',
        'hotdog',
        'sausage'
      ]
    ),
    (
      kcalPerG: 1.4,
      keywords: [
        'fish',
        'salmon',
        'tuna',
        'tilapia',
        'bangus',
        'sardine',
        'shrimp',
        'crab',
        'squid',
        'seafood',
        'isda',
        'hipon'
      ]
    ),
    (kcalPerG: 1.5, keywords: ['egg', 'itlog']),
    (kcalPerG: 1.5, keywords: ['milk', 'cheese', 'yogurt', 'cream', 'gatas']),
    (
      kcalPerG: 0.35,
      keywords: [
        'vegetable',
        'salad',
        'broccoli',
        'spinach',
        'cabbage',
        'carrot',
        'kangkong',
        'sitaw',
        'gulay',
        'ampalaya',
        'talong',
        'okra'
      ]
    ),
    (
      kcalPerG: 0.6,
      keywords: [
        'fruit',
        'apple',
        'banana',
        'mango',
        'orange',
        'grape',
        'watermelon',
        'saging',
        'mangga',
        'prutas'
      ]
    ),
    (kcalPerG: 0.5, keywords: ['broth', 'sabaw', 'soup']),
  ];

  // ── NLP parser state ─────────────────────────────────────────────────────
  bool _isParsing = false;
  FoodParseResult? _lastParseResult;
  // Resolved DB entries matched to each parsed item (null = not found in DB).
  List<FoodDbEntry?> _parsedDbMatches = [];
  String? _parseError;

  // ── Cloud AI (optional upgrade tier for disambiguation) ──────────────────
  final AiCoachService? _cloudAi;

  // ── Chat + exercise state ─────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  List<ChatMessage> _chatMessages = [];
  bool _isChatParsing = false;
  String? _chatParseError;
  bool _disposed = false;

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
    FoodSemanticSearchService? semanticSearch,
    EmbeddingService? embedder,
    OpenFoodFactsService? barcodeLookup,
    NotificationService? notifications,
  })  : _statsPresenter = statsPresenter,
        _fastingPresenter = fastingPresenter,
        _storage = storage,
        _foodDb = foodDb,
        _ai = aiCoach,
        _cloudAi = cloudAi,
        _semanticSearch = semanticSearch,
        _embedder = embedder,
        _barcodeLookup = barcodeLookup ?? OpenFoodFactsService(),
        _notifications = notifications ?? NotificationService() {
    _personalDict = PersonalFoodDictionary(storage);
    // Surface index progress to the UI without polling.
    _indexProgressSub =
        semanticSearch?.progressStream.listen((_) => notifyListeners());
    loadState();
  }

  @override
  void dispose() {
    _disposed = true;
    _indexProgressSub?.cancel();
    super.dispose();
  }

  // ── Core state ───────────────────────────────────────────────────────────────

  DailyNutritionLog get todayLog => _todayLog;
  NutritionGoals get goals => _goals;
  List<DailyNutritionLog> get history => _history;
  TdeeProfile? get tdeeProfile => _tdeeProfile;

  // ── Weight log ───────────────────────────────────────────────────────────────

  List<WeightEntry> get weightLog => _weightLog;
  WeightEntry? get latestWeight => _weightLog.isEmpty ? null : _weightLog.last;
  double? get weightDelta {
    if (_weightLog.length < 2) return null;
    return _weightLog.last.weightKg -
        _weightLog[_weightLog.length - 2].weightKg;
  }

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

  bool get isCalorieGoalMet => todayCalories >= effectiveGoal;
  bool get isOverGoal => todayCalories > effectiveGoal * 1.2;

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

  double get proteinProgress =>
      _goals.proteinGrams != null && _goals.proteinGrams! > 0
          ? (todayProtein / _goals.proteinGrams!).clamp(0.0, 1.0)
          : 0.0;

  double get carbsProgress =>
      _goals.carbsGrams != null && _goals.carbsGrams! > 0
          ? (todayCarbs / _goals.carbsGrams!).clamp(0.0, 1.0)
          : 0.0;

  double get fatProgress => _goals.fatGrams != null && _goals.fatGrams! > 0
      ? (todayFat / _goals.fatGrams!).clamp(0.0, 1.0)
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

  // ── Food library getters ─────────────────────────────────────────────────────

  List<FoodTemplate> get savedTemplates {
    final sorted = List<FoodTemplate>.from(_library);
    sorted.sort((a, b) {
      if (a.isPinned == b.isPinned) return 0;
      return a.isPinned ? -1 : 1;
    });
    return List.unmodifiable(sorted);
  }

  List<FoodTemplate> get recentFoods {
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
    // Also pull from history if recent list is short
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

  Future<List<String>> suggestFoodNames(String query, {int limit = 6}) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final e in _personalDict.all()) {
      if (e.name.toLowerCase().startsWith(q)) {
        if (seen.add(e.name.toLowerCase())) result.add(e.name);
        if (result.length >= limit) return result;
      }
    }
    final dbHits = await _foodDb.search(q);
    for (final e in dbHits) {
      if (result.length >= limit) break;
      if (seen.add(e.name.toLowerCase())) result.add(e.name);
    }
    return result;
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
    await _storage.saveAiPromptSkippedAt(
        DateTime.now().millisecondsSinceEpoch);
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
    notifyListeners();
  }

  Future<void> removeLearnedFood(String name) async {
    await _personalDict.remove(name);
    notifyListeners();
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
    notifyListeners();
  }
  int get aiDownloadProgress => _ai.downloadProgress ?? 0;
  String get aiSizeLabel => '~586 MB';
  AiMealEstimate? get lastEstimate => _lastEstimate;
  String? get aiEstimateError => _aiEstimateError;

  // ── Smart food search (RAG) getters ──────────────────────────────────────────

  /// Status enum surfaced to UI. Maps embedder + index state to a single value.
  FoodSearchStatus get foodSearchStatus {
    final embedder = _embedder;
    final semantic = _semanticSearch;
    if (embedder == null || semantic == null) return FoodSearchStatus.disabled;
    if (embedder.isDeviceIncompatible) return FoodSearchStatus.failed;
    if (embedder.isDownloading) return FoodSearchStatus.downloading;
    if (!embedder.isInstalled) return FoodSearchStatus.notInstalled;
    if (!embedder.isReady) return FoodSearchStatus.loading;
    if (semantic.isIndexing) return FoodSearchStatus.indexing;
    if (semantic.isReady) return FoodSearchStatus.ready;
    return FoodSearchStatus.idle;
  }

  IndexProgress get foodIndexProgress =>
      _semanticSearch?.progress ?? const IndexProgress.empty();

  int get foodEmbedderDownloadProgress => _embedder?.downloadProgress ?? 0;

  String? get foodEmbedderSizeLabel => _embedder?.modelSizeLabel;

  String? get foodEmbedderName => _embedder?.modelDisplayName;

  bool get isFoodSearchAvailable =>
      _embedder != null && _semanticSearch != null;

  /// Download the embedder model + tokenizer, then build the index.
  ///
  /// Idempotent. Re-entry while a download is in flight is a no-op.
  Future<void> enableFoodSearch() async {
    final embedder = _embedder;
    final semantic = _semanticSearch;
    if (embedder == null || semantic == null) return;
    if (embedder.isDownloading) return;

    _bundleError = null;
    notifyListeners(); // flip status to downloading
    try {
      if (!embedder.isInstalled) {
        await embedder.downloadModel(onProgress: (_) => notifyListeners());
      } else if (!embedder.isReady) {
        await embedder.init();
      }
    } catch (e) {
      debugPrint('NutritionPresenter.enableFoodSearch failed: $e');
      _bundleError = 'Smart search download failed: ${_summarize(e)}';
      notifyListeners();
      return;
    }
    notifyListeners();

    if (!embedder.isReady) return; // download/load failed; status reflects it
    await semantic.init();
    // Build runs in the background — don't block the caller.
    // ignore: unawaited_futures
    semantic.buildIndex();
    notifyListeners();
  }

  /// Wipe the vector index and rebuild from scratch. Used by Settings.
  Future<void> rebuildFoodIndex() async {
    final semantic = _semanticSearch;
    if (semantic == null) return;
    notifyListeners();
    // ignore: unawaited_futures
    semantic.rebuildIndex();
  }

  // ── AI bundle download (embedder + LLM) ───────────────────────────────────

  /// True while the bundle download is in flight (either phase).
  bool _isBundleDownloading = false;
  int _bundlePhase = 0; // 0 = idle, 1 = embedder, 2 = LLM
  String? _bundleError;

  bool get isAiBundleDownloading => _isBundleDownloading;

  /// Last bundle download error message, or null if none / cleared.
  /// Cleared automatically when a new download starts.
  String? get aiBundleError => _bundleError;

  /// Clear the surfaced error after the UI has shown it.
  void clearAiBundleError() {
    if (_bundleError == null) return;
    _bundleError = null;
    notifyListeners();
  }

  /// Coarse percent across both downloads, weighted by size (75 MB / 586 MB).
  /// Returns 0 when not bundling.
  int get aiBundleProgress {
    if (!_isBundleDownloading) return 0;
    const embedderWeight = 0.11; // 75 / (75 + 586)
    const llmWeight = 0.89;
    final embedderPct = _embedder?.downloadProgress ?? 0;
    final llmPct = _ai.downloadProgress ?? 0;
    return ((embedderPct * embedderWeight) + (llmPct * llmWeight)).round();
  }

  /// Human-readable phase label for the bundle UI.
  String get aiBundlePhaseLabel => switch (_bundlePhase) {
        1 => 'Smart search · 1 of 2 (~75 MB)',
        2 => 'AI Coach · 2 of 2 (~586 MB)',
        _ => '',
      };

  /// Returns true when neither model is installed yet.
  bool get isAiBundleAvailable {
    final embedder = _embedder;
    if (embedder == null) return false;
    return !embedder.isInstalled || !_ai.isAvailable;
  }

  /// Download the embedder first (small, gets smart search live fast), then
  /// the LLM (big, enhances disambiguation + AI Coach). Idempotent — already-
  /// installed components are skipped.
  Future<void> downloadAiBundle() async {
    if (_isBundleDownloading) return;
    final embedder = _embedder;
    if (embedder == null) return;

    _isBundleDownloading = true;
    _bundleError = null;

    // Phase 1 — embedder.
    if (!embedder.isInstalled) {
      _bundlePhase = 1;
      notifyListeners();
      try {
        await embedder.downloadModel(onProgress: (_) => notifyListeners());
      } catch (e) {
        debugPrint('NutritionPresenter.downloadAiBundle: embedder failed: $e');
        _bundleError = 'Smart search download failed: ${_summarize(e)}';
        _isBundleDownloading = false;
        _bundlePhase = 0;
        notifyListeners();
        return;
      }
      // Kick off semantic vector store + index build in the background.
      await _semanticSearch?.init();
      // ignore: unawaited_futures
      _semanticSearch?.buildIndex();
    }

    // Phase 2 — LLM.
    if (!_ai.isAvailable) {
      _bundlePhase = 2;
      notifyListeners();
      try {
        await _ai.downloadModel(onProgress: (_) => notifyListeners());
      } catch (e) {
        debugPrint('NutritionPresenter.downloadAiBundle: LLM failed: $e');
        _bundleError = 'AI Coach download failed: ${_summarize(e)}';
      }
    }

    _isBundleDownloading = false;
    _bundlePhase = 0;
    notifyListeners();
  }

  /// Trim long stack traces / framework noise so the SnackBar stays readable.
  String _summarize(Object e) {
    final msg = e.toString();
    final firstLine = msg.split('\n').first.trim();
    return firstLine.length > 140
        ? '${firstLine.substring(0, 140)}…'
        : firstLine;
  }

  // ── NLP parser getters ───────────────────────────────────────────────────────

  bool get isParsing => _isParsing;
  FoodParseResult? get lastParseResult => _lastParseResult;
  List<FoodDbEntry?> get parsedDbMatches => List.unmodifiable(_parsedDbMatches);
  String? get parseError => _parseError;

  // ── Chat + exercise getters ───────────────────────────────────────────────────

  DateTime get selectedDate => _selectedDate;
  bool get isSelectedDateToday =>
      _dateFmt.format(_selectedDate) == _dateFmt.format(DateTime.now());
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  bool get isChatParsing => _isChatParsing;
  String? get chatParseError => _chatParseError;

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
    if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;
    await _ensureTodayLogFresh();
    _todayLog = _todayLog.addEntry(entry, slot);
    notifyListeners();
    await _storage.saveNutritionLog(_todayLog);
    await _updateLogStreak();
    await _checkGoalMet();
    await _checkProteinGoalMet();
    await _checkOvershoot();
  }

  /// Log a food entry created from manual user input and add it to the chat feed.
  Future<void> addManualFoodEntry(FoodEntry entry) async {
    if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;
    await addFoodEntry(entry, MealSlot.meal);
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
    notifyListeners();
    await _persistChatMessages();
  }

  Future<void> removeFoodEntry(String entryId, MealSlot slot) async {
    _todayLog = _todayLog.removeEntry(entryId, slot);
    notifyListeners();
    await _storage.saveNutritionLog(_todayLog);
  }

  Future<void> addMealFromTemplate(FoodTemplate meal, MealSlot slot) async {
    if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;
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
    notifyListeners();

    // Persist log + chat together so a crash between them can't desync.
    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _updateLogStreak();
    await _checkGoalMet();
    await _checkProteinGoalMet();
    await _checkOvershoot();
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
    notifyListeners();

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
    _proteinGoalMetToday = false;
    notifyListeners();
    await _storage.saveNutritionGoals(newGoals);
    await _checkGoalMet();
  }

  Future<void> saveTdeeProfile(TdeeProfile profile) async {
    _tdeeProfile = profile;
    notifyListeners();
    await _storage.saveTdeeProfile(profile);
    await _checkGoalMet();
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
    notifyListeners();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> deleteFoodTemplate(String templateId) async {
    _library.removeWhere((t) => t.id == templateId);
    notifyListeners();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> renameTemplate(String templateId, String newName) async {
    final idx = _library.indexWhere((t) => t.id == templateId);
    if (idx == -1 || newName.trim().isEmpty) return;
    _library[idx] = _library[idx].copyWith(name: newName.trim());
    notifyListeners();
    await _storage.saveFoodLibrary(_library);
  }

  Future<void> togglePinTemplate(String templateId) async {
    final idx = _library.indexWhere((t) => t.id == templateId);
    if (idx == -1) return;
    _library[idx] = _library[idx].copyWith(isPinned: !_library[idx].isPinned);
    notifyListeners();
    await _storage.saveFoodLibrary(_library);
  }

  // ── Actions — AI estimation ───────────────────────────────────────────────────

  /// No-op — kept for API compatibility. The shared Qwen model is initialised
  /// by [OnDeviceAiCoachService.init] in [AiCoachPresenter].
  Future<void> initAi() async {
    notifyListeners();
  }

  Future<void> estimateMeal(String description) async {
    if (!isAiAvailable) return;
    _isAiEstimating = true;
    _lastEstimate = null;
    _aiEstimateError = null;
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
  }

  void clearEstimate() {
    _lastEstimate = null;
    _aiEstimateError = null;
    notifyListeners();
  }

  // ── Actions — NLP food parser ─────────────────────────────────────────────

  /// Parse [description] using the rule-based [FoodNlpParser], then look up
  /// each item in the food DB. Notifies listeners when done.
  Future<void> parseMeal(String description) async {
    _isParsing = true;
    _lastParseResult = null;
    _parsedDbMatches = [];
    _parseError = null;
    notifyListeners();

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
      notifyListeners();
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

    for (var i = 0; i < result.items.length; i++) {
      final entry =
          overrides[i] ?? _buildEntry(result.items[i], _parsedDbMatches[i]);
      await addFoodEntry(entry, slot);
    }

    _lastParseResult = null;
    _parsedDbMatches = [];
    notifyListeners();
  }

  void clearParseResult() {
    _lastParseResult = null;
    _parsedDbMatches = [];
    _parseError = null;
    notifyListeners();
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
  Future<_HybridMatch?> _hybridResolveItem({
    required String name,
    required String hyde,
  }) async {
    // Parallel: FTS5 on the user's `name`, semantic on the HyDE description.
    final ftsFuture = _foodDb.search(name);
    final semantic = _semanticSearch;
    final semanticFuture =
        (semantic != null && semantic.isReady && hyde.isNotEmpty)
            ? semantic.search(hyde, k: 10).catchError((Object e) {
                debugPrint('NutritionPresenter: semantic search failed: $e');
                return const <FoodSearchCandidate>[];
              })
            : Future<List<FoodSearchCandidate>>.value(const []);

    final results = await Future.wait([ftsFuture, semanticFuture]);
    final ftsHits = results[0] as List<FoodDbEntry>;
    final semHits = results[1] as List<FoodSearchCandidate>;

    if (ftsHits.isEmpty && semHits.isEmpty) return null;

    // RRF fusion: score(entry) = Σ 1/(k + rank), with k=60 by convention.
    const rrfK = 60;
    final scores = <String, double>{};
    final byId = <String, FoodDbEntry>{};

    for (var i = 0; i < ftsHits.length; i++) {
      final id = ftsHits[i].id;
      scores[id] = (scores[id] ?? 0) + 1.0 / (rrfK + i + 1);
      byId.putIfAbsent(id, () => ftsHits[i]);
    }
    for (var i = 0; i < semHits.length; i++) {
      final id = semHits[i].entry.id;
      scores[id] = (scores[id] ?? 0) + 1.0 / (rrfK + i + 1);
      byId.putIfAbsent(id, () => semHits[i].entry);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pick = byId[ranked.first.key]!;
    final runnerUps = ranked.skip(1).take(4).map((e) => byId[e.key]!).toList();

    // Confidence model. Three independent signals, multiplied/added so weak
    // matches genuinely fall below 0.6 and trigger the swap-chip UX.
    //   (a) dominance over runner-up — the RRF dominance ratio, no clamp floor
    //       (the previous floor of 0.5 made the gate unreachable)
    //   (b) both-channel bonus — if the pick was hit by FTS AND semantic, +0.10
    //   (c) word-boundary lexical bonus — every query word ≥3 chars appears as
    //       a whole word in the entry name. Substring matches don't count, so
    //       "red" no longer matches "layered" (the Sapin-Sapin / Red Rice case).
    final top1 = ranked.first.value;
    final top2 = ranked.length > 1 ? ranked[1].value : 0.0;
    double confidence = top2 == 0
        ? 0.55 // single hit — modest, intentionally below the 0.6 chip threshold
        : top1 / (top1 + top2);

    final pickId = pick.id;
    final inFts = ftsHits.any((h) => h.id == pickId);
    final inSem = semHits.any((h) => h.entry.id == pickId);
    if (inFts && inSem) {
      confidence += 0.10;
    }

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
    // Step 1 — semantic top-k.
    final semanticHit = await _resolveViaSemantic(item.name);
    if (semanticHit != null) return semanticHit;

    // Step 2 — FTS5 fallback (existing behaviour).
    return _resolveViaFts5(item.name, altName: altName);
  }

  /// Semantic search step. Returns null when not ready, low-confidence, or
  /// the LLM rerank doesn't yield a confident pick.
  Future<FoodDbEntry?> _resolveViaSemantic(String name) async {
    final semantic = _semanticSearch;
    if (semantic == null || !semantic.isReady) return null;

    final List<FoodSearchCandidate> candidates;
    try {
      candidates = await semantic.search(name, k: _semanticTopK);
    } catch (e) {
      debugPrint('NutritionPresenter: semantic search failed: $e');
      return null;
    }
    if (candidates.isEmpty) return null;

    // High-confidence top hit — ship it.
    if (candidates.first.score >= _semanticHighConfidence) {
      return candidates.first.entry;
    }

    // Below the "acceptable" floor — fall through to FTS5 entirely.
    if (candidates.first.score < _semanticAcceptable) return null;

    // Ambiguous band — ask the LLM to disambiguate. Cloud AI preferred;
    // falls back to on-device. Bound at 5 s.
    final disambiguator = (_cloudAi?.isAvailable ?? false)
        ? _cloudAi!
        : (_ai.isAvailable ? _ai : null);
    if (disambiguator == null) return null;
    try {
      final pick = await disambiguator
          .disambiguateFood(name, candidates)
          .timeout(const Duration(seconds: 5));
      if (pick == null || pick.confidence < _llmRerankConfidence) return null;

      final hit = candidates.firstWhere(
        (c) => c.entry.id == pick.foodId,
        orElse: () => candidates.first,
      );
      return hit.entry;
    } catch (e) {
      debugPrint('NutritionPresenter: disambiguateFood failed: $e');
      return null;
    }
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
      // FTS5 hits already pass isLearnableMatch (gated in _resolveViaFts5).
      // Semantic hits may NOT — the embedder finds meaning-similar foods even
      // when wording differs ("red rice" → "Rice, brown, cooked" at 0.85).
      // For those non-lexical matches we keep the user's typed name but
      // borrow the DB's per-100g macros — best of both worlds: real nutrition
      // data, faithful naming. The user logs what they said they ate.
      final isLexical = FoodMatchScorer.isLearnableMatch(dbEntry, parsed.name);
      final name = isLexical ? dbEntry.name : parsed.name;
      return base.copyWith(name: _formatDisplayName(name));
    }

    final estimatedKcal = _estimateCalories(parsed.name, parsed.grams);
    final (estProtein, estCarbs, estFat) = _macrosFromCalories(estimatedKcal);
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
  /// nor the on-device AI returned macros. Better than logging zero so the
  /// user's daily macro totals stay informative.
  (double, double, double) _macrosFromCalories(int calories) {
    if (calories <= 0) return (0.0, 0.0, 0.0);
    return (
      double.parse(((calories * 0.15) / 4).toStringAsFixed(1)),
      double.parse(((calories * 0.50) / 4).toStringAsFixed(1)),
      double.parse(((calories * 0.35) / 9).toStringAsFixed(1)),
    );
  }

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

  /// Last-resort calorie estimate from keyword density buckets.
  /// Matches keywords as whole words to avoid "eggplant" → egg or
  /// "milkshake" → milk false positives.
  int _estimateCalories(String name, double grams) {
    final tokens = name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9ñ]+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    for (final bucket in _calorieBuckets) {
      if (bucket.keywords.any(tokens.contains)) {
        return (grams * bucket.kcalPerG).round().clamp(1, 9999);
      }
    }
    return (grams * 1.5).round().clamp(1, 9999);
  }

  Future<void> downloadAiModel() async {
    if (isAiDownloading) return;
    notifyListeners();
    try {
      await _ai.downloadModel(onProgress: (_) => notifyListeners());
    } catch (_) {
      // Download failed — model remains unavailable; banner will stay visible.
    }
    notifyListeners();
  }

  // ── Actions — chat feed ───────────────────────────────────────────────────────

  /// Switch the viewed day. Loads that day's chat messages and nutrition log.
  Future<void> setSelectedDate(DateTime date) async {
    _selectedDate = date;
    final dateKey = _dateFmt.format(date);
    final raw = await _storage.loadChatMessagesRaw(dateKey);
    _chatMessages = raw.map(ChatMessage.fromJson).toList();
    _todayLog = await _storage.loadNutritionLogForDate(dateKey);
    notifyListeners();
  }

  // ── Weight log mutations ──────────────────────────────────────────────────

  Future<void> deleteWeight(String id) async {
    _weightLog = _weightLog.where((e) => e.id != id).toList();
    await _storage.saveWeightLog(_weightLog);
    notifyListeners();
  }

  /// Maximum chat input length. Above this we reject — long pastes can blow
  /// up AI prompt budgets and stall parsing for tens of seconds.
  static const int _maxChatInputLength = 500;

  /// Parse [text] as food or exercise, add to the chat feed, and persist.
  Future<void> parseChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isChatParsing) return;
    if (trimmed.length > _maxChatInputLength) {
      _chatParseError =
          'Input too long ($_maxChatInputLength char limit). Split into smaller messages.';
      notifyListeners();
      return;
    }
    _isChatParsing = true;
    _chatParseError = null;
    notifyListeners();

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
      notifyListeners();
    }
  }

  Future<void> _parseChatAsFood(String text) async {
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
        await _commitFoodChat(text, cloudResult.entries, cloudResult.alts,
            cloudResult.rawTexts);
        return;
      }
    }

    // Path B: on-device single-call (Plan 027 §2.1).
    if (_ai.isAvailable) {
      final localResult = await _tryLocalParseFood(text);
      if (localResult != null) {
        await _commitFoodChat(text, localResult.entries, localResult.alts,
            localResult.rawTexts);
        return;
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
        return;
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

      // Hybrid FTS + semantic with RRF fusion.
      final hybrid = await _hybridResolveItem(
        name: item.name,
        hyde: item.hydeDescription,
      );

      if (hybrid != null) {
        final entry = hybrid.pick.toFoodEntry(item.grams).copyWith(
              estimationSource: EstimationSource.db,
              confidence: hybrid.confidence,
            );
        entries.add(entry);
        // Plan 027 §2.1 — local hybrid resolve no longer auto-promotes to the
        // personal dict (too risky for false positives). Cloud-confirmed
        // picks still do, and the user can save manually via the chat row.
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
      final estKcal = _estimateCalories(item.name, item.grams);
      final (estProtein, estCarbs, estFat) = _macrosFromCalories(estKcal);
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

    await _commitFoodChat(
      text,
      entries,
      altsList,
      [for (final item in items) item.rawText],
    );
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
            item.resolverConfidence >= 0.6) {
          final hit = await _foodDb.getById(item.resolvedFoodId!);
          if (hit != null) {
            entry = hit.toFoodEntry(item.grams).copyWith(
                  estimationSource: EstimationSource.localAi,
                  confidence: item.resolverConfidence,
                );
          }
        }

        // No DB hit + no dict hit → keyword bucket fallback. Qwen does not
        // estimate macros itself in this tier (Plan 027 §2.1 pick-only).
        if (entry == null) {
          final estKcal = _estimateCalories(item.name, item.grams);
          final (estProtein, estCarbs, estFat) = _macrosFromCalories(estKcal);
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

      // IF-Sync gate runs at commit time, not here.
      final entries = <FoodEntry>[];
      final altsList = <List<ChatFoodAlternative>>[];
      final rawTexts = <String>[];

      for (final item in extracted.items) {
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
            item.resolverConfidence >= 0.6) {
          // Cloud picked a DB candidate. Hydrate from DB for fresh macros.
          // Tag as cloudAi so the badge shows "Cloud" — the resolution was
          // cloud-driven even though the macros came from the DB row.
          final hit = await _foodDb.getById(item.resolvedFoodId!);
          if (hit != null) {
            entry = hit.toFoodEntry(item.grams).copyWith(
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
          entry = FoodEntry(
            id: FoodEntry.generateId(),
            name: _formatDisplayName(item.name),
            calories: m.calories.round(),
            protein: m.proteinG,
            carbs: m.carbsG,
            fat: m.fatG,
            grams: item.grams,
            // Plan 027 §2.2 — cloud-estimated (no DB candidate) entries get
            // the cloudAi badge so users can distinguish them from local AI
            // estimates and from raw keyword fallbacks.
            estimationSource: EstimationSource.cloudAi,
            confidence: item.resolverConfidence > 0
                ? item.resolverConfidence
                : 0.6,
            loggedAt: DateTime.now(),
          );
          // Auto-promote even AI estimates when the model was confident.
          if (item.resolverConfidence >= 0.8 && m.calories > 0) {
            // ignore: unawaited_futures
            _personalDict.upsert(
              name: item.name,
              kcalPer100g: m.calories / (item.grams / 100.0),
              proteinPer100g: m.proteinG / (item.grams / 100.0),
              carbsPer100g: m.carbsG / (item.grams / 100.0),
              fatPer100g: m.fatG / (item.grams / 100.0),
            );
          }
        }

        if (entry == null) {
          // Neither cloud-resolved nor cloud-estimated nor in dict.
          // Bail and let the on-device path try.
          return null;
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
  FoodEntry _combineEntriesAsOneDish(List<FoodEntry> parts, String originalText) {
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

  /// Builds a deduped candidate pool by querying FTS over the whole text
  /// AND each ingredient fragment, then **round-robin** filling the final
  /// pool so multi-ingredient queries get representation from every
  /// fragment instead of being dominated by the first one.
  Future<List<FoodSearchCandidate>> _buildCandidatePool(String text) async {
    final fragments = _splitForCandidateRetrieval(text);
    // Search the whole text + each distinct fragment (skip dupes of full text).
    final queries = <String>{text, ...fragments}.toList();
    final searches = queries.map((q) => _foodDb.search(q)).toList();
    final hitLists = await Future.wait(searches);

    // Round-robin: take position 0 from each list, then position 1, etc.
    // This guarantees fragment hits aren't squeezed out by a dominant
    // whole-text hit list.
    final seen = <String, FoodSearchCandidate>{};
    const maxTotal = 15;
    final maxDepth = hitLists.fold<int>(
        0, (m, list) => list.length > m ? list.length : m);
    for (var depth = 0; depth < maxDepth; depth++) {
      for (final list in hitLists) {
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

  /// Shared commit path for both cloud and on-device branches. Adds
  /// entries to today's log, builds the chat message, persists, and runs
  /// streak/goal checks.
  Future<void> _commitFoodChat(
    String text,
    List<FoodEntry> entries,
    List<List<ChatFoodAlternative>> altsList,
    List<String> rawTexts,
  ) async {
    // IF-Sync gate: drop the entry if user is fasting and ifSync is enabled.
    if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;

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
    );
    _chatMessages.add(msg);
    notifyListeners();

    // Persist log + chat together so a crash between them can't desync.
    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);
    await _updateLogStreak();
    await _checkGoalMet();
    await _checkProteinGoalMet();
    await _checkOvershoot();
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
    notifyListeners();

    await Future.wait([
      _storage.saveNutritionLog(_todayLog),
      _persistChatMessages(),
    ]);

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

  // ── Barcode scan ─────────────────────────────────────────────────────────────

  /// Look up [barcode] against OpenFoodFacts. Returns the parsed result, or
  /// null when OFF doesn't have the barcode / the entry lacks calories. Pure
  /// I/O; the caller (UI) handles preview + confirm before logging.
  Future<BarcodeLookupResult?> lookupBarcode(String barcode) async {
    try {
      return await _barcodeLookup.lookup(barcode);
    } catch (e) {
      debugPrint('NutritionPresenter.lookupBarcode failed: $e');
      return null;
    }
  }

  /// Log [result] as a chat row + nutrition entry at [grams]. Also caches the
  /// product into [PersonalFoodDictionary] so future text searches like
  /// "bear brand 33g" hit it instantly without another network round-trip.
  Future<void> logScannedProduct(
    BarcodeLookupResult result, {
    required double grams,
  }) async {
    if (grams <= 0) return;
    if (_isChatParsing) return;
    _isChatParsing = true;
    notifyListeners();

    try {
      final entry = result.entry.toFoodEntry(grams).copyWith(
            estimationSource: EstimationSource.db,
            confidence: 0.95,
          );

      // IF-Sync gate: drop the entry if user is fasting and ifSync is enabled.
      if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;

      await _ensureTodayLogFresh();
      _todayLog = _todayLog.addEntries([entry], MealSlot.meal);

      final msg = ChatMessage(
        id: ChatMessage.generateId(),
        rawText: '📷 ${result.displayName}',
        timestamp: DateTime.now(),
        kind: ChatMessageKind.food,
        foodItems: [
          ChatFoodItem.fromFoodEntry(entry,
              amountText: '${grams.toStringAsFixed(0)}g')
        ],
        mealSlot: MealSlot.meal,
      );
      _chatMessages.add(msg);
      notifyListeners();

      await Future.wait([
        _storage.saveNutritionLog(_todayLog),
        _persistChatMessages(),
      ]);
      // Cache so the next "bear brand" text query also finds this product.
      // ignore: unawaited_futures
      _learnFromEntry(result.entry.name, entry);

      await _updateLogStreak();
      await _checkGoalMet();
      await _checkProteinGoalMet();
      await _checkOvershoot();
    } finally {
      _isChatParsing = false;
      notifyListeners();
    }
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
    notifyListeners();

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
    notifyListeners();

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

    // Remove old food entry from today's log.
    await removeFoodEntry(oldItem.entryId, msg.mealSlot);

    // Re-parse and look up in DB. Multi-item parse replaces the single slot.
    final result = FoodNlpParser.parse(trimmed);
    final List<FoodEntry> newEntries;
    final List<FoodDbEntry?> dbMatches;
    if (result.isNotEmpty) {
      dbMatches = await _resolveDbMatches(result);
      newEntries = [
        for (var i = 0; i < result.items.length; i++)
          _buildEntry(result.items[i], dbMatches[i]),
      ];
      // Teach the personal dict from each DB-resolved item.
      for (var i = 0; i < newEntries.length; i++) {
        if (dbMatches[i] != null) {
          await _learnFromEntry(result.items[i].name, newEntries[i]);
        }
      }
    } else {
      // NLP couldn't parse — keep oldItem's macros as a placeholder under the
      // new name. Do NOT learn this into the dict: the macros aren't
      // user-confirmed knowledge about the new food, just inherited from old.
      dbMatches = const [null];
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
    }

    for (final e in newEntries) {
      await addFoodEntry(e, msg.mealSlot);
    }

    final updatedItems = List<ChatFoodItem>.from(msg.foodItems);
    final replacementItems = [
      for (var i = 0; i < newEntries.length; i++)
        ChatFoodItem.fromFoodEntry(
          newEntries[i],
          amountText: result.isNotEmpty ? result.items[i].rawText : trimmed,
        ),
    ];
    updatedItems.replaceRange(itemIndex, itemIndex + 1, replacementItems);
    _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
    notifyListeners();
    await _persistChatMessages();
  }

  /// Persist a confirmed name → per-100g mapping to the personal dictionary.
  /// Skips entries that are not confident enough to cache:
  ///   • missing/zero grams (can't compute per-100g)
  ///   • low confidence (`< 0.6`) — weak DB matches and AI estimates set this,
  ///     so the dict only ever caches reliable mappings.
  Future<void> _learnFromEntry(String name, FoodEntry e) async {
    if (e.grams == null || e.grams! <= 0) return;
    if ((e.confidence ?? 1.0) < 0.6) return;
    await _personalDict.upsert(
      name: name,
      kcalPer100g: e.calories * 100 / e.grams!,
      proteinPer100g: e.protein != null ? e.protein! * 100 / e.grams! : null,
      carbsPer100g: e.carbs != null ? e.carbs! * 100 / e.grams! : null,
      fatPer100g: e.fat != null ? e.fat! * 100 / e.grams! : null,
    );
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
    notifyListeners();

    final updatedItems = <ChatFoodItem>[];
    for (var i = 0; i < min(newTexts.length, msg.foodItems.length); i++) {
      final oldItem = msg.foodItems[i];
      final newText = newTexts[i].trim();

      // Swap in today's log: remove old, add new.
      _todayLog = _todayLog.removeEntry(oldItem.entryId, msg.mealSlot);
      final result = FoodNlpParser.parse(newText);
      final FoodEntry newEntry;
      if (result.isNotEmpty) {
        final dbMatches = await _resolveDbMatches(result);
        newEntry = _buildEntry(result.items.first, dbMatches.first);
        if (dbMatches.first != null) {
          await _learnFromEntry(result.items.first.name, newEntry);
        }
      } else {
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
        // Same rationale as editChatFoodItem: don't learn placeholder macros.
      }
      _todayLog = _todayLog.addEntry(newEntry, msg.mealSlot);
      updatedItems
          .add(ChatFoodItem.fromFoodEntry(newEntry, amountText: newText));
    }

    await _storage.saveNutritionLog(_todayLog);
    _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
    _isChatParsing = false;
    notifyListeners();
    await _persistChatMessages();
    await _checkGoalMet();
    await _checkProteinGoalMet();
    await _checkOvershoot();
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
    final loggingTowardToday = _todayLog.date == _dateFmt.format(_selectedDate);
    if (!loggingTowardToday) return; // user is intentionally on a past day
    _todayLog = await _storage.loadNutritionLogForDate(today);
    _selectedDate = now;
    final raw = await _storage.loadChatMessagesRaw(today);
    _chatMessages = raw.map(ChatMessage.fromJson).toList();
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
      _storage.loadFoodFeedback().then((v) => _feedback = v),
      _storage.loadWeightLog().then((v) => _weightLog = v),
      _personalDict.init(),
    ]);
    final todayKey = _dateFmt.format(DateTime.now());
    final rawChat = await _storage.loadChatMessagesRaw(todayKey);
    _chatMessages = rawChat.map(ChatMessage.fromJson).toList();
    if (_disposed) return;

    // Reset same-day calorie notification flag on new-day load.
    _calorieGoalNotifiedToday = false;

    // Apply notification preferences: schedule or cancel weight reminder.
    final notifPrefs = await _storage.loadNotificationPreferences();
    if (notifPrefs.weightReminderEnabled) {
      await _notifications
          .scheduleWeightReminder(notifPrefs.weightReminderTime);
    } else {
      await _notifications.cancelWeightReminder();
    }

    notifyListeners();
  }

  // ── Internal RPG hooks ────────────────────────────────────────────────────────

  Future<void> _checkGoalMet() async {
    final today = _dateFmt.format(DateTime.now());
    if (isCalorieGoalMet && _goalMetDate != today) {
      await _onCalorieGoalMet(today);
    }
    // Fire calorie-goal notification once per day when user first hits the goal.
    if (isCalorieGoalMet && !_calorieGoalNotifiedToday) {
      final prefs = await _storage.loadNotificationPreferences();
      if (prefs.calorieGoalEnabled) {
        _calorieGoalNotifiedToday = true;
        await _notifications.showCalorieGoalNotification(
            todayCalories, effectiveGoal);
      }
    }
  }

  Future<void> _onCalorieGoalMet(String today) async {
    await _statsPresenter.addXp(30);

    // IF-Sync bonus: +10 XP when logging was locked to eating window
    if (_goals.ifSyncEnabled) {
      await _statsPresenter.addXp(10);
    }

    final yesterday =
        _dateFmt.format(DateTime.now().subtract(const Duration(days: 1)));
    _goalStreak = (_goalMetDate == yesterday) ? _goalStreak + 1 : 1;
    _goalMetDate = today;

    if (_goalStreak % 7 == 0) await _statsPresenter.awardStat('vit');

    await _storage.saveNutritionStreak(_goalStreak);
    await _storage.saveNutritionGoalMetDate(today);
    notifyListeners();
  }

  Future<void> _checkProteinGoalMet() async {
    if (_goals.proteinGrams == null) return;
    if (_proteinGoalMetToday || !isProteinGoalMet) return;
    _proteinGoalMetToday = true;
    await _statsPresenter.addXp(15);
    await _statsPresenter.awardStat('str');
  }

  Future<void> _checkOvershoot() async {
    if (!_goals.overshootPenaltyEnabled) return;
    if (isOverGoal) await _statsPresenter.modifyHp(-5);
  }

  Future<void> _updateLogStreak() async {
    final today = _dateFmt.format(DateTime.now());
    if (_logStreakDate == today) return; // already counted today
    final yesterday =
        _dateFmt.format(DateTime.now().subtract(const Duration(days: 1)));
    _logStreak = (_logStreakDate == yesterday) ? _logStreak + 1 : 1;
    _logStreakDate = today;
    await _onLogStreakUpdate();
    await _storage.saveLogStreak(_logStreak);
    await _storage.saveLogStreakDate(today);
    notifyListeners();
  }

  Future<void> _onLogStreakUpdate() async {
    // Award INT XP at 7/14/30-day milestones
    if (_logStreak == 7) {
      await _statsPresenter.addXp(20);
    } else if (_logStreak == 14) {
      await _statsPresenter.addXp(40);
    } else if (_logStreak == 30) {
      await _statsPresenter.addXp(80);
    }
  }
}

/// User-facing status of the smart food search (RAG) feature.
enum FoodSearchStatus {
  /// Services not wired (legacy build path).
  disabled,

  /// Embedder hardware/runtime not supported on this device.
  failed,

  /// Idle waiting for user to opt in.
  notInstalled,

  /// Embedder is downloading.
  downloading,

  /// Embedder installed but not yet loaded into memory.
  loading,

  /// Embedder ready but no rows indexed yet.
  idle,

  /// Index build in progress.
  indexing,

  /// Fully ready — semantic search is live.
  ready,
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
