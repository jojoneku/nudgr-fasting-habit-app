// What is on one credit statement: the card's own records inside the cycle,
// grouped the way an issuer's bill screen groups them, with totals that add
// up to the statement amount.
//
// The window is exactly the one [LedgerPresenter.payableAsOf] bills: from the
// day after the previous close through this close, that day included. A
// statement's amount is the card's balance at the close, so it is always
//
//   carried over  (owed at the previous close − paid during this cycle)
// + purchases     (outflows on the card in the window)
// + installments  (months billed onto the card at close — PR #682 charges)
// − refunds       (credits on the card in the window that are not payments)
// = bill amount
//
// and what is left on it is the bill amount less what has been paid since the
// close — the same figure [CreditStatementProgress] and
// [creditStatementRemaining] report, so this screen and the Bills row agree.
//
// Installment PURCHASE records (`isInstallment: true`) move no money and are
// never a line; their months appear as installment charges instead.

import 'package:intl/intl.dart';

import '../models/finance/bill.dart';
import '../models/finance/financial_account.dart';
import '../models/finance/transaction_record.dart';
import 'credit_cycle.dart';
import 'finance_format.dart';

/// Which group a statement line sits in.
enum StatementLineKind {
  /// An ordinary charge on the card.
  purchase,

  /// One month of an installment plan billed onto the card at close.
  installment,

  /// Money back onto the card that is not a payment (a merchant refund, a
  /// cashback credit).
  refund,

  /// A payment made after the close — what has been repaid on the statement.
  repayment,
}

/// One ledger record as it reads on a statement.
class StatementLine {
  /// The record itself, so tapping the line can open its edit form.
  final TransactionRecord txn;
  final StatementLineKind kind;

  /// The item, without the "— Installment n/N" suffix of an installment
  /// charge.
  final String title;

  /// "1/3" for an installment charge whose description still carries it;
  /// null otherwise.
  final String? installmentLabel;

  /// "05 Sep".
  final String dateLabel;

  /// Always positive; [kind] says which way it moved the balance.
  final double amount;

  const StatementLine({
    required this.txn,
    required this.kind,
    required this.title,
    required this.installmentLabel,
    required this.dateLabel,
    required this.amount,
  });

  /// True for lines that lower what is owed (refunds, repayments).
  bool get isCredit =>
      kind == StatementLineKind.refund || kind == StatementLineKind.repayment;

  /// "₱299.62", or "−₱50.00" for a credit.
  String get amountLabel =>
      isCredit ? '−${formatPeso(amount)}' : formatPeso(amount);
}

/// One titled group of lines on the statement ("Purchases", "Installments",
/// "Refunds", "Repaid"), only built when it has lines.
class StatementSection {
  final StatementLineKind kind;
  final String title;
  final List<StatementLine> lines;

  const StatementSection({
    required this.kind,
    required this.title,
    required this.lines,
  });

  double get total => lines.fold(0.0, (s, l) => s + l.amount);

  /// "₱845.69", or "−₱50.00" for a group of credits.
  String get totalLabel => lines.isNotEmpty && lines.first.isCredit
      ? '−${formatPeso(total)}'
      : formatPeso(total);

  /// "3 items" / "1 item".
  String get countLabel =>
      '${lines.length} ${lines.length == 1 ? 'item' : 'items'}';
}

/// Everything on one credit statement bill. Build with
/// [buildStatementBreakdown].
class StatementBreakdown {
  final Bill bill;
  final CreditCycle cycle;

  /// What the card owed at the end of the previous close (unfloored: an
  /// overpaid card carries a negative balance, i.e. a credit).
  final double previousBalance;

  /// Payments into the card dated inside this cycle — they went toward the
  /// previous statement, so they come off the carried-over balance.
  final double paidDuringCycle;

  final List<StatementLine> purchases;
  final List<StatementLine> installments;
  final List<StatementLine> refunds;

  /// Payments since the close, newest last.
  final List<StatementLine> repayments;

  /// Repaid toward this statement, capped at [billAmount] — the statement
  /// progress figure (the whole amount once the bill is marked paid).
  final double repaid;

