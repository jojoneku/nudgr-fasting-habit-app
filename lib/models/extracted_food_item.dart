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

  /// True when [estimatedMacros] was synthesised from a generic ~2 kcal/g
  /// ratio because the model failed to return macros. The values are rough
  /// approximations — the UI should flag them as unverified estimates.
  final bool macroFallback;

  const ExtractedFoodItem({
    required this.name,
    required this.grams,
    required this.hydeDescription,
    required this.rawText,
    this.resolvedFoodId,
    this.resolverConfidence = 0.0,
    this.estimatedMacros,
    this.macroFallback = false,
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

/// Outcome of [AiCoachService.parseFoodFromImage] (Plan 029). Unlike the text
/// path, photo parsing has distinct non-error terminal states the UI must
/// surface (no food detected, daily cap reached) — hence a status enum rather
/// than a nullable return.
enum PhotoParseStatus {
  /// At least one food item was detected. [PhotoParseResult.items] is non-empty.
  ok,

  /// The model reported the image contains no food (pet, person, empty plate).
  noFood,

  /// The server rejected the call with the per-user daily cap (HTTP 429).
  rateLimited,

  /// No cloud vision service is configured/available (signed out, no endpoint,
  /// on-device tier). The caller should prompt the user to enable Cloud AI.
  unavailable,

  /// The request never reached the server — no connection, DNS failure, or a
  /// transport-level timeout. This is the only status that warrants a
  /// "check your connection" message.
  networkError,

  /// The server was reached but returned an error response (non-2xx, not 429),
  /// e.g. a 5xx, an auth failure, or an unhandled op. The user's connection is
  /// fine; the backend is the problem. See [PhotoParseResult.httpStatus].
  serverError,

  /// The server replied 200 but the body couldn't be understood (malformed or
  /// empty JSON, missing fields).
  failed,
}

/// Result of a photo food-logging parse. Carries the detected [items] (always
/// `food_id`-less, macro-estimated) and the combine-vs-split [intent].
class PhotoParseResult {
  final PhotoParseStatus status;
  final List<ExtractedFoodItem> items;
  final ParseIntent intent;

  /// Diagnostic detail for logging only — an exception message or an HTTP body
  /// snippet. NEVER shown to the user verbatim.
  final String? detail;

  /// The HTTP status code when [status] is [PhotoParseStatus.serverError];
  /// null otherwise. Surfaced (as a code, not the body) so a confused user can
  /// quote it in a bug report.
  final int? httpStatus;

  const PhotoParseResult(
    this.status, {
    this.items = const [],
    this.intent = ParseIntent.itemsList,
    this.detail,
    this.httpStatus,
  });
}
