import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/utils/food_nlp_parser.dart';
import 'package:intermittent_fasting/utils/food_unit_converter.dart';

/// Default-portion behaviour for un-quantified food.
///
/// The failure these pin down: a bare dish name used to fall through to the
/// *piece* heuristic, so "chicken adobo" matched the 100 g `chicken` piece and
/// anything unrecognised — sinigang, pinakbet — took the 100 g generic against
/// a real bowl of 350 g. Every un-weighed ulam logged light, silently.
void main() {
  double? gramsFor(String text) {
    final parsed = FoodNlpParser.parse(text);
    return parsed.items.isEmpty ? null : parsed.items.first.grams;
  }

  group('a dish is served, not counted', () {
    test('ulam resolves to a serving, not one piece of its main ingredient',
        () {
      // The regression: "chicken" inside "chicken adobo" used to win at 100 g.
      expect(FoodUnitConverter.convert(1, 'piece', foodName: 'chicken adobo'),
          150.0);
      // A plain piece of chicken is still a piece.
      expect(FoodUnitConverter.convert(1, 'piece', foodName: 'chicken'), 100.0);
    });

    test('soups carry their broth', () {
      expect(FoodUnitConverter.dishServingSize('sinigang na baboy'), 350.0);
      expect(FoodUnitConverter.dishServingSize('bulalo'), 400.0);
      expect(FoodUnitConverter.dishServingSize('arroz caldo'), 300.0);
    });

    test('richer viands outweigh the plain bucket', () {
      expect(FoodUnitConverter.dishServingSize('kare-kare'), 200.0);
      expect(FoodUnitConverter.dishServingSize('pork caldereta'), 180.0);
      expect(FoodUnitConverter.dishServingSize('pork sisig'), 130.0);
      expect(FoodUnitConverter.dishServingSize('beef tapa'), 90.0);
    });

    test('an unknown name falls back rather than guessing a dish', () {
      expect(FoodUnitConverter.dishServingSize('zzz unknown'), 150.0);
      expect(
        FoodUnitConverter.dishServingSize('zzz unknown', fallback: 42),
        42.0,
      );
    });
  });

  group('serving-ish units are food-aware', () {
    test('a bowl of soup is not a bowl of viand', () {
      expect(FoodUnitConverter.convert(1, 'bowl', foodName: 'sinigang'), 350.0);
      expect(FoodUnitConverter.convert(1, 'bowl', foodName: 'adobo'), 150.0);
    });

    test('unknown food keeps the flat unit value', () {
      // bowl = 250 g, plate = 300 g from the approximate table.
      expect(FoodUnitConverter.convert(1, 'bowl', foodName: 'cereal'), 250.0);
      expect(FoodUnitConverter.convert(1, 'plate', foodName: 'cereal'), 300.0);
    });

    test('quantities multiply', () {
      expect(FoodUnitConverter.convert(2, 'serving', foodName: 'adobo'), 300.0);
    });
  });

  group('piece sizes that were wrong or missing', () {
    test('banana varieties are no longer one flat weight', () {
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'saba'), 65.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'latundan'), 80.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'lakatan'), 100.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'banana'), 120.0);
    });

    test('saba wins over the generic banana in "fried saba banana"', () {
      expect(
        FoodUnitConverter.convert(1, 'pc', foodName: 'fried saba banana'),
        65.0,
      );
    });

    test('pandesal split from the larger breads', () {
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'pandesal'), 30.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'ensaymada'), 60.0);
    });

    test('small dried fish beat the generic fish size', () {
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'tuyo'), 25.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'galunggong'), 90.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'fish'), 130.0);
    });

    test('street food is sized instead of defaulting to 100 g', () {
      expect(FoodUnitConverter.convert(5, 'pcs', foodName: 'fishball'), 40.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'turon'), 80.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'kwek-kwek'), 30.0);
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'empanada'), 100.0);
    });
  });

  group('end-to-end through the parser', () {
    test('un-quantified ulam gets a serving', () {
      expect(gramsFor('chicken adobo'), 150.0);
      expect(gramsFor('sinigang na baboy'), 350.0);
      expect(gramsFor('pinakbet'), 150.0);
    });

    test('the reported meal no longer under-portions its ulam', () {
      // "rice and chicken adobo" with no weights: rice keeps its 150 g default,
      // and the adobo is a 150 g serving rather than a 100 g piece of chicken.
      final items = FoodNlpParser.parse('rice and chicken adobo').items;
      expect(items, hasLength(2));
      expect(items[0].grams, 150.0);
      expect(items[1].grams, 150.0);
    });

    test('explicit weights still win over every default', () {
      expect(gramsFor('166g chicken adobo'), 166.0);
    });

    test('explicit piece counts still resolve as pieces', () {
      expect(gramsFor('2 pcs pandesal'), 60.0);
    });

    test('plain rice gets its documented default in English too', () {
      // The cloud prompt always defaulted cooked rice to 150 g; the client
      // table only knew "kanin", so English input silently took the 100 g
      // generic.
      expect(gramsFor('rice'), 150.0);
      expect(gramsFor('kanin'), 150.0);
    });

    test('"rice cake" is not treated as a serving of rice', () {
      expect(FoodUnitConverter.convert(1, 'pc', foodName: 'rice cake'), 35.0);
    });
  });
}
