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

import '../models/finance/financial_account.dart';
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
