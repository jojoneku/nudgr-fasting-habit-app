/// Keyword-based calorie density estimation for unknown foods.
///
/// Used as a last-resort fallback when no food-DB match is found and no AI
/// estimate is available. The bucket table plus compound-food overrides
/// were formerly embedded in `NutritionPresenter`; extracted here so they
/// can be unit-tested and reused without touching the presenter. (Plan 035 A2.)
///
/// Public API:
///   [estimateKcal]       — calories for a named food at a given gram weight
///   [bucketMacroRatios]  — (pR, cR, fR) energy fractions for a food name
///   [macrosFromCalories] — convert calorie + ratio triplet → (protein, carbs, fat)

// ── Bucket table ──────────────────────────────────────────────────────────────
// Order matters: first matching bucket wins. Specific dish keywords (sinigang,
// adobo) must appear BEFORE their ingredient keywords (baboy, chicken) so the
// dish context overrides the raw-ingredient density.
//
// pR/cR/fR are energy fractions (must sum to 1.0):
//   protein_g = (kcal * pR) / 4   carbs_g = (kcal * cR) / 4   fat_g = (kcal * fR) / 9
const _calorieBuckets = <({
  double kcalPerG,
  double pR,
  double cR,
  double fR,
  List<String> keywords,
})>[
  // ── Pure fat / condiments ──────────────────────────────────────────────────
  (
    kcalPerG: 7.5,
    pR: 0.00, cR: 0.02, fR: 0.98, // pure fat
    keywords: ['oil', 'butter', 'ghee', 'lard', 'margarine', 'mantika'],
  ),
  (
    kcalPerG: 5.5,
    pR: 0.14, cR: 0.14, fR: 0.72, // nuts: ~14/14/72
    keywords: [
      'nut',
      'almond',
      'peanut',
      'cashew',
      'pistachio',
      'walnut',
      'seed',
      'buto',
    ],
  ),
  // Fried/cured pork — before generic meat so "lechon kawali" beats "pork"
  (
    kcalPerG: 4.0,
    pR: 0.30, cR: 0.03, fR: 0.67, // high-fat pork
    keywords: ['lechon', 'kawali', 'chicharon', 'liempo', 'bagnet'],
  ),
  // Cured/processed meats — before generic meat so "longganisa" beats "pork"
  (
    kcalPerG: 3.0,
    pR: 0.25, cR: 0.05, fR: 0.70, // bacon/sausage-like
    keywords: ['longganisa', 'tocino', 'bacon', 'ham', 'salami', 'pepperoni'],
  ),
  // Protein powder — before dairy so "whey protein" beats "cream"
  (
    kcalPerG: 4.0,
    pR: 0.75, cR: 0.15, fR: 0.10, // high protein
    keywords: ['whey', 'casein'],
  ),
  (
    kcalPerG: 4.5,
    pR: 0.07, cR: 0.60, fR: 0.33, // baked sweets
    keywords: [
      'cake',
      'cookie',
      'biscuit',
      'pastry',
      'donut',
      'chocolate',
      'candy',
      'chips',
      'cracker',
    ],
  ),
  (
    kcalPerG: 3.5,
    pR: 0.00, cR: 1.00, fR: 0.00, // pure carbs
    keywords: ['sugar', 'syrup', 'honey', 'jam', 'jelly', 'asukal'],
  ),
  // Fried starchy foods — separate from generic chips/cake
  (
    kcalPerG: 3.2,
    pR: 0.05, cR: 0.57, fR: 0.38, // fried starch
    keywords: ['fries', 'churros'],
  ),
  // Baked goods lighter than cake — before fruit so "banana muffin" → muffin
  (
    kcalPerG: 3.0,
    pR: 0.08,
    cR: 0.58,
    fR: 0.34,
    keywords: ['muffin', 'brownie', 'waffle', 'pancake'],
  ),
  // Bread and bread-like baked goods — higher density than cooked rice
  (
    kcalPerG: 2.3,
    pR: 0.12,
    cR: 0.75,
    fR: 0.13,
    keywords: [
      'bread',
      'tinapay',
      'pandesal',
      'bun',
      'toast',
      'bagel',
      'pita',
      'ensaymada',
      'monay',
      'loaf',
    ],
  ),
  // Stir-fried noodle dishes (dry) — denser than soup-based noodles
  (
    kcalPerG: 2.0,
    pR: 0.12,
    cR: 0.65,
    fR: 0.23,
    keywords: ['pansit', 'pancit'],
  ),
  // Rice porridge / congee — mostly water, much lighter than plain rice
  (
    kcalPerG: 0.85,
    pR: 0.10,
    cR: 0.80,
    fR: 0.10,
    keywords: ['goto', 'lugaw'],
  ),
  // Dry grain kernels — raw oats, granola (before cooked starch bucket)
  (
    kcalPerG: 3.89,
    pR: 0.13,
    cR: 0.68,
    fR: 0.19,
    keywords: ['oat', 'granola'],
  ),
  // ── Starchy carbs ────────────────────────────────────────────────────────
  (
    kcalPerG: 1.3,
    pR: 0.09, cR: 0.85, fR: 0.06, // rice/pasta profile
    keywords: [
      'rice',
      'pasta',
      'noodle',
      'spaghetti',
      'flour',
      'cereal',
      'kanin',
      'bigas',
      'sotanghon',
      'mami',
      'arroz',
    ],
  ),
  // Purple yam — much denser than potato due to higher starch and sugar
  (
    kcalPerG: 1.4,
    pR: 0.06,
    cR: 0.90,
    fR: 0.04,
    keywords: ['ube', 'ubi'],
  ),
  // Root vegetables / tubers — denser than leafy veg, lighter than grains
  (
    kcalPerG: 0.8,
    pR: 0.08,
    cR: 0.88,
    fR: 0.04,
    keywords: ['potato', 'camote', 'yam', 'cassava', 'kamote', 'gabi'],
  ),
  // Legumes and soy — before generic protein so "tofu" doesn't fall to default
  (
    kcalPerG: 0.9,
    pR: 0.35, cR: 0.42, fR: 0.23, // moderate protein + carbs
    keywords: [
      'tofu',
      'tokwa',
      'monggo',
      'bean',
      'lentil',
      'garbanzos',
      'chickpea',
      'edamame',
    ],
  ),
  // Light fried rolls — before generic protein fallback
  (
    kcalPerG: 1.0,
    pR: 0.12,
    cR: 0.55,
    fR: 0.33,
    keywords: ['lumpia', 'lumpiang'],
  ),
  // Filipino clear soups — before meat/fish so "sinigang na baboy" → soup
  (
    kcalPerG: 0.65,
    pR: 0.30, cR: 0.25, fR: 0.15, // mostly water + veg
    keywords: ['sinigang', 'tinola', 'nilaga', 'bulalo', 'sopas'],
  ),
  // Filipino braised stews — before generic meat so "chicken adobo" → stew
  (
    kcalPerG: 1.5,
    pR: 0.35, cR: 0.08, fR: 0.57, // protein + fat (less starch)
    keywords: [
      'adobo',
      'mechado',
      'caldereta',
      'afritada',
      'menudo',
      'pochero',
      'dinuguan',
      'kare',
    ],
  ),
  // ── Proteins ─────────────────────────────────────────────────────────────
  (
    kcalPerG: 2.0,
    pR: 0.55, cR: 0.00, fR: 0.45, // protein-dominant; no carbs in meat
    keywords: [
      'beef',
      'pork',
      'chicken',
      'turkey',
      'lamb',
      'meat',
      'manok',
      'baboy',
      'baka',
      'hotdog',
      'sausage',
    ],
  ),
  (
    kcalPerG: 1.4,
    pR: 0.65, cR: 0.00, fR: 0.35, // fish is very lean
    keywords: [
      'fish',
      'salmon',
      'tuna',
      'tilapia',
      'bangus',
      'sardine',
      'shrimp',
      'crab',
      'squid',
      'seafood',
      'isda',
      'hipon',
    ],
  ),
  (
    kcalPerG: 1.5,
    pR: 0.35, cR: 0.05, fR: 0.60, // egg: protein + yolk fat
    keywords: ['egg', 'itlog'],
  ),
  (
    kcalPerG: 1.5,
    pR: 0.22, cR: 0.28, fR: 0.50, // dairy: mixed macro
    keywords: ['milk', 'cheese', 'yogurt', 'cream', 'gatas', 'kefir'],
  ),
  // ── Vegetables / Fruits / Broths ──────────────────────────────────────────
  (
    kcalPerG: 0.35,
    pR: 0.25, cR: 0.70, fR: 0.05, // mostly carbs + small protein
    keywords: [
      'vegetable',
      'salad',
      'broccoli',
      'spinach',
      'cabbage',
      'carrot',
      'kangkong',
      'sitaw',
      'gulay',
      'ampalaya',
      'talong',
      'eggplant',
      'aubergine',
      'okra',
      'cucumber',
      'pepino',
      'pechay',
      'onion',
      'sibuyas',
      'garlic',
      'bawang',
    ],
  ),
  (
    kcalPerG: 0.6,
    pR: 0.04, cR: 0.93, fR: 0.03, // fruit: almost pure carbs
    keywords: [
      'fruit',
      'apple',
      'banana',
      'mango',
      'orange',
      'grape',
      'watermelon',
      'saging',
      'mangga',
      'prutas',
    ],
  ),
  (
    kcalPerG: 0.5,
    pR: 0.25, cR: 0.15, fR: 0.10, // broth: dilute protein
    keywords: ['broth', 'sabaw', 'soup'],
  ),
];

