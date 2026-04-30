import '../models/food_db_entry.dart';

/// Scoring helpers for selecting the best food DB entry or AI item estimate.
/// Extracted from NutritionPresenter for reuse and testability.
class FoodMatchScorer {
  FoodMatchScorer._();

  // Words that transform a base food into a distinct processed product.
  // If these appear in a DB entry but NOT in the user's query, the entry is
  // penalised.
  static const _transformingWords = {
    'chips', 'crisps', 'puffs', 'crackers', 'cracker',
    'fried', 'battered', 'breaded', 'coated',
    'sauce', 'gravy', 'soup', 'stew', 'casserole', 'curry',
    'candy', 'candied', 'caramel',
    'pie', 'cake', 'tart', 'pudding',
    'instant', 'processed', 'imitation',
  };

  /// Pick the highest-scoring entry from [hits] for [query].
  /// Returns null if no entry scores above 0.
  static FoodDbEntry? pickBest(List<FoodDbEntry> hits, String query) {
    if (hits.isEmpty) return null;

    final q = query.toLowerCase();
    final qWords = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();

    int bestScore = 0; // must beat 0 to qualify
    FoodDbEntry? best;

    for (final entry in hits) {
      final s = _score(entry, qWords, q);
      if (s > bestScore) {
        bestScore = s;
        best = entry;
      }
    }
    return best;
  }

  static int _score(FoodDbEntry entry, List<String> qWords, String fullQuery) {
    final eName = entry.name.toLowerCase();
    if (eName == fullQuery) return 1000;

    final eWords = eName
        .split(RegExp(r'[,\s\-]+'))
        .where((w) => w.length > 1)
        .toList();

    int s = 0;
    for (final qw in qWords) {
      if (eWords.any((ew) => ew == qw)) {
        s += 5; // exact whole-word match
      } else if (eName.contains(qw)) {
        s += 1; // substring match
      } else if (eWords.any((ew) => qw.startsWith(ew) && ew.length >= 3)) {
        s += 1; // inflection: "skim" in DB vs "skimmed" in query
      }
    }

    for (final ew in eWords) {
      if (_transformingWords.contains(ew) &&
          !qWords.any((qw) => qw == ew || qw.contains(ew) || ew.contains(qw))) {
        s -= 5; // penalise unmentioned processing word
      }
    }

    // Penalise very verbose USDA-style names.
    s -= eWords.length ~/ 5;

    return s;
  }

  /// Returns true if [entry] is a confident enough match for [query] to be
  /// safely cached into the personal dictionary. Stricter than [pickBest]'s
  /// "any positive score" threshold:
  ///   • Every query word must appear as a whole word in the entry name
  ///     (rules out "scrambled eggs with noodles" matching "egg noodles").
  ///   • Entry must not introduce a transforming word the query didn't use
  ///     (rules out "rice cake" matching "rice").
  /// Exact-name match always passes.
  static bool isLearnableMatch(FoodDbEntry entry, String query) {
    final eName = entry.name.toLowerCase();
    final q = query.toLowerCase();
    if (eName == q) return true;

    final qWords = q
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
    if (qWords.isEmpty) return false;

    final eWords = eName
        .split(RegExp(r'[,\s\-()]+'))
        .where((w) => w.length > 1)
        .toSet();

    // Every query word must be present as a whole word.
    if (!qWords.every(eWords.contains)) return false;

    // Entry must not add a transforming word not in the query.
    for (final ew in eWords) {
      if (_transformingWords.contains(ew) && !qWords.contains(ew)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if [aiName] is semantically close enough to [nlpName]
  /// to trust as a normalization. Rejects:
  ///   • renames with no word overlap ("chicken adobo" → "chicken stew")
  ///   • AI introducing transforming words not in the NLP name
  ///     ("rice" → "fried rice", "potato" → "potato chips")
  static bool isReasonableNormalization(String nlpName, String aiName) {
    if (aiName.isEmpty) return false;
    final nlp = nlpName.toLowerCase();
    final ai = aiName.toLowerCase();
    if (ai == nlp) return true;

    final nlpWords =
        nlp.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final aiWords =
        ai.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();

    // Reject if AI added a transforming word the user didn't say.
    for (final aw in aiWords) {
      if (_transformingWords.contains(aw) && !nlpWords.contains(aw)) {
        return false;
      }
    }

    if (nlpWords.isEmpty) return true;

    final overlap = nlpWords
        .where((w) =>
            ai.contains(w) ||
            aiWords.any((aw) => aw.contains(w) || w.contains(aw)))
        .length;
    return overlap >= (nlpWords.length / 2).ceil();
  }
}
