// Regex + dictionary preprocessor for natural-language ledger input.
//
// The first layer of Plan 026's three-tier pipeline (regex+dict → AI dialog →
// form fallback). Pure logic — no I/O, no AI calls. Resolves the easy cases
// instantly so the AI is only paid for genuinely ambiguous inputs:
//
//   -500 food gcash         → committed instantly, no AI
//   500 gcash hamburger     → AI confirm card if "hamburger" isn't learned
//   -500 b food             → AI clarifies "BPI or BDO?"
//   transfer 1000 bpi gcash → committed instantly as transfer

import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/transaction_record.dart';
import 'food_fuzzy.dart';

const int _maxInputLength = 500;
const int _minAccountPrefixLength = 3;
const int _minAccountFuzzyLength = 4;

/// Longest account name, in words, the span matcher will try to match. Covers
/// "BPI Personal", "BPI Credit Card", "Maya Savings Pocket".
const int _maxAccountSpanWords = 4;

/// Hard cap on segments in one chat message. A message that splits into more
/// than this is almost certainly punctuation being read as a separator rather
/// than a genuine list, so it's parsed as a single entry instead.
const int _maxBatchSegments = 10;

/// Resolves [input] using the account/category lists and the personal
/// dictionary, returning a [PreparseResult] that may be:
///
///   * Fully resolved — commit immediately, no AI call.
///   * Partially resolved — pass to AI classifier.
///   * Hard-errored — show error chip, no AI call.
///
/// [viewingPastDate] short-circuits to the corresponding hard error so views
/// can disable logging while a past day is selected.
PreparseResult preparseFinanceInput({
  required String input,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedDict,
  bool viewingPastDate = false,
}) {
  final raw = input.trim();
  if (viewingPastDate) {
    return PreparseResult(
      rawInput: raw,
      hardError: FinanceParseError.viewingPastDate,
    );
  }
  if (raw.isEmpty) {
    return PreparseResult(rawInput: raw, hardError: FinanceParseError.empty);
  }
  if (raw.length > _maxInputLength) {
    return PreparseResult(rawInput: raw, hardError: FinanceParseError.tooLong);
  }

  // Only consider top-level, active accounts. Sub-accounts (savings pockets)
  // and custodian holdings are excluded from chat logging — see Plan 026 §4.
  final activeAccounts = accounts
      .where((a) => a.isActive && !a.isSubAccount && !a.isCustodian)
      .toList();

  final normalized = _normalize(raw);

  // Pattern A — transfer
  final transfer = _tryTransfer(normalized, activeAccounts);
  if (transfer != null) return transfer.copyWith(rawInput: raw);

  // Pattern A1 — paid on your card FOR someone who paid you back in cash. This
  // is never your spending or income, so it routes to a Credit Card → Cash
  // transfer. Must run before Pattern A2: the "for <someone>" + payback signal
  // distinguishes it from paying DOWN a card. ("paid 800 on my cc for jana,
  // she paid me back" → card→cash; "paid bpi cc 5000 from gcash" → pay-down.)
  final paidForSomeone = _tryPaidForSomeone(normalized, activeAccounts);
  if (paidForSomeone != null) return paidForSomeone.copyWith(rawInput: raw);

  // Pattern A2 — pay a credit account ("paid bpi cc 5000 from gcash"). Resolves
  // to a transfer that tops up (pays down) the credit account. Only fires when a
  // liability account is the clear target; otherwise falls through to amounts so
  // ordinary "pay jeepney 20" stays an expense.
  final payCredit = _tryPayCredit(normalized, activeAccounts);
  if (payCredit != null) return payCredit.copyWith(rawInput: raw);

  // Patterns B + C — signed / unsigned amount
  return _tryAmount(
    raw: raw,
    normalized: normalized,
    categories: categories,
    accounts: activeAccounts,
    learnedDict: learnedDict,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch entry point — one message, one or more transactions
// ─────────────────────────────────────────────────────────────────────────────

/// Separators that can introduce a second transaction in one message. Commas
/// are handled here too, but only after thousand-commas have been collapsed so
/// "1,500 food gcash" isn't torn in half.
final _segmentSplitter = RegExp(
  r'[\n;,]|\s+(?:and|then|also|plus)\s+',
  caseSensitive: false,
);

/// Splits [input] into one segment per transaction and preparses each.
///
/// A message only counts as a list when at least two segments carry a digit.
/// That single guard is what keeps ordinary prose intact: "coffee and donuts
/// 150 gcash" splits into "coffee" / "donuts 150 gcash", only one of which has
/// an amount, so it is parsed whole and the description survives. Likewise
/// "paid 800 on my cc for jana, she paid me back" stays one entry.
///
/// Prefer this over [preparseFinanceInput] on any surface that accepts free
/// text — a single-transaction message is just the length-1 case.
PreparseBatch preparseFinanceBatch({
  required String input,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedDict,
  bool viewingPastDate = false,
}) {
  final raw = input.trim();
  // Whole-message errors first: they don't depend on segmentation, and
  // reporting them per segment would multiply one problem into several.
  if (viewingPastDate) {
    return PreparseBatch.error(FinanceParseError.viewingPastDate, raw);
  }
  if (raw.isEmpty) return PreparseBatch.error(FinanceParseError.empty, raw);
  if (raw.length > _maxInputLength) {
    return PreparseBatch.error(FinanceParseError.tooLong, raw);
  }

  PreparseBatch single() => PreparseBatch(
        rawInput: raw,
        segments: [
          preparseFinanceInput(
            input: raw,
            categories: categories,
            accounts: accounts,
            learnedDict: learnedDict,
          ),
        ],
      );

  // Collapse thousand-commas before splitting, on the raw string so casing
  // (and therefore descriptions) survive.
  final decommad =
      raw.replaceAllMapped(RegExp(r'(\d),(?=\d{3}(?:\D|$))'), (m) => m[1]!);

  final pieces = decommad
      .split(_segmentSplitter)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  final withDigits = pieces.where((p) => RegExp(r'\d').hasMatch(p)).length;
  if (withDigits < 2 || pieces.length > _maxBatchSegments) return single();

  // Only amount-bearing pieces become transactions. A trailing "…and that's
  // it" or a leading "logged:" is noise, not an entry.
  final segments = [
    for (final p in pieces)
      if (RegExp(r'\d').hasMatch(p))
        preparseFinanceInput(
          input: p,
          categories: categories,
          accounts: accounts,
          learnedDict: learnedDict,
        ),
  ];
  if (segments.length < 2) return single();
  return PreparseBatch(rawInput: raw, segments: segments);
}

// ─────────────────────────────────────────────────────────────────────────────
// Normalization
// ─────────────────────────────────────────────────────────────────────────────

/// lowercase, trim, strip ₱/php/p prefix, drop thousand-commas, normalize
/// transfer aliases to the literal word "transfer".
String _normalize(String input) {
  var s = input.toLowerCase().trim();
  // strip currency markers attached to a number, on EITHER side:
  //   prefix — ₱120 / php120 / p120
  //   suffix — 120₱ / 120php / 120 php / 120p / 120 pesos
  // The lone `p` suffix carries a \b so it can't eat the p inside a word
  // ("120plates" stays intact); the multi-char markers don't need it.
  s = s.replaceAll(RegExp(r'(?:₱|php|p)(?=\d)'), '');
  s = s.replaceAll(RegExp(r'(?<=\d)\s*(?:php|pesos?|p\b|₱)'), '');
  // collapse thousand-commas inside numbers: 1,500 → 1500
  s = s.replaceAllMapped(
    RegExp(r'(\d),(?=\d{3}(?:\D|$))'),
    (m) => m.group(1)!,
  );
  // normalize transfer aliases
  s = s.replaceAllMapped(
    RegExp(r'\b(?:txfr|trf|t)\b|>|->|→'),
    (_) => 'transfer',
  );
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pattern A — transfer
// ─────────────────────────────────────────────────────────────────────────────

/// Directional-marker tokens that split a transfer's source from its
/// destination. `into`/`->`(→ "transfer") behave like `to`.
const _kTransferToMarkers = {'to', 'into'};
const _kTransferFromMarker = 'from';

PreparseResult? _tryTransfer(
    String normalized, List<FinancialAccount> accounts) {
  // Reject any input that doesn't contain the literal word "transfer" (arrow
  // and abbreviation aliases were normalized into it upstream).
  if (!RegExp(r'\btransfer\b').hasMatch(normalized)) return null;

  final amounts =
      RegExp(r'(?<=^|\s)(-?\d+(?:\.\d+)?)(?=\s|$)').allMatches(normalized);
  if (amounts.isEmpty) return null;
  if (amounts.length > 1) {
    return const PreparseResult(
        rawInput: '', hardError: FinanceParseError.multipleAmounts);
  }
  final amount = double.tryParse(amounts.first.group(1)!);
  if (amount == null || amount <= 0) {
    return const PreparseResult(
        rawInput: '', hardError: FinanceParseError.invalidAmount);
  }

  // Everything that isn't the amount or the word "transfer" is a label, with
  // direction markers left in place to segment on.
  final labels = normalized
      .replaceRange(amounts.first.start, amounts.first.end, ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && t != 'transfer')
      .toList();

  // Segment on direction markers, tagging each run of tokens with the marker
  // that introduced it. The run before any marker is untagged.
  final segments = <(String? marker, List<String> tokens)>[];
  String? marker;
  var current = <String>[];
  for (final tok in labels) {
    if (_kTransferToMarkers.contains(tok) || tok == _kTransferFromMarker) {
      segments.add((marker, current));
      marker = tok == _kTransferFromMarker ? _kTransferFromMarker : 'to';
      current = <String>[];
    } else {
      current.add(tok);
    }
  }
  segments.add((marker, current));

  List<String>? fromTokens;
  List<String>? toTokens;
  List<String>? leading;
  for (final (m, toks) in segments) {
    if (toks.isEmpty) continue;
    if (m == _kTransferFromMarker) {
      fromTokens ??= toks;
    } else if (m == 'to') {
      toTokens ??= toks;
    } else {
      leading ??= toks;
    }
  }

  // The untagged run fills whichever side is still open. "500 gcash from bpi"
  // makes gcash the destination; "transfer 500 bpi to gcash" makes it the
  // source. Word order, not resolution order, decides — resolving in order and
  // filling `from` first (as this used to) silently swapped the legs whenever
  // the source label was ambiguous and the destination happened to resolve.
  if (leading != null) {
    if (fromTokens == null) {
      fromTokens = leading;
    } else {
      toTokens ??= leading;
    }
  }

  final ambiguous = <String>[];
  String? fromId;
  String? toId;

  if (fromTokens != null) {
    final scan = _scanAccounts(fromTokens, accounts);
    ambiguous.addAll(scan.ambiguous);
    if (scan.spans.isNotEmpty) fromId = scan.spans.first.accountId;
    // No explicit destination marker: both accounts sit in the same run, so the
    // second name found is the destination ("transfer 1000 bpi gcash").
    if (toTokens == null && scan.spans.length > 1) {
      toId = scan.spans[1].accountId;
    }
  }
  if (toTokens != null) {
    final scan = _scanAccounts(toTokens, accounts);
    ambiguous.addAll(scan.ambiguous);
    if (scan.spans.isNotEmpty) toId = scan.spans.first.accountId;
  }
  if (toId == fromId) toId = null;

  return PreparseResult(
    rawInput: '',
    amount: amount,
    type: TransactionType.transfer,
    accountId: fromId,
    transferToAccountId: toId,
    unresolvedTokens: const [],
    ambiguousAccountTokens: ambiguous,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pattern A1 — paid on your card for someone (who paid you back in cash)
// ─────────────────────────────────────────────────────────────────────────────

PreparseResult? _tryPaidForSomeone(
    String normalized, List<FinancialAccount> accounts) {
  // Needs a pay verb, a "for <someone>" beneficiary, and a payback signal.
  // Without the payback signal we deliberately do NOT fire — the money hasn't
  // returned, so it should stay a normal (possibly reimbursable) expense rather
  // than a wash transfer.
  if (!RegExp(r'\b(?:paid|pay|spotted|covered)\b').hasMatch(normalized)) {
    return null;
  }
  if (!RegExp(r'\bfor\b').hasMatch(normalized)) return null;
  // PAST/completed payback only — the cash has already come back, so it's a
  // wash transfer. Future phrasings ("will pay me back", "reimbursable") fall
  // through to the reimbursable-expense suggestion in _tryAmount instead.
  final paybackRe =
      RegExp(r'paid me back|paid back|paid me|gave me cash|cash back|refunded');
  if (!paybackRe.hasMatch(normalized)) return null;

  // Exactly one amount, else let the AI handle it.
  final amounts = RegExp(r'(?<=^|\s)(\d+(?:\.\d+)?)(?=\s|$)')
      .allMatches(normalized)
      .toList();
  if (amounts.length != 1) return null;
  final amount = double.tryParse(amounts.first.group(1)!);
  if (amount == null || amount <= 0) return null;

  // The card charged (a liability) is the source; cash is the destination.
  final cardId = _matchAccountInText(normalized, accounts, liability: true);
  if (cardId == null) return null;
  // Destination defaults to the user's cash account; null falls through to AI
  // clarification ("which account did the cash land in?").
  final cashId = _firstAccountOfCategory(accounts, AccountCategory.cash);

  return PreparseResult(
    rawInput: '',
    amount: amount,
    type: TransactionType.transfer,
    accountId: cardId,
    transferToAccountId: cashId,
  );
}

String? _firstAccountOfCategory(
    List<FinancialAccount> accounts, AccountCategory category) {
  for (final a in accounts) {
    if (a.category == category) return a.id;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pattern A2 — pay a credit account
// ─────────────────────────────────────────────────────────────────────────────

PreparseResult? _tryPayCredit(
    String normalized, List<FinancialAccount> accounts) {
  final verbRe = RegExp(r'\b(?:paid|pay|settle)\b');
  if (!verbRe.hasMatch(normalized)) return null;

  // Exactly one amount, else let other patterns / the AI handle it.
  final amounts = RegExp(r'(?<=^|\s)(\d+(?:\.\d+)?)(?=\s|$)')
      .allMatches(normalized)
      .toList();
  if (amounts.length != 1) return null;
  final amount = double.tryParse(amounts.first.group(1)!);
  if (amount == null || amount <= 0) return null;

  // "from <account>" splits the credit target (left) from the funder (right).
  final fromIdx = normalized.indexOf(' from ');
  final targetText =
      fromIdx >= 0 ? normalized.substring(0, fromIdx) : normalized;
  final funderText = fromIdx >= 0 ? normalized.substring(fromIdx + 6) : '';

  // The payment only makes sense if a liability account is the clear target.
  final toId = _matchAccountInText(targetText, accounts, liability: true);
  if (toId == null) return null;

  // Funder is optional here — if absent/unresolved, the AI clarifies which
  // account to pay from before committing.
  final fromId = funderText.trim().isNotEmpty
      ? _matchAccountInText(funderText, accounts, liability: false)
      : null;
  if (fromId == toId) return null;

  return PreparseResult(
    rawInput: '',
    amount: amount,
    type: TransactionType.transfer,
    accountId: fromId,
    transferToAccountId: toId,
  );
}

/// Finds an account whose [FinancialAccount.isLiability] equals [liability] that
/// is named within [text]. Prefers the longest full-name substring (handles
/// multi-word names like "BPI CC"), then falls back to per-token prefix matches.
String? _matchAccountInText(
  String text,
  List<FinancialAccount> accounts, {
  required bool liability,
}) {
  final pool = accounts.where((a) => a.isLiability == liability).toList();
  final lower = text.toLowerCase();

  String? bestId;
  var bestLen = 0;
  for (final a in pool) {
    final name = a.name.toLowerCase();
    if (name.isNotEmpty && lower.contains(name) && name.length > bestLen) {
      bestId = a.id;
      bestLen = name.length;
    }
  }
  if (bestId != null) return bestId;

  for (final tok in lower.split(RegExp(r'\s+'))) {
    if (tok.length < _minAccountPrefixLength) continue;
    for (final a in pool) {
      for (final word in a.name.toLowerCase().split(RegExp(r'\s+'))) {
        if (word == tok) return a.id;
        if (word.length >= _minAccountPrefixLength &&
            (word.startsWith(tok) || tok.startsWith(word))) {
          return a.id;
        }
      }
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Patterns B + C — signed / unsigned amount
// ─────────────────────────────────────────────────────────────────────────────

PreparseResult _tryAmount({
  required String raw,
  required String normalized,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedDict,
}) {
  // Strict: at most one optional sign + integer/decimal at a word boundary.
  // Lookbehind/lookahead so adjacent tokens (e.g. "-500 -300") both match.
  final amountMatches =
      RegExp(r'(?<=^|\s)([+-]?\d+(?:\.\d+)?)(?=\s|$)').allMatches(normalized);

  if (amountMatches.isEmpty) {
    final anyDigits = RegExp(r'\d').hasMatch(normalized);
    return PreparseResult(
      rawInput: raw,
      hardError: anyDigits
          ? FinanceParseError.invalidAmount
          : FinanceParseError.noAmount,
    );
  }
  if (amountMatches.length > 1) {
    return PreparseResult(
      rawInput: raw,
      hardError: FinanceParseError.multipleAmounts,
    );
  }

  final match = amountMatches.first;
  final amountStr = match.group(1)!;
  final hasExplicitSign =
      amountStr.startsWith('+') || amountStr.startsWith('-');
  final magnitude =
      double.tryParse(hasExplicitSign ? amountStr.substring(1) : amountStr);
  if (magnitude == null) {
    return PreparseResult(
        rawInput: raw, hardError: FinanceParseError.invalidAmount);
  }
  if (magnitude <= 0) {
    return PreparseResult(
        rawInput: raw, hardError: FinanceParseError.invalidAmount);
  }
  final amount = magnitude;

  final explicitType = hasExplicitSign
      ? (amountStr.startsWith('-')
          ? TransactionType.outflow
          : TransactionType.inflow)
      : null;

  // Everything except the amount token is a "label" — try to resolve it.
  final before = normalized.substring(0, match.start).trim();
  final after = normalized.substring(match.end).trim();
  final tokens = [
    ...before.split(RegExp(r'\s+')),
    ...after.split(RegExp(r'\s+')),
  ]..removeWhere((t) => t.isEmpty);

  // Accounts first, over phrases rather than lone tokens, so a multi-word
  // account name is matched whole before its words are offered to anything
  // else. Only the first account matters here — a second name in a non-transfer
  // entry has no field to land in.
  final scan = _scanAccounts(tokens, accounts);
  // With exactly one loggable account there is nothing to disambiguate, so
  // naming it is optional — "500 food" resolves. Only applied as a fallback, so
  // an explicitly named account always wins.
  final String? accountId = scan.spans.isNotEmpty
      ? scan.spans.first.accountId
      : (accounts.length == 1 ? accounts.first.id : null);
  final categoryHits = <String>{};
  final unresolved = <String>[];
  final ambiguous = <String>[...scan.ambiguous];

  for (final tok in scan.leftover) {
    final catId = _resolveCategoryToken(tok, categories);
    if (catId != null) {
      categoryHits.add(catId);
      continue;
    }
    final dictHit = _lookupLearned(tok, learnedDict);
    if (dictHit != null && categories.any((c) => c.id == dictHit)) {
      categoryHits.add(dictHit);
      continue;
    }
    unresolved.add(tok);
  }

  // Sign / category cross-validation.
  String? categoryId;
  TransactionType? inferredType = explicitType;
  if (categoryHits.length == 1) {
    final cat = categories.firstWhere((c) => c.id == categoryHits.first);
    final implied = cat.type == CategoryType.income
        ? TransactionType.inflow
        : TransactionType.outflow;
    if (explicitType != null && explicitType != implied) {
      return PreparseResult(
        rawInput: raw,
        hardError: FinanceParseError.signCategoryMismatch,
      );
    }
    categoryId = cat.id;
    inferredType ??= implied;
  }

  // Sanity check: if we know the type, make sure there's at least one
  // category of that type available — otherwise the user can never resolve.
  if (inferredType != null && categoryId == null) {
    final wanted = inferredType == TransactionType.inflow
        ? CategoryType.income
        : CategoryType.expense;
    if (!categories.any((c) => c.type == wanted)) {
      return PreparseResult(
        rawInput: raw,
        hardError: FinanceParseError.noCategoriesForType,
      );
    }
  }

  // Suggest the reimbursable toggle when the text signals a spent-now,
  // owed-back expense. Only for expenses (never income).
  final reimbursable = _detectReimbursable(normalized) &&
      (inferredType == null || inferredType == TransactionType.outflow);

  return PreparseResult(
    rawInput: raw,
    amount: amount,
    type: inferredType,
    accountId: accountId,
    categoryId: categoryId,
    reimbursable: reimbursable,
    unresolvedTokens: unresolved,
    ambiguousAccountTokens: ambiguous,
  );
}

/// Detects a reimbursable-expense intent: money spent now that you expect back
/// later (future payback, owed-by, or work/business-expense phrasing). The
/// past-tense "paid me back"/"refunded" cases are handled as transfers upstream.
bool _detectReimbursable(String normalized) {
  return RegExp(
    r'reimburs' // reimburse / reimbursable / reimbursement / reimbursed
    r'|will pay me back|gonna pay me back|pay me back'
    r'|owes? me|owe me back|to be paid back'
    r'|claim it back|get it back|expense it'
    r'|work expense|business expense',
  ).hasMatch(normalized);
}

// ─────────────────────────────────────────────────────────────────────────────
// Account / category resolvers
// ─────────────────────────────────────────────────────────────────────────────

class _AccountMatch {
  final String? id;
  final bool wasAmbiguous;
  const _AccountMatch.miss()
      : id = null,
        wasAmbiguous = false;
  const _AccountMatch.hit(String this.id) : wasAmbiguous = false;
  const _AccountMatch.ambiguous()
      : id = null,
        wasAmbiguous = true;
}

/// Resolves a whole phrase — one or more adjacent tokens joined by a space —
/// against the account list.
///
/// Single-token behaviour is identical to matching one word; the point of
/// accepting a phrase is that multi-word account names ("BPI Personal") can
/// only ever be matched as one. Matching them token by token is what used to
/// make "500 bpi personal food" ask "BPI Personal or BPI Vybe?" — "bpi" alone
/// is genuinely ambiguous, and "personal" alone matches nothing, so the name
/// the user actually typed in full was never considered.
_AccountMatch _resolveAccountPhrase(
    String phrase, List<FinancialAccount> accounts) {
  final t = phrase.toLowerCase().trim();
  if (t.isEmpty) return const _AccountMatch.miss();

  // 1. Exact case-insensitive name match.
  for (final a in accounts) {
    if (a.name.toLowerCase() == t) return _AccountMatch.hit(a.id);
  }

  // 2. Prefix match. Resolve only if ≥ _minAccountPrefixLength chars; below
  // that, still flag ambiguous on ≥2 hits so the AI can clarify (the user
  // typed enough to be unambiguous-with-clarification, not enough to commit).
  final prefixHits =
      accounts.where((a) => a.name.toLowerCase().startsWith(t)).toList();
  if (prefixHits.length > 1) return const _AccountMatch.ambiguous();
  if (prefixHits.length == 1 && t.length >= _minAccountPrefixLength) {
    return _AccountMatch.hit(prefixHits.first.id);
  }

  // 3. Fuzzy match (Damerau–Levenshtein ≤ 1, phrase ≥ _minAccountFuzzyLength).
  if (t.length >= _minAccountFuzzyLength) {
    FinancialAccount? best;
    var bestD = 2;
    var ties = 0;
    for (final a in accounts) {
      final d = damerauLevenshtein(t, a.name.toLowerCase(), maxDistance: 1);
      if (d <= 1) {
        if (d < bestD) {
          best = a;
          bestD = d;
          ties = 1;
        } else if (d == bestD) {
          ties++;
        }
      }
    }
    if (best != null && ties == 1) return _AccountMatch.hit(best.id);
    if (best != null && ties > 1) return const _AccountMatch.ambiguous();
  }

  return const _AccountMatch.miss();
}

/// One account name found inside a token list, and the tokens it occupied.
class _AccountSpan {
  final String accountId;
  final int start; // inclusive
  final int end; // exclusive
  const _AccountSpan(this.accountId, this.start, this.end);
}

/// Result of sweeping a token list for account names.
class _AccountScan {
  /// Spans in left-to-right order of appearance. Word order is the only signal
  /// transfer direction has, so this list must stay ordered.
  final List<_AccountSpan> spans;

  /// Tokens no account claimed, in order — candidates for category / dict /
  /// unresolved classification.
  final List<String> leftover;

  /// Phrases that matched more than one account, for the AI to disambiguate.
  final List<String> ambiguous;

  const _AccountScan(this.spans, this.leftover, this.ambiguous);
}

/// Finds every account name in [tokens], preferring the longest phrase.
///
/// Longest-first is what makes multi-word names win over their own first word:
/// with accounts "BPI Personal" and "BPI Vybe", the two-token phrase
/// "bpi personal" resolves and consumes both tokens, so the ambiguous
/// single token "bpi" is never evaluated on its own.
_AccountScan _scanAccounts(
    List<String> tokens, List<FinancialAccount> accounts) {
  final claimed = List<bool>.filled(tokens.length, false);
  final spans = <_AccountSpan>[];
  final ambiguous = <String>[];

  final maxSpan = tokens.length < _maxAccountSpanWords
      ? tokens.length
      : _maxAccountSpanWords;

  for (var width = maxSpan; width >= 1; width--) {
    for (var start = 0; start + width <= tokens.length; start++) {
      final end = start + width;
      if (claimed.getRange(start, end).any((c) => c)) continue;
      final phrase = tokens.getRange(start, end).join(' ');
      final match = _resolveAccountPhrase(phrase, accounts);
      if (match.id != null) {
        spans.add(_AccountSpan(match.id!, start, end));
        for (var i = start; i < end; i++) {
          claimed[i] = true;
        }
      } else if (match.wasAmbiguous && width == 1) {
        // Only record single-token ambiguity. A multi-token phrase that matched
        // several accounts isn't a token the user can be asked about, and its
        // words may still resolve individually on a narrower pass.
        ambiguous.add(phrase);
      }
    }
  }

  spans.sort((a, b) => a.start.compareTo(b.start));
  final leftover = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (!claimed[i]) leftover.add(tokens[i]);
  }
  // A token that resolved on a wider pass isn't ambiguous after all.
  ambiguous.removeWhere((t) => !leftover.contains(t));
  return _AccountScan(spans, leftover, ambiguous);
}

/// Looks [token] up in the learned dictionary, matching how the dictionary
/// stores its keys, and tolerating a typo.
///
/// [FinancePersonalDictionary] normalizes every key by stripping non-alphanumeric
/// characters, so a raw indexed lookup missed any token carrying punctuation —
/// "jollibee," never found the "jollibee" the user had already taught it, and
/// the input went to the AI for a category it already knew.
///
/// The fuzzy pass exists for the same reason: these are mappings the user
/// confirmed themselves, so honouring "jollibe" is recalling their own answer,
/// not guessing. It needs a unique nearest key, matching how account names are
/// resolved — two equally-near keys are ambiguous, not a match.
String? _lookupLearned(String token, Map<String, String> learnedDict) {
  final direct = learnedDict[token];
  if (direct != null) return direct;
  final key = token.toLowerCase().replaceAll(RegExp(r"[^a-z0-9ñ']"), '');
  if (key.isEmpty) return null;
  final normalized = learnedDict[key];
  if (normalized != null) return normalized;
  if (key.length < _minAccountFuzzyLength) return null;

  String? best;
  var ties = 0;
  for (final entry in learnedDict.entries) {
    if (entry.key.length < _minAccountFuzzyLength) continue;
    if (damerauLevenshtein(key, entry.key, maxDistance: 1) > 1) continue;
    if (best == null) {
      best = entry.value;
      ties = 1;
    } else if (entry.value != best) {
      ties++;
    }
  }
  return ties == 1 ? best : null;
}

String? _resolveCategoryToken(String token, List<FinanceCategory> categories) {
  final t = token.toLowerCase();
  if (t.isEmpty) return null;

  for (final c in categories) {
    if (c.name.toLowerCase() == t) return c.id;
  }

  if (t.length >= _minAccountPrefixLength) {
    final prefixHits =
        categories.where((c) => c.name.toLowerCase().startsWith(t)).toList();
    if (prefixHits.length == 1) return prefixHits.first.id;
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// PreparseResult copyWith — local to this file since the model is immutable
// ─────────────────────────────────────────────────────────────────────────────

extension on PreparseResult {
  PreparseResult copyWith({String? rawInput}) => PreparseResult(
        amount: amount,
        type: type,
        accountId: accountId,
        transferToAccountId: transferToAccountId,
        categoryId: categoryId,
        reimbursable: reimbursable,
        unresolvedTokens: unresolvedTokens,
        ambiguousAccountTokens: ambiguousAccountTokens,
        hardError: hardError,
        rawInput: rawInput ?? this.rawInput,
      );
}
