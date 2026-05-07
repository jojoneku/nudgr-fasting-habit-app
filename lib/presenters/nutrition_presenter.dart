import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_meal_estimate.dart';
import '../models/ai_parsed_food.dart';
import '../models/chat_message.dart';
import '../models/daily_nutrition_log.dart';
import '../models/estimation_source.dart';
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
import '../models/personal_food_entry.dart';
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
  bool _isAiEstimating = false;
  AiMealEstimate? _lastEstimate;
  String? _aiEstimateError;

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

  // ── Chat + exercise state ─────────────────────────────────────────────────
  DateTime _selectedDate = DateTime.now();
  List<ChatMessage> _chatMessages = [];
  bool _isChatParsing = false;
  String? _chatParseError;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _calFmt = NumberFormat('#,###');

  NutritionPresenter({
    required StatsPresenter statsPresenter,
    required FastingPresenter fastingPresenter,
    required StorageService storage,
    required FoodDbService foodDb,
    required AiCoachService aiCoach,
    FoodSemanticSearchService? semanticSearch,
    EmbeddingService? embedder,
  })  : _statsPresenter = statsPresenter,
        _fastingPresenter = fastingPresenter,
        _storage = storage,
        _foodDb = foodDb,
        _ai = aiCoach,
        _semanticSearch = semanticSearch,
        _embedder = embedder {
    _personalDict = PersonalFoodDictionary(storage);
    // Surface index progress to the UI without polling.
    _indexProgressSub =
        semanticSearch?.progressStream.listen((_) => notifyListeners());
    loadState();
  }

  @override
  void dispose() {
    _indexProgressSub?.cancel();
    super.dispose();
  }

  // ── Core state ───────────────────────────────────────────────────────────────

  DailyNutritionLog get todayLog => _todayLog;
  NutritionGoals get goals => _goals;
  List<DailyNutritionLog> get history => _history;
  TdeeProfile? get tdeeProfile => _tdeeProfile;

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

  // ── AI getters ───────────────────────────────────────────────────────────────

  FoodDbService get foodDb => _foodDb;
  bool get isAiAvailable => _ai.isAvailable;
  bool get isAiEstimating => _isAiEstimating;
  bool get isAiDownloading => _ai.downloadProgress != null;
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

    notifyListeners(); // flip status to downloading
    try {
      if (!embedder.isInstalled) {
        await embedder.downloadModel(onProgress: (_) => notifyListeners());
      } else if (!embedder.isReady) {
        await embedder.init();
      }
    } catch (e) {
      debugPrint('NutritionPresenter.enableFoodSearch failed: $e');
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

  bool get isAiBundleDownloading => _isBundleDownloading;

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

    // Phase 1 — embedder.
    if (!embedder.isInstalled) {
      _bundlePhase = 1;
      notifyListeners();
      try {
        await embedder.downloadModel(onProgress: (_) => notifyListeners());
      } catch (e) {
        debugPrint('NutritionPresenter.downloadAiBundle: embedder failed: $e');
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
      }
    }

    _isBundleDownloading = false;
    _bundlePhase = 0;
    notifyListeners();
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

    // Ambiguous band — ask the LLM to disambiguate. Bound at 5 s.
    if (!_ai.isAvailable) return null;
    try {
      final pick = await _ai
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

    return FoodEntry(
      id: FoodEntry.generateId(),
      name: _formatDisplayName(parsed.name),
      calories: _estimateCalories(parsed.name, parsed.grams),
      grams: parsed.grams,
      estimationSource: EstimationSource.keywordDensity,
      confidence: 0.3,
      loggedAt: DateTime.now(),
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
    // Step 1: NLP parse — always the source of truth for grams when exact.
    final nlpResult = FoodNlpParser.parse(text);
    if (nlpResult.isEmpty) {
      _chatParseError = 'Could not identify any food items.';
      return;
    }

    // Step 2 (parallel): kick off AI normalize AND speculative DB lookups
    // using the raw NLP names. The AI normalize is only useful when DB misses
    // on the raw name (it refines the name for retry) or when NLP grams are
    // estimated (it refines grams). For the common case where DB hits on raw
    // input, AI normalize is wasted but no longer blocking.
    final aiNormalizeFuture = _ai.isAvailable
        ? _ai
            .normalizeFoodInput(nlpResult.items.map((i) => i.rawText).toList())
            .timeout(const Duration(seconds: 15))
            .catchError((Object e) {
            debugPrint('NutritionPresenter: AI normalize failed: $e');
            return null;
          })
        : Future<List<AiParsedFood>?>.value(null);

    final speculativeDbFuture =
        Future.wait(nlpResult.items.map((i) => _resolveOneDbItem(i)));

    final results = await Future.wait([aiNormalizeFuture, speculativeDbFuture]);
    final aiNormalized = results[0] as List<AiParsedFood>?;
    final speculativeDb = results[1] as List<FoodDbEntry?>;

    // Merge AI normalize back in (preserving the same name/grams policy as
    // before): adopt AI name only if it's a reasonable normalization, and
    // adopt AI grams only when NLP couldn't determine an exact value.
    final items =
        (aiNormalized != null && aiNormalized.length == nlpResult.items.length)
            ? List.generate(nlpResult.items.length, (i) {
                final ai = aiNormalized[i];
                final nlp = nlpResult.items[i];
                final keepName =
                    FoodMatchScorer.isReasonableNormalization(nlp.name, ai.name)
                        ? ai.name
                        : nlp.name;
                final keepGrams = nlp.isEstimated ? ai.grams : nlp.grams;
                return ParsedFoodItem(
                  rawText: nlp.rawText,
                  name: keepName,
                  grams: keepGrams,
                  isEstimated: nlp.isEstimated,
                );
              })
            : nlpResult.items;

    // Step 3: Personal dictionary — highest priority for user-confirmed foods.
    final entries = List<FoodEntry?>.filled(items.length, null);
    for (var i = 0; i < items.length; i++) {
      final dictHit = _personalDict.lookup(items[i].name);
      if (dictHit == null) {
        // Also try the original NLP name in case normalization changed it.
        final nlpHit = _personalDict.lookup(nlpResult.items[i].name);
        if (nlpHit != null) {
          entries[i] = _buildEntryFromDict(items[i], nlpHit);
        }
      } else {
        entries[i] = _buildEntryFromDict(items[i], dictHit);
      }
    }

    // Step 4: DB resolution. If the speculative DB lookup (using NLP name)
    // already hit, use it. Otherwise, retry with the AI-normalized name when
    // it differs from NLP. Learn each DB hit into the personal dict so the
    // next parse of the same food goes O(1).
    final dbRetries = <Future<void>>[];
    for (var i = 0; i < items.length; i++) {
      if (entries[i] != null) continue;

      final nameSameAsNlp =
          items[i].name.toLowerCase() == nlpResult.items[i].name.toLowerCase();

      if (nameSameAsNlp && speculativeDb[i] != null) {
        entries[i] = _buildEntry(items[i], speculativeDb[i]);
        // ignore: unawaited_futures
        _learnFromEntry(items[i].name, entries[i]!);
        continue;
      }

      // Either the name was AI-normalized OR the speculative lookup missed.
      // Retry with both names so scoring picks the best.
      final idx = i;
      dbRetries.add(() async {
        final altName = nlpResult.items[idx].name != items[idx].name
            ? nlpResult.items[idx].name
            : null;
        final dbEntry = await _resolveOneDbItem(items[idx], altName: altName);
        if (dbEntry != null) {
          entries[idx] = _buildEntry(items[idx], dbEntry);
          await _learnFromEntry(items[idx].name, entries[idx]!);
        }
      }());
    }
    await Future.wait(dbRetries);

    // Step 5: AI per-item macro estimate for still-unresolved items.
    final unresolvedIndices = [
      for (var i = 0; i < items.length; i++)
        if (entries[i] == null) i,
    ];
    if (unresolvedIndices.isNotEmpty && _ai.isAvailable) {
      try {
        final aiInputs = unresolvedIndices
            .map(
                (i) => AiParsedFood(name: items[i].name, grams: items[i].grams))
            .toList();
        final aiResults = await _ai
            .estimateMacrosForItems(aiInputs)
            .timeout(const Duration(seconds: 25));
        if (aiResults != null && aiResults.length == aiInputs.length) {
          for (var j = 0; j < unresolvedIndices.length; j++) {
            final i = unresolvedIndices[j];
            entries[i] = _aiItemToFoodEntry(aiResults[j], items[i]);
          }
        }
      } catch (e) {
        debugPrint('NutritionPresenter: AI macro estimate failed: $e');
      }
    }

    // Step 6: Keyword density fallback (last resort).
    for (var i = 0; i < items.length; i++) {
      entries[i] ??= _buildEntry(items[i], null);
    }

    // IF-Sync gate: same rule as addFoodEntry — drop the message if the user
    // is fasting and ifSync is enabled.
    if (_goals.ifSyncEnabled && !isEatingWindowOpen) return;

    // If the parse spanned a midnight boundary, _todayLog may still be keyed
    // for yesterday. Refresh before mutating so entries land on the right day.
    await _ensureTodayLogFresh();

    // Apply all entries to today's log in a single mutation, save once, and
    // run goal checks once. Avoids N redundant storage saves and
    // notifyListeners() calls when logging multiple items at once.
    final resolvedEntries = [for (final e in entries) e!];
    _todayLog = _todayLog.addEntries(resolvedEntries, MealSlot.meal);

    final msg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.food,
      foodItems: [
        for (var i = 0; i < items.length; i++)
          ChatFoodItem.fromFoodEntry(resolvedEntries[i],
              amountText: items[i].rawText),
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

  /// Builds a [FoodEntry] from an [AiItemEstimate] returned by
  /// [estimateMacrosForItems]. Calories are already computed for the exact
  /// gram weight (the prompt included grams), so no scaling is needed.
  FoodEntry _aiItemToFoodEntry(AiItemEstimate ai, ParsedFoodItem parsed) =>
      FoodEntry(
        id: FoodEntry.generateId(),
        name: _formatDisplayName(parsed.name),
        calories: ai.calories,
        protein: ai.protein,
        carbs: ai.carbs,
        fat: ai.fat,
        grams: parsed.grams,
        estimationSource: EstimationSource.aiPerItem,
        confidence: ai.confidence,
        loggedAt: DateTime.now(),
      );

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
      _personalDict.init(),
    ]);
    final todayKey = _dateFmt.format(DateTime.now());
    final rawChat = await _storage.loadChatMessagesRaw(todayKey);
    _chatMessages = rawChat.map(ChatMessage.fromJson).toList();
    notifyListeners();
  }

  // ── Internal RPG hooks ────────────────────────────────────────────────────────

  Future<void> _checkGoalMet() async {
    final today = _dateFmt.format(DateTime.now());
    if (isCalorieGoalMet && _goalMetDate != today) {
      await _onCalorieGoalMet(today);
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
