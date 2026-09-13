import 'package:intermittent_fasting/models/finance/financial_account.dart';

/// Pure transitions for the goal lifecycle (see `docs/goal_lifecycle_spec.md`).
///
/// Accounts are mutated from two places — `LedgerPresenter` (the source of
/// truth) and `TreasuryDashboardPresenter` (which owns the Goals & Savings
/// surface and persists directly before telling the ledger to re-read). Putting
/// the rules here keeps the two from drifting into subtly different ideas of
/// when a goal counts as funded.
///
/// Every function returns the account unchanged when the transition does not
/// apply, so callers can map over the whole account list without filtering.

/// Records the moment a goal first reaches its target.
///
/// Only ever *sets* the stamp. A later withdrawal must never un-fund a goal:
/// spending what you saved would otherwise erase the fact that you saved it,
/// which is the exact bug this lifecycle exists to fix.
FinancialAccount stampIfFunded(FinancialAccount account, DateTime now) {
  if (!account.hasGoalTarget) return account;
  if (account.goalFundedAt != null || account.goalRedeemedAt != null) {
    return account;
  }
  if (account.balance < account.goalTarget!) return account;
  return account.copyWith(goalFundedAt: now, updatedAt: now);
}

/// Keeps the funded stamp honest when the target itself is **raised**.
///
/// Re-planning a goal upward means the user has redefined "done", so a stamp
/// earned under the old, smaller target no longer describes anything true.
///
/// [previous] is the account as currently stored, and is what makes this safe:
/// without it, "the target went up" is indistinguishable from "the balance went
/// down", and every withdrawal from a funded goal would silently un-fund it —
/// the exact failure this lifecycle exists to prevent. Pass null for a brand-new
/// account. Lowering the target, editing any other field, or spending the money
/// all leave the stamp alone, and a redeemed goal is history and never touched.
FinancialAccount reconcileGoalStamps(
  FinancialAccount incoming,
  FinancialAccount? previous,
  DateTime now,
) {
  if (incoming.goalStage != GoalStage.funded) return incoming;
  final newTarget = incoming.goalTarget ?? 0;
  final oldTarget = previous?.goalTarget ?? newTarget;
  if (newTarget <= oldTarget) return incoming;
  if (incoming.balance >= newTarget) return incoming;
  return incoming.copyWith(goalFundedAt: null, updatedAt: now);
}

/// Marks a funded goal as spent on what it was for.
///
/// Callers must reach here from an explicit user action. The app cannot
/// distinguish "bought the phone" from "raided the jar for an emergency", and
/// those are a success and a setback — inferring either would mislabel the
/// other. [amount] defaults to the target, which is what was actually set aside.
FinancialAccount redeemGoal(
  FinancialAccount account,
  DateTime now, {
  double? amount,
}) {
  if (account.goalStage != GoalStage.funded) return account;
  return account.copyWith(
    goalRedeemedAt: now,
    goalRedeemedAmount: amount ?? account.goalTarget,
    updatedAt: now,
  );
}

/// Starts a completed goal over against a fresh target, keeping the account —
/// and therefore its whole transaction history — intact.
///
/// Explicit rather than automatic on redemption: an annual insurance fund
/// really is the same goal each year, but a phone in 2026 and a phone in 2029
/// are not. A restart onto a target the balance already clears re-stamps as
/// funded immediately, so callers should follow with [stampIfFunded].
FinancialAccount restartGoal(
  FinancialAccount account,
  DateTime now, {
  required double newTarget,
}) {
  if (newTarget <= 0) return account;
  if (account.category != AccountCategory.goal) return account;
  return account.copyWith(
    goalTarget: newTarget,
    goalFundedAt: null,
    goalRedeemedAt: null,
    goalRedeemedAmount: null,
    updatedAt: now,
  );
}
