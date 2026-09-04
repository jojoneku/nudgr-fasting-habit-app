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
import 'amount_input_formatter.dart';
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

/// The accounts a chat surface may bind a spoken name to.
///
/// Only top-level, active accounts. Sub-accounts (savings pockets) and
/// custodian holdings are excluded from chat logging — see Plan 026 §4 and
/// `docs/chat_logging_coverage.md` §3. Custodian accounts are usually named
/// after people ("Jana's money") and chat text mentions people constantly, so
/// including them would resolve `spotted jana 800` to an account instead of a
/// debtor.
///
/// Shared rather than inlined because Nudgy's `addTransaction` tool binds
/// account names too, and two copies of this predicate would drift.
List<FinancialAccount> chatEligibleAccounts(List<FinancialAccount> accounts) =>
    accounts
        .where((a) => a.isActive && !a.isSubAccount && !a.isCustodian)
        .toList();

/// Resolves [input] using the account/category lists and the personal
/// dictionary, returning a [PreparseResult] that may be:
///
///   * Fully resolved — commit immediately, no AI call.
///   * Partially resolved — pass to AI classifier.
///   * Hard-errored — show error chip, no AI call.
///
/// [viewingPastDate] short-circuits to the corresponding hard error so views
/// can disable logging while a past day is selected.
/// [now] is injectable so relative dates ("yesterday") are testable.
PreparseResult preparseFinanceInput({
  required String input,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedDict,
  bool viewingPastDate = false,
  DateTime? now,
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

  final activeAccounts = chatEligibleAccounts(accounts);

  // Pre-pass: lift the note, the dates and the beneficiary out before any
  // transaction pattern runs, so a date phrase can never be mistaken for an
  // amount and "3 days ago" doesn't read as a second transaction.
  final extras = _extractExtras(
    raw: raw,
    normalized: _normalize(raw),
    now: now ?? DateTime.now(),
    accountWords: _accountWords(activeAccounts),
  );
  final normalized = extras.text;

  // Pattern A — transfer
  final transfer = _tryTransfer(normalized, activeAccounts);
  if (transfer != null) return transfer.copyWith(rawInput: raw, extras: extras);

  // Pattern A1 — paid on your card FOR someone who paid you back in cash. This
  // is never your spending or income, so it routes to a Credit Card → Cash
  // transfer. Must run before Pattern A2: the "for <someone>" + payback signal
  // distinguishes it from paying DOWN a card. ("paid 800 on my cc for jana,
  // she paid me back" → card→cash; "paid bpi cc 5000 from gcash" → pay-down.)
  final paidForSomeone = _tryPaidForSomeone(normalized, activeAccounts);
  if (paidForSomeone != null) {
    return paidForSomeone.copyWith(rawInput: raw, extras: extras);
  }

  // Pattern A2 — pay a credit account ("paid bpi cc 5000 from gcash"). Resolves
  // to a transfer that tops up (pays down) the credit account. Only fires when a
  // liability account is the clear target; otherwise falls through to amounts so
  // ordinary "pay jeepney 20" stays an expense.
  final payCredit = _tryPayCredit(normalized, activeAccounts);
  if (payCredit != null) {
    return payCredit.copyWith(rawInput: raw, extras: extras);
  }

  // Patterns B + C — signed / unsigned amount
  return _tryAmount(
    raw: raw,
    normalized: normalized,
    categories: categories,
    accounts: activeAccounts,
    learnedDict: learnedDict,
    extras: extras,
  );
}

/// Every single word appearing in an account name, lowercased. Used to stop the
/// date and beneficiary extractors from claiming a word that is really part of
/// an account the user named.
Set<String> _accountWords(List<FinancialAccount> accounts) => {
      for (final a in accounts)
        for (final w in a.name.toLowerCase().split(RegExp(r'\s+')))
          if (w.isNotEmpty) w,
    };

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
  DateTime? now,
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
            now: now,
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
          now: now,
        ),
  ];
  if (segments.length < 2) return single();
  return PreparseBatch(rawInput: raw, segments: segments);
}

