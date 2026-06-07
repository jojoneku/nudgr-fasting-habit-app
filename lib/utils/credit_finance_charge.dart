// Pure credit-card math: finance charges, minimum due, late fees.
//
// v1 uses a monthly-rate approximation. BPI documents a precise daily method
// (dailyRate = monthlyRate × 12 ÷ 360, applied to the outstanding balance per
// day from statement date through payment). The day-count parameters below are
// reserved so callers don't change when we tighten the calculation later.
//
// All rates are clamped to the BSP cap (Circular 1165: ≤ 3%/month). See
// docs/credit_accounts_spec.md for sources.

/// BSP maximum monthly finance charge.
const double kBspMonthlyRateCap = 0.03;

/// Finance charge accrued on an [outstanding] balance carried past the due date
/// at [monthlyRate] (nominal). Returns 0 when nothing is carried or no rate set.
///
/// [daysInCycle], [paidAmount] and [daysUntilPayment] are reserved for the
/// precise daily-balance method and are ignored by the v1 approximation.
double computeFinanceCharge({
  required double outstanding,
  required double monthlyRate,
  int? daysInCycle,
  double? paidAmount,
  int? daysUntilPayment,
}) {
  if (outstanding <= 0 || monthlyRate <= 0) return 0;
  final rate = monthlyRate.clamp(0.0, kBspMonthlyRateCap);
  return outstanding * rate;
}

/// Minimum amount due: max([minPaymentRate] of balance, [minPaymentFloor]),
/// never more than the balance itself, plus any [pastDue] carried over.
double computeMinimumDue({
  required double balance,
  double minPaymentRate = 0.0357,
  double minPaymentFloor = 850,
  double pastDue = 0,
}) {
  if (balance <= 0) return pastDue > 0 ? pastDue : 0;
  final computed = balance * minPaymentRate;
  final base = computed < minPaymentFloor ? minPaymentFloor : computed;
  final capped = base > balance ? balance : base;
  return capped + pastDue;
}

/// Late fee = the smaller of [lateFeeFlat] and the [unpaidMinimumDue].
double computeLateFee({
  required double unpaidMinimumDue,
  double lateFeeFlat = 850,
}) {
  if (unpaidMinimumDue <= 0) return 0;
  return unpaidMinimumDue < lateFeeFlat ? unpaidMinimumDue : lateFeeFlat;
}
