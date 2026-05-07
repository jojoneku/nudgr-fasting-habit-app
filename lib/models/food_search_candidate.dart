import 'food_db_entry.dart';

/// Source that produced a [FoodSearchCandidate] in the resolution chain.
enum SearchSource { semantic, fts5, personalDict }

/// One candidate match returned by the food search pipeline.
///
/// Score semantics depend on [source]:
///   - [SearchSource.semantic]   — cosine similarity ∈ [-1, 1] (typically [0, 1])
///   - [SearchSource.fts5]       — normalised score ∈ [0, 1] from FoodMatchScorer
///   - [SearchSource.personalDict] — always 1.0 (exact prior confirmation)
class FoodSearchCandidate {
  final FoodDbEntry entry;
  final double score;
  final SearchSource source;

  const FoodSearchCandidate({
    required this.entry,
    required this.score,
    required this.source,
  });
}
