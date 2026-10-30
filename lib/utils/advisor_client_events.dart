import '../models/ai_tool.dart';

/// Names of the advisor's client events (Plan 065, phase 5). Each must be on
/// the Lambda's allow-list (`_CLIENT_EVENTS`), with the same fields.
abstract final class AdvisorClientEvent {
  /// A batch of Nudgy's changes is shown. Fields: `items`.
  static const batchOpened = 'batch_opened';

  /// The user answered a batch. Fields: `approved`, `declined`, `revised`,
  /// `removed`, `failed` — see [batchOutcomeCounts].
  static const batchAnswered = 'batch_answered';

  /// The user pressed stop. Fields: `phase` (`reply` or `batch`).
  static const stopPressed = 'stop_pressed';

  /// The user tapped "Not a log — ask Nudgy". No fields.
  static const askNudgyTapped = 'ask_nudgy_tapped';

  /// A batch an app restart interrupted was found again. Fields: `items`,
  /// `outcome` (`shown` or `not_reviewed`).
  static const batchResumed = 'batch_resumed';
}

// The start of each "not saved" summary the executor and the presenter send
// back for a batch row (FinanceActionsExecutor, AiCoachPresenter).
const _declinedPrefix = 'The user declined';
const _revisedPrefix = 'Not approved, and nothing was saved.';
const _removedPrefixes = ['The user removed', 'Not saved: it used the new'];

/// How each row of an answered batch came out, as `batch_answered` fields.
///
/// A row that is not ok and matches none of the known summaries counts as
/// `failed` (a save that failed, or a row the app could not show).
Map<String, Object> batchOutcomeCounts(List<AiToolResult> answers) {
  var approved = 0, declined = 0, revised = 0, removed = 0, failed = 0;
  for (final a in answers) {
    final s = a.summary;
    if (a.ok) {
      approved++;
    } else if (s.startsWith(_declinedPrefix)) {
      declined++;
    } else if (s.startsWith(_revisedPrefix)) {
      revised++;
    } else if (_removedPrefixes.any(s.startsWith)) {
      removed++;
    } else {
      failed++;
    }
  }
  return {
    'approved': approved,
    'declined': declined,
    'revised': revised,
    'removed': removed,
    'failed': failed,
  };
}
