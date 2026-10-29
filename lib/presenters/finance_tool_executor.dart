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
    this.confirmLabel,
    this.isDestructive = false,
    this.ledgerChoice,
    this.tier = ProposalTier.create,
    this.editable = const {},
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

  /// Optional custom label for the primary confirm button (e.g. "Mark Paid",
  /// "Delete Entry"). Defaults to "Add it" when null.
  final String? confirmLabel;

  /// True when this proposal removes or deletes an existing entity.
  final bool isDestructive;

  /// Set on a settlement that can also write the ledger entry for the money
  /// (mark a bill paid, a receivable received). Null on everything else.
  final LedgerEntryChoice? ledgerChoice;

  /// How much care the row asks for (Plan 065 phase 4). It decides how the
  /// row is drawn, never whether there is a card: every write has one.
  final ProposalTier tier;

  /// Fields the user may change in place on the row, each mapped to the tool
  /// input key it writes. An edit re-checks and re-describes the call, so the
  /// row always shows what will be saved.
  final Map<ProposalField, String> editable;

  /// True when widening the recurrence scope would also change later months,
  /// which makes the row a T3 change once the user picks it.
  bool get canTouchLaterMonths => isRecurring;

  /// The row's tier once the user picks a scope: a recurring change spread to
  /// later months is T3, whatever it was.
  ProposalTier tierWith({required bool laterMonths}) =>
      laterMonths && isRecurring ? ProposalTier.destructive : tier;

  /// What else changes when the scope is widened, for the red row.
  String get laterMonthsNote =>
      switch (call.name.split(RegExp('[A-Z]')).first) {
        'delete' => 'Also deletes it from every later month',
        'add' => 'Also adds it to every later month',
        _ => 'Also changes every later month',
      };

  /// This row with its review tier and editable fields set.
  PendingFinanceAction withReview({
    required ProposalTier tier,
    required Map<ProposalField, String> editable,
  }) =>
      PendingFinanceAction(
        call: call,
        title: title,
        details: details,
        isRecurring: isRecurring,
        confirmLabel: confirmLabel,
        isDestructive: isDestructive,
        ledgerChoice: ledgerChoice,
        tier: tier,
        editable: editable,
      );
}

/// Risk tiers from Plan 065 (audit 065a part 2).
enum ProposalTier {
  /// T1: a single create that is easy to undo. A normal row.
  create,

  /// T2: an edit of existing data, or a move of money. The row shows
  /// before → after.
  change,

  /// T3: a delete, a cascade, a bulk change or a change to later months. A
  /// red row that lists what else changes; Approve all asks once more.
  destructive,
}

/// A field a batch row can edit in place, with the existing pickers.
enum ProposalField { name, amount, account, category, date, day }

/// Every write Nudgy proposed in one step, reviewed as one list
/// (Plan 065 phase 4, decision 2).
class PendingBatch {
  const PendingBatch({required this.id, required this.actions});

  final String id;

  /// In the order the model called them.
  final List<PendingFinanceAction> actions;

  bool get hasDestructive =>
      actions.any((a) => a.tier == ProposalTier.destructive);

  /// True when Approve all must ask once more: a row is T3 as the user set
  /// it, [applyToFuture] being the card's scope choice per call id.
  bool needsSecondConfirm(Map<String, bool> applyToFuture) => actions.any((a) =>
      a.tierWith(laterMonths: applyToFuture[a.call.id] ?? false) ==
      ProposalTier.destructive);

  /// The approve button's words for [rowCount] rows: a lone change keeps its
  /// own verb ("Mark Paid"), a list says how many it saves.
  String approveLabel(int rowCount) {
    if (rowCount == 1 && actions.length == 1) {
      return actions.single.confirmLabel ?? 'Add it';
    }
    return rowCount == 1 ? 'Approve' : 'Approve all ($rowCount)';
  }
}

/// Whether settling a bill or receivable also records the money in the
/// ledger, or only flags it — because the user already logged it by hand.
///
/// A card control, like recurrence scope. Recording a payment the ledger
/// already holds counts it twice, and the model cannot see the ledger well
/// enough to know; the user can, so the card asks.
class LedgerEntryChoice {
  const LedgerEntryChoice({
    required this.alreadyLogged,
    required this.canRecord,
    this.match,
  });

  /// The card's starting answer: true when the model said the user already
  /// logged it, or when [match] was found.
  final bool alreadyLogged;

  /// False when no account resolves to record the money against. The card
  /// then offers "already logged" only, since recording needs an account.
  final bool canRecord;

  /// A ledger entry that looks like this payment, e.g.
  /// "Meralco ₱3500 on 2026-09-12", shown so the user can tell.
  final String? match;

  /// The line under the checkbox: what was found, or what each answer does.
  String get hint {
    final found = match;
    if (found != null) return 'Found in the ledger: $found';
    return canRecord
        ? 'Leave off to record a new ledger entry.'
        : 'No account to record it in, so it is only marked.';
  }
}

/// The half of the executor a confirm card talks to.
///
/// Split from [FinanceToolExecutor] so the two audiences stay separate: the
/// presenter's loop only ever needs to run tools, and the card only ever needs
/// to show and answer a proposal. Keeping them apart also lets the loop's tests
/// inject a fake that answers immediately, with no UI surface to stub.
abstract class FinanceProposalHost implements Listenable {
  /// The open batch, or null when nothing waits for an answer.
  PendingBatch? get batch;

  /// True when the batch's `logTransactions` rows sit on the ledger's review
  /// card and belong to this list.
  bool get batchHasLedgerRows;

  /// Rows the user is about to approve: the changes plus any ledger rows.
  int get openRowCount;

  /// False while a ledger row still needs a field: approving would save the
  /// ready rows behind the user's back.
  bool get canApproveAll;

  /// The first change awaiting confirmation, or null when nothing is pending.
  /// For a batch of one, the whole batch.
  PendingFinanceAction? get pending;

  /// The user said yes to a batch of one. [applyToFuture] and
  /// [alreadyLogged] come from the card, never the model. A null
  /// [alreadyLogged] keeps the card's starting answer
  /// ([LedgerEntryChoice.alreadyLogged]).
  Future<void> confirm({bool applyToFuture, bool? alreadyLogged});

  /// The user said no to everything still open.
  void decline();

  /// Approve every row still in the batch. Scope and "already in the
  /// ledger" are per row, keyed by tool call id, and come from the card.
  Future<void> approveAll({
    Map<String, bool> applyToFuture,
    Map<String, bool> alreadyLogged,
  });

  /// Remove one row: it is reported to the model as not saved.
  void removeAction(String callId);

  /// Change fields of one row in place. Returns why the change cannot be
  /// shown (an unknown account, say), or null when the row now shows it.
  String? editAction(String callId, Map<String, Object?> patch);

  /// The user typed in the chat while the batch was open: every open row is
  /// answered "not approved", with their words, so Nudgy can propose a new
  /// batch. Nothing is saved.
  void reviseAll(String userText);
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

  /// Every write call of one model step, as one batch the user reviews in one
  /// list. Completes when the user answers, with one result per call in call
  /// order. Same contract as [propose]: nothing is written before approval,
  /// and each result says what actually happened to that call.
  Future<List<AiToolResult>> proposeBatch(List<AiToolCall> calls);
}
