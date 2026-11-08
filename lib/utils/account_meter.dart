import 'package:intermittent_fasting/models/finance/financial_account.dart';

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
