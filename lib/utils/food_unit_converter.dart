/// Converts food quantities with units to grams.
///
/// Standard units (g, kg, ml, oz) are exact.
/// Volume/serving units (cup, bowl, plate, piece) are heuristic estimates.
class FoodUnitConverter {
  FoodUnitConverter._();

  static const Map<String, double> _exact = {
    'g': 1.0,
    'gm': 1.0,
    'gms': 1.0,
    'gram': 1.0,
    'grams': 1.0,
    'kg': 1000.0,
    'kgs': 1000.0,
    'kilogram': 1000.0,
    'kilograms': 1000.0,
    'oz': 28.35,
    'ounce': 28.35,
    'ounces': 28.35,
    'lb': 453.6,
    'lbs': 453.6,
    'pound': 453.6,
    'pounds': 453.6,
    'ml': 1.0,
    'mls': 1.0,
    'milliliter': 1.0,
    'milliliters': 1.0,
    'millilitre': 1.0,
    'millilitres': 1.0,
    'l': 1000.0,
    'liter': 1000.0,
    'liters': 1000.0,
    'litre': 1000.0,
    'litres': 1000.0,
    'floz': 29.57,
  };

  static const Map<String, double> _approximate = {
    'cup': 240.0,
    'cups': 240.0,
    'tbsp': 15.0,
    'tbs': 15.0,
    'tablespoon': 15.0,
    'tablespoons': 15.0,
    'tbspoon': 15.0,
    'tbspoons': 15.0,
    'tsp': 5.0,
    'teaspoon': 5.0,
    'teaspoons': 5.0,
    'tspoon': 5.0,
    'tspoons': 5.0,
    'bowl': 250.0,
    'bowls': 250.0,
    'plate': 300.0,
    'plates': 300.0,
    'slice': 30.0,
    'slices': 30.0,
    'serving': 150.0,
    'servings': 150.0,
    'handful': 30.0,
    'handfuls': 30.0,
    'scoop': 30.0,
    'scoops': 30.0,
    'bottle': 350.0,
    'bottles': 350.0,
    'can': 330.0,
    'cans': 330.0,
    'glass': 250.0,
    'glasses': 250.0,
    'sachet': 25.0,
    'sachets': 25.0,
    'pack': 30.0,
    'packs': 30.0,
    'stick': 10.0,
    'sticks': 10.0,
  };

  /// Units that mean "a portion of this dish" rather than a fixed volume, so
  /// they resolve through [dishServingSize] with the flat value as fallback.
  static const Set<String> _servingUnits = {
    'serving',
    'servings',
    'bowl',
    'bowls',
    'plate',
    'plates',
  };

  // "piece" units resolved via food-name heuristic.
  static const Set<String> _pieceUnits = {
    'piece',
    'pieces',
    'pc',
    'pcs',
    'item',
    'items',
  };

  /// All recognised unit strings — used by the parser to detect units in text.
  static Set<String> get knownUnits => {
        ..._exact.keys,
        ..._approximate.keys,
        ..._pieceUnits,
      };

  /// Convert [quantity] in [unit] to grams.
  /// Pass [foodName] to improve piece-size estimates.
  /// Returns null if [unit] is unrecognised.
  static double? convert(
    double quantity,
    String unit, {
    String? foodName,
  }) {
    final u = unit.toLowerCase().trim();

    if (_exact.containsKey(u)) return quantity * _exact[u]!;
    if (u == 'cup' || u == 'cups') {
      return quantity * _cupVolume(foodName ?? '');
    }
    // Serving-ish units are food-aware: a bowl of sinigang and a serving of
    // adobo are not the same weight, and a flat 150/250/300g for all three was
    // wrong in both directions.
    if (_servingUnits.contains(u)) {
      return quantity *
          dishServingSize(foodName ?? '', fallback: _approximate[u]!);
    }
    if (_approximate.containsKey(u)) return quantity * _approximate[u]!;
    if (_pieceUnits.contains(u)) {
      return quantity * _pieceSize(foodName ?? '');
    }
    return null;
  }