  /// Still owed on this statement.
  final double unpaid;

  const StatementBreakdown({
    required this.bill,
    required this.cycle,
    required this.previousBalance,
    required this.paidDuringCycle,
    required this.purchases,
    required this.installments,
    required this.refunds,
    required this.repayments,
    required this.repaid,
    required this.unpaid,
  });

  /// The statement amount as billed.
  double get billAmount => bill.amount;

  /// The balance brought forward from the previous statement, net of what was
  /// paid toward it during this cycle.
  double get carriedOver => previousBalance - paidDuringCycle;

  double get purchasesTotal => _sum(purchases);
  double get installmentsTotal => _sum(installments);
  double get refundsTotal => _sum(refunds);

  /// Every payment recorded since the close, uncapped (an overpayment stays on
  /// the card and lowers the next statement).
  double get repaymentsTotal => _sum(repayments);

  /// Charges and credits on this statement — "Transaction total: 10 items".
  int get itemCount => purchases.length + installments.length + refunds.length;

  /// Carried over + purchases + installments − refunds: the card's balance at
  /// the close, line by line.
  double get linesTotal =>
      carriedOver + purchasesTotal + installmentsTotal - refundsTotal;

  /// [billAmount] less [linesTotal]. Zero while the statement follows the
  /// ledger; non-zero only for a statement frozen before a line was edited
  /// (already paid) or one typed in by hand.
  double get unreconciled {
    final diff = billAmount - linesTotal;
    return diff.abs() < 0.005 ? 0 : diff;
  }

  /// True when the carried-over line is worth showing.
  bool get hasCarriedOver => carriedOver.abs() >= 0.005;

  /// True when the cycle has nothing on it at all.
  bool get isEmpty => itemCount == 0 && repayments.isEmpty;

  /// "05 Sep – 04 Oct".
  String get periodLabel =>
      '${_dayMonth.format(cycle.start)} – ${_dayMonth.format(cycle.close)}';

  /// "10 items" / "1 item".
  String get itemCountLabel =>
      '$itemCount ${itemCount == 1 ? 'item' : 'items'}';

  /// The non-empty groups, in issuer order: purchases, installments, refunds,
  /// then what has been repaid since the close.
  List<StatementSection> get sections => [
        for (final s in [
          StatementSection(
              kind: StatementLineKind.purchase,
              title: 'Purchases',
              lines: purchases),
          StatementSection(
              kind: StatementLineKind.installment,
              title: 'Installments',
              lines: installments),
          StatementSection(
              kind: StatementLineKind.refund, title: 'Refunds', lines: refunds),
          StatementSection(
              kind: StatementLineKind.repayment,
              title: 'Repaid',
              lines: repayments),
        ])
          if (s.lines.isNotEmpty) s,
      ];

  /// "Due Oct 15" — the bill's own due date, else the cycle's.
  String get dueLabel => 'Due ${DateFormat('MMM d').format(
        creditStatementDueDate(bill) ?? cycle.due,
      )}';

  /// "−₱850.00" — what has been repaid, as a deduction.
  String get repaidLabel => '−${formatPeso(repaid)}';

  /// "Carried over" as signed money: a credit from an overpaid card reads
  /// "−₱120.00".
  String get carriedOverLabel => carriedOver < 0
      ? '−${formatPeso(-carriedOver)}'
      : formatPeso(carriedOver);

  /// Shown when the bill no longer matches its lines (a statement settled
  /// before one of them was edited, or a hand-keyed amount); null otherwise.
  String? get unreconciledNote => unreconciled == 0
      ? null
      : 'These items now add up to ${formatPeso(linesTotal)}; the statement '
          'was billed at ${formatPeso(billAmount)}.';

  static double _sum(List<StatementLine> lines) =>
      lines.fold(0.0, (s, l) => s + l.amount);
}

final _dayMonth = DateFormat('dd MMM');

/// "Item — Installment 2/3" → ("Item", "2/3"); anything else is left whole.
final _installmentSuffix = RegExp(r'^(.*?)\s+—\s+Installment\s+(\d+/\d+)$');

