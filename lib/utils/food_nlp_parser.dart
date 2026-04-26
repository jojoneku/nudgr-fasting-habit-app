import '../models/food_parse_result.dart';
import 'food_unit_converter.dart';

/// Parses natural-language food descriptions into structured [FoodParseResult].
///
/// Handles patterns like:
///   "2 cups rice and chicken adobo"
///   "150g chicken breast"
///   "a bowl of sinigang"
///   "3 pieces siomai, 1 cup rice"
///   "chicken adobo"  → default serving
///
/// Pure utility — no state, no I/O. Falls back gracefully on ambiguous input.
class FoodNlpParser {
  FoodNlpParser._();

  // Splits compound inputs into individual food fragments.
  static final _splitter = RegExp(
    r'\s*(?:,|\band\b|\+|\bplus\b)\s*',
    caseSensitive: false,
  );

  // "(\d+.?\d*) (unit) (of)? food"  e.g. "2 cups of rice"
  static final _patternQuantityUnit = RegExp(
    r'^(\d+\.?\d*)\s+(' + _unitPattern + r')\s+(?:of\s+)?(.+)$',
    caseSensitive: false,
  );

  // "(\d+.?\d*)(g|ml) food"  e.g. "150g chicken" or "200ml milk"
  static final _patternInlineGram = RegExp(
    r'^(\d+\.?\d*)\s*(g|ml|kg|oz|lb)s?\s+(.+)$',
    caseSensitive: false,
  );

  // "food (unit)?" where unit may trail  e.g. "chicken 150g"
  static final _patternTrailingGram = RegExp(
    r'^(.+?)\s+(\d+\.?\d*)\s*(g|ml|kg|oz|lb)s?$',
    caseSensitive: false,
  );

  // "(\d+.?\d*) food" with no unit — treat as grams if > 10, else servings
  static final _patternQuantityOnly = RegExp(
    r'^(\d+\.?\d*)\s+(.+)$',
    caseSensitive: false,
  );

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Parse [input] into a [FoodParseResult].
  ///
  /// Always returns a result (never null). [usedModel] is always false —
  /// set it to true in the caller when Qwen3 was used upstream.
  static FoodParseResult parse(String input) {
    final cleaned = _normalize(input);
    if (cleaned.isEmpty) {
      return const FoodParseResult(items: [], usedModel: false);
    }

    final fragments = cleaned
        .split(_splitter)
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    final items = fragments
        .map(_parseFragment)
        .where((i) => i != null)
        .cast<ParsedFoodItem>()
        .toList();

    return FoodParseResult(items: items, usedModel: false);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    // "a cup" / "an apple" → "1 cup" / "1 apple"
    s = s.replaceAll(RegExp(r'^an?\s+'), '1 ');
    s = s.replaceAll(RegExp(r'\ban?\s+'), ' 1 ');
    // "some rice" → "rice"
    s = s.replaceAll(RegExp(r'\bsome\s+'), '');
    // "half a cup" → "0.5 cup"
    s = s.replaceAll(RegExp(r'\bhalf\s+a?\s*'), '0.5 ');
    // "quarter" → "0.25"
    s = s.replaceAll(RegExp(r'\bquarter\s+a?\s*'), '0.25 ');
    // collapse spaces
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static ParsedFoodItem? _parseFragment(String fragment) {
    if (fragment.isEmpty) return null;

    // Pattern: "150g chicken breast" or "200ml milk"
    final inlineGram = _patternInlineGram.firstMatch(fragment);
    if (inlineGram != null) {
      final qty = double.tryParse(inlineGram.group(1)!) ?? 1.0;
      final unit = inlineGram.group(2)!;
      final name = _cleanName(inlineGram.group(3)!);
      final grams = FoodUnitConverter.convert(qty, unit, foodName: name);
      if (grams != null && grams > 0) {
        return ParsedFoodItem(
          rawText: fragment,
          name: name,
          grams: grams,
          isEstimated: false,
        );
      }
    }

    // Pattern: "chicken 150g" (trailing gram)
    final trailing = _patternTrailingGram.firstMatch(fragment);
    if (trailing != null) {
      final name = _cleanName(trailing.group(1)!);
      final qty = double.tryParse(trailing.group(2)!) ?? 1.0;
      final unit = trailing.group(3)!;
      final grams = FoodUnitConverter.convert(qty, unit, foodName: name);
      if (grams != null && grams > 0) {
        return ParsedFoodItem(
          rawText: fragment,
          name: name,
          grams: grams,
          isEstimated: false,
        );
      }
    }

    // Pattern: "2 cups of rice" / "1 bowl sinigang"
    final quantityUnit = _patternQuantityUnit.firstMatch(fragment);
    if (quantityUnit != null) {
      final qty = double.tryParse(quantityUnit.group(1)!) ?? 1.0;
      final unit = quantityUnit.group(2)!;
      final name = _cleanName(quantityUnit.group(3)!);
      final grams = FoodUnitConverter.convert(qty, unit, foodName: name);
      if (grams != null && grams > 0) {
        return ParsedFoodItem(
          rawText: fragment,
          name: name,
          grams: grams,
          isEstimated: !FoodUnitConverter.isExact(unit),
        );
      }
    }

    // Pattern: "2 chicken adobo" (bare number, no unit) → treat as servings
    final quantityOnly = _patternQuantityOnly.firstMatch(fragment);
    if (quantityOnly != null) {
      final qty = double.tryParse(quantityOnly.group(1)!) ?? 1.0;
      final name = _cleanName(quantityOnly.group(2)!);
      if (!_looksLikeUnit(name)) {
        // quantity ≥ 10 with no unit → assume grams
        final grams = qty >= 10 ? qty : qty * 150.0;
        return ParsedFoodItem(
          rawText: fragment,
          name: name,
          grams: grams,
          isEstimated: qty < 10,
        );
      }
    }

    // Fallback: just a food name → 100g default serving
    final name = _cleanName(fragment);
    if (name.isNotEmpty) {
      return ParsedFoodItem(
        rawText: fragment,
        name: name,
        grams: 100.0,
        isEstimated: true,
      );
    }

    return null;
  }

  static String _cleanName(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'^(of|the|some)\s+'), '')
        .trim();
  }

  static bool _looksLikeUnit(String word) =>
      FoodUnitConverter.knownUnits.contains(word.toLowerCase());

  // Pre-computed unit alternation string for regex patterns.
  static final String _unitPattern = () {
    final units = FoodUnitConverter.knownUnits
        .map(RegExp.escape)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // longest first
    return units.join('|');
  }();
}
