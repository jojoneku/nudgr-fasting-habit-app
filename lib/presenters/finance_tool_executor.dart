import 'package:flutter/foundation.dart';

import '../models/ai_tool.dart';

/// A change Nudgy proposed, waiting for the user to say yes or no.
///
/// Deliberately a plain description rather than a half-built entity: the card
/// renders these fields, and the entity is only constructed once the user has
/// confirmed. Nothing that could accidentally be persisted exists until then.
class PendingFinanceAction {
  const PendingFinanceAction({
    required this.call,
    required this.title,
    required this.details,
    required this.isRecurring,
  });

  final AiToolCall call;

  /// One line naming what will happen, e.g. "Set aside ₱3,000 for Braces".
  final String title;

  /// Label/value rows for the card body.
  final List<({String label, String value})> details;

  /// Whether the proposal repeats. Only a recurring action offers the
  /// future-months scope choice, because only a recurring one has a series to
  /// spread across.
  final bool isRecurring;
}

/// The half of the executor a confirm card talks to.
///
/// Split from [FinanceToolExecutor] so the two audiences stay separate: the
/// presenter's loop only ever needs to run tools, and the card only ever needs
/// to show and answer a proposal. Keeping them apart also lets the loop's tests
/// inject a fake that answers immediately, with no UI surface to stub.
abstract class FinanceProposalHost implements Listenable {
  /// The change awaiting confirmation, or null when nothing is pending.
  PendingFinanceAction? get pending;

  /// The user said yes. [applyToFuture] comes from the card, never the model.
  Future<void> confirm({bool applyToFuture});

  /// The user said no.
  void decline();
}

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
