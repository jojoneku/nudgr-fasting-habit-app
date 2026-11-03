import '../models/finance/capture_settings.dart';
import '../models/finance/captured_transaction.dart';
import '../models/finance/finance_category.dart';
import '../models/finance/finance_parse_result.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/raw_capture.dart';
import '../models/finance/transaction_record.dart';
import '../services/finance_personal_dictionary.dart';
import 'capture_templates.dart';
import 'finance_nlp_parser.dart'
    show matchAccountNameInText, resolveCategoryByName;

/// Pure function from one queued notification to an inbox row, or `null`
/// when the notification is not a money movement at all.
///
/// Reject first: an OTP or security prompt, a promo, a reminder, or a failed /
/// pending / reversed transaction never becomes a row ([captureRejectReason]).
/// A text that no template matched and that holds no amount is dropped too,
/// unless it holds a digit *and* a direction cue or the user's own card
/// suffix — a money alert always carries a figure, so "Transfer funds from
/// Maya Easy Credit" (a cue, no figure) and "Over 50% OFF!" (a figure, no
/// cue) are both product nudges the cue list has not met yet. Everything
/// else becomes a row, even with no parsed amount — the user can type one.
///
/// Resolution order — each step fills only what is still null:
///  1. a per-app template (`capture_templates.dart`) sets direction and lifts
///     amount / counterparty / own last-4;
///  2. the generic pass finds the first amount that is not a balance (a bare
///     number counts only straight after a money verb), a direction cue word,
///     a counterparty after `to` / `at` / `from`, and the user's own masked
///     card suffix (one that follows `your`, with no `to` / `from` between);
///  3. account: the last-4 map, else the per-source default, else the
///     account whose name matches the source app's name (a "Maya" push lands
///     on the Maya account without the user mapping it first);
///  4. transfer: a counterparty that names one of the user's *other*
///     accounts, or a whole-name mention in the body that is not the user's
///     own instrument (`using your Maya card` is not a transfer to Maya),
///     turns the row into a transfer with the reserved transfer category;
///  5. category: the personal dictionary, then the category list by name;
///  6. date: the post time. Notifications arrive live, so this is right.
///
/// Confidence: 1.0 template, 0.6 generic with a direction, 0.3 amount only,
/// 0 when no amount was found.
CapturedTransaction? parseCapture(
  RawCapture raw, {
  required CaptureSettings settings,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  FinancePersonalDictionary? dict,
  DateTime? now,
}) {
  final text = _collapse('${raw.title}. ${raw.text}');
  final body = _collapse(raw.text);

  if (captureRejectReason(text) != null) return null;

  double? amount;
  TransactionType? type;
  String? counterparty;
  String? last4;
  var confidence = 0.0;
  // Google Wallet names the user's card in the payment line ("with Visa BPI
  // •••• 1234"); that is the source side, never the other end of a transfer.
  var scanBodyForTransfer = true;
  String? cardLabel;

  // 0. Google Wallet: payment line + merchant field, either order.
  if (raw.packageName == kGoogleWalletPackage) {
    final w = _parseWalletPayment(raw.title, raw.text);
    if (w == null) return null;
    amount = w.amount;
    type = TransactionType.outflow;
    counterparty = w.merchant;
    last4 = w.last4;
    cardLabel = w.cardLabel;
    confidence = 1.0;
    scanBodyForTransfer = false;
  }

  // 1. Template.
  var templateHit = false;
  for (final t
      in kCaptureTemplates[raw.packageName] ?? const <CaptureTemplate>[]) {
    if (amount != null) break;
    final m = t.pattern.firstMatch(body) ?? t.pattern.firstMatch(text);
    if (m == null) continue;
    templateHit = true;
    // A template without an `amount` group fixes the direction only; the
    // generic pass still looks for the number and the row keeps 0.6.
    if (t.pattern.pattern.contains('(?<amount>')) {
      amount = _parseAmount(_group(m, 'amount'));
      if (amount == null) continue;
      confidence = 1.0;
    }
    type = t.type;
    counterparty = _cleanCounterparty(_group(m, 'counterparty'));
    last4 = _group(m, 'last4') ?? _group(m, 'last4b') ?? _group(m, 'last4c');
    break;
  }

  // 2. Generic pass. No template and no amount: the text has to hold a
  //    digit *and* a direction cue or the user's own card suffix to be a
  //    money alert at all. A digit alone is not enough — "Over 50% OFF!",
  //    "70% OFF holiday deals" and "expires in 2 hours" all hold one (seen
  //    on device from Shopee, 2026-11-03); a cue alone is not either —
  //    "Transfer funds from Maya Easy Credit" has the verb and no figure.
  amount ??= _firstTransactionAmount(body) ?? _firstTransactionAmount(text);
  type ??= _directionOf(text);
  last4 ??= _ownLast4(text);
  if (!templateHit &&
      amount == null &&
      (!_anyDigit.hasMatch(text) || (type == null && last4 == null))) {
    return null;
  }
  counterparty ??= _genericCounterparty(body, type);
  if (confidence == 0 && amount != null) {
    confidence = type == null ? 0.3 : 0.6;
  }

  // 3. Account: the learned suffix, else the card label's own name
  //    ("Visa BPI •••• 1234" → the BPI card), else the per-source default.
  String? accountId;
  if (last4 != null) {
    accountId = accountForSuffix(settings.accountByLast4, last4);
  }
  if (accountId == null && cardLabel != null) {
    // "BPI Debit Mastercard" is the BPI bank account, not the BPI credit
    // card; a label that says neither is a credit card first, as Wallet
    // mostly carries those.
    final debit = _debitLabel.hasMatch(cardLabel);
    accountId =
        matchAccountNameInText(cardLabel, accounts, liability: !debit) ??
            matchAccountNameInText(cardLabel, accounts, liability: debit);
  }
  accountId ??= settings.accountBySource[raw.packageName];
  final liveIds = accounts.map((a) => a.id).toSet();
  if (accountId != null && !liveIds.contains(accountId)) accountId = null;
  accountId ??= resolveSourceAccount(
    packageName: raw.packageName,
    appLabel: raw.appLabel,
    settings: settings,
    accounts: accounts,
  );

  // 4. Transfer between the user's own accounts.
  String? transferTo;
  String? categoryId;
  final other = _otherAccountIn(
    counterparty: counterparty,
    text: scanBodyForTransfer ? body : '',
    accounts: accounts,
    exclude: accountId,
  );
  if (other != null && type != null && accountId != null) {
    if (type == TransactionType.outflow) {
      transferTo = other;
    } else {
      transferTo = accountId;
      accountId = other;
    }
    type = TransactionType.transfer;
    categoryId = FinanceCategory.transferCategoryId;
  }

  // 5. Category.
  if (categoryId == null && type != null && type != TransactionType.transfer) {
    categoryId = _categoryFor(counterparty, type, categories, dict);
  }

  // Mail: the title is the sender, so the row is labelled by it and a row
  // with no counterparty is described by the subject line, not the sender.
  final isMail = raw.packageName == kGmailPackage;
  final description = counterparty?.isNotEmpty == true
      ? counterparty!
      : isMail && body.isNotEmpty
          ? _firstSentence(body)
          : (raw.title.trim().isNotEmpty
              ? raw.title.trim()
              : '${raw.appLabel} transaction');
  final sourceLabel = isMail && raw.title.trim().isNotEmpty
      ? raw.title.trim()
      : raw.appLabel.isNotEmpty
          ? raw.appLabel
          : settings.labelFor(raw.packageName);

  final fp = raw.fingerprint.isNotEmpty
      ? raw.fingerprint
      : '${raw.packageName}|${raw.postedAt.millisecondsSinceEpoch}|${body.hashCode}';

  return CapturedTransaction(
    id: 'cap_${raw.postedAt.millisecondsSinceEpoch}_${fp.length > 8 ? fp.substring(0, 8) : fp}',
    source: CaptureSource.androidNotification,
    sourceApp: raw.packageName,
    sourceLabel: sourceLabel,
    capturedAt: raw.postedAt,
    rawTitle: raw.title,
    rawText: raw.text,
    fingerprint: fp,
    draft: ParsedTransaction(
      amount: amount,
      type: type,
      accountId: accountId,
      transferToAccountId: transferTo,
      categoryId: categoryId,
      description: description,
      descriptionIsClean: true,
      date: raw.postedAt,
    ),
    confidence: confidence,
    accountLast4: last4,
    updatedAt: now ?? DateTime.now(),
  );
}

