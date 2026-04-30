import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/food_db_entry.dart';
import 'package:intermittent_fasting/utils/food_match_scorer.dart';

FoodDbEntry _entry(String name) => FoodDbEntry(
      id: name,
      name: name,
      caloriesPer100g: 100,
    );

void main() {
  group('FoodMatchScorer.isLearnableMatch', () {
    test('exact name match passes', () {
      expect(
        FoodMatchScorer.isLearnableMatch(_entry('Chicken Breast'),
            'chicken breast'),
        isTrue,
      );
    });

    test('USDA-style name with prep word passes', () {
      expect(
        FoodMatchScorer.isLearnableMatch(
            _entry('Chicken Breast, Cooked'), 'chicken breast'),
        isTrue,
      );
    });

    test('single-word query against USDA-style name passes', () {
      expect(
        FoodMatchScorer.isLearnableMatch(_entry('Salmon, Cooked'), 'salmon'),
        isTrue,
      );
    });

    test('weak partial match is rejected — egg noodles vs scrambled eggs', () {
      // The classic poisoning case the user surfaced.
      expect(
        FoodMatchScorer.isLearnableMatch(
            _entry('Scrambled Eggs with Noodles'), 'egg noodles'),
        isFalse,
      );
    });

    test('transforming word in entry but not query is rejected', () {
      // "rice" must not learn from "Rice Cake" — they have different macros.
      expect(
        FoodMatchScorer.isLearnableMatch(_entry('Rice Cake'), 'rice'),
        isFalse,
      );
    });

    test('transforming word present in both query and entry passes', () {
      expect(
        FoodMatchScorer.isLearnableMatch(
            _entry('Rice Cake, Plain'), 'rice cake'),
        isTrue,
      );
    });

    test('Filipino dish in parenthetical form passes', () {
      // DB stores "Adobong Manok (Chicken Adobo)" — query "chicken adobo"
      // should still find the right whole-word match.
      expect(
        FoodMatchScorer.isLearnableMatch(
            _entry('Adobong Manok (Chicken Adobo)'), 'chicken adobo'),
        isTrue,
      );
    });
  });

  group('FoodMatchScorer.pickBest', () {
    test('exact match wins over partial', () {
      final hits = [_entry('Egg, Raw'), _entry('Egg Noodles, Cooked')];
      expect(
        FoodMatchScorer.pickBest(hits, 'egg noodles')?.name,
        'Egg Noodles, Cooked',
      );
    });

    test('returns null when no positive score', () {
      // No tokens overlap at all.
      final hits = [_entry('Beef Steak')];
      expect(FoodMatchScorer.pickBest(hits, 'banana'), isNull);
    });
  });

  group('FoodMatchScorer.isReasonableNormalization', () {
    test('AI-introduced transforming word is rejected', () {
      // "rice" must not become "fried rice" silently.
      expect(
        FoodMatchScorer.isReasonableNormalization('rice', 'fried rice'),
        isFalse,
      );
    });

    test('legitimate Filipino dish normalization passes', () {
      expect(
        FoodMatchScorer.isReasonableNormalization('adobo', 'chicken adobo'),
        isTrue,
      );
    });

    test('completely different name is rejected', () {
      expect(
        FoodMatchScorer.isReasonableNormalization(
            'chicken adobo', 'beef wellington'),
        isFalse,
      );
    });

    test('identical names pass', () {
      expect(
        FoodMatchScorer.isReasonableNormalization('rice', 'rice'),
        isTrue,
      );
    });
  });
}