/// The breakdown of statement [bill] of [account] for [cycle], read from
/// [transactions] (the whole ledger; other accounts' records are skipped).
///
/// [paid] is what statement progress says is paid toward the bill (see
/// [CreditStatementProgress]); the unpaid figure is [bill]'s amount less it.
StatementBreakdown buildStatementBreakdown({
  required FinancialAccount account,
  required Bill bill,
  required CreditCycle cycle,
  required Iterable<TransactionRecord> transactions,
  required double paid,
}) {
  // Same day boundaries as LedgerPresenter.payableAsOf: a record dated on the
  // close belongs to this statement, the day after rides the next one.
  final start = DateTime(cycle.start.year, cycle.start.month, cycle.start.day);
  final afterClose =
      DateTime(cycle.close.year, cycle.close.month, cycle.close.day + 1);

  // Owed at the previous close: today's balance unwound across everything
  // dated from this cycle's first day on (spending raises what is owed).
  var previousBalance = account.balance;
  var paidDuringCycle = 0.0;
  final purchases = <StatementLine>[];
  final installments = <StatementLine>[];
  final refunds = <StatementLine>[];
  final repayments = <StatementLine>[];

  for (final t in transactions) {
    if (t.accountId != account.id || t.isInstallment) continue;
    if (t.date.isBefore(start)) continue;
    final isInflow = t.type == TransactionType.inflow;
    previousBalance += isInflow ? t.amount : -t.amount;

    if (!t.date.isBefore(afterClose)) {
      // After the close: payments (and any other credit) toward this
      // statement, exactly what LedgerPresenter.paymentsToLiabilitySince counts.
      if (isInflow) {
        repayments.add(_line(t, StatementLineKind.repayment));
      }
      continue;
    }

    if (isInflow) {
      if (_isPayment(t)) {
        paidDuringCycle += t.amount;
      } else {
        refunds.add(_line(t, StatementLineKind.refund));
      }
    } else if (t.installmentId != null) {
      installments.add(_line(t, StatementLineKind.installment));
    } else {
      purchases.add(_line(t, StatementLineKind.purchase));
    }
  }

  int byDate(StatementLine a, StatementLine b) {
    final d = a.txn.date.compareTo(b.txn.date);
    return d != 0 ? d : a.txn.id.compareTo(b.txn.id);
  }

  final cap = bill.amount < 0 ? 0.0 : bill.amount;
  final repaid = paid.clamp(0.0, cap);
  final unpaid = bill.amount - repaid;

  return StatementBreakdown(
    bill: bill,
    cycle: cycle,
    previousBalance: previousBalance,
    paidDuringCycle: paidDuringCycle,
    purchases: purchases..sort(byDate),
    installments: installments..sort(byDate),
    refunds: refunds..sort(byDate),
    repayments: repayments..sort(byDate),
    repaid: repaid,
    unpaid: unpaid > 0.005 ? unpaid : 0,
  );
}

/// An inflow that pays the card down rather than crediting a purchase back:
/// a transfer leg in, or an entry booked against a bill.
bool _isPayment(TransactionRecord t) =>
    t.transferGroupId != null ||
    t.transferToAccountId != null ||
    t.billId != null;

StatementLine _line(TransactionRecord t, StatementLineKind kind) {
  String title = t.description.trim();
  String? installmentLabel;
  if (kind == StatementLineKind.installment) {
    final m = _installmentSuffix.firstMatch(title);
    if (m != null) {
      title = m.group(1)!;
      installmentLabel = m.group(2);
    }
  }
  if (title.isEmpty) {
    title = switch (kind) {
      StatementLineKind.purchase => 'Purchase',
      StatementLineKind.installment => 'Installment',
      StatementLineKind.refund => 'Refund',
      StatementLineKind.repayment => 'Payment',
    };
  }
  return StatementLine(
    txn: t,
    kind: kind,
    title: title,
    installmentLabel: installmentLabel,
    dateLabel: _dayMonth.format(t.date),
    amount: t.amount,
  );
}
