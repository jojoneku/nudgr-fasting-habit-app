import 'package:intermittent_fasting/models/settle_request.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// The wording of a settle surface for one [kind] and set of [targets]: the
/// title, subtitle, field labels and button label.
///
/// Shared by the mobile Settle sheet and the web Settle dialog (Plan 071
/// Phase 5) so the two apps name the same action the same way. [isBatch] is
/// usually `targets.length > 1`; the pre-v2 web batch wrapper forces it on for
/// a batch of one.
class SettleCopy {
  final SettleKind kind;
  final List<SettleTarget> targets;
  final bool isBatch;

  const SettleCopy({
    required this.kind,
    required this.targets,
    required this.isBatch,
  });

  int get count => targets.length;
  double get total => targets.fold(0.0, (s, t) => s + t.amount);
  SettleTarget get _single => targets.first;

  String get title {
    if (isBatch) {
      return switch (kind) {
        SettleKind.bill => 'Pay $count bills',
        SettleKind.receivable => 'Receive $count receivables',
        SettleKind.setAside => 'Fund $count set-asides',
        SettleKind.installment => 'Pay $count installments',
        SettleKind.cardPayment => 'Pay $count cards',
      };
    }
    final name = _single.name;
    return switch (kind) {
      SettleKind.bill || SettleKind.installment => 'Mark $name paid',
      SettleKind.receivable => 'Receive $name',
      SettleKind.setAside => 'Fund $name',
      SettleKind.cardPayment => 'Pay $name',
    };
  }

  String get subtitle {
    if (isBatch) {
      final sum = formatPeso(total);
      return switch (kind) {
        SettleKind.bill => '$sum total · each bill settles for its own amount',
        SettleKind.receivable =>
          '$sum total · each one settles for its own amount',
        SettleKind.setAside =>
          '$sum total · setting money aside is a transfer, not spending',
        SettleKind.installment =>
          "$sum total · this month's payments, each on its own card",
        SettleKind.cardPayment => '$sum total',
      };
    }
    final scheduled = formatPeso(_single.amount);
    final when = _single.dateLabel;
    final whenPart = when != null ? ' · $when' : '';
    return switch (kind) {
      SettleKind.cardPayment =>
        'You owe $scheduled · lowers what you owe from the account you pick',
      SettleKind.installment => 'Monthly $scheduled · charged to its own card',
      SettleKind.setAside => 'Planned $scheduled$whenPart',
      _ => 'Scheduled $scheduled$whenPart',
    };
  }

  String get amountLabel => switch (kind) {
        SettleKind.receivable => 'Amount received',
        SettleKind.setAside => 'Amount to set aside',
        _ => 'Amount paid',
      };

  String get dateLabel => switch (kind) {
        SettleKind.receivable => 'Received on',
        SettleKind.setAside => 'Funded on',
        _ => 'Paid on',
      };

  String get accountLabel => switch (kind) {
        SettleKind.receivable => 'Deposit into',
        SettleKind.setAside => 'Fund from',
        _ => 'Pay from',
      };

  String get confirmLabel {
    if (isBatch) {
      return switch (kind) {
        SettleKind.bill => 'Mark $count paid',
        SettleKind.receivable => 'Mark $count received',
        SettleKind.setAside => 'Fund $count',
        _ => 'Pay $count',
      };
    }
    return switch (kind) {
      SettleKind.bill || SettleKind.installment => 'Mark paid',
      SettleKind.receivable => 'Mark received',
      SettleKind.setAside => 'Fund',
      SettleKind.cardPayment => 'Pay',
    };
  }

  /// The verb an error toast names, so "Could not fund: …" reads as the
  /// action that failed.
  String get failureVerb => switch (kind) {
        SettleKind.cardPayment => 'record payment',
        _ => confirmLabel.toLowerCase(),
      };

  /// The "Already in the ledger" switch's explanation.
  String get alreadyLoggedSubtitle => kind == SettleKind.receivable
      ? 'Turn on if you logged this deposit by hand'
      : 'Turn on if you logged this payment by hand';
}