// ── Public API ────────────────────────────────────────────────────────────────

/// Returns the (pR, cR, fR) energy-fraction profile for [name].
/// Falls back to the generic 15/50/35 split when no bucket keyword matches.
(double, double, double) bucketMacroRatios(String name) {
  final tokens = name.toLowerCase().split(RegExp(r'\W+')).toSet();
  for (final bucket in _calorieBuckets) {
    if (bucket.keywords.any(tokens.contains)) {
      return (bucket.pR, bucket.cR, bucket.fR);
    }
  }
  return (0.15, 0.50, 0.35); // generic fallback
}

/// Converts [calories] to (protein_g, carbs_g, fat_g) using the given
/// energy fractions. Defaults to the generic 15/50/35 split.
(double, double, double) macrosFromCalories(
  int calories, {
  double pR = 0.15,
  double cR = 0.50,
  double fR = 0.35,
}) {
  if (calories <= 0) return (0.0, 0.0, 0.0);
  return (
    double.parse(((calories * pR) / 4).toStringAsFixed(1)),
    double.parse(((calories * cR) / 4).toStringAsFixed(1)),
    double.parse(((calories * fR) / 9).toStringAsFixed(1)),
  );
}

/// Last-resort calorie estimate from keyword density buckets.
/// Matches keywords as whole words to avoid "eggplant" → egg or
/// "milkshake" → milk false positives.
int estimateKcal(String name, double grams) {
  final raw = name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9ñ]+'))
      .where((t) => t.isNotEmpty)
      .toSet();
  // Stem simple plurals so "eggs" matches "egg", "noodles" → "noodle", etc.
  final tokens = {
    ...raw,
    ...raw
        .where((t) => t.endsWith('s') && t.length > 3)
        .map((t) => t.substring(0, t.length - 1)),
  };

  // ── Compound-food context overrides ──────────────────────────────────────
  // These must come BEFORE the bucket loop so that a liquid/condiment modifier
  // overrides the solid-ingredient bucket that would otherwise fire first.

  // Coconut water — very dilute (~19 kcal/100ml); must beat coconut-milk bucket
  if (tokens.contains('coconut') &&
      tokens.intersection({'water', 'tubig', 'buko'}).isNotEmpty) {
    return (grams * 0.19).round().clamp(1, 9999);
  }

  // Almond milk — unusually dilute (~15 kcal/100ml); checked before generic plant-milk
  if (tokens.contains('almond') && tokens.contains('milk')) {
    return (grams * 0.15).round().clamp(1, 9999);
  }

  // Coconut milk (full-fat) — very rich (~230 kcal/100ml)
  if (tokens.contains('coconut') &&
      tokens.intersection({'milk', 'gatas'}).isNotEmpty) {
    return (grams * 2.3).round().clamp(1, 9999);
  }

  // Plant-based milks — lighter than their solid base (~35 kcal/100ml avg)
  const plantBases = {
    'oat',
    'soy',
    'rice',
    'cashew',
    'hemp',
    'hazelnut',
    'macadamia',
  };
  if ((tokens.contains('milk') || tokens.contains('gatas')) &&
      tokens.intersection(plantBases).isNotEmpty) {
    return (grams * 0.35).round().clamp(1, 9999);
  }

  // Clear broths and stocks — ~5 kcal/100ml (bones/meat flavour, not mass)
  if (tokens.intersection({'broth', 'sabaw', 'stock', 'bouillon'}).isNotEmpty) {
    return (grams * 0.05).round().clamp(1, 9999);
  }

  // Thin condiments — fish sauce, soy sauce, vinegar, ketchup (~40 kcal/100ml)
  // Exclude rich condiments that happen to contain "sauce" (peanut, cream, butter)
  if (tokens.intersection({
        'sauce',
        'patis',
        'toyo',
        'vinegar',
        'suka',
        'catsup',
        'ketchup',
      }).isNotEmpty &&
      tokens.intersection({
        'peanut',
        'cream',
        'butter',
        'mayo',
        'coconut',
        'hollandaise',
        'bechamel',
      }).isEmpty) {
    return (grams * 0.4).round().clamp(1, 9999);
  }

  // Eggplant/talong — raw: 25 kcal/100g; fried absorbs oil to ~90 kcal/100g
  if (tokens.intersection({'eggplant', 'talong', 'aubergine'}).isNotEmpty) {
    return (grams * (tokens.contains('fried') ? 0.9 : 0.25))
        .round()
        .clamp(1, 9999);
  }

  // Other fried vegetables — oil absorption raises density ~3× vs raw
  const friedVegTokens = {
    'vegetable',
    'broccoli',
    'spinach',
    'cabbage',
    'carrot',
    'kangkong',
    'sitaw',
    'gulay',
    'ampalaya',
    'okra',
    'cucumber',
    'pechay',
  };
  if (tokens.contains('fried') &&
      tokens.intersection(friedVegTokens).isNotEmpty) {
    return (grams * 0.9).round().clamp(1, 9999);
  }

  // Fried chicken / Chickenjoy — breading + frying raises density to ~2.9 kcal/g
  if ((tokens.contains('fried') || tokens.contains('chickenjoy')) &&
      tokens.intersection({'chicken', 'manok', 'chickenjoy'}).isNotEmpty) {
    return (grams * 2.9).round().clamp(1, 9999);
  }

  // Scrambled eggs — standard serving is 2 eggs with butter; ~1.67 kcal/g
  if (tokens.contains('scrambled') &&
      tokens.intersection({'egg', 'itlog'}).isNotEmpty) {
    return (grams * 1.67).round().clamp(1, 9999);
  }

  for (final bucket in _calorieBuckets) {
    if (bucket.keywords.any(tokens.contains)) {
      return (grams * bucket.kcalPerG).round().clamp(1, 9999);
    }
  }
  return (grams * 1.5).round().clamp(1, 9999);
}
