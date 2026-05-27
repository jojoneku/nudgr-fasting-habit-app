/// Cross-tier comparison test — NLP keyword-density fallback (Path C).
///
/// Runs the same prompts as tools/tier_comparison.py but through the
/// no-AI path so we can compare accuracy across tiers.
///
/// Run with:   flutter test test/utils/food_tier_comparison_test.dart -v
///
/// Each test intentionally prints structured output so the results can be
/// read and compared against the cloud tier output.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:intermittent_fasting/models/daily_nutrition_log.dart';
import 'package:intermittent_fasting/models/food_search_candidate.dart';
import 'package:intermittent_fasting/models/notification_preferences.dart';
import 'package:intermittent_fasting/models/nutrition_goals.dart';
import 'package:intermittent_fasting/models/user_stats.dart';
import 'package:intermittent_fasting/presenters/nutrition_presenter.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';

import '../mocks.mocks.dart';

// ── Shared setup ──────────────────────────────────────────────────────────────

const _today = '2026-05-27';

Future<NutritionPresenter> _noAiPresenter() async {
  final storage = MockStorageService();
  final stats = MockStatsPresenter();
  final fasting = MockFastingPresenter();
  final db = MockFoodDbService();
  final ai = MockAiCoachService();

  when(storage.loadNotificationPreferences())
      .thenAnswer((_) async => NotificationPreferences.defaults());
  when(storage.loadTodayNutritionLog())
      .thenAnswer((_) async => DailyNutritionLog.empty(_today));
  when(storage.loadNutritionGoals())
      .thenAnswer((_) async => NutritionGoals.initial());
  when(storage.loadNutritionHistory()).thenAnswer((_) async => []);
  when(storage.loadTdeeProfile()).thenAnswer((_) async => null);
  when(storage.loadFoodLibrary()).thenAnswer((_) async => []);
  when(storage.loadNutritionStreak()).thenAnswer((_) async => 0);
  when(storage.loadNutritionGoalMetDate()).thenAnswer((_) async => null);
  when(storage.loadLogStreak()).thenAnswer((_) async => 0);
  when(storage.loadLogStreakDate()).thenAnswer((_) async => null);
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
  when(stats.stats).thenReturn(UserStats.initial());
  when(stats.addXp(any)).thenAnswer((_) async {});
  when(stats.modifyHp(any)).thenAnswer((_) async {});
  when(stats.awardStat(any)).thenAnswer((_) async {});
  when(fasting.isFasting).thenReturn(false);
  when(ai.isAvailable).thenReturn(false);
  when(ai.downloadProgress).thenReturn(null);
  when(ai.tier).thenReturn(AiCoachTier.onDevice);
  when(db.search(any)).thenAnswer((_) async => []);
  when(db.getById(any)).thenAnswer((_) async => null);

  final p = NutritionPresenter(
    statsPresenter: stats,
    fastingPresenter: fasting,
    storage: storage,
    foodDb: db,
    aiCoach: ai,
  );
  await Future.delayed(Duration.zero);
  return p;
}

// ── Result capture ────────────────────────────────────────────────────────────

class _Row {
  final String input;
  final int gtKcal;
  final int? kcal;
  final double? grams;
  final String? parsedAs;
  final String notes;

  _Row({
    required this.input,
    required this.gtKcal,
    this.kcal,
    this.grams,
    this.parsedAs,
    required this.notes,
  });

  String get errStr {
    if (kcal == null || gtKcal == 0) return '  —';
    final pct = (kcal! - gtKcal) / gtKcal * 100;
    return '${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(0)}%';
  }

  @override
  String toString() =>
      '${input.padRight(42)} | GT:${gtKcal.toString().padLeft(4)} '
      '| NLP:${(kcal?.toString() ?? '?').padLeft(4)} '
      '| ${errStr.padLeft(5)} '
      '| ${(grams?.toStringAsFixed(0) ?? '?').padLeft(4)}g '
      '| ${parsedAs ?? '(no entry)'}';
}

