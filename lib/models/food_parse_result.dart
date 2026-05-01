/// A single food item extracted from natural language input.
class ParsedFoodItem {
  /// The original text fragment, e.g. "2 cups rice"
  final String rawText;

  /// Normalized food name for DB lookup, e.g. "rice"
  final String name;

  /// Resolved quantity in grams.
  final double grams;

  /// True if the gram conversion was a heuristic estimate (e.g. "a handful").
  final bool isEstimated;

  const ParsedFoodItem({
    required this.rawText,
    required this.name,
    required this.grams,
    required this.isEstimated,
  });
}

/// The full output of [FoodNlpParser] — a list of parsed items and
/// a flag indicating whether the model was used as fallback.
class FoodParseResult {
  final List<ParsedFoodItem> items;

  /// False = rule-based parser only. True = Qwen3 was used as fallback.
  final bool usedModel;

  const FoodParseResult({required this.items, required this.usedModel});

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}
