// Pure credit billing-cycle math: which statement a date falls on, when that
// statement closes, and when its payment is due.
//
// A cycle runs from the day after one statement close through the next close,
// inclusive. A charge dated ON the close day belongs to the cycle that closed;
// one dated the day after rides the next statement. Example — closes the 20th,
// due 15 days later: a charge on Sep 21 lands on the Oct 20 statement, due
// Nov 4, while the Sep 20 statement (due Oct 5) never saw it.
//
// The bill generator, the dashboard due line and the "next statement" note all
// read cycles from here so they cannot disagree about which cycle is which.

import '../models/finance/bill.dart';
import '../models/finance/credit_brand_presets.dart';
import '../models/finance/financial_account.dart';
import 'credit_finance_charge.dart';
import 'finance_format.dart';

/// One statement cycle of a credit account.
class CreditCycle {
  /// First day of the cycle (the day after the previous statement closed).
  final DateTime start;

  /// The statement date — the last day whose charges are on this statement.
  final DateTime close;

  /// When payment for this statement is due.
  final DateTime due;

  const CreditCycle({
    required this.start,
    required this.close,
    required this.due,
  });

  /// The 'YYYY-MM' month the statement's bill is filed under: the month its
  /// payment is due, which is not always the month it closed in.
  String get dueMonthKey => toMonthKey(due);

  /// True when [date] (any time of day) falls inside this cycle.
  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && !d.isAfter(close);
  }

  @override
  bool operator ==(Object other) =>
      other is CreditCycle &&
      other.start == start &&
      other.close == close &&
      other.due == due;

  @override
  int get hashCode => Object.hash(start, close, due);

  @override
  String toString() => 'CreditCycle($start → $close, due $due)';
}

/// Payment due date for a statement that closed on [close].
///
/// [daysAfter] wins when set (close + N days, which rolls across month ends
/// naturally). Otherwise [dueDay] is the first such day-of-month strictly after
/// the close: closes the 1st, due the 15th → same month; closes the 20th, due
/// the 5th → next month. A due day equal to the close day means next month —
/// nobody is billed and due on the same day.
DateTime creditDueDate(DateTime close, {int? dueDay, int? daysAfter}) {
  if (daysAfter != null) {
    return DateTime(close.year, close.month, close.day + daysAfter);
  }
  if (dueDay == null) {
    throw ArgumentError('creditDueDate needs dueDay or daysAfter');
  }
  final day = dueDay.clamp(1, 28);
  return day > close.day
      ? DateTime(close.year, close.month, day)
      : DateTime(close.year, close.month + 1, day);
}

/// The cycle whose statement closes in [year]/[month].
///
/// [statementDay] is clamped to 1–28 like everywhere else, so every month has
/// exactly one close.
CreditCycle creditCycleClosingIn(
  int year,
  int month, {
  required int statementDay,
  int? dueDay,
  int? daysAfter,
}) {
  final stmt = statementDay.clamp(1, 28);
  final close = DateTime(year, month, stmt);
  return CreditCycle(
    start: DateTime(year, month - 1, stmt + 1),
    close: close,
    due: creditDueDate(close, dueDay: dueDay, daysAfter: daysAfter),
  );
}

/// The cycle that [date] falls in — i.e. the statement a charge made on
/// [date] will appear on.
CreditCycle creditCycleContaining(
  DateTime date, {
  required int statementDay,
  int? dueDay,
  int? daysAfter,
}) {
  final stmt = statementDay.clamp(1, 28);
  final closesThisMonth = date.day <= stmt;
  final y = date.year;
  final m = closesThisMonth ? date.month : date.month + 1;
  final anchor = DateTime(y, m); // normalises a December roll-over
  return creditCycleClosingIn(anchor.year, anchor.month,
      statementDay: stmt, dueDay: dueDay, daysAfter: daysAfter);
}

/// Account-level conveniences. Null when [a] has no billing cycle configured.
extension CreditCycleAccount on FinancialAccount {
  /// The cycle closing in [year]/[month] for this account.
  CreditCycle? cycleClosingIn(int year, int month) => hasBillingCycle
      ? creditCycleClosingIn(year, month,
          statementDay: statementDay!,
          dueDay: paymentDueDay,
          daysAfter: dueDaysAfterStatement)
      : null;

  /// The cycle a charge on [date] lands in for this account.
  CreditCycle? cycleContaining(DateTime date) => hasBillingCycle
      ? creditCycleContaining(date,
          statementDay: statementDay!,
          dueDay: paymentDueDay,
          daysAfter: dueDaysAfterStatement)
      : null;
}

// ─── Statement bills ─────────────────────────────────────────────────────────
//
// A cycle says when a statement closes and falls due; whether anything is
// actually owed on it is the statement BILL's business. The dashboard due line,
// the minimum due and the due-date reminder all read "is there a statement
// waiting on payment, and when" from the helpers below, so a card with a
// balance but a ₱0 (or settled) statement never reads as "due".