final RegExp _debitLabel =
    RegExp(r'\b(?:debit|savings|prepaid|atm)\b', caseSensitive: false);

/// The account learned for a masked suffix. Exact first; otherwise the one
/// entry whose digits end with [suffix] (or that [suffix] ends with), so the
/// BPI app's three-digit `637` finds the `1637` the BPI email taught. Two
/// candidates mean a guess, so none is returned.
String? accountForSuffix(Map<String, String> byLast4, String suffix) {
  final exact = byLast4[suffix];
  if (exact != null) return exact;
  String? hit;
  for (final e in byLast4.entries) {
    if (e.key.endsWith(suffix) || suffix.endsWith(e.key)) {
      if (hit != null && hit != e.value) return null;
      hit = e.value;
    }
  }
  return hit;
}

/// The account a source app lands on when the user has mapped none: the
/// account whose name matches the app's name ("Maya" → Maya, "MariBank" →
/// MariBank, "Shopee" → ShopeePay). The user's own mapping in
/// `accountBySource` always wins; this only fills the gap, and it never
/// guesses for mail, where the app name says nothing about the money.
/// Returns null when no account name matches or the account no longer exists.
String? resolveSourceAccount({
  required String packageName,
  required String appLabel,
  required CaptureSettings settings,
  required List<FinancialAccount> accounts,
}) {
  if (packageName == kGmailPackage || accounts.isEmpty) return null;
  final mapped = settings.accountBySource[packageName];
  if (mapped != null && accounts.any((a) => a.id == mapped)) return mapped;
  final presetLabel = settings.labelFor(packageName);
  for (final label in {
    appLabel.trim(),
    if (presetLabel != packageName) presetLabel.trim(),
  }) {
    if (label.isEmpty) continue;
    final id = matchAccountNameInText(label, accounts);
    if (id != null) return id;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Wallet
// ─────────────────────────────────────────────────────────────────────────────

class _WalletPayment {
  final double amount;
  final String? merchant;
  final String? last4;
  final String cardLabel;
  const _WalletPayment(this.amount, this.merchant, this.last4, this.cardLabel);
}

final RegExp _walletLineRe = RegExp(kWalletPaymentLine, caseSensitive: false);
final RegExp _walletLast4Re = RegExp(kWalletCardLast4);
const Set<String> _walletAppNames = {
  'google wallet',
  'google pay',
  'wallet',
  'gpay',
};

/// Finds the payment line in the title or the text and takes the other field
/// as the merchant. `null` when neither field is a payment (card added, pass
/// updated, setup complete).
_WalletPayment? _parseWalletPayment(String title, String text) {
  final t = _collapse(title);
  final b = _collapse(text);
  final tm = _walletLineRe.firstMatch(t);
  final bm = _walletLineRe.firstMatch(b);
  if (tm == null && bm == null) return null;
  final RegExpMatch m;
  final String other;
  if (tm != null && bm != null) {
    // Both look like money (a merchant with digits): the card mask decides.
    final titleHasCard = _walletLast4Re.hasMatch(t);
    final bodyHasCard = _walletLast4Re.hasMatch(b);
    if (bodyHasCard && !titleHasCard) {
      m = bm;
      other = t;
    } else {
      m = tm;
      other = b;
    }
  } else if (tm != null) {
    m = tm;
    other = b;
  } else {
    m = bm!;
    other = t;
  }
  final amount = _parseWalletAmount(_group(m, 'amount'));
  if (amount == null) return null;
  final card = _group(m, 'card')?.trim() ?? '';
  final last4 = _walletLast4Re.firstMatch(card)?.namedGroup('last4');
  var merchant = _group(m, 'merchant') ?? _group(m, 'merchant2');
  merchant ??= other;
  merchant = _cleanCounterparty(merchant);
  if (merchant != null && _walletAppNames.contains(merchant.toLowerCase())) {
    merchant = null;
  }
  return _WalletPayment(amount, merchant, last4, card);
}

/// `1,250.00`, `12,34` (decimal comma), `1 234,56`, `1.234,56`.
double? _parseWalletAmount(String? raw) {
  if (raw == null) return null;
  var s = raw.replaceAll(RegExp(r'[ \u00A0\u202F]'), '');
  final decimalComma = RegExp(r'^\d{1,3}(?:\.\d{3})*,\d{1,2}$').hasMatch(s) ||
      RegExp(r'^\d+,\d{1,2}$').hasMatch(s);
  if (decimalComma) {
    s = s.replaceAll('.', '').replaceFirst(',', '.');
  } else {
    s = s.replaceAll(',', '');
  }
  final v = double.tryParse(s);
  if (v == null || v <= 0) return null;
  return v;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reject-first filter
// ─────────────────────────────────────────────────────────────────────────────

/// Why a notification is not a money movement, or `null` when it may be one.
///
/// Reasons: `otp` (a code or security prompt — never kept, never shown),
/// `promo` (marketing, product nudges, bill reminders), `failed` (a
/// transaction that did not or has not yet happened). Word lists follow the
/// reject-first classifier in danrave1234/paytsek, trimmed to what PH apps
/// actually send; `cashback` and `refund` stay out because those are money in.
String? captureRejectReason(String text) {
  if (_otpCue.hasMatch(text)) return 'otp';
  if (_failedCue.hasMatch(text)) return 'failed';
  if (_promoCue.hasMatch(text)) return 'promo';
  return null;
}

final RegExp _otpCue = RegExp(
  r'\bOTP\b|one[- ]time\s+(?:pin|password|code)|authentication\s+code|verification\s+code|\bMPIN\b|do\s+not\s+share|never\s+share|login\s+attempt|new\s+device|\bpassword\b|\bsuspicious\b',
  caseSensitive: false,
);
final RegExp _failedCue = RegExp(
  r'\bfailed\b|\bunsuccessful\b|\bdeclined\b|\bpending\b|\bprocessing\b|\breversed\b|\bcancel(?:led|ed)?\b|\bexpired\b|\bnot\s+(?:be\s+)?completed\b',
  caseSensitive: false,
);
final RegExp _promoCue = RegExp(
  r'\bpromo\b|\bvoucher\b|\bdiscount\b|\braffle\b|\bwin\b|\bGForest\b|\bGLife\b|\bGInvest\b|\bGCredit\b|\bGLoan\b|\bGGives\b|\bGSave\b|\bGInsure\b|\bexclusive\b|\blimited\s+time\b|\bapply\s+now\b|\btap\s+to\s+(?:start|learn|apply|claim|try|join|explore|get)\b|\bget\s+started\b|\bturn\s+on\b|\bneeds?\s+a\s+(?:refill|top[- ]?up)\b|\breminder\b|\bis\s+due\b|\bdue\s+(?:on|today|tomorrow)\b'
  // Marketing shapes seen on device 2026-11-03 (Shopee "Over 50% OFF!",
  // "70% OFF holiday deals", "unlock your Lucky Draw before it expires in…";
  // MariBank "Don't let your Wi-Fi drop!"; Maya "earn up to ₱4,000"). A
  // percentage or an amount followed by "off", a sale or deal, "up to", an
  // expiry, a lucky draw, an unlock / claim call-to-action, a "don't let /
  // miss" hook, and parcel tracking are never a posted transaction. "free"
  // stays out: "Transfer fee: Free" is printed on real GCash sends.
  r'|(?<=\d|%)\s*off\b|\d\s?%|\bsale\b|\bdeals?\b|\bup\s+to\b|\bexpir(?:e|es|ing|y)\b|\blucky\s+draw\b|\bunlock\b|\bclaim\s+(?:your|now|it)\b|\bdon(?:\u2019|\x27)?t\s+(?:let|miss|forget)\b|\bmiss\s+out\b|\bparcel\b|\btrack\s+your\b|\bshop\s+now\b|\bbuy\s+now\b|\bhurry\b|\blast\s+(?:chance|day)\b|\btoday\s+only\b|\bt&cs?\s+apply\b|\bterms\s+apply\b|\bcongrat(?:s|ulations)\b|\brefer(?:ral)?\s+(?:a|your|now)\b|\bsurvey\b|\bintroducing\b',
  caseSensitive: false,
);

// ─────────────────────────────────────────────────────────────────────────────
// Generic pass helpers
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _anyDigit = RegExp(r'\d');

final RegExp _amountRe = RegExp(
  // The trailing guard keeps a half-cut "PHP 4,0…" from reading as 4.
  r'(?:PHP|PhP|Php|php|₱|\bP)\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)(?![\d,])',
);

/// A number with two decimals straight after a money verb, no currency mark:
/// `received 500.00 in your wallet`. Two decimals so a date or a ref never
/// reads as money.
final RegExp _bareAmountAfterVerbRe = RegExp(
  r'\b(?:received|sent|paid|credited(?:\s+with)?|debited|transferred|amount(?:\s+of)?:?)\s+(\d{1,3}(?:,\d{3})+\.\d{2}|\d+\.\d{2})\b',
  caseSensitive: false,
);

/// Words that mark an amount as a *balance*, not the movement.
final RegExp _balanceCue = RegExp(
  r'(balance|bal\.|available|limit|remaining|outstanding|total due)',
  caseSensitive: false,
);

final RegExp _outCue = RegExp(
  r'\b(sent|paid|payment|purchase|purchased|debited|debit|withdrawn|withdrawal|transferred|transfer|cash[- ]?out|spent|charged|charge|bill|used|for the amount)\b',
  caseSensitive: false,
);
final RegExp _inCue = RegExp(
  r'\b(received|credited|credit|refund|refunded|cash[- ]?in|cashed in|deposited|deposit|reimburse(?:d|ment)?|salary|payout|incoming)\b',
  caseSensitive: false,
);

final RegExp _toCue = RegExp(
  r'\b(?:to|at)\s+' + kCounterpartyGroup,
  caseSensitive: false,
);
final RegExp _fromCue = RegExp(
  r'\bfrom\s+' + kCounterpartyGroup,
  caseSensitive: false,
);
final RegExp _last4Re = RegExp(kLast4Group, caseSensitive: false);

String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The subject-like first sentence of an email head, capped for a row title.
String _firstSentence(String s) {
  final cut = s.indexOf(RegExp(r'[.!?]\s|\s(?:Dear|Hi|Hello)\b'));
  var out = cut > 0 ? s.substring(0, cut) : s;
  out = out.replaceFirst(_trailingJunk, '');
  if (out.length > 48) out = '${out.substring(0, 47).trim()}…';
  return out;
}

String? _group(RegExpMatch m, String name) {
  try {
    return m.namedGroup(name);
  } on ArgumentError {
    return null;
  }
}

double? _parseAmount(String? raw) {
  if (raw == null) return null;
  final v = double.tryParse(raw.replaceAll(',', ''));
  if (v == null || v <= 0) return null;
  return v;
}

/// The first amount whose preceding 30 characters do not say "balance".
double? _firstTransactionAmount(String text) {
  double? fallback;
  for (final m in _amountRe.allMatches(text)) {
    final v = _parseAmount(m.group(1));
    if (v == null) continue;
    final start = m.start - 30 < 0 ? 0 : m.start - 30;
    final before = text.substring(start, m.start);
    if (_balanceCue.hasMatch(before)) {
      fallback ??= v;
      continue;
    }
    return v;
  }
  if (fallback != null) return fallback;
  final bare = _bareAmountAfterVerbRe.firstMatch(text);
  return bare == null ? null : _parseAmount(bare.group(1));
}

/// Direction from whichever cue word comes first.
TransactionType? _directionOf(String text) {
  final out = _outCue.firstMatch(text);
  final inn = _inCue.firstMatch(text);
  if (out == null && inn == null) return null;
  if (out == null) return TransactionType.inflow;
  if (inn == null) return TransactionType.outflow;
  // "payment received" / "received your payment": the inflow word wins when
  // the two are adjacent, because the outflow word is then the object.
  if ((inn.start - out.end).abs() <= 2) return TransactionType.inflow;
  return out.start < inn.start
      ? TransactionType.outflow
      : TransactionType.inflow;
}

String? _genericCounterparty(String text, TransactionType? type) {
  final re = type == TransactionType.inflow ? _fromCue : _toCue;
  final m = re.firstMatch(text) ??
      (type == null
          ? null
          : (type == TransactionType.inflow ? _toCue : _fromCue)
              .firstMatch(text));
  return _cleanCounterparty(m == null ? null : _group(m, 'counterparty'));
}

final RegExp _yourCue = RegExp(r'\byour\b', caseSensitive: false);
final RegExp _peerCue = RegExp(r'\b(?:to|from)\b', caseSensitive: false);

/// The user's own masked suffix: one that follows `your` with no `to` /
/// `from` between (`using your card ending in 1234`, `Your account XXXX1234`).
/// A suffix after `from bank with account ending 1234` or `to BDO account
/// ending in XXXX5678` belongs to the other party and is skipped.
String? _ownLast4(String text) {
  for (final m in _last4Re.allMatches(text)) {
    final start = m.start - 45 < 0 ? 0 : m.start - 45;
    final before = text.substring(start, m.start);
    final your = _yourCue.allMatches(before).lastOrNull;
    if (your == null) continue;
    if (_peerCue.hasMatch(before.substring(your.end))) continue;
    return _group(m, 'last4') ?? _group(m, 'last4b') ?? _group(m, 'last4c');
  }
  return null;
}

final RegExp _trailingJunk = RegExp(r'[\s.,;:!\-–—]+$');
final RegExp _leadingJunk = RegExp(r'^[\s.,;:!\-–—]+');

/// A phone number or masked account glued after a name:
/// `JUAN D. 09171234567`, `MI*A P. 0915••••847`, `B. +639752505196`.
final RegExp _trailingDigits =
    RegExp(r'(?:\s+\(?\+?[\d•*xX][\d•*xX\- ]{5,}\)?)+$');

/// Words that are not a counterparty at all.
const Set<String> _placeholderNames = {
  'bank',
  'a bank',
  'account',
  'your account',
  'wallet',
  'your wallet',
  'you',
};

/// Trims delimiters, a trailing phone number or reference, and caps the length.
String? _cleanCounterparty(String? raw) {
  if (raw == null) return null;
  var s = _collapse(raw)
      .replaceFirst(_leadingJunk, '')
      .replaceFirst(_trailingJunk, '');
  // Reference numbers and dates glued to the name.
  s = s.replaceFirst(
      RegExp(r'\s+(ref(?:erence)?\.?\s*(?:no\.?)?|on \d{1,2} \w+ \d{4}).*$',
          caseSensitive: false),
      '');
  s = s.replaceFirst(_trailingDigits, '').replaceFirst(_trailingJunk, '');
  if (s.isEmpty || s.length < 2) return null;
  if (_placeholderNames.contains(s.toLowerCase())) return null;
  // "XXXXXXXX6634 Transfer" — a masked account number is never a name.
  if (RegExp(r'^[*xX•.]{2,}\d').hasMatch(s)) return null;
  // "up to PHP 1,000" — a currency mark is never a name.
  if (RegExp(r'^(?:PHP|Php|₱|P)\s?\d', caseSensitive: false).hasMatch(s)) {
    return null;
  }
  if (s.length > 60) s = s.substring(0, 60).trim();
  return s;
}

/// Another of the user's accounts named by the counterparty or the text.
String? _otherAccountIn({
  required String? counterparty,
  required String text,
  required List<FinancialAccount> accounts,
  required String? exclude,
}) {
  final pool = accounts.where((a) => a.isActive && a.id != exclude).toList();
  if (pool.isEmpty) return null;
  if (counterparty != null) {
    final hit = matchAccountNameInText(counterparty, pool) ??
        _accountByDistinctWord(counterparty, pool);
    if (hit != null) return hit;
  }
  // Only an exact, whole-name mention counts in the body: a word-prefix match
  // over free text would turn "BPI" inside a merchant name into a transfer.
  // A mention right after "your" is the user's own instrument on *this* side
  // ("using your Maya card"), not the other end of a transfer.
  final lower = text.toLowerCase();
  String? best;
  var bestLen = 0;
  for (final a in pool) {
    final name = a.name.toLowerCase().trim();
    if (name.length < 3) continue;
    for (final m in RegExp('\\b${RegExp.escape(name)}\\b').allMatches(lower)) {
      final start = m.start - 20 < 0 ? 0 : m.start - 20;
      if (RegExp(r'\byour\s+(?:\w+\s+){0,2}$')
          .hasMatch(lower.substring(start, m.start))) {
        continue;
      }
      if (name.length > bestLen) {
        best = a.id;
        bestLen = name.length;
      }
      break;
    }
  }
  return best;
}

/// Words an account name shares with every other account.
const Set<String> _genericAccountWords = {
  'savings',
  'credit',
  'card',
  'account',
  'bank',
  'wallet',
  'fund',
  'main',
  'cash',
};

/// `Juan D. Bank Of The Philippine Islands (BPI) ••••1637` names the BPI
/// account by its distinct word, even when the account is "BPI Savings".
String? _accountByDistinctWord(
    String counterparty, List<FinancialAccount> pool) {
  final lower = counterparty.toLowerCase();
  for (final a in pool) {
    for (final w in a.name.toLowerCase().split(RegExp(r'\s+'))) {
      if (w.length < 3 || _genericAccountWords.contains(w)) continue;
      if (RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(lower)) return a.id;
    }
  }
  return null;
}

String? _categoryFor(
  String? counterparty,
  TransactionType type,
  List<FinanceCategory> categories,
  FinancePersonalDictionary? dict,
) {
  if (counterparty == null) return null;
  final wantType = type == TransactionType.inflow
      ? CategoryType.income
      : CategoryType.expense;
  final pool = categories.where((c) => c.type == wantType).toList();
  final poolIds = pool.map((c) => c.id).toSet();

  final whole = dict?.lookup(counterparty);
  if (whole != null && poolIds.contains(whole)) return whole;

  final words =
      counterparty.split(RegExp(r'[\s\-_/]+')).where((w) => w.length >= 3);
  for (final w in words) {
    final learned = dict?.lookup(w);
    if (learned != null && poolIds.contains(learned)) return learned;
  }
  for (final w in words) {
    final byName = resolveCategoryByName(w, pool);
    if (byName != null) return byName;
  }
  return null;
}
