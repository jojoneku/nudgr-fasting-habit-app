// Planning-word veto for the quick-log router (Plan 065, phase 1d).
//
// Nudgy's chat sends a message that reads like an expense straight to the
// ledger's quick-log pipeline, and everything else to the advisor model. A
// sentence about money the user has not spent yet — "I want to pay 5000 for
// the BPI card next month" — carries an amount and a spend verb, so it was
// put on a log card instead of being answered. These words mark a plan or a
// question, never a report of something done, so their presence vetoes the
// quick-log route. Both routers (`AiCoachPresenter.looksLikeExpenseLog` and
// `LedgerPresenter.recognisesLoggableEntry`) read this one list.
//
// "think" is deliberately absent: "I think I spent 200 on grab" is a log.

final _planningWords = RegExp(
  r'\b(want|wants|wanna|plan|plans|planning|should|if|how|next|thinking)\b',
  caseSensitive: false,
);

/// True when [text] talks about a plan or asks a question rather than
/// reporting money already spent, so it must go to the advisor, not quick log.
bool hasPlanningIntent(String text) => _planningWords.hasMatch(text);
