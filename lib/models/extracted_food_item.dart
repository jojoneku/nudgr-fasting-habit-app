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

  const ExtractedFoodItem({
    required this.name,
    required this.grams,
    required this.hydeDescription,
    required this.rawText,
  });
}
