import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// Which figure an [AccountMeter] tracks.
enum AccountMeterKind {
  /// A credit card, credit line or BNPL plan with a limit: how much of the
  /// limit is used.
  credit,

  /// A goal, or a savings account with a target: how far toward the target.
  goal,
}

/// The bar under an account row and the words beside it. Built only by
/// [accountMeterFor], so mobile and web draw the same meter for the same
/// account.
class AccountMeter {
  final AccountMeterKind kind;

  /// How full the bar is, 0..1. For credit this is the share of the limit in
  /// use; for a goal it is the share of the target saved.
  final double fraction;

  /// '₱8,000.00 available of ₱20,000.00' or '45% of ₱6,000.00'.
  final String label;

  const AccountMeter({
    required this.kind,
    required this.fraction,
    required this.label,
  });
}

/// The meter for [account], or null when the account has none.
///
/// Only two kinds of account get one: a credit account with a limit (reads
/// [FinancialAccount.availableCredit] and [FinancialAccount.utilization]) and
/// a goal or savings account with a target (reads
/// [FinancialAccount.goalProgress], which pins a reached goal at 100%). A
/// completed goal has no meter: after the purchase the balance is back to ₱0,
/// and its row says what it funded instead.
AccountMeter? accountMeterFor(FinancialAccount account) {
  final limit = account.creditLimit;
  if (account.isLiability) {
    final used = account.utilization;
    final available = account.availableCredit;
    if (limit == null || limit <= 0 || used == null || available == null) {
      return null;
    }
    return AccountMeter(
      kind: AccountMeterKind.credit,
      fraction: used.clamp(0.0, 1.0),
      label: '${formatPesoMinus(available)} available of ${formatPeso(limit)}',
    );
  }

  final target = account.goalTarget ?? 0;
  if (target <= 0) return null;
  if (account.goalStage == GoalStage.redeemed) return null;
  final fraction = goalMeterFraction(account);
  return AccountMeter(
    kind: AccountMeterKind.goal,
    fraction: fraction,
    label: '${formatPercent(fraction)} of ${formatPeso(target)}',
  );
}

/// Progress toward the target, 0..1, for any account that has one.
///
/// A goal reads [FinancialAccount.goalProgress] (pinned at 100% once funded,
/// so spending a reached goal does not drop its bar to zero). A savings
/// account with a target has no lifecycle, so it is the plain balance share.
/// The one rule behind the mobile `GoalProgressCard` and the web `WebGoalCard`.
double goalMeterFraction(FinancialAccount account) {
  if (account.hasGoalTarget) return account.goalProgress;
  final target = account.goalTarget ?? 0;
  if (target <= 0) return 0;
  return (account.balance / target).clamp(0.0, 1.0);
}
