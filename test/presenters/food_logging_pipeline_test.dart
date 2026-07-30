/// End-to-end food-logging pipeline tests.
///
/// Covers all three tiers in [NutritionPresenter._parseChatAsFood]:
///   Path A — cloud AI (parseFoodWithCandidates → DB hydration or macros)
///   Path B — on-device AI single-call (parseFoodWithCandidates → hybrid)
///   Path C — no-AI NLP fallback (FoodNlpParser → keyword-density)
///
/// Each test drives [NutritionPresenter.parseChat] and inspects the
/// resulting [FoodEntry] list via [todayLog.allEntries].
///
/// Known-good macro ground truth used throughout:
///   Large egg (whole, raw): ~143 kcal / 100 g  →  1 large egg ≈ 57 g → ~81 kcal
///   Chicken breast (raw):  ~165 kcal / 100 g
///   White rice (cooked):   ~130 kcal / 100 g
///   Banana (raw):          ~89 kcal / 100 g
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/food_entry.dart';
import 'package:intermittent_fasting/models/meal_slot.dart';
import 'package:intermittent_fasting/models/estimation_source.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/models/food_db_entry.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';

import '../mocks.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

FoodDbEntry _dbEntry({
  required String id,
  required String name,
  required double cal,
  double protein = 0,
  double carbs = 0,
  double fat = 0,
}) =>
    FoodDbEntry(
      id: id,
      name: name,
      caloriesPer100g: cal,
      proteinPer100g: protein,
      carbsPer100g: carbs,
      fatPer100g: fat,
    );

ExtractedFoodItem _extracted({
  required String name,
  required double grams,
  String? foodId,
  double confidence = 0.0,
  EstimatedMacros? macros,
}) =>
    ExtractedFoodItem(
      name: name,
      grams: grams,
      hydeDescription: name,
      rawText: name,
      resolvedFoodId: foodId,
      resolverConfidence: confidence,
      estimatedMacros: macros,
    );

EstimatedMacros _macros(double cal, double p, double c, double f) =>
    EstimatedMacros(calories: cal, proteinG: p, carbsG: c, fatG: f);

/// Calories within ±[pct]% of expected.
Matcher _calApprox(int expected, {double pct = 0.15}) => predicate<int>(
      (v) => (v - expected).abs() <= expected * pct,
      'calories ≈ $expected (±${(pct * 100).round()}%)',
    );

// ── Presenter factory ─────────────────────────────────────────────────────────

// Must be the real current day: the presenter's day-rollover guard
// (_ensureTodayLogFresh) compares _todayLog.date to DateTime.now(); a stale
// constant makes it think the day rolled over and reload/reset mid-test.
final _today = DateFormat('yyyy-MM-dd').format(DateTime.now());

