import '../models/ai_tool.dart';

/// Runs the tools Nudgy calls.
///
/// Split out from [AiCoachPresenter] for two reasons. The loop and the tool
/// bodies fail in completely different ways and are worth testing apart, and
/// the tools reach into presenters the advisor otherwise has no business
/// holding — bills, budgets — which per CLAUDE.md #9 are assembled in
/// `TreasuryPresenters`, not in the chat presenter.
///
/// The split between the two methods is the safety property of this change,
/// not an organisational nicety. [runRead] executes. [propose] does not: it
/// puts a card in front of the user and reports back whatever they decided.
abstract class FinanceToolExecutor {
  /// Execute a read-only tool now. Reads mutate nothing, and gating them
  /// behind a card would turn every edit into a two-card interaction.
  Future<AiToolResult> runRead(AiToolCall call);

  /// Surface a mutating call as a proposal and wait for the user's decision.
  ///
  /// MUST NOT write anything before the user confirms, and MUST report what
  /// actually happened — a decline returns [AiToolResult.declined], never a
  /// success. Reporting a save the user refused is the exact failure advisor
  /// rule 8 exists to prevent.
  Future<AiToolResult> propose(AiToolCall call);
}
