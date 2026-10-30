import 'package:intermittent_fasting/models/finance/installment.dart';
import 'package:intermittent_fasting/models/finance/receivable.dart';

// ─── Receivables of a plan bought for someone else (Plan 067) ───────────────
//
// A plan with [Installment.paidForName] set has one receivable from that person
// per payment month: same month the plan bills, same monthly amount. The rules
// below are the whole contract, and both the save (the bills presenter's
// reconcile) and the form's review step read them, so the review shows exactly
// what the save writes:
//
// - Open (not received) receivables follow the plan: payment n moves to the
//   plan's month n, takes the new amount and name. Extra ones go, missing ones
//   are added.
// - A received receivable is never changed. Its payment number is not made
//   again.
// - Plan deleted or switched to "for yourself": open ones go, received ones
//   stay as history with the link to the plan cleared.
// - Plan cancelled: months it already billed keep their receivables, the rest
//   go.

/// What reconciling one receivable does.
enum InstallmentReceivableChange {
  /// A new receivable for a month that has none.
  add,

  /// An open receivable moved to the plan's new month, amount or name.
  update,

  /// An open receivable that already matches the plan.
  unchanged,

  /// A received receivable, left as it is.
  keepReceived,

  /// A received receivable that stays, with its link to the plan cleared.
  unlinkReceived,

  /// An open receivable that is deleted.
  remove,
}

/// One receivable and what the reconcile does to it. [receivable] is the
/// version to save — the old one for [InstallmentReceivableChange.remove].
class InstallmentReceivableStep {
  final InstallmentReceivableChange change;
  final Receivable receivable;

  /// The payment number the receivable held before this step. Kept apart
  /// from [receivable], since an unlinked one no longer carries it.
  final int? number;

  InstallmentReceivableStep(this.change, this.receivable, {int? number})
      : number = number ?? receivable.installmentNumber;

  /// True when the step changes stored data.
  bool get writes =>
      change != InstallmentReceivableChange.unchanged &&
      change != InstallmentReceivableChange.keepReceived;
}

/// Deterministic id of payment [number] (1-based) of plan [planId], so two
/// devices reconciling the same plan write the same row.
String installmentReceivableId(String planId, int number) =>
    'instrcv_${planId}_$number';

/// "Papa — Xiaomi Redmi Note 15 (1/12)".
String installmentReceivableName(Installment plan, int number) =>
    '${plan.paidForName} — ${plan.name} ($number/${plan.totalMonths})';

/// The steps that bring [linked] — every receivable whose
/// [Receivable.installmentId] is [planId] — in line with [plan].
///
/// [plan] is null when the plan was deleted. [dueDateFor] gives the expected
/// date for a payment month (the card's due date then), or null. [billedCount]
/// is how many months the plan has billed; it matters only for a cancelled
/// plan. [now] stamps the `createdAt` of added receivables. Steps come back
/// ordered by payment number, removed ones last.
List<InstallmentReceivableStep> planInstallmentReceivables({
  required String planId,
  required Installment? plan,
  required Iterable<Receivable> linked,
  required String categoryId,
  DateTime? Function(String month)? dueDateFor,
  int billedCount = 0,
  DateTime? now,
}) {
  final received = <Receivable>[];
  final open = <int, Receivable>{};
  final strays = <Receivable>[];
  for (final r in linked) {
    final n = r.installmentNumber;
    if (r.isReceived) {
      received.add(r);
    } else if (n == null || open.containsKey(n)) {
      strays.add(r);
    } else {
      open[n] = r;
    }
  }

  final steps = <InstallmentReceivableStep>[];
  if (plan == null || !plan.isPaidForSomeone) {
    for (final r in received) {
      steps.add(InstallmentReceivableStep(
        InstallmentReceivableChange.unlinkReceived,
        r.copyWith(installmentId: null, installmentNumber: null),
        number: r.installmentNumber,
      ));
    }
    for (final r in [...open.values, ...strays]) {
      steps.add(
          InstallmentReceivableStep(InstallmentReceivableChange.remove, r));
    }
    return _ordered(steps);
  }

  // A cancelled plan bills nothing more: only months it already billed keep a
  // receivable.
  final lastNumber =
      plan.isActive ? plan.totalMonths : billedCount.clamp(0, plan.totalMonths);
  final receivedNumbers = {for (final r in received) r.installmentNumber};
  for (final r in received) {
    steps.add(
        InstallmentReceivableStep(InstallmentReceivableChange.keepReceived, r));
  }
  for (var n = 1; n <= lastNumber; n++) {
    if (receivedNumbers.contains(n)) continue;
    final month = plan.monthForIndex(n - 1);
    final expected = dueDateFor?.call(month);
    final current = open.remove(n);
    if (current == null) {
      steps.add(InstallmentReceivableStep(
        InstallmentReceivableChange.add,
        Receivable(
          id: installmentReceivableId(plan.id, n),
          name: installmentReceivableName(plan, n),
          receivableType: ReceivableType.reimbursement,
          amount: plan.monthlyAmount,
          expectedDate: expected,
          month: month,
          categoryId: categoryId,
          installmentId: plan.id,
          installmentNumber: n,
          createdAt: now,
        ),
      ));
      continue;
    }
    final name = installmentReceivableName(plan, n);
    final same = current.name == name &&
        (current.amount - plan.monthlyAmount).abs() < 0.005 &&
        current.month == month &&
        current.expectedDate == expected &&
        current.categoryId == categoryId;
    steps.add(same
        ? InstallmentReceivableStep(
            InstallmentReceivableChange.unchanged, current)
        : InstallmentReceivableStep(
            InstallmentReceivableChange.update,
            current.copyWith(
              name: name,
              amount: plan.monthlyAmount,
              month: month,
              expectedDate: expected,
              categoryId: categoryId,
              // A hand-set rank belongs to the old month's list.
              sortIndex: current.month == month ? current.sortIndex : null,
            ),
          ));
  }
  for (final r in [...open.values, ...strays]) {
    steps.add(InstallmentReceivableStep(InstallmentReceivableChange.remove, r));
  }
  return _ordered(steps);
}

List<InstallmentReceivableStep> _ordered(
    List<InstallmentReceivableStep> steps) {
  int group(InstallmentReceivableStep s) =>
      s.change == InstallmentReceivableChange.remove ? 1 : 0;
  return steps
    ..sort((a, b) {
      final byGroup = group(a).compareTo(group(b));
      if (byGroup != 0) return byGroup;
      return (a.number ?? 0).compareTo(b.number ?? 0);
    });
}
