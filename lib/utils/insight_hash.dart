import 'dart:convert';

/// Stable hashing + canonical rounding for the Insight Engine (Plan 057).
///
/// The digest that feeds the trigger engine and the LLM prompt must be
/// hashed the same way every time regardless of run, platform, or map
/// insertion order — otherwise harmless floating-point jitter (or a
/// differently-ordered `Map`) would look like a state change and defeat the
/// per-section hash gate. [Object.hash] is unsuitable here: it is seeded
/// per-process, so the same content hashes differently across runs. This
/// file uses a plain FNV-1a hash over a canonical (sorted-key) JSON string
/// instead.

/// Rounds a kilocalorie value to the nearest whole calorie — collapses
/// meaningless fractional jitter (e.g. 2000.4 vs 2000.44) before hashing.
int roundKcal(num kcal) => kcal.round();

/// Rounds a kilogram value to one decimal place.
double roundKg(num kg) => (kg * 10).round() / 10;

/// Rounds a currency amount to the nearest whole unit (no cents/centavos).
int roundCurrency(num amount) => amount.round();

/// Recursively rebuilds [value] with every nested map's keys sorted, so the
/// resulting structure serializes identically regardless of original key
/// insertion order.
Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    final out = <String, Object?>{};
    for (final k in sortedKeys) {
      out[k] = _canonicalValue(value[k]);
    }
    return out;
  }
  if (value is Iterable) {
    return value.map(_canonicalValue).toList();
  }
  return value;
}

/// A deterministic JSON string for [data] — keys sorted recursively — so
/// identical logical content always yields the same string, independent of
/// the original `Map`'s insertion order.
String canonicalize(Map<String, Object?> data) =>
    jsonEncode(_canonicalValue(data));

/// 32-bit FNV-1a. Simple, dependency-free, and — unlike [Object.hash] —
/// stable across runs and platforms, which is what a persisted content-hash
/// baseline requires.
int _fnv1a(String input) {
  const prime = 0x01000193; // 16777619
  var hash = 0x811c9dc5; // 2166136261
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Stable content hash of [data] as an 8-character lowercase hex string.
/// Two maps with identical canonical content (see [canonicalize]) always
/// hash the same — the basis of the per-section "did anything change?" gate
/// in `InsightSnapshot`.
String hashMarkers(Map<String, Object?> data) =>
    _fnv1a(canonicalize(data)).toRadixString(16).padLeft(8, '0');