/// Creates a [NutritionPresenter] with all storage methods stubbed.
/// Pass [localAi] / [cloudAi] / [foodDb] to inject specific mock instances;
/// the caller is then responsible for stubbing those mocks AFTER this call.
/// Any mock NOT passed in gets a safe default stub here (isAvailable=false,
/// empty search results).
Future<NutritionPresenter> _makePresenter({
  MockAiCoachService? localAi,
  MockAiCoachService? cloudAi,
  MockFoodDbService? foodDb,
  MockStorageService? injectedStorage,
  List<DailyNutritionLog>? history,
}) async {
  final storage = injectedStorage ?? MockStorageService();
  final stats = MockStatsPresenter();
  final fasting = MockFastingPresenter();
  final db = foodDb ?? MockFoodDbService();
  final ai = localAi ?? MockAiCoachService();

  // Storage stubs.
  when(storage.loadNotificationPreferences())
      .thenAnswer((_) async => NotificationPreferences.defaults());
  when(storage.loadTodayNutritionLog())
      .thenAnswer((_) async => DailyNutritionLog.empty(_today));
  when(storage.loadNutritionGoals())
      .thenAnswer((_) async => NutritionGoals.initial());
  when(storage.loadNutritionHistory())
      .thenAnswer((_) async => history ?? const <DailyNutritionLog>[]);
  when(storage.loadTdeeProfile()).thenAnswer((_) async => null);
  when(storage.loadFoodLibrary()).thenAnswer((_) async => []);
  when(storage.loadNutritionStreak()).thenAnswer((_) async => 0);
  when(storage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
  when(storage.loadLogStreak()).thenAnswer((_) async => 0);
  when(storage.loadLogStreakDate()).thenAnswer((_) async => null);
  when(storage.loadCalorieGoalCreditedDates())
      .thenAnswer((_) async => <String>{});
  when(storage.loadProteinGoalCreditedDates())
      .thenAnswer((_) async => <String>{});
  when(storage.loadStreakMilestonePaid()).thenAnswer((_) async => 0);
  when(storage.saveCalorieGoalCreditedDates(any)).thenAnswer((_) async {});
  when(storage.saveProteinGoalCreditedDates(any)).thenAnswer((_) async {});
  when(storage.saveStreakMilestonePaid(any)).thenAnswer((_) async {});
  when(storage.saveNutritionLog(any)).thenAnswer((_) async {});
  when(storage.saveNutritionGoals(any)).thenAnswer((_) async {});
  when(storage.saveNutritionStreak(any)).thenAnswer((_) async {});
  when(storage.saveNutritionGoalMetDate(any)).thenAnswer((_) async {});
  when(storage.saveLogStreak(any)).thenAnswer((_) async {});
  when(storage.saveLogStreakDate(any)).thenAnswer((_) async {});
  when(storage.loadPersonalDict()).thenAnswer((_) async => []);
  when(storage.loadFoodFeedback()).thenAnswer((_) async => []);
  when(storage.saveFoodFeedback(any)).thenAnswer((_) async {});
  when(storage.loadChatMessagesRaw(any)).thenAnswer((_) async => []);
  when(storage.loadWeightLog()).thenAnswer((_) async => []);
  when(storage.loadBodyMeasurements()).thenAnswer((_) async => []);
  when(storage.loadMeasurementUnit())
      .thenAnswer((_) async => MeasurementUnit.metric);
  when(storage.loadLastRecompXpDate()).thenAnswer((_) async => null);
  when(storage.loadNutritionLogForDate(any))
      .thenAnswer((_) async => DailyNutritionLog.empty(_today));

  // Stats stubs.
  when(stats.stats).thenReturn(UserStats.initial());
  when(stats.addXp(any)).thenAnswer((_) async {});
  when(stats.modifyHp(any)).thenAnswer((_) async {});
  when(stats.awardStat(any)).thenAnswer((_) async {});

  // Fasting stub — not fasting.
  when(fasting.isFasting).thenReturn(false);

  // Default stubs for mocks we created internally (not passed in by caller).
  // Caller-provided mocks must be stubbed by the caller AFTER this returns.
  if (localAi == null) {
    when(ai.isAvailable).thenReturn(false);
    when(ai.downloadProgress).thenReturn(null);
    when(ai.tier).thenReturn(AiCoachTier.onDevice);
  }
  if (foodDb == null) {
    when(db.search(any)).thenAnswer((_) async => []);
    when(db.getById(any)).thenAnswer((_) async => null);
  }

  final p = NutritionPresenter(
    statsPresenter: stats,
    fastingPresenter: fasting,
    storage: storage,
    foodDb: db,
    aiCoach: ai,
    cloudAi: cloudAi,
  );
  await Future.delayed(Duration.zero);
  return p;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── PATH A: Cloud AI ────────────────────────────────────────────────────────

  group('Path A — Cloud AI', () {
    late MockAiCoachService cloudAi;
    late MockFoodDbService db;

    setUp(() {
      cloudAi = MockAiCoachService();
      db = MockFoodDbService();
    });

    /// Stubs that every cloud test needs; call after _makePresenter.
    void _baseCloudStubs() {
      when(cloudAi.isAvailable).thenReturn(true);
      when(cloudAi.tier).thenReturn(AiCoachTier.cloud);
      when(cloudAi.downloadProgress).thenReturn(null);
      when(db.search(any)).thenAnswer((_) async => []);
      when(db.getById(any)).thenAnswer((_) async => null);
    }

    // ── DB-resolved picks ───────────────────────────────────────────────────

    test('cloud picks DB candidate — uses DB macros, tags cloudAi', () async {
      // Ground truth: chicken breast 165 kcal/100g.
      const chickenId = 'usda-chicken-breast';
      final dbEntry = _dbEntry(
          id: chickenId,
          name: 'Chicken, Broilers, Breast, Cooked',
          cal: 165,
          protein: 31,
          carbs: 0,
          fat: 3.6);

      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(db.search(any)).thenAnswer((_) async => [dbEntry]);
      when(db.getById(chickenId)).thenAnswer((_) async => dbEntry);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'chicken breast',
                grams: 100,
                foodId: chickenId,
                confidence: 0.95),
          ],
        ),
      );

      await p.parseChat('100g chicken breast');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.estimationSource, EstimationSource.cloudAi);
      expect(entries.first.calories, _calApprox(165));
      expect(entries.first.grams, 100);
    });

    test('2 boiled eggs — non-gram unit converted, DB macros used', () async {
      // 2 large eggs ≈ 114 g → ~163 kcal at 143 kcal/100g.
      const eggId = 'usda-egg-whole';
      final dbEntry = _dbEntry(
          id: eggId,
          name: 'Egg, Whole, Raw',
          cal: 143,
          protein: 12.6,
          carbs: 0.7,
          fat: 9.5);

      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(db.search(any)).thenAnswer((_) async => [dbEntry]);
      when(db.getById(eggId)).thenAnswer((_) async => dbEntry);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'boiled eggs',
                grams: 114, // 2 × 57 g
                foodId: eggId,
                confidence: 0.92),
          ],
        ),
      );

      await p.parseChat('2 boiled eggs');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.grams, closeTo(114, 5));
      expect(entries.first.calories, _calApprox(163));
      expect(entries.first.estimationSource, EstimationSource.cloudAi);
    });

    test('1pc fried chicken thigh — piece-size resolved, DB macros used',
        () async {
      // Fried chicken thigh ≈ 150 g, 196 kcal/100g → ~294 kcal.
      const fryId = 'usda-chicken-thigh-fried';
      final dbEntry = _dbEntry(
          id: fryId,
          name: 'Chicken, Thigh, Fried',
          cal: 196,
          protein: 18.6,
          carbs: 7.8,
          fat: 11.0);

      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(db.search(any)).thenAnswer((_) async => [dbEntry]);
      when(db.getById(fryId)).thenAnswer((_) async => dbEntry);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'fried chicken thigh',
                grams: 150,
                foodId: fryId,
                confidence: 0.88),
          ],
        ),
      );

      await p.parseChat('1pc fried chicken wings thigh part');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.grams, closeTo(150, 10));
      expect(entries.first.calories, _calApprox(294));
    });

    // ── Estimated macros (no DB candidate) ─────────────────────────────────

    test('out-of-DB food — cloud estimated_macros used, tags cloudAi',
        () async {
      // Banana muffin 52g — not in DB, cloud estimates ~150 kcal.
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'banana muffin',
                grams: 52,
                macros: _macros(150, 2.5, 22, 6)),
          ],
        ),
      );

      await p.parseChat('52g banana muffin');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.grams, 52);
      expect(entries.first.estimationSource, EstimationSource.cloudAi);
      expect(entries.first.calories, _calApprox(150));
    });

    test('repeat-learn: out-of-DB cloud estimate NOT learned on first sight',
        () async {
      final storage = MockStorageService();
      final p = await _makePresenter(
          cloudAi: cloudAi, foodDb: db, injectedStorage: storage);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'banana muffin',
                grams: 52,
                macros: _macros(150, 2.5, 22, 6)),
          ],
        ),
      );

      await p.parseChat('52g banana muffin');
      await Future.delayed(const Duration(milliseconds: 20));

      // No history of this food → a single open estimate must not be cached.
      verifyNever(storage.savePersonalDict(any));
    });

    test('repeat-learn: out-of-DB cloud estimate IS learned after repeats',
        () async {
      final storage = MockStorageService();
      // Two prior logs of the same food → this log is the 3rd (_kLearnAfterLogs).
      final prior = DailyNutritionLog(
        date: '2026-06-10',
        meals: {
          MealSlot.meal: [
            FoodEntry(
                id: 'h1',
                name: 'banana muffin',
                calories: 150,
                loggedAt: DateTime(2026, 6, 10)),
            FoodEntry(
                id: 'h2',
                name: 'banana muffin',
                calories: 150,
                loggedAt: DateTime(2026, 6, 11)),
          ],
        },
      );
      final p = await _makePresenter(
          cloudAi: cloudAi,
          foodDb: db,
          injectedStorage: storage,
          history: [prior]);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'banana muffin',
                grams: 52,
                macros: _macros(150, 2.5, 22, 6)),
          ],
        ),
      );

      await p.parseChat('52g banana muffin');
      await Future.delayed(const Duration(milliseconds: 20));

      // 3rd sighting → promoted into the personal dictionary.
      verify(storage.savePersonalDict(any)).called(greaterThanOrEqualTo(1));
    });

    test('explicit gram override — user states 12g, cloud returned 40g',
        () async {
      // The Dart gram-reconciliation guard should clamp to 12g and
      // scale macros proportionally (160 × 12/40 = 48 kcal).
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'chocolate crinkle',
                grams: 40, // cloud's wrong value
                macros: _macros(160, 2, 26, 5)),
          ],
        ),
      );

      await p.parseChat('French Baker Chocolate Crinkle 12g');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.grams, closeTo(12, 1));
      // Macros must be proportionally scaled (~48 kcal, not 160).
      expect(entries.first.calories, _calApprox(48));
    });

    test('multi-item explicit grams — user states 166g rice + 81g adobo',
        () async {
      // Reproduces the reported under-count. The user weighed each component
      // and typed both; the model came back with smaller portions. The
      // single-item guard cannot fire here (two items, two gram mentions), so
      // nothing reconciles the model's guess against what the user stated.
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            // Model under-portions both against the user's stated weights.
            _extracted(
                name: 'rice', grams: 120, macros: _macros(156, 3, 34, 0.4)),
            _extracted(
                name: 'chicken adobo',
                grams: 60,
                macros: _macros(112, 11, 1, 7)),
          ],
        ),
      );

      await p.parseChat('166g rice, 81g chicken adobo');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(2));
      // Each item must honour the weight the user stated for it.
      expect(entries[0].grams, closeTo(166, 1));
      expect(entries[1].grams, closeTo(81, 1));
      // ...and its macros must scale with it, not stay at the model's portion.
      expect(entries[0].calories, _calApprox(216));
      expect(entries[1].calories, _calApprox(151));
    });

    test('leading total — composite dish keeps the whole stated weight',
        () async {
      // "247g rice and chicken adobo" states a TOTAL for the plate, and the
      // model flags it as one composite dish. Its split summed to 180g, losing
      // 27% of the meal — and the single-dish merge would have reported that
      // shortfall as the entire dish.
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'rice', grams: 120, macros: _macros(156, 3, 34, 0.4)),
            _extracted(
                name: 'chicken adobo',
                grams: 60,
                macros: _macros(112, 11, 1, 7)),
          ],
        ),
      );

      await p.parseChat('247g rice and chicken adobo');

      // singleDish intent collapses the parts into one logged entry.
      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.grams, closeTo(247, 2));
      // 268 kcal × (247/180) ≈ 368 — the mass that went missing comes back.
      expect(entries.first.calories, _calApprox(368));
    });

    test('weight attached to one ingredient does not rescale the others',
        () async {
      // "eggs with 100g sardines" weighs the sardines only. Treating it as a
      // total would shrink the eggs to make room, which is the opposite error.
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'eggs', grams: 120, macros: _macros(172, 15, 1, 12)),
            _extracted(
                name: 'sardines', grams: 60, macros: _macros(125, 12, 0, 8)),
          ],
        ),
      );

      await p.parseChat('eggs with 100g sardines');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(2));
      // Eggs untouched at the model's estimate...
      expect(entries[0].grams, closeTo(120, 1));
      expect(entries[0].calories, _calApprox(172));
      // ...sardines corrected to the stated 100g (125 × 100/60 ≈ 208).
      expect(entries[1].grams, closeTo(100, 1));
      expect(entries[1].calories, _calApprox(208));
    });

    test('canonical USDA name not split — "Egg, Whole, Cooked, Scrambled 100g"',
        () async {
      // The Dart canonical-USDA guard collapses the response to one item
      // even if cloud incorrectly decomposes it.
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(name: 'Egg', grams: 40, macros: _macros(57, 5, 0, 4)),
            _extracted(name: 'Whole', grams: 30, macros: _macros(43, 4, 0, 3)),
            _extracted(
                name: 'Scrambled', grams: 30, macros: _macros(43, 4, 0, 3)),
          ],
        ),
      );

      await p.parseChat('Egg, Whole, Cooked, Scrambled 100g');

      expect(p.todayLog.allEntries, hasLength(1));
    });

    test('multi-item meal — separate entries with correct DB-scaled kcal',
        () async {
      // Rice: 200g × 130/100 = 260 kcal.
      // Chicken: 150g × 165/100 = 248 kcal.
      const riceId = 'usda-rice';
      const chickenId = 'usda-chicken';
      final rice = _dbEntry(
          id: riceId,
          name: 'Rice, White, Cooked',
          cal: 130,
          protein: 2.7,
          carbs: 28,
          fat: 0.3);
      final chicken = _dbEntry(
          id: chickenId,
          name: 'Chicken Breast, Cooked',
          cal: 165,
          protein: 31,
          carbs: 0,
          fat: 3.6);

      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(db.getById(riceId)).thenAnswer((_) async => rice);
      when(db.getById(chickenId)).thenAnswer((_) async => chicken);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'rice', grams: 200, foodId: riceId, confidence: 0.90),
            _extracted(
                name: 'chicken',
                grams: 150,
                foodId: chickenId,
                confidence: 0.90),
          ],
        ),
      );

      await p.parseChat('200g rice and 150g chicken');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(2));
      expect(
          entries
              .firstWhere((e) => e.name.toLowerCase().contains('rice'))
              .calories,
          _calApprox(260));
      expect(
          entries
              .firstWhere((e) => e.name.toLowerCase().contains('chicken'))
              .calories,
          _calApprox(248));
    });

    // ── Fallthrough ─────────────────────────────────────────────────────────

    test('cloud returns null — falls to Path C keyword-density', () async {
      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(cloudAi.parseFoodWithCandidates(any, any))
          .thenAnswer((_) async => null);

      await p.parseChat('100g white rice');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.estimationSource, EstimationSource.keywordDensity);
    });

    test('confident pick (confidence ≥ 0.70) — resolves from DB, tags cloudAi',
        () async {
      const foodId = 'some-db-food';
      final entry =
          _dbEntry(id: foodId, name: 'Some Food', cal: 200, protein: 10);

      final p = await _makePresenter(cloudAi: cloudAi, foodDb: db);
      _baseCloudStubs();
      when(db.getById(foodId)).thenAnswer((_) async => entry);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'something',
                grams: 100,
                foodId: foodId,
                confidence: 0.75),
          ],
        ),
      );

      await p.parseChat('something');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.estimationSource, EstimationSource.cloudAi);
      expect(entries.first.calories, _calApprox(200));
    });
  });

  // ── PATH B: On-device AI ────────────────────────────────────────────────────

  group('Path B — On-Device AI', () {
    late MockAiCoachService localAi;
    late MockFoodDbService db;

    setUp(() {
      localAi = MockAiCoachService();
      db = MockFoodDbService();
    });

    void _baseLocalStubs() {
      when(localAi.isAvailable).thenReturn(true);
      when(localAi.tier).thenReturn(AiCoachTier.onDevice);
      when(localAi.downloadProgress).thenReturn(null);
      when(db.search(any)).thenAnswer((_) async => []);
      when(db.getById(any)).thenAnswer((_) async => null);
    }

    test('on-device picks DB candidate — tags localAi', () async {
      // 1 boiled egg ≈ 57 g, 155 kcal/100g → ~88 kcal.
      const eggId = 'usda-egg';
      final dbEntry = _dbEntry(
          id: eggId,
          name: 'Egg, Whole, Boiled',
          cal: 155,
          protein: 13,
          carbs: 1.1,
          fat: 11);

      final p = await _makePresenter(localAi: localAi, foodDb: db);
      _baseLocalStubs();
      when(db.search(any)).thenAnswer((_) async => [dbEntry]);
      when(db.getById(eggId)).thenAnswer((_) async => dbEntry);
      when(localAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.itemsList,
          items: [
            _extracted(
                name: 'boiled egg', grams: 57, foodId: eggId, confidence: 0.88),
          ],
        ),
      );

      await p.parseChat('1 boiled egg');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.estimationSource, EstimationSource.localAi);
      expect(entries.first.calories, _calApprox(88));
    });

    test('on-device returns null — falls to Path C', () async {
      final p = await _makePresenter(localAi: localAi, foodDb: db);
      _baseLocalStubs();
      when(localAi.parseFoodWithCandidates(any, any))
          .thenAnswer((_) async => null);

      await p.parseChat('100g white rice');

      expect(p.todayLog.allEntries, hasLength(1));
      expect(p.todayLog.allEntries.first.estimationSource,
          EstimationSource.keywordDensity);
    });
  });

  // ── PATH C: No-AI NLP fallback ──────────────────────────────────────────────

  group('Path C — NLP keyword fallback (no AI)', () {
    test('gram-explicit input — entry logged with keywordDensity source',
        () async {
      final p = await _makePresenter();
      await p.parseChat('100g chicken breast');

      final entries = p.todayLog.allEntries;
      expect(entries, hasLength(1));
      expect(entries.first.estimationSource, EstimationSource.keywordDensity);
      expect(entries.first.grams, closeTo(100, 5));
      expect(entries.first.calories, greaterThan(0));
    });

    test('"2 eggs" — non-gram unit produces an entry', () async {
      final p = await _makePresenter();
      await p.parseChat('2 eggs');

      expect(p.todayLog.allEntries, isNotEmpty);
      expect(p.todayLog.allEntries.first.calories, greaterThan(0));
    });

    test('"1 pc fried chicken" — piece count produces an entry', () async {
      final p = await _makePresenter();
      await p.parseChat('1 pc fried chicken');

      expect(p.todayLog.allEntries, isNotEmpty);
      expect(p.todayLog.allEntries.first.calories, greaterThan(0));
    });

    test('unrecognised gibberish — no crash; either entry or chatParseError',
        () async {
      final p = await _makePresenter();
      await p.parseChat('xyzzy foo blorb 9999');

      // Should not throw. If no entry logged, error is set.
      if (p.todayLog.allEntries.isEmpty) {
        expect(p.chatParseError, isNotNull);
      }
    });

    test('calorie total increments after logging', () async {
      final p = await _makePresenter();
      final before = p.todayCalories;
      await p.parseChat('100g chicken breast');
      expect(p.todayCalories, greaterThan(before));
    });
  });

  // ── DELETE + UNDO (Nudgr nutrition redesign) ──────────────────────────────────

  group('Delete + undo', () {
    test('restoreChatMessage re-adds the entry and its calories', () async {
      final p = await _makePresenter();
      await p.parseChat('100g chicken breast');
      expect(p.chatMessages, hasLength(1));

      final msg = p.chatMessages.single;
      final calWith = p.todayCalories;
      expect(calWith, greaterThan(0));

      await p.removeChatMessage(msg.id);
      expect(p.chatMessages, isEmpty);
      expect(p.todayLog.allEntries, isEmpty);
      expect(p.todayCalories, 0);

      await p.restoreChatMessage(msg);
      expect(p.chatMessages, hasLength(1));
      expect(p.chatMessages.single.id, msg.id);
      expect(p.todayLog.allEntries, hasLength(1));
      expect(p.todayCalories, calWith);
    });

    test('restoreChatMessage is a no-op if the message is still present',
        () async {
      final p = await _makePresenter();
      await p.parseChat('100g chicken breast');
      final msg = p.chatMessages.single;

      await p.restoreChatMessage(msg); // not removed — must not duplicate
      expect(p.chatMessages, hasLength(1));
      expect(p.todayLog.allEntries, hasLength(1));
    });
  });

  // ── COMPOSER REVIEW FLOW (resolve → preview → commit) ─────────────────────────

  group('Composer review flow', () {
    test('previewChat resolves WITHOUT logging', () async {
      final p = await _makePresenter();
      await p.previewChat('100g chicken breast');

      expect(p.hasPendingChat, isTrue);
      expect(p.pendingChatEntries, isNotEmpty);
      // Nothing committed yet — log + feed are still empty.
      expect(p.todayLog.allEntries, isEmpty);
      expect(p.chatMessages, isEmpty);
      expect(p.todayCalories, 0);
    });

    test('commitPendingChat logs the reviewed estimate', () async {
      final p = await _makePresenter();
      await p.previewChat('100g chicken breast');
      final kcal = p.pendingChatEntries.fold<int>(0, (s, e) => s + e.calories);

      await p.commitPendingChat();

      expect(p.hasPendingChat, isFalse);
      expect(p.todayLog.allEntries, hasLength(1));
      expect(p.chatMessages, hasLength(1)); // creates the log-entry row
      expect(p.todayCalories, kcal);
    });

    test('discardPendingChat drops the estimate without logging', () async {
      final p = await _makePresenter();
      await p.previewChat('100g chicken breast');
      expect(p.hasPendingChat, isTrue);

      p.discardPendingChat();

      expect(p.hasPendingChat, isFalse);
      expect(p.todayLog.allEntries, isEmpty);
      expect(p.chatMessages, isEmpty);
    });

    test('CONTROL: two atomic parseChat calls are additive', () async {
      final p = await _makePresenter();
      await p.parseChat('100g chicken breast');
      await p.parseChat('100g white rice');
      expect(p.chatMessages, hasLength(2));
      expect(p.todayLog.allEntries, hasLength(2));
    });

    test('logging two meals via the composer is ADDITIVE', () async {
      final p = await _makePresenter();

      await p.previewChat('100g chicken breast');
      await p.commitPendingChat();

      await p.previewChat('100g white rice');
      await p.commitPendingChat();

      // Both meals must survive — the second must not replace the first.
      expect(p.chatMessages, hasLength(2));
      expect(p.todayLog.allEntries, hasLength(2));
    });

    test('previewChat ACCUMULATES a second item into the pending estimate',
        () async {
      final p = await _makePresenter();

      await p.previewChat('100g chicken breast');
      final firstCount = p.pendingChatEntries.length;
      final firstKcal = p.pendingChatTotalCalories;
      expect(firstCount, greaterThan(0));

      // Second item BEFORE committing — must add to the estimate, not replace.
      await p.previewChat('100g white rice');

      expect(p.hasPendingChat, isTrue);
      expect(p.pendingChatEntries.length, greaterThan(firstCount));
      expect(p.pendingChatTotalCalories, greaterThan(firstKcal));
      // Still nothing logged until commit.
      expect(p.todayLog.allEntries, isEmpty);

      // Committing the merged estimate produces ONE combined log row.
      await p.commitPendingChat();
      expect(p.chatMessages, hasLength(1));
      expect(p.todayLog.allEntries.length, greaterThan(firstCount));
    });

    test('recomputePendingChatEntry re-resolves and keeps the typed name',
        () async {
      final p = await _makePresenter();
      await p.previewChat('100g chicken breast');
      expect(p.pendingChatEntries, isNotEmpty);

      await p.recomputePendingChatEntry(0, 'Grilled chicken');

      // The user's typed name is kept as the label…
      expect(p.pendingChatEntries.first.name, 'Grilled chicken');
      // …and nothing is committed by editing.
      expect(p.hasPendingChat, isTrue);
      expect(p.todayLog.allEntries, isEmpty);
    });

    test('recomputePendingChatEntry ignores empty name / bad index', () async {
      final p = await _makePresenter();
      await p.previewChat('100g chicken breast');
      final original = p.pendingChatEntries.first.name;

      await p.recomputePendingChatEntry(0, '   '); // empty after trim
      await p.recomputePendingChatEntry(5, 'Nope'); // out of range

      expect(p.pendingChatEntries.first.name, original);
    });
  });

  // ── TIER PRIORITY ───────────────────────────────────────────────────────────

  group('Tier priority — cloud > local > NLP', () {
    late MockAiCoachService cloudAi;
    late MockAiCoachService localAi;
    late MockFoodDbService db;

    setUp(() {
      cloudAi = MockAiCoachService();
      localAi = MockAiCoachService();
      db = MockFoodDbService();
      when(cloudAi.isAvailable).thenReturn(true);
      when(cloudAi.tier).thenReturn(AiCoachTier.cloud);
      when(cloudAi.downloadProgress).thenReturn(null);
      when(localAi.isAvailable).thenReturn(true);
      when(localAi.tier).thenReturn(AiCoachTier.onDevice);
      when(localAi.downloadProgress).thenReturn(null);
    });

    test('cloud available → cloud runs, local never called', () async {
      final p =
          await _makePresenter(localAi: localAi, cloudAi: cloudAi, foodDb: db);
      when(db.search(any)).thenAnswer((_) async => []);
      when(db.getById(any)).thenAnswer((_) async => null);
      when(cloudAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(
                name: 'chicken', grams: 100, macros: _macros(165, 31, 0, 3.6)),
          ],
        ),
      );

      await p.parseChat('100g chicken');

      verifyNever(localAi.parseFoodWithCandidates(any, any));
      verify(cloudAi.parseFoodWithCandidates(any, any)).called(1);
      expect(p.todayLog.allEntries.first.estimationSource,
          EstimationSource.cloudAi);
    });

    test('cloud returns null → local AI runs', () async {
      const eggId = 'usda-egg';
      final dbEntry = _dbEntry(
          id: eggId,
          name: 'Egg, Whole',
          cal: 143,
          protein: 12,
          carbs: 0.7,
          fat: 9.5);

      final p =
          await _makePresenter(localAi: localAi, cloudAi: cloudAi, foodDb: db);
      when(db.search(any)).thenAnswer((_) async => [dbEntry]);
      when(db.getById(eggId)).thenAnswer((_) async => dbEntry);
      when(cloudAi.parseFoodWithCandidates(any, any))
          .thenAnswer((_) async => null);
      when(localAi.parseFoodWithCandidates(any, any)).thenAnswer(
        (_) async => ParseFoodResult(
          intent: ParseIntent.singleDish,
          items: [
            _extracted(name: 'egg', grams: 57, foodId: eggId, confidence: 0.90),
          ],
        ),
      );

      await p.parseChat('1 egg');

      verify(localAi.parseFoodWithCandidates(any, any)).called(1);
      expect(p.todayLog.allEntries.first.estimationSource,
          EstimationSource.localAi);
    });

    test('both AI unavailable → NLP fallback only, no AI calls made', () async {
      when(cloudAi.isAvailable).thenReturn(false);
      when(localAi.isAvailable).thenReturn(false);

      final p =
          await _makePresenter(localAi: localAi, cloudAi: cloudAi, foodDb: db);
      when(db.search(any)).thenAnswer((_) async => []);

      await p.parseChat('100g rice');

      verifyNever(cloudAi.parseFoodWithCandidates(any, any));
      verifyNever(localAi.parseFoodWithCandidates(any, any));
      expect(p.todayLog.allEntries.first.estimationSource,
          EstimationSource.keywordDensity);
    });
  });
}
