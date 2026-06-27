// Heuristic router for the hub's unified quick-log bar.
//
// One input bar feeds two existing pipelines — the finance ledger chat
// (`LedgerPresenter.sendChatInput`) and nutrition chat logging
// (`NutritionPresenter.parseChat`, which itself splits food vs exercise). This
// is the thin layer in front that decides which pipeline a free-text entry
// belongs to. It is pure logic — no I/O, no AI — so the bar stays fast and the
// decision is unit-testable.
//
// Routing rule (predictable over clever): exercise text goes to nutrition; a
// message carrying a *finance signal* (a currency marker, a signed amount, a
// money verb, or a known account name) goes to finance; everything else
// defaults to nutrition. Finance entries in real use almost always carry such a
// cue ("spent 200…", "₱150 grab", "-500 food gcash"), while a bare food entry
// ("2 eggs", "chicken 200g") carries none — so the default favours food, and a
// genuinely ambiguous money note just needs a verb or ₱ to route correctly. A
// misroute is recoverable either way: finance shows a confirm/clarify panel,
// nutrition surfaces a soft "couldn't identify food" message.

import 'exercise_nlp_parser.dart';

enum QuickLogTarget { finance, nutrition }

abstract final class QuickLogRouter {
  // Money verbs that signal a ledger entry. Matched on word boundaries so
  // "payday" / "billboard" don't trip "pay" / "bill".
  static const List<String> _financeVerbs = [
    'spent',
    'spend',
    'spending',
    'paid',
    'pay',
    'paying',
    'bought',
    'buy',
    'buying',
    'purchase',
    'purchased',
    'cost',
    'costs',
    'salary',
    'income',
    'earned',
    'refund',
    'refunded',
    'reimburse',
    'reimbursed',
    'transfer',
    'transferred',
    'withdraw',
    'withdrew',
    'withdrawal',
    'deposit',
    'deposited',
    'owe',
    'owed',
    'lent',
    'borrowed',
    'loan',
    'expense',
    'bill',
    'bills',
  ];

  // Currency markers: ₱ / $ symbols, the word peso(s)/php, or a "p" stuck to a
  // number ("p200"). A bare standalone "p" is ignored to avoid false hits.
  static final RegExp _currencyRe = RegExp(
    r'[₱$]|(?<![a-z])php(?![a-z])|(?<![a-z])pesos?(?![a-z])|(?<![a-z])p\d',
    caseSensitive: false,
  );

  // A signed amount like "-500" or "+500" — only the ledger uses sign to mean
  // expense/income, so its presence is a strong finance cue.
  static final RegExp _signedAmountRe = RegExp(r'(?<![\w.])[-+]\d');

  /// Decides which pipeline [text] should be logged through.
  ///
  /// [accountNames] are the user's ledger account labels (e.g. "gcash", "bpi");
  /// a word-boundary match on any of them is treated as a finance signal so
  /// account-anchored entries like "500 gcash hamburger" route to finance even
  /// without a verb. Pass an empty set when unavailable.
  static QuickLogTarget route(
    String text, {
    Set<String> accountNames = const {},
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return QuickLogTarget.nutrition;

    // Exercise is logged through nutrition (parseChat's exercise branch).
    if (ExerciseNlpParser.looksLikeExercise(trimmed)) {
      return QuickLogTarget.nutrition;
    }

    return _hasFinanceSignal(trimmed, accountNames)
        ? QuickLogTarget.finance
        : QuickLogTarget.nutrition;
  }

  static bool _hasFinanceSignal(String text, Set<String> accountNames) {
    final lower = text.toLowerCase();

    if (_currencyRe.hasMatch(lower)) return true;
    if (_signedAmountRe.hasMatch(lower)) return true;

    for (final verb in _financeVerbs) {
      if (_hasWord(lower, verb)) return true;
    }

    for (final name in accountNames) {
      final token = name.trim().toLowerCase();
      if (token.isEmpty) continue;
      if (_hasWord(lower, token)) return true;
    }

    return false;
  }

  // Word-boundary match on the letter side: "cash" matches "cash" but not
  // "cashew"; a trailing digit/space is allowed so "gcash500" still hits.
  static bool _hasWord(String haystack, String word) {
    final re = RegExp(r'(?<![a-z])' + RegExp.escape(word) + r'(?![a-z])');
    return re.hasMatch(haystack);
  }
}
