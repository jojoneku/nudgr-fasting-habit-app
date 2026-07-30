import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/models/extracted_food_item.dart';
import 'package:intermittent_fasting/utils/food_gram_reconciler.dart';

/// Unit coverage for the weight-enforcement rules. The pipeline tests prove the
/// end-to-end effect; these pin the individual decisions, including the ones
/// where the right answer is to leave the model alone.
void main() {
  ExtractedFoodItem item(
    String name,
    double grams, {
    double? cal,
    double p = 0,
    double c = 0,
    double f = 0,
  }) =>
      ExtractedFoodItem(
        name: name,
        grams: grams,
        hydeDescription: name,
        rawText: name,
        estimatedMacros: cal == null
            ? null
            : EstimatedMacros(calories: cal, proteinG: p, carbsG: c, fatG: f),
      );

  group('findGramMentions', () {
    test('reads every weight in order', () {
      final m = findGramMentions('166g rice, 81g chicken adobo');
      expect(m.map((e) => e.grams), [166, 81]);
    });

    test('flags a leading weight as describing the whole input', () {
      expect(findGramMentions('247g rice and adobo').single.leadsInput, isTrue);
    });

    test('a weight mid-sentence does not lead', () {
      expect(
        findGramMentions('eggs with 100g sardines').single.leadsInput,
        isFalse,
      );
    });

    test('no weights, no mentions', () {
      expect(findGramMentions('rice and chicken adobo'), isEmpty);
      expect(findGramMentions(''), isEmpty);
    });

    test('ignores non-gram numbers', () {
      expect(findGramMentions('2 eggs and 3 slices of bread'), isEmpty);
    });
  });

  group('single item', () {
    test('user weight overrides the model and scales macros', () {
      final out = reconcileExplicitGrams(
        'French Baker Chocolate Crinkle 12g',
        [item('chocolate crinkle', 40, cal: 160, p: 2, c: 26, f: 5)],
      );
      expect(out.single.grams, closeTo(12, 0.01));
      expect(out.single.estimatedMacros!.calories, closeTo(48, 0.5));
      expect(out.single.estimatedMacros!.carbsG, closeTo(7.8, 0.2));
    });

    test('leaves the model alone when it already agrees', () {
      final original = item('crinkle', 40, cal: 160);
      final out = reconcileExplicitGrams('41g crinkle', [original]);
      expect(identical(out.single, original), isTrue);
    });
  });

  group('per-item weights', () {
    test('each item takes the weight that names it', () {
      final out = reconcileExplicitGrams(
        '166g rice, 81g chicken adobo',
        [
          item('rice', 120, cal: 156),
          item('chicken adobo', 60, cal: 112),
        ],
      );
      expect(out[0].grams, closeTo(166, 0.01));
      expect(out[0].estimatedMacros!.calories, closeTo(215.8, 1));
      expect(out[1].grams, closeTo(81, 0.01));
      expect(out[1].estimatedMacros!.calories, closeTo(151.2, 1));
    });

    test('matches by name, not by position', () {
      final out = reconcileExplicitGrams(
        '81g chicken adobo, 166g rice',
        [
          item('rice', 120, cal: 156),
          item('chicken adobo', 60, cal: 112),
        ],
      );
      expect(out[0].grams, closeTo(166, 0.01), reason: 'rice');
      expect(out[1].grams, closeTo(81, 0.01), reason: 'adobo');
    });

    test('a weight naming nothing recognisable is discarded, not misapplied',
        () {
      // The weight does not lead, so it is ingredient-scoped — and it names a
      // food the model never extracted. Guessing which item it meant would be
      // worse than leaving the model's portions alone.
      final out = reconcileExplicitGrams(
        'rice and adobo, 90g sinigang',
        [item('rice', 120, cal: 156), item('adobo', 60, cal: 112)],
      );
      expect(out[0].grams, 120);
      expect(out[1].grams, 60);
    });

    test('a leading weight over a decomposed dish is still its total', () {
      // "90g sinigang" naming a dish the model broke into components: the
      // components must add up to the weight the user put on the scale.
      final out = reconcileExplicitGrams(
        '90g sinigang',
        [item('pork', 80, cal: 200), item('vegetables', 100, cal: 40)],
      );
      expect(out.fold<double>(0, (s, i) => s + i.grams), closeTo(90, 0.01));
    });
  });

  group('leading total', () {
    test('rescales the split so it sums to the stated weight', () {
      final out = reconcileExplicitGrams(
        '247g rice and chicken adobo',
        [
          item('rice', 120, cal: 156),
          item('chicken adobo', 60, cal: 112),
        ],
      );
      final total = out.fold<double>(0, (s, i) => s + i.grams);
      expect(total, closeTo(247, 0.01));
      // The model's 2:1 split is preserved, only rescaled.
      expect(out[0].grams / out[1].grams, closeTo(2.0, 0.01));
      final kcal =
          out.fold<double>(0, (s, i) => s + i.estimatedMacros!.calories);
      expect(kcal, closeTo(367.7, 2));
    });

    test('corrects an over-shooting split too', () {
      final out = reconcileExplicitGrams(
        '150g eggs with sardines',
        [item('eggs', 200, cal: 286), item('sardines', 100, cal: 208)],
      );
      expect(out.fold<double>(0, (s, i) => s + i.grams), closeTo(150, 0.01));
    });

    test('leaves a split that already adds up', () {
      final items = [
        item('eggs', 90, cal: 129),
        item('sardines', 60, cal: 125)
      ];
      final out = reconcileExplicitGrams('150g eggs with sardines', items);
      expect(identical(out, items), isTrue);
    });
  });

  group('ingredient-scoped weight', () {
    test('applies to that ingredient only', () {
      final out = reconcileExplicitGrams(
        'eggs with 100g sardines',
        [item('eggs', 120, cal: 172), item('sardines', 60, cal: 125)],
      );
      expect(out[0].grams, 120, reason: 'eggs untouched');
      expect(out[1].grams, closeTo(100, 0.01));
      expect(out[1].estimatedMacros!.calories, closeTo(208.3, 1));
    });
  });

  group('safety', () {
    test('no items, nothing to do', () {
      expect(reconcileExplicitGrams('166g rice', const []), isEmpty);
    });

    test('items with no macros still get their weight corrected', () {
      final out = reconcileExplicitGrams('166g rice', [item('rice', 120)]);
      expect(out.single.grams, closeTo(166, 0.01));
      expect(out.single.estimatedMacros, isNull);
    });

    test('a zero-gram item is left alone rather than divided by zero', () {
      final out = reconcileExplicitGrams('166g rice', [item('rice', 0)]);
      expect(out.single.grams, 0);
    });

    test('preserves resolver metadata while rescaling', () {
      final out = reconcileExplicitGrams('166g rice', [
        ExtractedFoodItem(
          name: 'rice',
          grams: 120,
          hydeDescription: 'cooked white rice',
          rawText: '166g rice',
          resolvedFoodId: 'db-123',
          resolverConfidence: 0.91,
          estimatedMacros: const EstimatedMacros(
              calories: 156, proteinG: 3, carbsG: 34, fatG: 0.4),
          macroFallback: true,
        ),
      ]);
      expect(out.single.resolvedFoodId, 'db-123');
      expect(out.single.resolverConfidence, 0.91);
      expect(out.single.macroFallback, isTrue);
      expect(out.single.hydeDescription, 'cooked white rice');
    });
  });
}