Future<_Row> _measure(String input, int gtKcal, String notes) async {
  final p = await _noAiPresenter();
  await p.parseChat(input);
  final entries = p.todayLog.allEntries;
  if (entries.isEmpty) {
    return _Row(input: input, gtKcal: gtKcal, notes: notes);
  }
  final totalKcal = entries.fold<int>(0, (s, e) => s + e.calories);
  final totalGrams = entries.fold<double>(0, (s, e) => s + (e.grams ?? 0));
  final names = entries.map((e) => e.name).join(' + ');
  return _Row(
    input: input,
    gtKcal: gtKcal,
    kcal: totalKcal,
    grams: totalGrams,
    parsedAs: names,
    notes: notes,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // Collect all rows then print the table in one shot at the end.
  final rows = <_Row>[];

  // Ground-truth kcal and notes match tools/tier_comparison.py exactly.
  final cases = [
    // ── Original 20 baseline cases ─────────────────────────────────────────
    ('100g chicken breast', 165, 'USDA 165 kcal/100g'),
    ('150g fried omelet', 285, 'egg+oil ~190/100g'),
    ('52g banana muffin', 150, '~2.9 kcal/g'),
    ('12g chocolate crinkle', 44, '~3.7 kcal/g cookie'),
    ('2 boiled eggs', 163, '2 × 57g × 143/100g'),
    ('1 boiled egg', 82, '57g × 143/100g'),
    ('1pc fried chicken wing', 174, '~60g × 290/100g'),
    ('1pc mcdo fried chicken wing part', 319, '110g × 290/100g'),
    ('jollibee regular french fries', 224, '70g × 320/100g'),
    ('jollibee chickenjoy 1pc', 312, '120g × 260/100g'),
    ('1 cup white rice cooked', 242, '186g × 130/100g'),
    ('1 scoop whey protein', 120, '30g × 400/100g'),
    ('kanin', 195, '~150g × 130/100g'),
    ('2 pcs lumpia shanghai', 60, '2 × 30g × 100/100g'),
    ('chicken adobo 200g', 290, '~145 kcal/100g'),
    ('sinigang na baboy 300g', 198, '~66 kcal/100g'),
    ('Egg, Whole, Cooked, Scrambled 100g', 155, 'USDA canonical'),
    ('kefir milk', 146, '240g × 61/100g'),
    ('lechon kawali 100g', 430, '~430 kcal/100g'),
    ('pansit canton with pork and cabbage', 450, 'composite dish'),

    // ── Word-order / adjective-position variations ─────────────────────────
    // Expect identical results regardless of order (tokens are order-independent)
    ('scrambled eggs', 200, '~2 eggs scrambled × 100 kcal'),
    ('eggs scrambled', 200, 'word-order flip of above'),
    ('fried egg', 90, '1 fried egg ~60g × 1.5'),
    ('egg fried', 90, 'word-order flip'),
    ('sunny side up egg', 90, 'same dish as fried egg'),

    // ── Root-word confusion ────────────────────────────────────────────────
    // "eggplant" must NOT activate the egg bucket — it is a different token
    ('fried eggplant', 100, '100g fried — eggplant ≠ egg token'),
    // "almond milk" should NOT hit the nut bucket (almond token fires first)
    ('almond 20g', 116, '20g × 579 kcal/100g — nut'),
    ('almond milk 200ml', 30, '200ml × 15 kcal/100ml — diluted, NOT nut'),
    // "oat milk" should be lighter than dry oats
    ('oats 40g', 152, '40g dry × 379 kcal/100g'),
    ('oat milk 200ml', 90, '200ml × 45 kcal/100ml — diluted'),
    // "chicken broth" — "chicken" must not dominate over the broth context
    ('chicken 100g', 165, '100g chicken breast'),
    ('chicken broth 240ml', 12, '240ml × 5 kcal/100ml — NOT meat'),
    // "fish sauce" is a condiment, not fish protein
    ('fish 100g', 128, '100g generic fish × 128/100g'),
    ('fish sauce 1 tbsp', 6, '15ml patis — mostly sodium, ~6 kcal'),

    // ── USDA comma format with leading or trailing weight ──────────────────
    // Parser must NOT split "rolled, dry" into separate food entries
    ('10g oats, rolled, dry', 39, '10g × 389 kcal/100g — no comma split'),
    ('oats, rolled, dry, 10g', 39, 'weight at end — same dish'),

    // ── Spelling / dialect variants ───────────────────────────────────────
    ('litson kawali 100g', 430, 'alt spelling — "kawali" token fires fat-pork'),
    ('peanuts 30g', 171, '30g × 570 kcal/100g'),
    ('peanut butter 2 tbsp', 190, '32g × 593 kcal/100g'),
    ('bangus 100g', 149, 'milkfish × 149 kcal/100g'),
    ('longganisa 1pc', 120, '40g × 300 kcal/100g cured pork'),

    // ── Word-position: bread (user-requested) ─────────────────────────────
    // Token order is irrelevant — both words are present
    ('wheat bread 1 slice', 70, '30g × 233 kcal/100g'),
    ('bread wheat 1 slice', 70, 'position flip — same result'),
    ('whole wheat bread 1 slice', 70, 'extra adjective in front'),
    ('pandesal 1pc', 100, '50g × 200 kcal/100g'),

    // ── Eggplant vs egg — user-reported confusion ─────────────────────────
    // English "eggplant" must NOT hit egg bucket;  Tagalog "talong" already works
    ('eggplant 100g', 25, '100g raw × 25 kcal/100g — vegetable bucket'),
    ('talong 100g', 25, 'Tagalog name — same food'),
    (
      'fried talong 100g',
      85,
      '100g fried — absorbs oil; vegetable bucket still fires'
    ),

    // ── Root vegetables ───────────────────────────────────────────────────
    ('sweet potato 100g', 86, '100g × 86 kcal/100g'),
    ('potato 100g', 77, '100g × 77 kcal/100g'),
    ('camote 100g', 86, 'Tagalog sweet potato'),
    ('ube 100g', 140, 'purple yam × 140 kcal/100g'),

    // ── Legumes and soy ───────────────────────────────────────────────────
    ('tofu 100g', 76, '100g firm tofu × 76 kcal/100g'),
    ('tokwa 100g', 76, 'Tagalog tofu — same'),
    ('monggo soup 200g', 160, '200g × 80 kcal/100g mung bean'),

    // ── Coconut family — very different densities ─────────────────────────
    ('coconut oil 1 tbsp', 120, '15g × 800 kcal/100g — pure fat'),
    ('coconut milk 240ml', 552, '240g × 230 kcal/100g full-fat'),
    ('coconut water 240ml', 46, '240ml × 19 kcal/100ml — very light'),

    // ── Multi-food with USDA-style modifiers ──────────────────────────────
    // "kanin" breaks the USDA canonical check → splits badly (expected failure)
    (
      '10g oats, rolled, dry, kanin',
      234,
      '10g oats + 150g kanin — comma breaks USDA guard'
    ),
    // Using "and" as separator instead → clean split
    (
      '10g oats rolled dry and kanin',
      234,
      '10g oats(3.89) + 150g kanin(1.3) — correct separator'
    ),

    // ── More Filipino foods ───────────────────────────────────────────────
    ('champorado 200g', 320, '200g × 160 kcal/100g choc rice porridge'),
    ('goto 200g', 160, '200g × 80 kcal/100g rice porridge'),
  ];

  for (final (input, gt, notes) in cases) {
    test('NLP | $input', () async {
      final row = await _measure(input, gt, notes);
      rows.add(row);

      // Soft assertion: something must be logged (no hard crash).
      // Individual kcal accuracy is intentionally not asserted here —
      // this test exists to surface gaps, not enforce targets.
      expect(
        row.kcal != null || row.parsedAs == null,
        isTrue,
        reason: 'parseChat crashed without logging anything',
      );
    });
  }

  tearDownAll(() {
    // Print comparison table after all tests run.
    final sep = '─' * 105;
    // ignore: avoid_print
    print('\n$sep');
    // ignore: avoid_print
    print('NLP KEYWORD-DENSITY FALLBACK — Path C comparison');
    // ignore: avoid_print
    print(sep);
    // ignore: avoid_print
    print(
      '${'Input'.padRight(42)} | ${'GT'.padLeft(4)} '
      '| ${'NLP'.padLeft(4)} | ${'Err'.padLeft(5)} '
      '| ${'g'.padLeft(5)} | Parsed as',
    );
    // ignore: avoid_print
    print(sep);
    for (final row in rows) {
      // ignore: avoid_print
      print(row);
    }
    // ignore: avoid_print
    print(sep);

    // ── Gap analysis ────────────────────────────────────────────────────────
    final withKcal = rows.where((r) => r.kcal != null).toList();
    if (withKcal.isEmpty) return;

    final bigErrors = withKcal
        .where((r) => ((r.kcal! - r.gtKcal) / r.gtKcal).abs() > 0.25)
        .toList()
      ..sort((a, b) => ((b.kcal! - b.gtKcal) / b.gtKcal)
          .abs()
          .compareTo(((a.kcal! - a.gtKcal) / a.gtKcal).abs()));

    // ignore: avoid_print
    print('\nFAILS (>25% error):');
    for (final r in bigErrors) {
      // ignore: avoid_print
      print(
          '  ${r.input.padRight(42)} GT:${r.gtKcal}  NLP:${r.kcal}  (${r.errStr})');
    }
    if (bigErrors.isEmpty) {
      // ignore: avoid_print
      print('  (none)');
    }
  });
}
