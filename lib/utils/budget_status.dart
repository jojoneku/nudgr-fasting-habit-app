import 'package:intermittent_fasting/utils/finance_format.dart';

/// Fraction of an allocation spent from which a budget row reads "Watch".
///
/// One number for every surface that badges budget health — the mobile and
/// web Budget pages and both Dashboard Budget health cards. The surfaces used
/// to disagree (75 % here, 85 % there), so the same row could be calm on one
/// page and amber on the next. Past 1.0 a row is "Over"; that boundary is not
/// configurable.
const double kBudgetWatchThreshold = 0.75;

/// Health of one budget row or group. Views map it to a color; the label from
/// [budgetStatusFor] carries the same meaning in text, so status is never
/// shown by color alone.
enum BudgetStatus { onTrack, watch, over, funded }

/// The one rule for budget status, shared by mobile and web (Plan 071,
/// Phase 2). Returns the status and its label:
///
/// - Savings ([accountBacked]): 'Funded' once [spent] (money funded in)
///   reaches [allocated], else 'On track'. Funding past a goal is the goal
///   working, so savings never read "Over".
/// - Income ([isIncome]): 'Received' once [spent] (money received) reaches
///   [allocated], else '₱X to come'.
/// - Expense: 'Over by ₱X' when [spent] passes [allocated]; 'Watch · N%' from
///   [kBudgetWatchThreshold] up to and including 100 %; else 'On track'.
///   A row with no allocation but some spending reads 'No budget set'
///   (watch) — it is not over a limit, but it needs a look.
({BudgetStatus status, String label}) budgetStatusFor({
  required double allocated,
  required double spent,
  bool accountBacked = false,
  bool isIncome = false,
}) {
  if (accountBacked) {
    return allocated > 0 && spent >= allocated
        ? (status: BudgetStatus.funded, label: 'Funded')
        : (status: BudgetStatus.onTrack, label: 'On track');
  }
  if (isIncome) {
    return allocated > 0 && spent >= allocated
        ? (status: BudgetStatus.funded, label: 'Received')
        : (
            status: BudgetStatus.onTrack,
            label: '${formatPesoWhole(allocated - spent)} to come',
          );
  }
  if (allocated <= 0) {
    return spent > 0
        ? (status: BudgetStatus.watch, label: 'No budget set')
        : (status: BudgetStatus.onTrack, label: 'On track');
  }
  if (spent > allocated) {
    return (
      status: BudgetStatus.over,
      label: 'Over by ${formatPesoWhole(spent - allocated)}',
    );
  }
  final used = spent / allocated;
  if (used >= kBudgetWatchThreshold) {
    return (
      status: BudgetStatus.watch,
      label: 'Watch · ${(used * 100).round()}%',
    );
  }
  return (status: BudgetStatus.onTrack, label: 'On track');
}

/// The note beside a budget group's subtotal: 'Funded' for a savings group
/// that reached its target, otherwise 'N% used' (or 'N% funded' for savings).
/// Empty when nothing is allocated.
String budgetGroupUsedLabel({
  required double allocated,
  required double spent,
  required bool isSavings,
}) {
  if (allocated <= 0) return '';
  if (isSavings && spent >= allocated) return 'Funded';
  final pct = (spent / allocated * 100).round();
  return isSavings ? '$pct% funded' : '$pct% used';
}