/// What is still owed on statement bill [b]: nothing once it is marked paid
/// (a partial payment also closes the bill), else the amount less anything
/// already recorded against it.
double creditStatementRemaining(Bill b) {
  if (b.isPaid) return 0;
  final left = b.amount - (b.paidAmount ?? 0);
  return left > 0 ? left : 0;
}

/// Due date of statement bill [b]: its filing month plus its due day, the day
/// clamped to the month's length. Null when the month key is malformed.
DateTime? creditStatementDueDate(Bill b) {
  final parts = b.month.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return null;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, b.dueDay.clamp(1, lastDay));
}

/// The statement of account [accountId] still waiting on payment: the
/// earliest-due unpaid credit-card bill for it (generated or hand-keyed) with
/// money left on it. Null when nothing is owed on any statement — the card may
/// still carry a balance, but it belongs to a cycle that has not closed yet.
Bill? findOpenCreditStatement(Iterable<Bill> bills, String accountId) {
  Bill? best;
  DateTime? bestDue;
  for (final b in bills) {
    if (b.billType != BillType.creditCard || b.accountId != accountId) {
      continue;
    }
    if (creditStatementRemaining(b) <= 0) continue;
    final due = creditStatementDueDate(b);
    if (due == null) continue;
    if (bestDue == null || due.isBefore(bestDue)) {
      best = b;
      bestDue = due;
    }
  }
  return best;
}

/// The cycle statement bill [b] belongs to for account [a]: the one whose
/// payment falls due in the bill's month. Null when [a] has no billing cycle
/// or no cycle is due that month (a hand-keyed bill filed under an arbitrary
/// month). Should two cycles fall due in one month (a long days-after-close
/// rule across February), the one due on the bill's day wins, else the later.
CreditCycle? cycleForStatement(FinancialAccount a, Bill b) {
  if (!a.hasBillingCycle) return null;
  final parts = b.month.split('-');
  if (parts.length != 2) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return null;
  CreditCycle? match;
  // Due at most kMaxDueDaysAfterStatement (45) days after close, so the close
  // is in the bill's month or one of the two before it.
  for (var back = 2; back >= 0; back--) {
    final anchor = DateTime(year, month - back);
    final cycle = a.cycleClosingIn(anchor.year, anchor.month)!;
    if (cycle.dueMonthKey != b.month) continue;
    if (cycle.due.day == b.dueDay) return cycle;
    match = cycle;
  }
  return match;
}

/// Minimum amount due on a [statement] of account [a] under its
/// [FinancialAccount.effectiveMinimumRule] — the brand preset's rate and floor
/// (BSP defaults otherwise), a fixed amount capped at the statement, or the
/// whole statement.
double creditStatementMinimum(FinancialAccount a, double statement) {
  final preset = creditBrandPresetByKey(a.creditBrand);
  return computeMinimumForRule(
    rule: a.effectiveMinimumRule,
    statement: statement,
    minPaymentRate: preset?.minPaymentRate ?? 0.0357,
    minPaymentFloor: preset?.minPaymentFloor ?? 850,
    fixedAmount: a.minimumFixedAmount,
  );
}

/// How far payment of one credit statement has got.
class CreditStatementProgress {
  /// The statement amount.
  final double amount;

  /// Paid toward it so far, capped at [amount] (any excess stays on the
  /// account and lowers the next statement by itself).
  final double paid;

  /// The minimum due on the whole statement ([amount] under pay-in-full).
  final double minimum;

  const CreditStatementProgress({
    required this.amount,
    required this.paid,
    required this.minimum,
  });

  /// Paid toward [amount] and the minimum from the bill as stored: paid in full
  /// once flagged paid, else whatever [Bill.paidAmount] says so far.
  factory CreditStatementProgress.ofBill(Bill b, FinancialAccount a) {
    final paid = b.isPaid ? b.amount : (b.paidAmount ?? 0);
    return CreditStatementProgress(
      amount: b.amount,
      paid: paid.clamp(0.0, b.amount < 0 ? 0.0 : b.amount),
      minimum: creditStatementMinimum(a, b.amount),
    );
  }

  /// Still owed on the statement.
  double get remaining => amount - paid > 0.005 ? amount - paid : 0;

  /// Still owed toward the minimum.
  double get minimumRemaining => minimum - paid > 0.005 ? minimum - paid : 0;

  /// True once the minimum is covered — no late fee from here on.
  bool get minimumMet => minimumRemaining == 0;

  /// True once the whole statement is covered.
  bool get fullyPaid => remaining == 0;

  /// True once anything has been paid toward it.
  bool get started => paid > 0.005;
}
