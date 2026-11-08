/// The shapes behind every "this is now paid / received / funded" action, on
/// mobile (`showSettleSheet`) and on web (`showWebSettleDialog`).
///
/// Moved out of `views/web/widgets/web_settle_dialog.dart` and
/// `views/treasury/bills/batch_settle_sheet.dart` (Plan 071 Phase 5) so both
/// apps share one copy. Plain data only — no Flutter imports.
library;

/// Which kind of obligation is being settled. Decides the wording, the tone of
/// the primary button, and which fields are asked for — the money moves
/// differently for each (Plan 063 §5).
enum SettleKind { bill, receivable, setAside, installment, cardPayment }

/// One row being settled. One target is single mode (editable amount); several
/// are batch mode (each settles for its own full amount, the rows are listed,
/// and only what the batch shares is asked once).
class SettleTarget {
  final String id;
  final String name;

  /// The scheduled figure — the bill amount, the receivable, the allocation,
  /// the monthly payment, or the card's payable.
  final double amount;

  /// "due Oct 16" / "Oct 16" — shown in the subtitle and beside a batch row.
  final String? dateLabel;

  /// The account on file for this row (a bill's payment account, a set-aside's
  /// funding account). Seeds the picker in single mode when it is on offer.
  final String? accountId;

  /// A set-aside's destination on file, when it names one.
  final String? destinationId;

  const SettleTarget({
    required this.id,
    required this.name,
    required this.amount,
    this.dateLabel,
    this.accountId,
    this.destinationId,
  });
}

/// What the user settled on. Handed to the caller's write callback and
/// returned once that write succeeds, so the toast can quote the amount that
/// was actually recorded rather than the one that was scheduled.
///
/// The single-settle fields plus the two batch-only ones
/// ([useSavedDestinations], [targetIds]).
class SettleResult {
  /// The amount actually settled — in single mode the user's figure (a partial
  /// payment or an overpayment); in batch mode the total of the rows.
  final double amount;

  /// What the entry said it would be, kept so callers can tell a deliberate
  /// partial payment from the scheduled figure.
  final double? scheduledAmount;

  /// When it happened. Defaults to today but is freely back-datable.
  final DateTime date;

  /// Funding (or deposit) account. Null when the flow has no account picker,
  /// when [recordInLedger] is false, or when no account could cover a batch.
  final String? accountId;

  /// Second account for set-asides — where the money lands. Null means "spend
  /// it" (a plain outflow rather than a transfer).
  final String? destinationId;

  /// False when the user already logged the movement in the ledger by hand, so
  /// the entry is flagged settled without creating a transaction.
  final bool recordInLedger;

  /// Batch set-asides: rows that name a destination of their own keep it and
  /// [destinationId] applies only to the rest.
  final bool useSavedDestinations;

  /// The ids of the rows settled, in the order they were given.
  final List<String> targetIds;

  const SettleResult({
    required this.amount,
    required this.date,
    this.scheduledAmount,
    this.accountId,
    this.destinationId,
    this.recordInLedger = true,
    this.useSavedDestinations = true,
    this.targetIds = const [],
  });

  /// True when the settled amount differs from what was scheduled — the callers
  /// use it to word the confirmation toast honestly.
  bool get isPartial =>
      scheduledAmount != null && amount < scheduledAmount! - 0.005;
  bool get isOverpayment =>
      scheduledAmount != null && amount > scheduledAmount! + 0.005;

  /// The batch shape the pre-v2 web batch call sites were written against.
  BatchSettleChoice toBatchChoice() => BatchSettleChoice(
        accountId: accountId,
        toAccountId: destinationId,
        useSavedDestinations: useSavedDestinations,
        alreadyInLedger: !recordInLedger,
        date: date,
      );
}

/// Which kind of obligation a batch is settling, in the pre-v2 web batch
/// dialog's terms. Kept for `showWebBatchSettleDialog` and the old web Bills
/// page until the Plan 063 v1 cleanup removes them.
enum BatchSettleKind { bills, receivables, setAsides, installments }

/// A batch settle choice in the pre-v2 shape: every selected row is settled
/// for its own full amount. See [SettleResult.toBatchChoice].
class BatchSettleChoice {
  /// Funding account (bills, set-asides) or deposit account (receivables).
  /// Null when [alreadyInLedger] is set, or for installments, which are each
  /// paid from their own account.
  final String? accountId;

  /// Set-aside destination applied to rows that don't carry one of their own.
  /// Null means "spend it" — a plain outflow, no transfer.
  final String? toAccountId;

  /// Let rows that already name a destination keep it, and apply
  /// [toAccountId] only to the rest.
  final bool useSavedDestinations;

  /// The user already logged these in the ledger by hand: flag them settled
  /// without writing transactions or touching balances.
  final bool alreadyInLedger;

  final DateTime date;

  const BatchSettleChoice({
    required this.accountId,
    required this.toAccountId,
    required this.useSavedDestinations,
    required this.alreadyInLedger,
    required this.date,
  });
}
