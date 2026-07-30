/// Enforces the weights a user actually typed against the portions the model
/// guessed.
///
/// The AI prompt already asks for this (parse-food rules 5 and 8), but a prompt
/// is a request, not a guarantee — and until now only the *single-item* case was
/// checked on the client. A multi-item log had no enforcement at all, so a model
/// that under-portioned silently under-counted the meal:
///
/// * `"166g rice, 81g chicken adobo"` → the model may return 120g / 60g, and
///   both stood. The user weighed their food and the app ignored it.
/// * `"247g rice and chicken adobo"` states a TOTAL for the plate. The model
///   splits it across ingredients, but nothing checked that the split adds back
///   up — a split summing to 180g quietly loses 27% of the meal, and the
///   composite-dish merge then reports that shortfall as the whole dish.
///
/// This mirrors the prompt's own rules deterministically, on the client, where
/// it is testable and needs no redeploy:
///
/// * A weight **leading** the input, with several items parsed out of it, is the
///   total for the dish — items are scaled proportionally to sum to it.
/// * A weight **attached to an ingredient** applies to that ingredient only; the
///   others are left alone.
/// * Several weights mean one per item — each is matched to its item by name and
///   applied individually.
///
/// Macros scale with the weight, so calories track the correction. Pure
/// functions only: no I/O, no state.
library;

import '../models/extracted_food_item.dart';

/// Weights within this fraction of the model's own figure are left alone — the
/// model effectively agreed, and rescaling would only add rounding noise.
const double _kAgreementTolerance = 0.05;

final RegExp _gramMention = RegExp(
  r'(\d+(?:\.\d+)?)\s*(?:g|gm|gms|gram|grams)\b',
  caseSensitive: false,
);

/// Same separators [FoodNlpParser] splits fragments on, so "166g rice, 81g
/// adobo" and "166g rice and 81g adobo" behave identically.
final RegExp _fragmentSplitter = RegExp(
  r'\s*(?:,|\band\b|\+|\bplus\b|\bwith\b)\s*',
  caseSensitive: false,
);

/// A weight the user typed, together with the text fragment carrying it.
class GramMention {
  final double grams;

  /// The fragment the weight appeared in, e.g. `"81g chicken adobo"`.
  final String fragment;

  /// True when the weight opens the whole input — the signal that it describes
  /// the dish as a whole rather than one ingredient of it.
  final bool leadsInput;

  const GramMention({
    required this.grams,
    required this.fragment,
    required this.leadsInput,
  });
}

/// Every explicit weight in [text], in order of appearance.
List<GramMention> findGramMentions(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];

  final leadingMatch =
      _gramMention.matchAsPrefix(trimmed) ?? _gramMention.firstMatch(trimmed);
  final leadOffset = leadingMatch?.start ?? -1;

  final out = <GramMention>[];
  for (final fragment in trimmed.split(_fragmentSplitter)) {
    final f = fragment.trim();
    if (f.isEmpty) continue;
    for (final m in _gramMention.allMatches(f)) {
      final grams = double.tryParse(m.group(1)!);
      if (grams == null || grams <= 0) continue;
      // A weight "leads" only if it is the first thing in the input and sits in
      // the first fragment — "247g rice and adobo" leads, "rice with 100g
      // sardines" does not.
      final leads = out.isEmpty &&
          leadOffset >= 0 &&
          leadOffset <= 1 &&
          trimmed.startsWith(f);
      out.add(GramMention(grams: grams, fragment: f, leadsInput: leads));
    }
  }
  return out;
}

/// Returns [items] with the user's stated weights applied. Input is never
/// mutated; when nothing needs correcting the original list comes back.
List<ExtractedFoodItem> reconcileExplicitGrams(
  String text,
  List<ExtractedFoodItem> items,
) {
  if (items.isEmpty) return items;
  final mentions = findGramMentions(text);
  if (mentions.isEmpty) return items;

  // One weight, one item: the long-standing single-item rule.
  if (mentions.length == 1 && items.length == 1) {
    return [_scaled(items.first, mentions.first.grams)];
  }

  // One weight leading a multi-item extraction: a total for the whole dish.
  if (mentions.length == 1 && mentions.first.leadsInput) {
    return _scaledToTotal(items, mentions.first.grams);
  }

  // Otherwise each weight belongs to whichever item it names.
  return _applyPerItem(items, mentions);
}

/// Scales every item so their weights sum to [total], preserving the model's
/// split ratio. A split that lost or gained mass is corrected without second-
/// guessing how the model apportioned it.
List<ExtractedFoodItem> _scaledToTotal(
  List<ExtractedFoodItem> items,
  double total,
) {
  final sum = items.fold<double>(0, (s, i) => s + i.grams);
  if (sum <= 0) return items;
  if ((sum - total).abs() / total <= _kAgreementTolerance) return items;
  final ratio = total / sum;
  return [
    for (final i in items) _scaled(i, i.grams * ratio),
  ];
}

/// Matches each mention to the item it names and applies that weight to it
/// alone. Items no mention refers to are left untouched.
List<ExtractedFoodItem> _applyPerItem(
  List<ExtractedFoodItem> items,
  List<GramMention> mentions,
) {
  final out = [...items];
  final claimed = <int>{};

  for (final mention in mentions) {
    final idx = _bestMatch(out, mention.fragment, claimed);
    if (idx == null) continue;
    claimed.add(idx);
    out[idx] = _scaled(out[idx], mention.grams);
  }
  return out;
}

/// Index of the unclaimed item whose name best overlaps [fragment], or null
/// when nothing plausibly matches — a wrong match would move a weight onto the
/// wrong food, which is worse than leaving the model's guess in place.
int? _bestMatch(
  List<ExtractedFoodItem> items,
  String fragment,
  Set<int> claimed,
) {
  final fragTokens = _tokens(fragment);
  if (fragTokens.isEmpty) return null;

  int? best;
  var bestScore = 0;
  for (var i = 0; i < items.length; i++) {
    if (claimed.contains(i)) continue;
    final nameTokens = _tokens(items[i].name);
    if (nameTokens.isEmpty) continue;
    final score = nameTokens.where(fragTokens.contains).length;
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return bestScore > 0 ? best : null;
}

/// Lowercased word tokens, with the weight itself and units stripped so
/// "81g chicken adobo" tokenises to {chicken, adobo}.
Set<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(_gramMention, ' ')
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.length > 1)
    .toSet();

/// Re-weights one item to [grams], scaling its macros by the same factor.
ExtractedFoodItem _scaled(ExtractedFoodItem item, double grams) {
  if (grams <= 0 || item.grams <= 0) return item;
  if ((item.grams - grams).abs() / grams <= _kAgreementTolerance) return item;

  final ratio = grams / item.grams;
  final m = item.estimatedMacros;
  return ExtractedFoodItem(
    name: item.name,
    grams: grams,
    hydeDescription: item.hydeDescription,
    rawText: item.rawText,
    resolvedFoodId: item.resolvedFoodId,
    resolverConfidence: item.resolverConfidence,
    estimatedMacros: m == null
        ? null
        : EstimatedMacros(
            calories: m.calories * ratio,
            proteinG: m.proteinG * ratio,
            carbsG: m.carbsG * ratio,
            fatG: m.fatG * ratio,
          ),
    macroFallback: item.macroFallback,
  );
}
