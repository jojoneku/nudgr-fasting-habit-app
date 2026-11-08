import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The checks every settle surface runs before it hands a [SettleResult] to
/// its caller. Pure functions so the mobile Settle sheet and the web Settle
/// dialog apply the same rules (Plan 071 Phase 5).

/// Below this a difference is rounding, not money.
const double _kCent = 0.005;

/// Reads a typed amount: thousands separators and surrounding spaces are
/// ignored. Null when the text is not a number.
double? parseSettleAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').trim());

/// Why [amount] cannot be settled, or null when it can.
///
/// Every kind needs a positive amount. A card payment may not go above what
/// is owed ([scheduled] is the card's payable): paying more would push the
/// liability negative, which no account can mean. The other kinds allow an
/// overpayment (a rounded final installment, a tip on a bill).
String? settleAmountError({
  required double? amount,
  required SettleKind kind,
  required double scheduled,
}) {
  if (amount == null || !amount.isFinite || amount <= 0) {
    return 'Enter an amount';
  }
  if (kind == SettleKind.cardPayment &&
      scheduled > 0 &&
      amount > scheduled + _kCent) {
    return 'More than the ${formatPeso(scheduled)} owed';
  }
  return null;
}

/// True when [from] does not hold [amount]. Named, never blocking: the user
/// may be about to move money in first. A liability (paying with a card) is
/// never "short" — its balance is what is owed, not what is available.
bool settleShortBalance({
  required double amount,
  required FinancialAccount from,
}) {
  if (from.isLiability) return false;
  return amount - from.balance > _kCent;
}

/// The note shown under the account picker when [from] is short, or null.
/// Receivables deposit money, so there is nothing to be short of.
String? settleShortBalanceNote({
  required SettleKind kind,
  required double amount,
  required FinancialAccount? from,
}) {
  if (kind == SettleKind.receivable || from == null) return null;
  if (!settleShortBalance(amount: amount, from: from)) return null;
  final short = amount - from.balance;
  return '${formatPeso(from.balance)} · short by ${formatPeso(short)}. '
      '${from.name} does not have enough. Pick another account, or move '
      'money in first.';
}

/// Bills and receivables can be flagged settled without writing the ledger
/// (the user already logged the movement by hand). A set-aside *is* the
/// transfer, an installment payment IS its transaction and a card payment is
/// a transfer, so none of those offers the choice.
bool settleOffersLedgerToggle(SettleKind kind) =>
    kind == SettleKind.bill || kind == SettleKind.receivable;

/// Installments ride on their own card, so there is no account to pick.
bool settleAsksAccount(SettleKind kind, {required bool recordInLedger}) =>
    kind != SettleKind.installment && recordInLedger;
