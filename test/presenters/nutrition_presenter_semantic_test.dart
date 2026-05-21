import 'package:intermittent_fasting/models/notification_preferences.dart';
// Tests for the RAG semantic-search step of NutritionPresenter._resolveOneDbItem.
//
// We exercise the public `parseFoodItemsForTemplate` entry point, which calls
// the same private `_resolveOneDbItem` pipeline used by parseChat() but
// without touching today's log or chat persistence — keeps these focused on
// resolution behaviour.
//
// Strategy: hand-write a minimal fake FoodSemanticSearchService rather than
// regenerate mockito mocks, so this file is self-contained.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:intermittent_fasting/models/ai_chat_message.dart';
import 'package:intermittent_fasting/models/ai_coach_context.dart';
import 'package:intermittent_fasting/models/ai_meal_estimate.dart';
import 'package:intermittent_fasting/models/ai_parsed_food.dart';
import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/finance_parse_result.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/food_db_entry.dart';
import 'package:intermittent_fasting/models/food_parse_result.dart';
import 'package:intermittent_fasting/models/food_search_candidate.dart';
import 'package:intermittent_fasting/models/index_progress.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/food_semantic_search_service.dart';
import '../mocks.mocks.dart';

void main() {
  late MockStorageService mockStorage;
  late MockStatsPresenter mockStats;
  late MockFastingPresenter mockFasting;
  late _FakeAiCoach fakeAi;
  late MockFoodDbService mockFoodDb;
  late _FakeSemanticSearch fakeSemantic;

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  FoodDbEntry yogurtEntry() => const FoodDbEntry(
        id: 'fdc-1',
        name: 'Yogurt, plain, whole milk',
        category: 'Dairy and Egg Products',
        caloriesPer100g: 61,
        proteinPer100g: 3.5,
        carbsPer100g: 4.7,
        fatPer100g: 3.3,
      );

  FoodDbEntry adoboEntry() => const FoodDbEntry(
        id: 'fdc-2',
        name: 'Adobo, chicken',
        category: 'Pinoy Dishes',
        caloriesPer100g: 175,
        proteinPer100g: 19.0,
        carbsPer100g: 1.5,
        fatPer100g: 10.0,
      );

  setUp(() async {
    mockStorage = MockStorageService();
    when(mockStorage.loadNotificationPreferences())
        .thenAnswer((_) async => NotificationPreferences.defaults());
    mockStats = MockStatsPresenter();
    mockFasting = MockFastingPresenter();
    fakeAi = _FakeAiCoach();
    mockFoodDb = MockFoodDbService();
    fakeSemantic = _FakeSemanticSearch();

    when(mockStorage.loadTodayNutritionLog())
        .thenAnswer((_) async => DailyNutritionLog.empty(today()));
    when(mockStorage.loadNutritionGoals())
        .thenAnswer((_) async => NutritionGoals.initial());
    when(mockStorage.loadNutritionHistory()).thenAnswer((_) async => []);
    when(mockStorage.loadTdeeProfile()).thenAnswer((_) async => null);
    when(mockStorage.loadFoodLibrary()).thenAnswer((_) async => []);
    when(mockStorage.loadNutritionStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
    when(mockStorage.loadLogStreak()).thenAnswer((_) async => 0);
    when(mockStorage.loadLogStreakDate()).thenAnswer((_) async => null);
    when(mockStorage.loadPersonalDict()).thenAnswer((_) async => []);
    when(mockStorage.loadFoodFeedback()).thenAnswer((_) async => []);
    when(mockStorage.saveFoodFeedback(any)).thenAnswer((_) async {});
    when(mockStorage.loadChatMessagesRaw(any)).thenAnswer((_) async => []);

    when(mockFasting.isFasting).thenReturn(false);
  });

  NutritionPresenter buildPresenter({
    required _FakeSemanticSearch semantic,
  }) {
    final p = NutritionPresenter(
      statsPresenter: mockStats,
      fastingPresenter: mockFasting,
      storage: mockStorage,
      foodDb: mockFoodDb,
      aiCoach: fakeAi,
      semanticSearch: semantic,
    );
    return p;
  }

  group('semantic resolution', () {
    test('high-confidence top hit short-circuits FTS5', () async {
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.92,
          source: SearchSource.semantic,
        ),
      ];
      // FTS5 should NOT be called when semantic is high-confidence.
      when(mockFoodDb.search(any))
          .thenThrow(StateError('FTS5 should not be called'));

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter
          .parseFoodItemsForTemplate('creamy yogurt with berries');

      // Option A: query is non-lexical against the DB entry, so we preserve
      // the user's typed name (title-cased) and inherit the DB's macros.
      expect(entries, hasLength(1));
      expect(entries.first.name, 'Creamy Yogurt With Berries');
      // Macros inherit from yogurtEntry (61 kcal/100g × default 100g).
      expect(entries.first.calories, 61);
      expect(fakeSemantic.lastQuery, 'creamy yogurt with berries');
    });

    test('low-confidence semantic falls through to FTS5', () async {
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.40, // below _semanticAcceptable (0.55)
          source: SearchSource.semantic,
        ),
      ];
      when(mockFoodDb.search(any)).thenAnswer((_) async => [adoboEntry()]);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('adobo');

      // Semantic was tried but fell through; FTS5 returned adobo.
      expect(entries, hasLength(1));
      expect(entries.first.name, 'Adobo, Chicken');
    });

    test('mid-confidence + AI unavailable falls through to FTS5', () async {
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.65, // ambiguous band
          source: SearchSource.semantic,
        ),
      ];
      fakeAi.available = false;
      when(mockFoodDb.search(any)).thenAnswer((_) async => [adoboEntry()]);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('adobo');

      expect(entries.first.name, 'Adobo, Chicken');
    });

    test('mid-confidence + AI picks top via disambiguateFood', () async {
      final candidates = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.65,
          source: SearchSource.semantic,
        ),
        FoodSearchCandidate(
          entry: adoboEntry(),
          score: 0.61,
          source: SearchSource.semantic,
        ),
      ];
      fakeSemantic.results = candidates;
      fakeAi.available = true;
      fakeAi.disambiguation =
          const FoodDisambiguation(foodId: 'fdc-2', confidence: 0.85);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('adobo');

      expect(entries.first.name, 'Adobo, Chicken');
      verifyNever(mockFoodDb.search(any));
    });

    test('mid-confidence + AI low-confidence falls through to FTS5', () async {
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.65,
          source: SearchSource.semantic,
        ),
      ];
      fakeAi.available = true;
      fakeAi.disambiguation = const FoodDisambiguation(
        foodId: 'fdc-1',
        confidence: 0.40, // below _llmRerankConfidence (0.70)
      );
      when(mockFoodDb.search(any)).thenAnswer((_) async => [adoboEntry()]);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('adobo');

      expect(entries.first.name, 'Adobo, Chicken');
    });

    test('semantic search disabled when service is null', () async {
      // No semanticSearch arg — presenter should bypass step 1 entirely.
      when(mockFoodDb.search(any)).thenAnswer((_) async => [yogurtEntry()]);

      final p = NutritionPresenter(
        statsPresenter: mockStats,
        fastingPresenter: mockFasting,
        storage: mockStorage,
        foodDb: mockFoodDb,
        aiCoach: fakeAi,
      );
      await Future<void>.delayed(Duration.zero);

      final entries = await p.parseFoodItemsForTemplate('yogurt');

      expect(entries.first.name, 'Yogurt, Plain, Whole Milk');
    });

    test('weak FTS5 match falls through (red rice ≠ sapin sapin)', () async {
      // Reproduces the user-reported bug: querying "red rice" used to log
      // "Sapin-sapin (rice cake)" with confidence 0.5 because pickBest
      // returned a positive score for the partial token overlap. After the
      // gate, FTS5 should reject this and the entry falls through to the
      // density-bucket fallback (in this no-AI test setup).
      fakeSemantic.ready = false; // skip semantic step
      const sapinSapin = FoodDbEntry(
        id: 'fdc-99',
        name: 'Sapin-sapin (rice cake)',
        category: 'Pinoy Sweets',
        caloriesPer100g: 320,
        carbsPer100g: 60,
      );
      when(mockFoodDb.search(any)).thenAnswer((_) async => [sapinSapin]);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('red rice');

      // The entry should NOT be logged as sapin-sapin. Without a real DB hit
      // the keyword-density fallback kicks in and the name is preserved as
      // "red rice" (not silently rewritten).
      expect(entries.first.name, 'Red Rice');
      expect(entries.first.name, isNot('Sapin-sapin (rice cake)'));
    });

    test('semantic non-lexical match keeps user name + DB macros (Option A)',
        () async {
      // "red rice" embeds close to brown rice in vector space, but the words
      // don't lexically match. Expect: log "Red Rice" (user's name, title-cased)
      // with brown-rice macros (real nutrition data, faithful naming).
      const brownRice = FoodDbEntry(
        id: 'fdc-100',
        name: 'rice, brown, cooked', // intentionally lowercase to test casing
        category: 'Grains',
        caloriesPer100g: 112,
        proteinPer100g: 2.6,
        carbsPer100g: 23.5,
        fatPer100g: 0.9,
      );
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: brownRice,
          score: 0.87,
          source: SearchSource.semantic,
        ),
      ];

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('red rice');

      expect(entries.first.name, 'Red Rice',
          reason: 'should preserve and title-case user name');
      // Macros borrowed from brown rice (real DB data).
      expect(entries.first.calories, greaterThan(0));
    });

    test('semantic lexical match uses DB name (title-cased)', () async {
      // "yogurt" lexically matches "Yogurt, plain, whole milk" (every query
      // word appears in entry words). Expect: log the DB name, title-cased.
      const yogurt = FoodDbEntry(
        id: 'fdc-1',
        name: 'yogurt, plain, whole milk',
        caloriesPer100g: 61,
      );
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurt,
          score: 0.92,
          source: SearchSource.semantic,
        ),
      ];

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('yogurt');

      expect(entries.first.name, 'Yogurt, Plain, Whole Milk');
    });

    test('semantic disabled when isReady=false', () async {
      fakeSemantic.ready = false;
      // Even with cached results, search is skipped because isReady is false.
      fakeSemantic.results = [
        FoodSearchCandidate(
          entry: yogurtEntry(),
          score: 0.99,
          source: SearchSource.semantic,
        ),
      ];
      when(mockFoodDb.search(any)).thenAnswer((_) async => [adoboEntry()]);

      final presenter = buildPresenter(semantic: fakeSemantic);
      await Future<void>.delayed(Duration.zero);

      final entries = await presenter.parseFoodItemsForTemplate('adobo');

      // FTS5 path used.
      expect(entries.first.name, 'Adobo, Chicken');
      expect(fakeSemantic.lastQuery, isNull);
    });
  });
}

