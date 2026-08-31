// One-call finance extraction (Plan 058).
//
// The whole message goes to the model once and comes back as a list of
// transactions. This replaces the split-then-classify-each-fragment pipeline in
// `finance_nlp_parser.dart` + `finance_classifier_parser.dart`, which cut the
// message on "and"/"then"/"," before the model ever read it, dropped every
// fragment carrying no digit, and then called the classifier once per fragment
// with only that fragment visible. Context stated once — the account, the date —
// reached exactly one entry, and the words that named them were often in the
// piece that got dropped.
//
// Pure: prompt in, validated drafts out. No I/O, so every rule below is
// unit-testable without a model.

import 'dart:convert';

import '../models/finance/extracted_entry.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/transaction_record.dart';

/// Hard cap on entries from one message. A message describing more than this is
/// far more likely to be a paragraph the model over-segmented than a genuine
/// list, and the cap also bounds the response size against `max_tokens`.
const int kMaxExtractedEntries = 10;

/// Learned token→category pairs sent with the prompt. The dictionary grows
/// without limit as the user confirms entries, but the prompt has a size cap
/// (`_MAX_PROMPT_LEN` in the Lambda, which truncates silently), so only this
/// many are carried. They are the model's hint, not its only source — an
/// unlisted token is still inferred from meaning.
const int kMaxLearnedPairsInPrompt = 40;

/// Builds the extraction prompt.
///
/// Ordering is deliberate: the stable blocks (role, rules, accounts,
/// categories, dictionary) come first and the volatile ones (today, the
/// message) last, so a prompt cache can be switched on later without moving
/// anything. [now] is injected so "yesterday" is testable.
String buildFinanceExtractionPrompt({
  required String message,
  required List<FinanceCategory> categories,
  required List<FinancialAccount> accounts,
  required Map<String, String> learnedMappings,
  required DateTime now,
  required String Function(String categoryId) categoryNameFor,
}) {
  final accountsJson = jsonEncode(accounts
      .map((a) => {
            'name': a.name,
            'kind': a.category.name,
            if (a.isLiability) 'liability': true,
          })
      .toList(growable: false));

  final categoriesJson = jsonEncode(categories
      .map((c) => {'name': c.name, 'type': c.type.name})
      .toList(growable: false));

  // Send the dictionary as token→category *name*, not id: the model answers in
  // names, so ids would be a vocabulary it can't use and would waste prompt.
  final dict = <String, String>{};
  for (final entry in learnedMappings.entries) {
    if (dict.length >= kMaxLearnedPairsInPrompt) break;
    final name = categoryNameFor(entry.value);
    if (name.isEmpty) continue;
    dict[entry.key] = name;
  }
  final dictJson = jsonEncode(dict);

  final today = _isoDate(now);
  final weekday = _weekdayName(now);

  return 'You extract personal-finance transactions from a message. '
      'Output JSON only — no prose, no code fences.\n'
      '\n'
      'ACCOUNTS (choose by exact "name"): $accountsJson\n'
      'CATEGORIES (choose by exact "name"): $categoriesJson\n'
      'LEARNED token -> category: $dictJson\n'
      '\n'
      'OUTPUT SHAPE:\n'
      '{"entries":[{"type":"outflow|inflow|transfer","amount":0,'
      '"account":"","transferTo":null,"category":"","description":"",'
      '"note":null,"date":"YYYY-MM-DD","reimbursable":false,'
      '"expectedReimbursementDate":null,"owedBy":null,"confidence":0.0,'
      '"missing":[]}],"unclear":null}\n'
      '\n'
      'RULES:\n'
      '1. One entry per distinct amount. Words with no amount of their own are '
      'DESCRIPTION for the nearest entry — never a separate entry, never '
      'discarded.\n'
      '2. CONTEXT STATED ONCE APPLIES TO EVERY ENTRY IT PLAUSIBLY COVERS. '
      '"in maribank ... all yesterday" sets the account AND the date for every '
      'entry in that message. This is the most important rule here.\n'
      '3. "account" and "category" MUST be an exact "name" from the lists '
      'above. Never invent one. If nothing fits, set the field null and add its '
      'name to "missing".\n'
      '4. "missing" lists ONLY these structured fields you could not determine: '
      'amount, type, account, transferTo, category. Never list description, '
      'note or owedBy.\n'
      '5. "date" is always an absolute YYYY-MM-DD, resolved against TODAY '
      'below. Never a phrase like "yesterday". Never a future date unless the '
      'message explicitly names one.\n'
      '6. "description" is a short Title Case label for what the money was for '
      '("Avocado Ice Cream", "Grab Ride", "Electric Bill"). Never include the '
      'amount, the account name, or the date.\n'
      '7. A category\'s "type" must agree with the entry\'s: income categories '
      'go with "inflow", expense categories with "outflow".\n'
      '8. "transfer" means money moving between two of the accounts above. '
      'It needs "transferTo", which must differ from "account", and no '
      'category.\n'
      '9. Set "reimbursable" true when the message says someone owes it back '
      '("work expense", "she\'ll pay me back", "spotted"), and put the debtor '
      'in "owedBy".\n'
      '10. "confidence" is your own 0-1 certainty for that one entry.\n'
      '11. At most $kMaxExtractedEntries entries.\n'
      '12. If the message names no amount at all, return {"entries":[],'
      '"unclear":"<one short question>"}.\n'
      '\n'
      'TODAY: $today ($weekday)\n'
      'MESSAGE: "${message.replaceAll('"', "'")}"\n'
      'Output:';
}