  /// Grams in one serving of a prepared dish.
  ///
  /// Distinct from a *piece*: "1 pc chicken" is 100 g of chicken, but "chicken
  /// adobo" with no quantity means a serving of the dish — meat plus sauce —
  /// which is half again as much. Before this existed, a bare dish name fell
  /// through to the piece heuristic and every ulam logged ~100 g, and anything
  /// unrecognised (sinigang, pinakbet) took the 100 g generic against a real
  /// bowl of 350 g. That under-count is invisible to the user: nothing in the
  /// UI says the portion was guessed.
  ///
  /// [fallback] is returned when the name matches no known dish.
  static double dishServingSize(String foodName, {double fallback = 150.0}) {
    final n = foodName.toLowerCase();

    // Soups and rice porridges are mostly broth — a bowl weighs far more than
    // a plated viand.
    if (_has(n, ['bulalo', 'nilaga', 'lomi'])) return 400.0;
    if (_has(n, [
      'sinigang',
      'tinola',
      'sopas',
      'batchoy',
      'mami',
      'macaroni soup',
      'chicken soup',
      'miso soup',
      'sabaw',
    ])) {
      return 350.0;
    }
    if (_has(n, ['arroz caldo', 'lugaw', 'goto', 'congee', 'porridge'])) {
      return 300.0;
    }
    if (_has(n, ['munggo', 'mongo', 'monggo'])) return 250.0;

    // Rice-meal combos ("silog") are a plated set, not a single viand.
    if (_has(n, ['silog', 'rice meal', 'rice bowl'])) return 350.0;

    // Noodle dishes.
    if (_has(n, ['spaghetti', 'carbonara', 'pasta', 'lasagna'])) return 250.0;
    if (_has(n, ['pansit', 'pancit', 'sotanghon', 'bihon', 'canton'])) {
      return 200.0;
    }

    // Richer / saucier viands.
    if (_has(n, ['kare-kare', 'kare kare', 'crispy pata'])) return 200.0;
    if (_has(n, ['dinuguan', 'caldereta', 'kaldereta', 'curry'])) return 180.0;
    if (_has(n, ['sisig', 'bicol express', 'laing'])) return 130.0;
    if (_has(n, ['lechon kawali', 'liempo', 'bagnet'])) return 120.0;
    if (_has(n, ['tapa', 'tocino'])) return 90.0;

    // Vegetable dishes.
    if (_has(n, [
      'pinakbet',
      'chopsuey',
      'chop suey',
      'ginisang gulay',
      'gulay',
      'ampalaya',
      'kangkong',
      'togue',
      'utan',
    ])) {
      return 150.0;
    }

    // The broad viand bucket — adobo, menudo, afritada and friends.
    if (_has(n, [
      'adobo',
      'menudo',
      'afritada',
      'mechado',
      'giniling',
      'picadillo',
      'bistek',
      'steak',
      'estofado',
      'humba',
      'paksiw',
      'escabeche',
      'relleno',
      'embutido',
      'morcon',
      'ginataan',
      'binagoongan',
      'sarciado',
      'guisado',
      'gisado',
      'stew',
      'ulam',
      'viand',
    ])) {
      return 150.0;
    }

    return fallback;
  }

  /// Whether [unit] is a weight/volume unit that produces an exact gram value.
  static bool isExact(String unit) => _exact.containsKey(unit.toLowerCase());

  // ── Internals ─────────────────────────────────────────────────────────────

  // Food-aware cup volumes (g per cup, 240 ml default).
  static double _cupVolume(String name) {
    final n = name.toLowerCase();
    // Cooked rice is ~186g/cup (denser than water due to starch).
    if (_has(n, ['rice', 'kanin'])) return 186.0;
    // Dry oats are ~81g/cup.
    if (_has(n, ['oat', 'oatmeal'])) return 81.0;
    return 240.0;
  }