/// Hand-written fakes — avoid regenerating mockito mocks for an interface
/// addition (`disambiguateFood`) made in the same change as these tests.

class _FakeAiCoach implements AiCoachService {
  bool available = false;
  FoodDisambiguation? disambiguation;

  @override
  bool get isAvailable => available;

  @override
  int? get downloadProgress => null;

  @override
  AiCoachTier get tier => AiCoachTier.onDevice;

  @override
  Future<void> downloadModel({
    void Function(int progress)? onProgress,
  }) async {}

  @override
  Stream<String> respond({
    required List<AiChatMessage> messages,
    required AiCoachContext context,
    bool isThinking = false,
  }) async* {}

  @override
  Future<FoodParseResult?> parseFood(String description) async => null;

  @override
  Future<List<ExtractedFoodItem>?> extractFoodItems(String text) async => null;

  @override
  Future<AiMealEstimate?> estimateMacros(String description) async => null;

  @override
  Future<List<AiItemEstimate>?> estimateMacrosForItems(
    List<AiParsedFood> items,
  ) async =>
      null;

  @override
  Future<List<AiParsedFood>?> normalizeFoodInput(
    List<String> fragments,
  ) async =>
      null;

  @override
  Future<FoodDisambiguation?> disambiguateFood(
    String userQuery,
    List<FoodSearchCandidate> candidates,
  ) async =>
      disambiguation;

  @override
  Future<ClassifierStep?> runFinanceClassifierStep({
    required List<LedgerChatTurn> conversation,
    required PreparseResult preparse,
    required List<FinanceCategory> categories,
    required List<FinancialAccount> accounts,
    required Map<String, String> learnedMappings,
    required int turnCount,
  }) async =>
      null;

  @override
  void dispose() {}
}

class _FakeSemanticSearch implements FoodSemanticSearchService {
  bool ready = true;
  List<FoodSearchCandidate> results = const [];
  String? lastQuery;

  @override
  bool get isReady => ready;

  @override
  bool get isIndexing => false;

  @override
  IndexProgress get progress => const IndexProgress.empty();

  @override
  Stream<IndexProgress> get progressStream => const Stream.empty();

  @override
  Future<List<FoodSearchCandidate>> search(String query, {int k = 5}) async {
    lastQuery = query;
    return results.take(k).toList();
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> buildIndex({
    int batchSize = 32,
    void Function(IndexProgress)? onProgress,
  }) async {}

  @override
  Future<void> rebuildIndex({
    int batchSize = 32,
    void Function(IndexProgress)? onProgress,
  }) async {}

  @override
  Future<void> dispose() async {}
}
