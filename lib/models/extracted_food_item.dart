/// One food item parsed from natural-language chat input.
///
/// Produced by [OnDeviceAiCoachService.extractFoodItems] in a single LLM
/// inference. The `hydeDescription` is a HyDE-style canonical description —
/// "what would the USDA food DB row for this look like?" — used as a second
/// retrieval channel alongside the raw `name` for hybrid search.
///
/// Examples:
///   "1 cup rolled oats" → ExtractedFoodItem(
///     name: "rolled oats", grams: 80,
///     hydeDescription: "Oats, rolled, regular and quick, dry, unenriched")
///
///   "kefir milk" → ExtractedFoodItem(
///     name: "kefir", grams: 240,
///     hydeDescription: "Kefir, lowfat, plain")
class ExtractedFoodItem {
  /// User-facing food name. Display this in the chat row.
  final String name;

  /// Resolved gram weight. The LLM converts cups/scoops/etc. to grams.
  final double grams;

  /// Canonical description for embedding-based DB lookup. Closer to USDA
  /// phrasing than the user's raw input, which boosts semantic search recall
  /// for queries that mix common names with descriptive words ("kefir milk").
  /// May be empty when the LLM couldn't form one — caller should fall back
  /// to using [name] for both retrieval channels.
  final String hydeDescription;

  /// What the user actually typed for this fragment. Preserved for the chat
  /// UI's "raw input" subtitle.
  final String rawText;

  /// Plan 026: when the cloud `parseFoodWithCandidates` op matched this item
  /// to a candidate from the local DB, the picked id. Null when no candidate
  /// fit, or when extracted via the older `extractFoodItems` path.
  final String? resolvedFoodId;

  /// Plan 026: the cloud's confidence in [resolvedFoodId]. 0.0 when not set.
  final double resolverConfidence;

  /// Plan 026: cloud-estimated macros for the whole item (already scaled to
  /// [grams]). Populated only when [resolvedFoodId] is null, so the caller
  /// has something to log even for out-of-DB foods.
  final EstimatedMacros? estimatedMacros;

  const ExtractedFoodItem({
    required this.name,
    required this.grams,
    required this.hydeDescription,
    required this.rawText,
    this.resolvedFoodId,
    this.resolverConfidence = 0.0,
    this.estimatedMacros,
  });
}

/// Cloud-estimated macros for one item. Used when no DB candidate matched.
class EstimatedMacros {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const EstimatedMacros({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Plan 027 — whether the AI thinks the user is logging one composite dish
/// (combine ingredients into a single log entry) or a list of separate items
/// (keep them as distinct entries). Drives the combine-vs-split UX.
enum ParseIntent { singleDish, itemsList }

/// Result of [AiCoachService.parseFoodWithCandidates] including the AI's
/// intent classification. The caller decides whether to fold items into
/// one [FoodEntry] based on [intent].
class ParseFoodResult {
  final List<ExtractedFoodItem> items;
  final ParseIntent intent;

  const ParseFoodResult({required this.items, required this.intent});

  static ParseIntent intentFromJson(String? value) {
    return value == 'single_dish'
        ? ParseIntent.singleDish
        : ParseIntent.itemsList;
  }
}
