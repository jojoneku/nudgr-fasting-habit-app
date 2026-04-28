import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_meal_estimate.dart';
import '../models/chat_message.dart';
import '../models/daily_nutrition_log.dart';
import '../models/exercise_entry.dart';
import '../models/food_db_entry.dart';
import '../models/food_entry.dart';
import '../models/food_parse_result.dart';
import '../models/food_template.dart';
import '../models/meal_slot.dart';
import '../models/nutrition_goals.dart';
import '../models/tdee_profile.dart';
import '../services/ai_coach_service.dart';
import '../services/food_db_service.dart';
import '../services/storage_service.dart';
import '../utils/exercise_nlp_parser.dart';
import '../utils/food_nlp_parser.dart';
import 'fasting_presenter.dart';
import 'stats_presenter.dart';

class NutritionPresenter extends ChangeNotifier {
  final StatsPresenter _statsPresenter;
  final FastingPresenter _fastingPresenter;
  final StorageService _storage;
  final FoodDbService _foodDb;
  final AiCoachService _ai;

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
  })  : _statsPresenter = statsPresenter,
        _fastingPresenter = fastingPresenter,
        _storage = storage,
        _foodDb = foodDb,
        _ai = aiCoach {
    loadState();
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
        ChatFoodItem.fromFoodEntry(entry,
            amountText: '${entry.calories} kcal'),
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
              aiEstimated: e.aiEstimated,
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
    await _persistChatMessages();

    notifyListeners();
    await _storage.saveNutritionLog(_todayLog);
    await _updateLogStreak();
    await _checkGoalMet();
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
        _parseError = 'Could not identify any food items. Try being more specific.';
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
      final entry = overrides[i] ?? _buildEntry(result.items[i], _parsedDbMatches[i]);
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

  /// Multi-token search + best-match scoring for one parsed item.
  /// Searches the full name AND individual significant tokens to improve recall
  /// for variant spellings (e.g. "skimmed milk" → "MILK, SKIM").
  Future<FoodDbEntry?> _resolveOneDbItem(ParsedFoodItem item) async {
    final allHits = <String, FoodDbEntry>{};

    for (final h in await _foodDb.search(item.name)) {
      allHits[h.id] = h;
    }

    // Per-token fallback to surface entries that share only one keyword.
    final tokens = item.name
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toList();
    if (tokens.length > 1) {
      for (final token in tokens) {
        for (final h in await _foodDb.search(token)) {
          allHits.putIfAbsent(h.id, () => h);
        }
      }
    }

    if (allHits.isEmpty) return null;
    return _pickBestDbMatch(allHits.values.toList(), item.name);
  }

  /// Picks the DB entry that best matches [query] from [hits].
  FoodDbEntry? _pickBestDbMatch(List<FoodDbEntry> hits, String query) {
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first;

    final q = query.toLowerCase();
    final qWords =
        q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();

    int bestScore = -999;
    FoodDbEntry best = hits.first;

    for (final entry in hits) {
      final score = _dbMatchScore(entry, qWords, q);
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    return best;
  }

  // Words that transform a base food into a distinct processed product.
  // If these appear in a DB entry but NOT in the user's query, the entry is
  // penalised — prevents "potato chips" winning over "potatoes, raw" for the
  // bare query "potato".
  static const _transformingWords = {
    'chips', 'crisps', 'puffs', 'crackers', 'cracker',
    'fried', 'battered', 'breaded', 'coated', 'deep-fried',
    'sauce', 'gravy', 'soup', 'stew', 'casserole', 'curry',
    'candy', 'candied', 'caramel',
    'pie', 'cake', 'tart', 'pudding',
    'instant', 'processed', 'imitation',
  };

  int _dbMatchScore(FoodDbEntry entry, List<String> qWords, String fullQuery) {
    final eName = entry.name.toLowerCase();

    if (eName == fullQuery) return 1000;

    // Split entry name on commas, spaces, hyphens for word-level matching.
    final eWords = eName
        .split(RegExp(r'[,\s\-]+'))
        .where((w) => w.length > 1)
        .toList();

    int score = 0;
    for (final qw in qWords) {
      if (eName.contains(qw)) {
        score += 3; // direct substring hit
      } else if (eWords.any((ew) => qw.startsWith(ew) && ew.length >= 3)) {
        // Handles inflections: "skim" in DB matches "skimmed" in query.
        score += 1;
      }
    }

    // Penalise transforming/processing words in the DB entry that the user
    // did not mention. Each unmentioned transforming word deducts 5 points,
    // ensuring e.g. "potato chips" loses to "potatoes, raw" for query "potato"
    // while "fried chicken" still wins for query "fried chicken".
    for (final ew in eWords) {
      if (_transformingWords.contains(ew) &&
          !qWords.any((qw) => qw == ew || qw.contains(ew) || ew.contains(qw))) {
        score -= 5;
      }
    }

    // Penalise very verbose USDA-style names (prefer shorter, cleaner entries).
    score -= entry.name.split(' ').length ~/ 4;

    return score;
  }

  FoodEntry _buildEntry(ParsedFoodItem parsed, FoodDbEntry? dbEntry) {
    if (dbEntry != null) {
      return dbEntry.toFoodEntry(parsed.grams);
    }
    // No DB match — estimate calories by weight using a keyword-density table.
    return FoodEntry(
      id: FoodEntry.generateId(),
      name: parsed.name,
      calories: _estimateCalories(parsed.name, parsed.grams),
      grams: parsed.grams,
      aiEstimated: true,
      loggedAt: DateTime.now(),
    );
  }

  /// Estimates calories from [grams] using a keyword-based calorie-density
  /// lookup. Returns a rough but non-zero value when no DB entry is found.
  int _estimateCalories(String name, double grams) {
    final n = name.toLowerCase();
    final double kcalPerGram;
    if (_containsAny(n, ['oil', 'butter', 'ghee', 'lard', 'margarine'])) {
      kcalPerGram = 7.5;
    } else if (_containsAny(
        n, ['nut', 'almond', 'peanut', 'cashew', 'pistachio', 'walnut', 'seed', 'buto'])) {
      kcalPerGram = 5.5;
    } else if (_containsAny(n, ['sugar', 'syrup', 'honey', 'jam', 'jelly'])) {
      kcalPerGram = 3.5;
    } else if (_containsAny(
        n, ['cake', 'cookie', 'biscuit', 'pastry', 'donut', 'chocolate', 'candy', 'chips', 'cracker'])) {
      kcalPerGram = 4.5;
    } else if (_containsAny(
        n, ['rice', 'pasta', 'noodle', 'spaghetti', 'bread', 'flour', 'oat', 'cereal', 'kanin', 'bigas', 'pancit'])) {
      kcalPerGram = 1.3;
    } else if (_containsAny(
        n, ['beef', 'pork', 'chicken', 'turkey', 'lamb', 'meat', 'manok', 'baboy', 'baka', 'longganisa', 'hotdog', 'sausage', 'tocino', 'tapa', 'liempo'])) {
      kcalPerGram = 2.0;
    } else if (_containsAny(
        n, ['fish', 'salmon', 'tuna', 'tilapia', 'bangus', 'sardine', 'shrimp', 'crab', 'squid', 'seafood', 'isda', 'hipon'])) {
      kcalPerGram = 1.4;
    } else if (_containsAny(n, ['egg', 'itlog'])) {
      kcalPerGram = 1.5;
    } else if (_containsAny(n, ['milk', 'cheese', 'yogurt', 'cream', 'gatas'])) {
      kcalPerGram = 1.5;
    } else if (_containsAny(
        n, ['vegetable', 'salad', 'broccoli', 'spinach', 'cabbage', 'carrot', 'kangkong', 'sitaw', 'gulay', 'ampalaya', 'talong', 'okra'])) {
      kcalPerGram = 0.35;
    } else if (_containsAny(
        n, ['fruit', 'apple', 'banana', 'mango', 'orange', 'grape', 'watermelon', 'saging', 'mangga', 'prutas'])) {
      kcalPerGram = 0.6;
    } else if (_containsAny(
        n, ['soup', 'broth', 'sabaw', 'sinigang', 'nilaga', 'tinola', 'adobo', 'kare'])) {
      kcalPerGram = 0.5;
    } else {
      kcalPerGram = 1.5; // generic mixed-dish default
    }
    return (grams * kcalPerGram).round().clamp(1, 9999);
  }

  bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);

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

  /// Parse [text] as food or exercise, add to the chat feed, and persist.
  Future<void> parseChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isChatParsing) return;
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
    // Step 1: NLP parse — splitting into fragments + quantity extraction.
    // Always used as fallback if AI normalization fails or is unavailable.
    final nlpResult = FoodNlpParser.parse(text);
    if (nlpResult.isEmpty) {
      _chatParseError = 'Could not identify any food items.';
      return;
    }

    // Step 2: AI name + grams normalization (best-effort).
    // Qwen3 normalizes food names to USDA-friendly form and converts
    // volume units using food-specific density (e.g. "3 cups rice" → 555g).
    // Indexed JSON ensures any ordering mismatch is caught and rejected.
    var items = nlpResult.items;
    if (_ai.isAvailable) {
      try {
        final fragments = nlpResult.items.map((i) => i.rawText).toList();
        final aiParsed = await _ai
            .normalizeFoodInput(fragments)
            .timeout(const Duration(seconds: 15));
        if (aiParsed != null && aiParsed.length == fragments.length) {
          items = List.generate(nlpResult.items.length, (i) {
            final ai = aiParsed[i];
            return ParsedFoodItem(
              rawText: nlpResult.items[i].rawText,
              name: ai.name,
              grams: ai.grams,
              isEstimated: false,
            );
          });
        }
      } catch (e) {
        debugPrint(
            'NutritionPresenter: AI normalization failed, using NLP: $e');
      }
    }

    // Step 3: DB lookup using normalized (or NLP) names.
    final dbMatches = await Future.wait(items.map(_resolveOneDbItem));

    // Step 4: For unresolved items only, ask AI for macro estimates.
    // Passing only the unresolved names (not the full original input) keeps
    // the estimation focused and reduces misassignment risk.
    AiMealEstimate? aiEstimate;
    final unresolvedNames = [
      for (var i = 0; i < items.length; i++)
        if (dbMatches[i] == null) items[i].name,
    ];
    if (unresolvedNames.isNotEmpty && _ai.isAvailable) {
      try {
        aiEstimate = await _ai
            .estimateMacros(unresolvedNames.join(', '))
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint('NutritionPresenter: AI macro estimate failed: $e');
      }
    }

    // Step 5: Build and log each food entry.
    final foodItems = <ChatFoodItem>[];
    for (var i = 0; i < items.length; i++) {
      final parsed = items[i];
      final dbEntry = dbMatches[i];
      final FoodEntry entry;
      if (dbEntry != null) {
        entry = _buildEntry(parsed, dbEntry);
      } else {
        final aiItem =
            aiEstimate != null ? _findAiItem(aiEstimate, parsed.name) : null;
        entry = aiItem != null
            ? _aiItemToFoodEntry(aiItem, parsed)
            : _buildEntry(parsed, null);
      }
      await addFoodEntry(entry, MealSlot.meal);
      foodItems
          .add(ChatFoodItem.fromFoodEntry(entry, amountText: parsed.rawText));
    }

    final msg = ChatMessage(
      id: ChatMessage.generateId(),
      rawText: text,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.food,
      foodItems: foodItems,
      mealSlot: MealSlot.meal,
    );
    _chatMessages.add(msg);
    await _persistChatMessages();
  }

  /// Finds the AI item whose name best overlaps with [itemName].
  /// Requires a minimum match score to avoid spurious assignments.
  AiItemEstimate? _findAiItem(AiMealEstimate estimate, String itemName) {
    if (estimate.items.isEmpty) return null;
    final query = itemName.toLowerCase();
    final qWords =
        query.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

    AiItemEstimate? best;
    int bestScore = 1; // require at least 1 point

    for (final ai in estimate.items) {
      final aName = ai.name.toLowerCase();
      int score = 0;
      if (aName.contains(query) || query.contains(aName)) score += 5;
      for (final w in qWords) {
        if (aName.contains(w)) score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        best = ai;
      }
    }
    // Fallback: if nothing matched but only one AI item, use it.
    if (best == null && estimate.items.length == 1) return estimate.items.first;
    return best;
  }

  /// Builds a [FoodEntry] from an AI estimate, preserving the NLP-parsed [grams].
  FoodEntry _aiItemToFoodEntry(AiItemEstimate ai, ParsedFoodItem parsed) =>
      FoodEntry(
        id: FoodEntry.generateId(),
        name: parsed.name,
        calories: ai.calories,
        protein: ai.protein,
        carbs: ai.carbs,
        fat: ai.fat,
        grams: parsed.grams,
        aiEstimated: true,
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

  /// Remove a chat message. Food items are also removed from [_todayLog].
  Future<void> removeChatMessage(String messageId) async {
    final msg = _chatMessages.cast<ChatMessage?>().firstWhere(
          (m) => m!.id == messageId,
          orElse: () => null,
        );
    if (msg == null) return;
    if (msg.kind == ChatMessageKind.food) {
      for (final item in msg.foodItems) {
        await removeFoodEntry(item.entryId, msg.mealSlot);
      }
    }
    _chatMessages.removeWhere((m) => m.id == messageId);
    notifyListeners();
    await _persistChatMessages();
  }

  /// Re-parse [newText] for item at [itemIndex] in [messageId], update in-place.
  Future<void> editChatFoodItem(
      String messageId, int itemIndex, String newText) async {
    final msgIdx = _chatMessages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final msg = _chatMessages[msgIdx];
    if (itemIndex >= msg.foodItems.length) return;
    final oldItem = msg.foodItems[itemIndex];

    // Remove old food entry from today's log.
    await removeFoodEntry(oldItem.entryId, msg.mealSlot);

    // Re-parse and look up in DB.
    final result = FoodNlpParser.parse(newText.trim());
    final FoodEntry newEntry;
    if (result.isNotEmpty) {
      final dbMatches = await _resolveDbMatches(result);
      newEntry = _buildEntry(result.items.first, dbMatches.first);
    } else {
      newEntry = FoodEntry(
        id: FoodEntry.generateId(),
        name: newText.trim(),
        calories: oldItem.calories,
        protein: oldItem.protein,
        carbs: oldItem.carbs,
        fat: oldItem.fat,
        grams: oldItem.grams,
        aiEstimated: true,
        loggedAt: DateTime.now(),
      );
    }
    await addFoodEntry(newEntry, msg.mealSlot);

    final updatedItems = List<ChatFoodItem>.from(msg.foodItems);
    updatedItems[itemIndex] =
        ChatFoodItem.fromFoodEntry(newEntry, amountText: newText.trim());
    _chatMessages[msgIdx] = msg.copyWithFoodItems(updatedItems);
    notifyListeners();
    await _persistChatMessages();
  }

  /// Batch-edit all food items in a message at once.
  /// [newTexts] must match [message.foodItems] by index.
  Future<void> editAllChatFoodItems(
      String messageId, List<String> newTexts) async {
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
      } else {
        newEntry = FoodEntry(
          id: FoodEntry.generateId(),
          name: newText,
          calories: oldItem.calories,
          protein: oldItem.protein,
          carbs: oldItem.carbs,
          fat: oldItem.fat,
          grams: oldItem.grams,
          aiEstimated: true,
          loggedAt: DateTime.now(),
        );
      }
      _todayLog = _todayLog.addEntry(newEntry, msg.mealSlot);
      updatedItems.add(
          ChatFoodItem.fromFoodEntry(newEntry, amountText: newText));
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

  // ── Load state ───────────────────────────────────────────────────────────────

  Future<void> loadState() async {
    _todayLog = await _storage.loadTodayNutritionLog();
    _goals = await _storage.loadNutritionGoals();
    _history = await _storage.loadNutritionHistory();
    _tdeeProfile = await _storage.loadTdeeProfile();
    _library = await _storage.loadFoodLibrary();
    _goalStreak = await _storage.loadNutritionStreak();
    _goalMetDate = await _storage.loadNutritionGoalMetDate();
    _logStreak = await _storage.loadLogStreak();
    _logStreakDate = await _storage.loadLogStreakDate();
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
