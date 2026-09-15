import 'package:intermittent_fasting/models/grocery/remembered_price.dart';
import 'package:intermittent_fasting/utils/food_fuzzy.dart';

/// Autocomplete over the user's grocery price memory.
///
/// The cart's `lookup()` is an exact-key hit — it only fires once the typed
/// name matches a remembered item character-for-character. That is useless
/// while typing: "bear" never reaches "Bear Brand 320g". This ranks *partial*
/// input against everything the user has ever priced, so the add-item sheet can
/// show past entries (with their last price) as the name is typed.
///
/// Ranking is tiered — an exact/prefix hit always outranks a fuzzy one — with
/// frequency then recency as the tiebreak inside a tier. Pure function: no
/// state, no I/O. The presenter owns the memory; this only sorts it.

/// Match quality tiers, best first. Lower ordinal wins.
enum _Tier {
  exact,
  prefix,
  wordPrefix,
  contains,
  allTokens,
  fuzzy,
}

/// Ranked price-memory matches for a partially typed item [query].
///
/// An empty [query] returns the most recently confirmed items — so opening the
/// sheet already shows "what I usually buy" before a single keystroke.
/// Returns at most [limit] entries.
List<RememberedPrice> searchPriceMemory(
  String query,
  Iterable<RememberedPrice> memory, {
  int limit = 6,
}) {
  final all = memory.toList();
  if (all.isEmpty) return const [];

  final q = _normalize(query);
  if (q.isEmpty) {
    all.sort(_byRecency);
    return all.take(limit).toList(growable: false);
  }

  final qTokens = q.split(' ').where((t) => t.isNotEmpty).toList();
  // "bearbrand" should still reach "Bear Brand" — try the glued-token splits
  // the food search already uses, but only for a single-token query.
  final splits = qTokens.length == 1 ? compoundSplits(q) : const <String>[];

  final scored = <_Ranked>[];
  for (final entry in all) {
    final tier = _tierFor(q, qTokens, splits, entry);
    if (tier != null) scored.add(_Ranked(entry, tier));
  }

  scored.sort((a, b) {
    final byTier = a.tier.index.compareTo(b.tier.index);
    if (byTier != 0) return byTier;
    return _byRecency(a.entry, b.entry);
  });

  return scored.take(limit).map((s) => s.entry).toList(growable: false);
}

/// Best tier [entry] achieves against the query, or null when it does not match
/// at all. Checked best-first so the cheap comparisons short-circuit the fuzzy
/// one, which is the only expensive path.
_Tier? _tierFor(
  String q,
  List<String> qTokens,
  List<String> splits,
  RememberedPrice entry,
) {
  final name = _normalize(entry.displayName);
  if (name.isEmpty) return null;
  if (name == q) return _Tier.exact;
  if (name.startsWith(q)) return _Tier.prefix;

  final nameTokens = name.split(' ').where((t) => t.isNotEmpty).toList();
  if (nameTokens.any((t) => t.startsWith(q))) return _Tier.wordPrefix;
  if (name.contains(q)) return _Tier.contains;

  // Every typed token prefixes some word in the name — lets "bear 320" find
  // "Bear Brand 320g" even though the words aren't adjacent.
  if (qTokens.length > 1 &&
      qTokens.every((t) => nameTokens.any((n) => n.startsWith(t)))) {
    return _Tier.allTokens;
  }

  // A barcode-keyed entry can be recalled by typing the code itself.
  final barcode = entry.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty && barcode.startsWith(q)) {
    return _Tier.prefix;
  }

  for (final split in splits) {
    if (name.startsWith(split) || name.contains(split)) return _Tier.contains;
  }

  // Typo tolerance last — "bearbrnd" → "Bear Brand". Deliberately not run for
  // 1–2 character queries, where almost everything is within the edit budget.
  if (q.length >= 3 &&
      rankByEditDistance<String>(
        q,
        [name, ...nameTokens],
        extractName: (s) => s,
        limit: 1,
      ).isNotEmpty) {
    return _Tier.fuzzy;
  }

  return null;
}

/// Frequency first (a weekly staple outranks a one-off), recency as the
/// tiebreak, name last so the order is stable across rebuilds.
int _byRecency(RememberedPrice a, RememberedPrice b) {
  final byCount = b.timesSeen.compareTo(a.timesSeen);
  if (byCount != 0) return byCount;
  final bySeen = b.lastSeen.compareTo(a.lastSeen);
  if (bySeen != 0) return bySeen;
  return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _Ranked {
  final RememberedPrice entry;
  final _Tier tier;
  const _Ranked(this.entry, this.tier);
}
