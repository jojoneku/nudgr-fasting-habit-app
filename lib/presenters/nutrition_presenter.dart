import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/ai_meal_estimate.dart';
import '../models/daily_nutrition_log.dart';
import '../models/food_entry.dart';
import '../models/food_template.dart';
import '../models/meal_slot.dart';
import '../models/nutrition_goals.dart';
import '../models/tdee_profile.dart';
import '../services/ai_estimation_service.dart';
import '../services/food_db_service.dart';
import '../services/storage_service.dart';
import 'fasting_presenter.dart';
import 'stats_presenter.dart';

class NutritionPresenter extends ChangeNotifier {
  final StatsPresenter _statsPresenter;
  final FastingPresenter _fastingPresenter;
  final StorageService _storage;
  final FoodDbService _foodDb;
  final AiEstimationService _ai;

  DailyNutritionLog _todayLog = DailyNutritionLog.empty('');
  NutritionGoals _goals = NutritionGoals.initial();
  List<DailyNutritionLog> _history = [];
  TdeeProfile? _tdeeProfile;
  List<FoodTemplate> _library = [];

  int _goalStreak = 0;       // consecutive days calorie goal met
  String? _goalMetDate;      // last date calorie goal was met
  int _logStreak = 0;        // consecutive days with ≥1 entry
  String? _logStreakDate;    // last date an entry was logged

  bool _proteinGoalMetToday = false;
  bool _isAiEstimating = false;
  AiMealEstimate? _lastEstimate;
  String? _aiError;
  bool _aiJustInstalled = false;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _calFmt  = NumberFormat('#,###');

  NutritionPresenter({
    required StatsPresenter statsPresenter,
    required FastingPresenter fastingPresenter,
    required StorageService storage,
    required FoodDbService foodDb,
    required AiEstimationService aiEstimation,
  })  : _statsPresenter = statsPresenter,
        _fastingPresenter = fastingPresenter,
        _storage = storage,
        _foodDb = foodDb,
        _ai = aiEstimation {
    loadState();
  }

  // ── Core state ───────────────────────────────────────────────────────────────

  DailyNutritionLog       get todayLog      => _todayLog;
  NutritionGoals          get goals         => _goals;
  List<DailyNutritionLog> get history       => _history;
  TdeeProfile?            get tdeeProfile   => _tdeeProfile;

  // ── Calorie getters ──────────────────────────────────────────────────────────

  int get todayCalories => _todayLog.totalCalories;

  int get effectiveGoal => _goals.mode == TrackingMode.standard && _tdeeProfile != null
      ? _tdeeProfile!.targetCalories
      : _goals.dailyCalories;

  double get calorieProgress =>
      effectiveGoal > 0 ? (todayCalories / effectiveGoal).clamp(0.0, 1.5) : 0.0;

  bool get isCalorieGoalMet => todayCalories >= effectiveGoal;
  bool get isOverGoal        => todayCalories > effectiveGoal * 1.2;

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
  double get todayCarbs   => _todayLog.totalCarbs;
  double get todayFat     => _todayLog.totalFat;

  double get proteinProgress => _goals.proteinGrams != null && _goals.proteinGrams! > 0
      ? (todayProtein / _goals.proteinGrams!).clamp(0.0, 1.0)
      : 0.0;

  double get carbsProgress => _goals.carbsGrams != null && _goals.carbsGrams! > 0
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

  int  get goalStreak => _goalStreak;
  int  get logStreak  => _logStreak;

  // ── Food library getters ─────────────────────────────────────────────────────

  List<FoodTemplate> get savedTemplates => List.unmodifiable(_library);

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

  FoodDbService   get foodDb             => _foodDb;
  bool            get isAiAvailable      => _ai.isModelAvailable;
  bool            get isAiEstimating     => _isAiEstimating;
  bool            get isAiDownloading    => _ai.isDownloading;
  int             get aiDownloadProgress => _ai.downloadProgress;
  String          get aiSizeLabel        => _ai.modelSizeLabel;
  AiMealEstimate? get lastEstimate       => _lastEstimate;
  String?         get aiError            => _aiError;
  String?         get aiDownloadError    => _ai.downloadError;
  bool            get aiJustInstalled    => _aiJustInstalled;

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
      _library[idx] = _library[idx].copyWith(useCount: _library[idx].useCount + 1);
      await _storage.saveFoodLibrary(_library);
    }
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

  // ── Actions — AI estimation ───────────────────────────────────────────────────

  Future<void> estimateMeal(String description) async {
    if (!isAiAvailable) return;
    _isAiEstimating = true;
    _lastEstimate = null;
    _aiError = null;
    _aiJustInstalled = false;
    notifyListeners();
    try {
      _lastEstimate = await _ai.estimate(description);
    } catch (e) {
      _lastEstimate = null;
      _aiError = 'Estimation failed — try rephrasing your meal.';
    } finally {
      _isAiEstimating = false;
      notifyListeners();
    }
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
    _aiError = null;
    notifyListeners();
  }

  Future<void> downloadAiModel() async {
    if (_ai.isDownloading) return;
    notifyListeners();
    await _ai.downloadModel(onProgress: (_) => notifyListeners());
    if (_ai.isModelAvailable) _aiJustInstalled = true;
    notifyListeners();
  }

  // ── Load state ───────────────────────────────────────────────────────────────

  Future<void> loadState() async {
    _todayLog     = await _storage.loadTodayNutritionLog();
    _goals        = await _storage.loadNutritionGoals();
    _history      = await _storage.loadNutritionHistory();
    _tdeeProfile  = await _storage.loadTdeeProfile();
    _library      = await _storage.loadFoodLibrary();
    _goalStreak   = await _storage.loadNutritionStreak();
    _goalMetDate  = await _storage.loadNutritionGoalMetDate();
    _logStreak    = await _storage.loadLogStreak();
    _logStreakDate = await _storage.loadLogStreakDate();
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

    final yesterday = _dateFmt.format(DateTime.now().subtract(const Duration(days: 1)));
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
    final yesterday = _dateFmt.format(DateTime.now().subtract(const Duration(days: 1)));
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
