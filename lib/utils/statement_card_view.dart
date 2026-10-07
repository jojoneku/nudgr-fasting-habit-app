// View models for the Bills tab's credit statement card and for installment
// rows on cards that bill through statements. Built by
// BillsReceivablesPresenter; the views only read them.

import '../models/finance/bill.dart';
import '../models/finance/financial_account.dart';
import 'finance_format.dart';

/// How urgent a statement's due line reads.
enum StatementDueTone {
  /// More than three days out.
  normal,

  /// Due within three days, or today.
  soon,

  /// Past its due date and not paid.
  overdue,

  /// Paid in full.
  paid,
}

/// Everything the statement card shows, resolved.
class StatementCardView {
  final Bill bill;

  /// The card or BNPL account the statement belongs to — its badge leads the
  /// card instead of a spending category, which said "food" on a ShopeePay
  /// statement.
  final FinancialAccount account;

  /// "Statement · 05 Sep – 04 Oct", or "Statement" when no cycle is known.
  final String periodLabel;

  /// What is still owed on it; the full amount once nothing is paid yet.
  final double unpaid;

  /// The statement amount as billed.
  final double amount;

  /// "Due Oct 15 · in 8 days", "Due today", "Overdue · Oct 15",
  /// "Paid Sep 25".
  final String dueLabel;
  final StatementDueTone dueTone;

  /// 0–1 share paid while part-paid; null otherwise.
  final double? progress;

  /// "Paid ₱850.00 of ₱2,424.40 · min met" while part-paid; null otherwise.
  final String? progressLabel;

  /// "Min ₱850.00" while unpaid and the minimum is below the full amount.
  final String? minimumLabel;

  /// "3 purchases · 6 installments"; null when nothing is on it yet.
  final String? compositionLabel;

  /// "View 9 items" / "View items".
  final String itemsLabel;

  const StatementCardView({
    required this.bill,
    required this.account,
    required this.periodLabel,
    required this.unpaid,
    required this.amount,
    required this.dueLabel,
    required this.dueTone,
    required this.progress,
    required this.progressLabel,
    required this.minimumLabel,
    required this.compositionLabel,
    required this.itemsLabel,
  });

  bool get isPaid => bill.isPaid;

  /// The big number: what is left to pay, or the total once paid.
  double get headlineAmount => isPaid ? amount : unpaid;

  /// The line under the big number.
  String get headlineCaption => isPaid
      ? 'Paid in full'
      : (progress != null ? 'Left of ${formatPeso(amount)}' : 'To pay');

  /// The small tag after the account name.
  String get kindLabel => switch (account.category) {
        AccountCategory.bnpl => 'BNPL',
        AccountCategory.creditLine => 'LINE',
        _ => 'CC',
      };
}

/// Where one installment month stands on a card that bills through
/// statements. Its month is paid by paying the statement, so the row takes
/// its state from that statement rather than calling a billed month "paid".
class InstallmentStatementStatus {
  /// The statement this month is on; null before it is billed.
  final Bill? statement;

  /// True only once that statement is paid (or the plan is finished).
  final bool paid;

  /// "1/3 · on statement, due Oct 15", "1/3 · paid with statement",
  /// "2/3 · bills on the next statement".
  final String label;

  /// "View ShopeePay statement" when [statement] is set; else null.
  final String? linkLabel;

  /// "Linked to ShopeePay statement · can't be paid alone" — why the row has
  /// no Pay button: the issuer bills the month on the statement, and only the
  /// statement can be paid.
  final String note;

  /// Share of the plan actually paid (0–1): months billed onto a statement
  /// that has been paid. A month billed onto an open statement is not paid
  /// yet, so it does not move the bar.
  final double progress;

  const InstallmentStatementStatus({
    required this.statement,
    required this.paid,
    required this.label,
    required this.linkLabel,
    required this.note,
    required this.progress,
  });
}
