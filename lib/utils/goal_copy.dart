/// The "How goals are funded" note, shared by the web Goals page and the
/// mobile Goals screen so both say the same thing.
///
/// Goals are funded through budget set-asides (Bills → Mark paid → Set aside
/// into), never a raw transfer: a raw transfer would count twice against the
/// month-end outlook.
const String kGoalsFundingNote =
    'Each goal is a Savings row in your budget. Money reaches it through a '
    'set-aside (Bills → Mark paid → Set aside into), not through a raw '
    'transfer, so the month-end outlook stays right. "Start again" clears a '
    'completed goal\'s spent stamp and starts it toward a new target; the '
    'account and its history stay put.';

/// The Start again sheet / dialog's explanation, shared by mobile and web.
///
/// Start again reaches completed goals and active goals that have not reached
/// their target (`TreasuryDashboardPresenter.canStartAgain`); a reached goal
/// is marked spent first. Only the completed ones carry a stamp to clear, so
/// the copy says so conditionally rather than claiming every goal has one.
const String kGoalRestartNote =
    'Sets a new target and starts tracking toward it. If the goal was '
    'completed, its spent stamp is cleared. The account and everything in its '
    'history stay put.';