// ─────────────────────────────────────────────────────────────────────────────
// Pre-pass extractions — note, dates, owedBy, arithmetic
// ─────────────────────────────────────────────────────────────────────────────

/// Extras pulled out of the text before the transaction patterns run, plus the
/// text with the consumed spans removed.
class _Extras {
  final String text;
  final String? note;
  final DateTime? date;
  final String? owedBy;
  final DateTime? paybackDate;
  const _Extras(this.text, this.note, this.date, this.owedBy, this.paybackDate);
}

const _kWeekdays = <String, int>{
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

const _kMonths = <String, int>{
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// A date phrase found in [text]: the value, and the span to remove.
class _DateHit {
  final DateTime date;
  final int start;
  final int end;
  const _DateHit(this.date, this.start, this.end);
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Most recent [weekday] at or before [now]. `last friday` forces a step back a
/// full week when today already is that weekday, which is how people say it.
DateTime _recentWeekday(DateTime now, int weekday, {required bool forcePast}) {
  final today = _dayOf(now);
  var delta = today.weekday - weekday;
  if (delta < 0) delta += 7;
  if (delta == 0 && forcePast) delta = 7;
  return today.subtract(Duration(days: delta));
}

/// Finds the first date phrase in [text].
///
/// Deliberately conservative about what counts as a date, because a false
/// positive silently back-dates money:
///
///  * Weekday names must be spelled in full — a three-letter "sun" or "mar"
///    collides with real account names.
///  * A month abbreviation is skipped when it prefix-matches an account name
///    ([accountWords]), so "mar 20" stays Maribank rather than becoming March.
///  * Slash forms ("08/20") are not read at all: they are indistinguishable
///    from the division the calculator syntax allows.
_DateHit? _findDate(String text, DateTime now, Set<String> accountWords) {
  final today = _dayOf(now);

  final relative = RegExp(
    r'\b(?:(today)|(yesterday)|day before yesterday|last week'
    r'|(\d{1,3})\s+days?\s+ago)\b',
  ).firstMatch(text);
  if (relative != null) {
    final whole = relative.group(0)!;
    final DateTime value;
    if (relative.group(1) != null) {
      value = today;
    } else if (relative.group(2) != null) {
      value = today.subtract(const Duration(days: 1));
    } else if (relative.group(3) != null) {
      value = today.subtract(Duration(days: int.parse(relative.group(3)!)));
    } else if (whole == 'last week') {
      value = today.subtract(const Duration(days: 7));
    } else {
      value = today.subtract(const Duration(days: 2)); // day before yesterday
    }
    return _DateHit(value, relative.start, relative.end);
  }

  final weekday = RegExp(
    '\\b(last\\s+)?(${_kWeekdays.keys.join('|')})\\b',
  ).firstMatch(text);
  if (weekday != null) {
    final value = _recentWeekday(now, _kWeekdays[weekday.group(2)!]!,
        forcePast: weekday.group(1) != null);
    return _DateHit(value, weekday.start, weekday.end);
  }

  final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
  if (iso != null) {
    final value = _safeDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
        int.parse(iso.group(3)!));
    if (value != null) return _DateHit(value, iso.start, iso.end);
  }

  final monthNames = _kMonths.keys.join('|');
  final named = RegExp(
    '\\b(?:($monthNames)\\s+(\\d{1,2})|(\\d{1,2})\\s+($monthNames))\\b',
  ).firstMatch(text);
  if (named != null) {
    final monthWord = named.group(1) ?? named.group(4)!;
    final dayStr = named.group(2) ?? named.group(3)!;
    // A short month name that could be an account prefix is not a date.
    if (!(monthWord.length <= 4 && accountWords.contains(monthWord))) {
      var value =
          _safeDate(today.year, _kMonths[monthWord]!, int.parse(dayStr));
      // A date later this year is far more likely last year's than the future.
      if (value != null && value.isAfter(today)) {
        value =
            _safeDate(today.year - 1, _kMonths[monthWord]!, int.parse(dayStr));
      }
      if (value != null) return _DateHit(value, named.start, named.end);
    }
  }

  return null;
}

/// Builds a date, returning null when the day overflows its month (so "feb 31"
/// is treated as not-a-date rather than silently rolling into March).
DateTime? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime(year, month, day);
  if (d.month != month || d.day != day) return null;
  return d;
}

/// A `note:` or `//` marker and everything after it, to the end of the segment.
final _noteMarker = RegExp(r'(?:\bnote\s*:|//)\s*(.*)$', caseSensitive: false);

/// Cue words that mark a following date as the *payback* date rather than the
/// transaction date ("spotted jana 800, she'll pay me back friday").
final _paybackCue = RegExp(
  r'pay(?:s|ing)?\s+(?:me\s+)?back|paid\s+(?:me\s+)?back|payback'
  r'|reimburse\w*|owes?\s+me',
);

/// Verbs that name a person outright — the word after one is who owes you.
final _lendVerb = RegExp(
  r'\b(?:spotted|lent|loaned|fronted|sponsored)\s+([a-z][\w\x27-]*)',
);

/// "<name> owes me" / "owed by <name>".
final _owesMe = RegExp(r'\b([a-z][\w\x27-]*)\s+owes?\s+me\b');
final _owedBy = RegExp(r'\bowed\s+by\s+([a-z][\w\x27-]*)\b');
final _forSomeone = RegExp(r'\bfor\s+([a-z][\w\x27-]*)');

/// Words that are never a person's name in this context, so `for <word>` can't
/// mistake a purpose for a beneficiary.
const _kNotNames = {
  'me',
  'my',
  'myself',
  'us',
  'the',
  'a',
  'an',
  'this',
  'that',
  'it',
  'work',
  'business',
  'food',
  'lunch',
  'dinner',
  'breakfast',
  'gas',
  'fuel',
  'rent',
  'bills',
  'bill',
  'groceries',
  'grocery',
  'now',
  'later',
  'today',
  'tomorrow',
  'free',
};

/// Collapses a calculator-style expression to a single number.
///
/// Only expressions with **no whitespace around the operator** are read, which
/// is what keeps "-500 -300" two amounts (a genuine ambiguity the caller must
/// reject) while "285+15" becomes one. A leading sign stays attached to the
/// result so "-285+15" is still an outflow.
String _collapseArithmetic(String text) => text.replaceAllMapped(
      RegExp(
          r'(?<=^|\s)([+-]?)(\d+(?:\.\d+)?(?:[+\-*/×÷]\d+(?:\.\d+)?)+)(?=\s|$)'),
      (m) {
        final value = evalAmountExpression(m.group(2)!);
        if (value == null) return m.group(0)!;
        final text = value == value.roundToDouble()
            ? value.toStringAsFixed(0)
            : value.toString();
        return '${m.group(1)}$text';
      },
    );

/// Pulls note, dates and the beneficiary out of [normalized], returning the
/// text the transaction patterns should parse.
///
/// Only the note and the date spans are removed. Everything else stays put:
/// the transfer patterns downstream key off words like "for" and "paid me
/// back", so consuming those would stop a card→cash wash transfer being
/// recognised at all.
_Extras _extractExtras({
  required String raw,
  required String normalized,
  required DateTime now,
  required Set<String> accountWords,
}) {
  var text = normalized;

  // 1. Note — `note:` or `//` to the end of the segment. Taken from the raw
  // string so the note keeps its capitalisation.
  String? note;
  final noteRe = _noteMarker;
  final rawNote = noteRe.firstMatch(raw);
  if (rawNote != null) {
    final captured = rawNote.group(1)?.trim() ?? '';
    if (captured.isNotEmpty) note = captured;
  }
  text = text.replaceAll(noteRe, ' ').trim();

  // 2. Payback date — a date that follows a payback cue belongs to the
  // receivable, not the transaction, so it is claimed first.
  DateTime? paybackDate;
  final cue = _paybackCue.firstMatch(text);
  if (cue != null) {
    final after = text.substring(cue.end);
    final hit = _findDate(after, now, accountWords);
    if (hit != null) {
      paybackDate = hit.date;
      // Remove only the date span. The cue words stay: downstream patterns
      // (and the reimbursable detector) match on them.
      text = text.replaceRange(cue.end + hit.start, cue.end + hit.end, ' ');
    }
  }

  // 3. Transaction date — from whatever text is left.
  DateTime? date;
  final hit = _findDate(text, now, accountWords);
  if (hit != null) {
    date = hit.date;
    text = text.replaceRange(hit.start, hit.end, ' ');
  }

  // 4. Beneficiary. Matched on the normalized text for position, then read back
  // out of the raw string so "Jana" is stored as the user wrote it.
  String? owedBy;
  for (final re in [_lendVerb, _owesMe, _owedBy]) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    final candidate = m.group(1)!;
    if (_kNotNames.contains(candidate) || accountWords.contains(candidate)) {
      continue;
    }
    owedBy = candidate;
    break;
  }
  // "for <someone>" is only a beneficiary when the text says the money is
  // coming back — otherwise "for food" would name food as the debtor.
  if (owedBy == null && _paybackCue.hasMatch(text)) {
    final m = _forSomeone.firstMatch(text);
    final candidate = m?.group(1);
    if (candidate != null &&
        !_kNotNames.contains(candidate) &&
        !accountWords.contains(candidate)) {
      owedBy = candidate;
    }
  }
  if (owedBy != null) owedBy = _originalCasing(raw, owedBy);

  // 5. Calculator expressions, last: the date pass must see "3 days ago"
  // before the digits could be folded into an amount.
  text = _collapseArithmetic(text);

  return _Extras(text.replaceAll(RegExp(r'\s+'), ' ').trim(), note, date,
      owedBy, paybackDate);
}

