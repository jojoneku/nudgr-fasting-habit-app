/// Name matching for Nudgy's `find` tool (Plan 065 phase 3).
///
/// Pure functions, no state. A query matches a row when every meaningful
/// word of it appears somewhere in the row's text, in any order: "meralco aug
/// bill" finds "Meralco" in August, and "bpi card" finds "BPI Credit Card".
/// Substring containment, not equality, so "grab" matches "GrabFood".
library;

/// Words that carry no meaning in a lookup. Dropped before matching, so "my
/// internet bill" and "internet" find the same row.
const Set<String> kFindFillerWords = {
  'a', 'an', 'the', 'my', 'our', 'your', 'me', 'i', 'of', 'for', 'to', 'in',
  'on', 'at', 'from', 'with', 'and', 'or', 'please', 'this', 'that', 'is',
  'was', 'did', 'do', 'when', 'what', 'which', 'how', 'much', 'month',
  'monthly', 'last', 'payment', 'paid', 'pay',
  // The entity words: "find(entity: bill, query: 'internet bill')".
  'bill', 'bills', 'receivable', 'receivables', 'setaside', 'set-aside',
  'setasides', 'budget', 'budgets', 'account', 'accounts', 'installment',
  'installments', 'plan', 'group', 'groups',
};

const List<String> _monthNames = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// The calendar month (1–12) a word names — "aug", "august", "sept" — or
/// null. Three letters at least, so "ma" is not March.
int? monthNumberOf(String word) {
  final w = word.toLowerCase();
  if (w.length < 3) return null;
  for (var i = 0; i < _monthNames.length; i++) {
    if (_monthNames[i].startsWith(w)) return i + 1;
  }
  return null;
}

/// A query split into the words that must match, plus a month it named.
class FindQuery {
  const FindQuery(this.words, this.monthNumber);

  /// Lowercase words, filler and month names removed. Empty means "list all".
  final List<String> words;

  /// A month the query named in words ("meralco aug"), or null.
  final int? monthNumber;

  bool get isEmpty => words.isEmpty;
}

/// Splits [query] into meaningful words. A month name is taken out as
/// [FindQuery.monthNumber] rather than matched as text, unless it is the only
/// word (then it is a name, e.g. a bill called "May").
FindQuery parseFindQuery(String query) {
  final raw = query
      .toLowerCase()
      .split(RegExp(r"[^a-z0-9₱.\-']+"))
      .map((w) => w.replaceAll("'", ''))
      .where((w) => w.isNotEmpty)
      .toList();
  final words = <String>[];
  int? month;
  for (final w in raw) {
    if (kFindFillerWords.contains(w)) continue;
    final m = monthNumberOf(w);
    if (m != null &&
        raw.where((x) => !kFindFillerWords.contains(x)).length > 1) {
      month ??= m;
      continue;
    }
    words.add(w);
  }
  return FindQuery(words, month);
}

/// True when every word of [q] appears in [haystack] (any order).
bool findMatches(FindQuery q, String haystack) {
  final h = haystack.toLowerCase();
  return q.words.every(h.contains);
}

/// Up to [limit] of [names] closest to [q], best first, for a `not_found`
/// reply: names sharing the most query words, then the smallest edit distance
/// from the joined query. Never empty when [names] is not.
List<String> nearestNames(FindQuery q, Iterable<String> names,
    {int limit = 5}) {
  final query = q.words.join(' ');
  final scored = <({String name, int shared, int distance})>[];
  for (final n in names.toSet()) {
    final lower = n.toLowerCase();
    final shared = q.words
        .where((w) =>
            lower.contains(w) ||
            lower.split(RegExp(r'\s+')).any((t) => _distance(t, w) <= 1))
        .length;
    scored.add((name: n, shared: shared, distance: _distance(lower, query)));
  }
  scored.sort((a, b) {
    final s = b.shared.compareTo(a.shared);
    return s != 0 ? s : a.distance.compareTo(b.distance);
  });
  return [for (final s in scored.take(limit)) s.name];
}

/// Levenshtein distance, for ranking near misses only.
int _distance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}