  static double _pieceSize(String foodName) {
    final n = foodName.toLowerCase();

    // A prepared dish is served, not counted: "chicken adobo" must not fall
    // through to the 100 g `chicken` piece below. Checked first so dish names
    // win over the ingredient words inside them.
    final dish = dishServingSize(n, fallback: -1);
    if (dish > 0) return dish;

    // Compound names first: "fishball" contains "fish", "eggplant" contains
    // "egg". A broad ingredient word further down would otherwise claim them —
    // 5 pcs fishball came out as 650 g of fish.
    if (_has(n, ['fishball', 'fish ball'])) return 8.0;
    if (_has(n, ['squidball', 'squid ball', 'kikiam'])) return 12.0;
    if (_has(n, ['kwek', 'tokneneng'])) return 30.0;
    if (_has(n, ['isaw', 'barbecue stick', 'bbq stick'])) return 35.0;
    if (_has(n, ['turon'])) return 80.0;
    if (_has(n, ['empanada'])) return 100.0;
    // Also catches "rice cake", which would otherwise inherit cooked rice's
    // 150 g from the staple check below.
    if (_has(n, ['puto', 'kutsinta', 'rice cake'])) return 35.0;
    if (_has(n, ['bibingka', 'suman', 'palitaw'])) return 90.0;
    if (_has(n, ['shrimp', 'hipon'])) return 15.0;
    if (_has(n, ['spam', 'luncheon meat'])) return 30.0;
    if (_has(n, ['nugget'])) return 18.0;
    if (_has(n, ['pizza slice'])) return 80.0;

    // "rice" as well as "kanin": the cloud prompt has always defaulted cooked
    // rice to 150 g, but this table only knew the Tagalog word, so anyone
    // typing English got the 100 g generic instead. ("rice bowl" / "rice meal"
    // are combos and were already claimed by the dish table above.)
    if (_has(n, ['kanin', 'sinaing', 'rice', 'sinangag'])) return 150.0;
    // Split from the old flat 50 g: a pandesal is a small roll, an ensaymada
    // or monay is roughly double it.
    if (_has(n, ['pandesal'])) return 30.0;
    if (_has(n, ['monay', 'ensaymada', 'bread roll'])) return 60.0;
    if (_has(n, ['loaf', 'tinapay'])) return 120.0;
    // Must come before 'egg' — "eggplant".contains("egg") is true
    if (_has(n, ['eggplant', 'talong', 'aubergine'])) return 100.0;
    // Scrambled eggs = standard 2-egg serving before the 1-egg piece default
    // Both word orders must be matched; substring check can't do order-independent
    if (_has(n, ['scrambled egg', 'eggs scrambled'])) return 120.0;
    if (_has(n, ['egg', 'itlog', 'itlog na maalat', 'salted egg'])) return 60.0;
    // Local banana varieties differ enough to matter: the old flat 120 g was a
    // Cavendish and nearly double a saba.
    if (_has(n, ['saba'])) return 65.0;
    if (_has(n, ['latundan', 'senorita'])) return 80.0;
    if (_has(n, ['lakatan', 'saging'])) return 100.0;
    if (_has(n, ['banana'])) return 120.0;
    if (_has(n, ['apple', 'orange', 'mango', 'mangga', 'pear'])) return 150.0;
    if (_has(n, ['cookie', 'biscuit', 'biskwit'])) return 15.0;
    if (_has(n, ['candy', 'kendi', 'gummy'])) return 10.0;
    if (_has(n, ['lollipop'])) return 12.0;
    if (_has(n, ['tilapia', 'bangus', 'milkfish', 'dalagang bukid'])) {
      return 150.0;
    }
    if (_has(n, ['tuyo', 'daing', 'dilis'])) return 25.0;
    if (_has(n, ['tinapa', 'galunggong'])) return 90.0;
    if (_has(n, ['fish', 'isda'])) return 130.0;
    if (_has(
        n, ['chicken leg', 'drumstick', 'chicken thigh', 'paa ng manok'])) {
      return 120.0;
    }
    // "wing part" = full wing (flat+drumet) — heavier than a single wing
    if (_has(n, ['wing part'])) return 110.0;
    if (_has(n, ['chicken wing', 'pakpak'])) return 60.0;
    if (_has(n, ['chicken', 'manok'])) return 100.0;
    if (_has(n, ['hotdog', 'sausage', 'longganisa', 'chorizo'])) return 40.0;
    if (_has(n, ['lumpia', 'spring roll', 'lumpiang shanghai'])) return 30.0;
    if (_has(n, ['siomai', 'shumai', 'dumpling', 'gyoza'])) return 20.0;
    if (_has(n, ['meatball', 'bola-bola'])) return 25.0;
    if (_has(n, ['burger', 'patty'])) return 90.0;
    if (_has(n, ['slice of pizza', 'pizza'])) return 80.0;
    if (_has(n, ['taco', 'tortilla'])) return 70.0;
    if (_has(n, ['donut', 'doughnut'])) return 55.0;
    if (_has(n, ['cupcake', 'muffin'])) return 60.0;
    if (_has(n, ['chocolate', 'tsokolate'])) return 15.0;
    if (_has(n, ['pansit', 'pancit'])) return 200.0;
    if (_has(n, ['fries', 'french fry', 'french fries'])) return 70.0;

    // Street food and merienda staples — previously all 100 g by default,
    // which overstated the small ones and understated the big ones.
    return 100.0; // generic default
  }

  static bool _has(String name, List<String> keywords) =>
      keywords.any(name.contains);
}