/// The part of [rawInput] that can still serve as a description, with the spans
/// the preparser turned into structured fields removed — the `note:` / `//`
/// tail and up to two date phrases (a payback date and a transaction date).
///
/// The commit path derives a description from raw input, so without this the
/// note text and the words "yesterday" would be repeated in the label of a
/// transaction that already carries them as a note and a date.
String chatDescriptionSource({
  required String rawInput,
  required List<FinancialAccount> accounts,
  DateTime? now,
}) {
  var s = rawInput.replaceAll(_noteMarker, ' ');
  final words = _accountWords(accounts);
  final clock = now ?? DateTime.now();
  // Find on a lowercased copy, cut from the original. Bail out if lowercasing
  // changed the length, since the indices would no longer line up.
  for (var pass = 0; pass < 2; pass++) {
    final lower = s.toLowerCase();
    if (lower.length != s.length) break;
    final hit = _findDate(lower, clock, words);
    if (hit == null) break;
    s = s.replaceRange(hit.start, hit.end, ' ');
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Recovers how the user actually capitalised [lowercased] in [raw].
String _originalCasing(String raw, String lowercased) {
  final m = RegExp('\\b${RegExp.escape(lowercased)}\\b', caseSensitive: false)
      .firstMatch(raw);
  return m?.group(0) ?? lowercased;
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
  required _Extras extras,
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

  // The beneficiary is only meaningful on an expense you expect back, so it
  // rides along only when the reimbursable signal fired. Storing a name on an
  // ordinary purchase would put a debtor on money nobody owes.
  final owedBy = reimbursable ? extras.owedBy : null;
  final paybackDate = reimbursable ? extras.paybackDate : null;

  // A name the beneficiary extractor claimed is not an unresolved token — it is
  // already accounted for, so asking the AI about it would be a wasted turn.
  final owedByToken = extras.owedBy?.toLowerCase();
  final remainingUnresolved = owedByToken == null
      ? unresolved
      : unresolved.where((t) => t != owedByToken).toList();

  return PreparseResult(
    rawInput: raw,
    amount: amount,
    type: inferredType,
    accountId: accountId,
    categoryId: categoryId,
    reimbursable: reimbursable,
    date: extras.date,
    note: extras.note,
    owedBy: owedBy,
    expectedReimbursementDate: paybackDate,
    unresolvedTokens: remainingUnresolved,
    ambiguousAccountTokens: ambiguous,
  );
}

/// Detects a reimbursable-expense intent: money spent now that you expect back
/// later (future payback, owed-by, or work/business-expense phrasing). The
/// past-tense "paid me back"/"refunded" cases are handled as transfers upstream.
bool _detectReimbursable(String normalized) {
  return RegExp(
    r'reimburs' // reimburse / reimbursable / reimbursement / reimbursed
    // Conjugated, so the natural "she pays me back" / "paying me back" are
    // recognised too. Missing them meant the payback cue fired for the date
    // but the reimbursable flag did not, and the whole chain — flag, debtor,
    // payback date — was then discarded downstream.
    r'|pay(?:s|ing)?\s+me\s+back'
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
  _collapseNameFragments(spans, tokens, accounts);
  final leftover = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (!claimed[i]) leftover.add(tokens[i]);
  }
  // A token that resolved on a wider pass isn't ambiguous after all.
  ambiguous.removeWhere((t) => !leftover.contains(t));
  return _AccountScan(spans, leftover, ambiguous);
}

/// An account name's words, punctuation stripped: "Credit Card (Maya)" becomes
/// {credit, card, maya}.
Set<String> _accountNameWords(FinancialAccount a) => a.name
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9ñ]+'))
    .where((w) => w.isNotEmpty)
    .toSet();

/// Collapses a run of touching spans that is really one account's name written
/// loosely, in place.
///
/// The span matcher tries the widest phrase first, so a name written exactly is
/// matched whole. A name written out of order is not: with accounts "MAYA" and
/// "Credit Card (Maya)", the run "maya credit card" matches no phrase entire, so
/// it falls to the narrower passes and comes back as *two* spans — "credit card"
/// (a prefix of the card) and "maya" (the e-wallet, exactly). The caller then
/// takes the leftmost, which is the e-wallet: money on the card was logged
/// against the wallet, and the user's own words named the card three times.
///
/// A run collapses only when exactly one account's name words account for every
/// token in it. That is what keeps a two-account transfer intact: "bpi gcash"
/// touches too, but no account is named by both words, so it stays two spans and
/// the direction survives. Two accounts covering the same run is ambiguous, not
/// a merge, so it is left alone for the AI to ask about.
void _collapseNameFragments(
  List<_AccountSpan> spans,
  List<String> tokens,
  List<FinancialAccount> accounts,
) {
  if (spans.length < 2) return;
  var i = 0;
  while (i < spans.length - 1) {
    // Grow the widest run of spans that touch end-to-start from here.
    var j = i;
    while (j < spans.length - 1 && spans[j].end == spans[j + 1].start) {
      j++;
    }
    if (j == i) {
      i++;
      continue;
    }
    final start = spans[i].start;
    final end = spans[j].end;
    final runTokens = {
      for (final t in tokens.getRange(start, end))
        for (final w in t.toLowerCase().split(RegExp(r'[^a-z0-9ñ]+')))
          if (w.isNotEmpty) w,
    };
    final covering = accounts
        .where((a) => _accountNameWords(a).containsAll(runTokens))
        .toList();
    if (covering.length == 1) {
      spans.replaceRange(i, j + 1, [
        _AccountSpan(covering.first.id, start, end),
      ]);
    }
    i++;
  }
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
  /// Stamps the raw input, and folds in what the pre-pass lifted out of the
  /// text. The transfer patterns build their result from the stripped text and
  /// know nothing about the note or dates, so this is where those rejoin.
  ///
  /// [_Extras.owedBy] is deliberately NOT applied here: a transfer has no
  /// debtor. Only the expense path in [_tryAmount] carries it.
  PreparseResult copyWith({String? rawInput, _Extras? extras}) =>
      PreparseResult(
        amount: amount,
        type: type,
        accountId: accountId,
        transferToAccountId: transferToAccountId,
        categoryId: categoryId,
        reimbursable: reimbursable,
        date: extras?.date ?? date,
        note: extras?.note ?? note,
        owedBy: owedBy,
        expectedReimbursementDate: expectedReimbursementDate,
        unresolvedTokens: unresolvedTokens,
        ambiguousAccountTokens: ambiguousAccountTokens,
        hardError: hardError,
        rawInput: rawInput ?? this.rawInput,
      );
}
