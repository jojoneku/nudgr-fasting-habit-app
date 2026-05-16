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
// Normalization
// ─────────────────────────────────────────────────────────────────────────────

/// lowercase, trim, strip ₱/php/p prefix, drop thousand-commas, normalize
/// transfer aliases to the literal word "transfer".
String _normalize(String input) {
  var s = input.toLowerCase().trim();
  // strip currency markers attached to digits
  s = s.replaceAll(RegExp(r'(?:₱|php|p)(?=\d)'), '');
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

PreparseResult? _tryTransfer(
    String normalized, List<FinancialAccount> accounts) {
  // Two shapes after normalization (arrow aliases → "transfer"):
  //   A. transfer <amount> <from> [to] <to>
  //   B. <amount> <from> transfer <to>
  // Reject any input that doesn't contain the literal word "transfer".
  if (!RegExp(r'\btransfer\b').hasMatch(normalized)) return null;

  // Try shape A first.
  var m =
      RegExp(r'^transfer\s+(-?\d+(?:\.\d+)?)\s+(.+)$').firstMatch(normalized);
  // Shape B — amount leads, "transfer" sits between the two account labels.
  m ??= RegExp(r'^(-?\d+(?:\.\d+)?)\s+(.+?)\s+transfer\s+(.+)$')
      .firstMatch(normalized);
  if (m == null) return null;

  final amount = double.tryParse(m.group(1)!);
  if (amount == null) {
    return const PreparseResult(
        rawInput: '', hardError: FinanceParseError.invalidAmount);
  }
  if (amount <= 0) {
    return const PreparseResult(
        rawInput: '', hardError: FinanceParseError.invalidAmount);
  }

  // Shape B captures `from` and `to` in groups 2 and 3; shape A captures all
  // remaining labels in group 2.
  final String remainder;
  if (m.groupCount >= 3 && m.group(3) != null) {
    remainder = '${m.group(2)!} ${m.group(3)!}';
  } else {
    remainder = m.group(2)!;
  }
  final parts = remainder.contains(' to ')
      ? remainder.split(' to ')
      : remainder.split(RegExp(r'\s+'));

  final tokens = parts.expand((p) => p.trim().split(RegExp(r'\s+'))).toList()
    ..removeWhere((t) => t.isEmpty);

  String? fromId;
  String? toId;
  final ambiguous = <String>[];

  for (final tok in tokens) {
    final r = _resolveAccount(tok, accounts);
    if (r.id == null) {
      if (r.wasAmbiguous) ambiguous.add(tok);
      continue;
    }
    if (fromId == null) {
      fromId = r.id;
    } else if (toId == null && r.id != fromId) {
      toId = r.id;
    }
  }

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

  String? accountId;
  final categoryHits = <String>{};
  final unresolved = <String>[];
  final ambiguous = <String>[];

  for (final tok in tokens) {
    final accRes = _resolveAccount(tok, accounts);
    if (accRes.id != null) {
      accountId ??= accRes.id;
      continue;
    }
    if (accRes.wasAmbiguous) {
      ambiguous.add(tok);
      continue;
    }
    final catId = _resolveCategoryToken(tok, categories);
    if (catId != null) {
      categoryHits.add(catId);
      continue;
    }
    final dictHit = learnedDict[tok];
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

  return PreparseResult(
    rawInput: raw,
    amount: amount,
    type: inferredType,
    accountId: accountId,
    categoryId: categoryId,
    unresolvedTokens: unresolved,
    ambiguousAccountTokens: ambiguous,
  );
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

_AccountMatch _resolveAccount(String token, List<FinancialAccount> accounts) {
  final t = token.toLowerCase();
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

  // 3. Fuzzy match (Damerau–Levenshtein ≤ 1, token ≥ _minAccountFuzzyLength).
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
        unresolvedTokens: unresolvedTokens,
        ambiguousAccountTokens: ambiguousAccountTokens,
        hardError: hardError,
        rawInput: rawInput ?? this.rawInput,
      );
}