/// The outcome of one extraction call.
class ExtractionResult {
  final List<ExtractedEntry> entries;

  /// Set when the model could find nothing to log and asked something back.
  final String? unclear;

  const ExtractionResult({this.entries = const [], this.unclear});

  bool get isEmpty => entries.isEmpty;
}

/// Parses raw model output into validated drafts.
///
/// Returns null when no JSON object can be found or it doesn't decode — the
/// caller treats that as "the cloud tier failed" and falls back to the regex
/// path, rather than showing the user a half-read message.
///
/// Every named entity is bound against the live account/category lists. A name
/// that doesn't match is NOT fatal: that one field is left null and added to
/// [ExtractedEntry.missing], so the row reaches the confirm card with a picker
/// instead of taking the whole message to a blank form.
ExtractionResult? parseFinanceExtractionResponse({
  required String text,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  required DateTime now,
}) {
  final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
  if (match == null) return null;

  final dynamic decoded;
  try {
    decoded = jsonDecode(match.group(0)!);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final rawEntries = decoded['entries'];
  final unclear = (decoded['unclear'] as String?)?.trim();

  if (rawEntries is! List) {
    // A response with no entries list but a question is a legitimate "I found
    // nothing to log"; anything else is malformed.
    if (unclear != null && unclear.isNotEmpty) {
      return ExtractionResult(unclear: unclear);
    }
    return null;
  }

  final entries = <ExtractedEntry>[];
  for (final raw in rawEntries) {
    if (entries.length >= kMaxExtractedEntries) break;
    if (raw is! Map<String, dynamic>) continue;
    final entry = _bindEntry(
      raw: raw,
      accounts: accounts,
      categories: categories,
      now: now,
    );
    if (entry != null) entries.add(entry);
  }

  if (entries.isEmpty) {
    return ExtractionResult(
      unclear: (unclear != null && unclear.isNotEmpty) ? unclear : null,
    );
  }
  return ExtractionResult(entries: entries);
}

/// Binds one raw entry object. Returns null only when there is nothing usable
/// at all — no amount and no way to ask for one.
ExtractedEntry? _bindEntry({
  required Map<String, dynamic> raw,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  required DateTime now,
}) {
  final missing = <EntryField>{};

  // The model is asked to declare what it couldn't determine. Trust that as a
  // starting point, then verify every field ourselves below — a model that
  // forgot to list a gap must not produce a row that looks complete.
  final declared = raw['missing'];
  if (declared is List) {
    for (final f in declared.whereType<String>()) {
      final field = EntryField.values
          .where((e) => e.name.toLowerCase() == f.trim().toLowerCase())
          .firstOrNull;
      if (field != null) missing.add(field);
    }
  }

  final amount = (raw['amount'] as num?)?.toDouble();
  final hasAmount = amount != null && amount > 0;
  if (!hasAmount) missing.add(EntryField.amount);

  final typeName = (raw['type'] as String?)?.trim().toLowerCase();
  var type =
      TransactionType.values.where((t) => t.name == typeName).firstOrNull;

  final accountId = _accountIdByName(raw['account'] as String?, accounts);
  if (accountId == null) missing.add(EntryField.account);

  String? transferToId;
  String? categoryId;

  if (type == TransactionType.transfer) {
    transferToId = _accountIdByName(raw['transferTo'] as String?, accounts);
    // A destination equal to the source is not a transfer; treat it as absent
    // so the picker asks, rather than committing a no-op that moves nothing.
    if (transferToId == null || transferToId == accountId) {
      transferToId = null;
      missing.add(EntryField.transferTo);
    }
  } else {
    final cat = _categoryByName(raw['category'] as String?, categories);
    if (cat == null) {
      missing.add(EntryField.category);
    } else {
      final wanted = cat.type == CategoryType.income
          ? TransactionType.inflow
          : TransactionType.outflow;
      if (type == null) {
        // The category settles the direction on its own, so an omitted type is
        // recoverable rather than a gap to ask about.
        type = wanted;
      } else if (type != wanted) {
        // A stated type that contradicts its category is the model being
        // inconsistent with itself. The category names the money's purpose and
        // is the more specific claim, so keep it and take its direction.
        type = wanted;
      }
      categoryId = cat.id;
    }
  }

  if (type == null) missing.add(EntryField.type);

  // Nothing to show and nothing to ask about — drop the row rather than render
  // an empty card line.
  if (!hasAmount && accountId == null && categoryId == null) return null;

  final date = _parseIsoDate(raw['date'] as String?, now);
  final description = (raw['description'] as String?)?.trim() ?? '';
  final note = _nullIfBlank(raw['note'] as String?);
  final owedBy = _nullIfBlank(raw['owedBy'] as String?);
  final reimbursable =
      raw['reimbursable'] == true && type != TransactionType.inflow;

  return ExtractedEntry(
    txn: ParsedTransaction(
      amount: hasAmount ? amount : null,
      type: type,
      accountId: accountId,
      transferToAccountId: transferToId,
      categoryId: categoryId,
      reimbursable: reimbursable,
      date: date,
      note: note,
      owedBy: reimbursable ? owedBy : null,
      expectedReimbursementDate: reimbursable
          ? _parseIsoDate(raw['expectedReimbursementDate'] as String?, now,
              allowFuture: true)
          : null,
      description: description,
      // The model writes a clean label, so the commit path must not run its
      // strip-the-raw-input pass over it.
      descriptionIsClean: description.isNotEmpty,
    ),
    missing: missing,
    confidence: (raw['confidence'] as num?)?.toDouble() ?? 1,
  );
}

String? _accountIdByName(String? name, List<FinancialAccount> accounts) {
  final n = name?.trim().toLowerCase();
  if (n == null || n.isEmpty) return null;
  for (final a in accounts) {
    if (a.name.toLowerCase() == n) return a.id;
  }
  return null;
}

FinanceCategory? _categoryByName(
    String? name, List<FinanceCategory> categories) {
  final n = name?.trim().toLowerCase();
  if (n == null || n.isEmpty) return null;
  for (final c in categories) {
    if (c.name.toLowerCase() == n) return c;
  }
  return null;
}

/// Reads a `YYYY-MM-DD` date. Returns null when absent or unparseable, which
/// the commit path already treats as "stamp now".
///
/// A past-dated entry is normal (logging yesterday's spending is the common
/// case); a future one is almost always the model mis-resolving a relative
/// phrase, so it is rejected back to null unless the caller expects one — a
/// payback date is legitimately in the future.
DateTime? _parseIsoDate(String? raw, DateTime now, {bool allowFuture = false}) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  if (!allowFuture && parsed.isAfter(endOfToday)) return null;
  return parsed;
}

String? _nullIfBlank(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _weekdayName(DateTime d) => const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ][d.weekday - 1];
