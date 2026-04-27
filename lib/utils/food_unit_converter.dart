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

  // "piece" units resolved via food-name heuristic.
  static const Set<String> _pieceUnits = {
    'piece', 'pieces', 'pc', 'pcs', 'item', 'items',
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
    if (_approximate.containsKey(u)) return quantity * _approximate[u]!;
    if (_pieceUnits.contains(u)) {
      return quantity * _pieceSize(foodName ?? '');
    }
    return null;
  }

  /// Whether [unit] is a weight/volume unit that produces an exact gram value.
  static bool isExact(String unit) => _exact.containsKey(unit.toLowerCase());

  // ── Internals ─────────────────────────────────────────────────────────────

  static double _pieceSize(String foodName) {
    final n = foodName.toLowerCase();
    if (_has(n, ['pandesal', 'bread roll', 'monay', 'ensaymada'])) return 50.0;
    if (_has(n, ['loaf', 'tinapay'])) return 120.0;
    if (_has(n, ['egg', 'itlog', 'itlog na maalat', 'salted egg'])) return 60.0;
    if (_has(n, ['banana', 'saging', 'lakatan', 'latundan'])) return 120.0;
    if (_has(n, ['apple', 'orange', 'mango', 'mangga', 'pear'])) return 150.0;
    if (_has(n, ['cookie', 'biscuit', 'biskwit'])) return 15.0;
    if (_has(n, ['candy', 'kendi', 'gummy'])) return 10.0;
    if (_has(n, ['lollipop'])) return 12.0;
    if (_has(n, ['tilapia', 'bangus', 'milkfish', 'dalagang bukid'])) return 150.0;
    if (_has(n, ['fish', 'isda'])) return 130.0;
    if (_has(n, ['chicken leg', 'drumstick', 'chicken thigh', 'paa ng manok'])) return 120.0;
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
    return 100.0; // generic default
  }

  static bool _has(String name, List<String> keywords) =>
      keywords.any(name.contains);
}
