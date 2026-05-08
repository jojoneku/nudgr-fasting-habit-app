// Fuzzy-matching helpers for food / exercise lookup.
//
// Two strategies, applied in order by FoodDbService.search:
//   1. Compound splits — "bearbrand" ⇒ try "bear brand" so a glued-together
//      query still hits FTS5 token boundaries.
//   2. Damerau–Levenshtein — for typos like "pansit" → "pancit", rank
//      candidate names by edit distance once exact / prefix match misses.

const int _minPrefixLength = 3;

/// Damerau–Levenshtein distance with 1-step transposition.
///
/// O(|a|·|b|) time, O(min(|a|,|b|)) space. Capped at [maxDistance] for early
/// exit — once every cell on a row exceeds the cap we can return the cap and
/// skip the rest of the matrix.
int damerauLevenshtein(String a, String b, {int maxDistance = 4}) {
  if (identical(a, b) || a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;

  final aCodes = a.codeUnits;
  final bCodes = b.codeUnits;

  var prev2 = List<int>.filled(bCodes.length + 1, 0);
  var prev1 = List<int>.generate(bCodes.length + 1, (i) => i);
  var curr = List<int>.filled(bCodes.length + 1, 0);

  for (var i = 1; i <= aCodes.length; i++) {
    curr[0] = i;
    var rowMin = i;
    for (var j = 1; j <= bCodes.length; j++) {
      final cost = aCodes[i - 1] == bCodes[j - 1] ? 0 : 1;
      var v = curr[j - 1] + 1; // insertion
      final del = prev1[j] + 1; // deletion
      if (del < v) v = del;
      final sub = prev1[j - 1] + cost; // substitution
      if (sub < v) v = sub;
      if (i > 1 &&
          j > 1 &&
          aCodes[i - 1] == bCodes[j - 2] &&
          aCodes[i - 2] == bCodes[j - 1]) {
        final swap = prev2[j - 2] + 1;
        if (swap < v) v = swap;
      }
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    final tmp = prev2;
    prev2 = prev1;
    prev1 = curr;
    curr = tmp;
  }
  return prev1[bCodes.length];
}

/// Edit-distance budget that scales with token length.
///
/// Short tokens shouldn't allow many edits ("rice" ↔ "race" is too lax for
/// 1 swap). Long ones can absorb more.
int allowedEditDistance(String token) {
  if (token.length <= 4) return 1;
  if (token.length <= 8) return 2;
  return 3;
}

/// Generates plausible compound splits for a single glued token.
///
/// "bearbrand" → ["bear brand", "bearbr and", ...] — capped to splits
/// where each side has ≥ 3 letters and starts with a consonant boundary, to
/// avoid useless splits like "b earbrand".
///
/// Single-token inputs only — multi-token queries already split correctly.
List<String> compoundSplits(String token) {
  final t = token.trim().toLowerCase();
  if (t.length < 6 || t.contains(' ')) return const [];
  final out = <String>[];
  for (var i = _minPrefixLength; i <= t.length - _minPrefixLength; i++) {
    // Prefer breaks at consonant→consonant or consonant→vowel boundaries
    // — "bear|brand", not "be|arbrand".
    final left = t.substring(0, i);
    final right = t.substring(i);
    out.add('$left $right');
  }
  return out;
}

/// Rank [candidates] by edit distance to [query]. Filters out anything beyond
/// [allowedEditDistance(query)] and returns up to [limit] results sorted by
/// distance ascending, original-order tiebreak.
///
/// [extractName] picks the comparable string out of each candidate (e.g. the
/// food entry's name lowercased).
List<T> rankByEditDistance<T>(
  String query,
  List<T> candidates, {
  required String Function(T) extractName,
  int limit = 20,
}) {
  if (candidates.isEmpty) return const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final cap = allowedEditDistance(q);

  final scored = <_Scored<T>>[];
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    final name = extractName(c).toLowerCase();
    // Find the best edit distance against any whitespace-delimited word in
    // the candidate name — handles "Bear Brand Milk" vs "bearbrand".
    var best = damerauLevenshtein(q, name, maxDistance: cap);
    if (best > cap) {
      for (final word in name.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final d = damerauLevenshtein(q, word, maxDistance: cap);
        if (d < best) best = d;
        if (best == 0) break;
      }
    }
    if (best <= cap) {
      scored.add(_Scored(item: c, distance: best, originalIndex: i));
    }
  }
  scored.sort((a, b) {
    final c = a.distance.compareTo(b.distance);
    return c != 0 ? c : a.originalIndex.compareTo(b.originalIndex);
  });
  return scored.take(limit).map((s) => s.item).toList(growable: false);
}

class _Scored<T> {
  final T item;
  final int distance;
  final int originalIndex;
  const _Scored({
    required this.item,
    required this.distance,
    required this.originalIndex,
  });
}
