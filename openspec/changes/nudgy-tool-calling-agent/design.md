# Design — Nudgy Tool-Calling Agent

## Context

`AiCoachPresenter.send()` already routes two ways: a message that looks like an expense log goes to `LedgerPresenter.sendChatInput`, everything else goes to `adviseFinance`. Logging writes through a confirm card; the advisor writes nothing at all.

Three existing facts decide most of this design before any choice is made.

1. **The Lambda has no user data.** Its only outbound HTTP is the Supabase `increment_ai_usage` RPC. Every figure the advisor sees arrives in `payload["context"]`, assembled client-side by `_buildContext()`. There is no server-side store to mutate.
2. **The advisor is a blocking call behind a 30s wall.** `adviseFinance` is `invoke_model` (not the streaming variant) behind an `AWS::Serverless::HttpApi`, whose integration timeout is capped at 30 seconds and cannot be raised.
3. **The mutators already exist and already have owners.** `BillsReceivablesPresenter` owns bills, receivables and set-asides; `BudgetPresenter` owns budgets and groups. CLAUDE.md #8 requires writes go through the owner.

## Goals / Non-Goals

**Goals**
- Nudgy can create, edit and delete bills, receivables, set-asides and budgets.
- No mutation reaches storage without an explicit user confirmation.
- Recurrence scope is always visible before a write that can touch future months.
- A conversation that triggers no tool costs exactly what it costs today.

**Non-Goals**
- Server-side tool execution, batch mutators, accounts, transaction editing, streaming, on-device tool calling. See proposal Non-goals.

## Decisions

### D1 — The tool loop runs on the client

The Lambda returns `tool_use` blocks; it never executes them. `AiCoachPresenter` executes against the presenters it already holds and sends `tool_result` blocks on a fresh request.

This is forced by context fact 1: the server cannot read a bill, so it cannot act on one. It is also the reason the 30s wall (fact 2) never becomes a problem here. A server-side loop would have to fit N sequential Bedrock calls inside one 30-second HTTP request, which a two-hop conversation would already strain. A client-side loop gives every hop a full, independent 30s budget, and the user sees progress between hops instead of staring at one long spinner.

Consequence: `CloudAiCoachService.adviseFinance` currently yields a bare `String`. It needs a result type carrying either text or a list of tool calls, plus the assistant turn to replay. This is the largest single piece of plumbing in the change.

### D2 — Read tools are part of the minimum, not a later refinement

Plan 058 called edit and delete "structural — a chat line names no existing row." That was correct for an extractor that only ever created. It stops being true once the model can look a row up, and *only* then.

So the tool set is paired: `findBills`, `findReceivables`, `findSetAsides`, `findBudgets` return matching rows with their ids, and every mutating tool takes an id that came from a find. A model that has not called a find has no id to pass. This is what keeps "delete my internet bill" from resolving against the wrong row.

Find tools execute client-side with no confirmation — they are reads, they mutate nothing, and gating them behind a card would make every edit a two-card interaction.

### D3 — A mutating tool call produces a proposal, never a write

`tool_use` for a mutating tool puts the chat in `ChatPhase.reviewing` with a confirm card. The user commits; the presenter calls the owner's mutator; the *result of the commit* becomes the `tool_result`.

The ordering matters and is easy to get backwards. The tool result must describe what actually happened, not what was proposed, or the model will narrate a successful save the user declined. A declined card returns a tool result saying so, and the model is expected to acknowledge it rather than retry.

This preserves the substance of advisor rule 8 while making its literal text false. The rule is rewritten, not deleted: *you propose; never claim it is done until the confirmation returns.*

### D4 — `applyToFuture` is a card control, never a model argument

Every bill and receivable mutator takes `applyToFuture`. On a delete it is the difference between removing one month's row and erasing a recurring series across every future month, and nothing in a chat sentence reliably distinguishes "cancel my internet bill" from "cancel it for this month."

The tool schema therefore **omits** `applyToFuture`. It is not a field the model can set, correctly or otherwise. The confirm card renders it as an explicit choice with the consequence spelled out, defaulting to the narrower scope. A model that wants the wider scope has to ask the user in prose, which is the correct interaction anyway.

### D5 — Metering moves to per user turn

`increment_ai_usage` is called per Bedrock invocation and `_DAILY_CAP` is 100. Under a tool loop a single question can cost four invocations, so the effective cap would drop to roughly 25 conversations a day without anyone changing a setting.

The client sends a turn id; the Lambda counts the first hop of a turn and passes subsequent hops through. Cheating the cap by fabricating turn ids is possible and not worth defending against — the loop has its own hard hop ceiling (D6), which is the real bound.

### D6 — The loop has a hard hop ceiling

Runaway loops are the standard failure of this pattern. The client stops after a fixed number of hops (start at 5) and tells the user plainly that Nudgy did not finish, rather than continuing silently. A hop that returns neither text nor a tool call also terminates.

### D7 — Prompt caching stops being optional

Each hop resends the full history plus the system prompt, which is already large before the snapshot and historical grid are appended. Without caching, a four-hop conversation pays for that prefix four times.

Plan 058 §9 already notes the prompt is ordered for caching and only needs enabling. `_ADVISOR_SYSTEM_PREFIX` is static and sits first, so a breakpoint after it is safe. Whether a second breakpoint after the snapshot pays off depends on whether the client sends byte-identical context across hops; `cache_read` on the `adviseFinance` `cost_line` answers that empirically. Do not guess it — measure, then place the second breakpoint.

### D8 — A chat-created savings budget fires the same set-aside offer as the page

`add_budget_sheet.dart:125` calls `createRecurringSetAsideFor` when a savings budget is saved, because that is the one moment the user has both in mind. A budget created through chat must do the same, or the two surfaces disagree about what saving a budget means.

Implemented as: the budget confirm card offers the matching set-aside inline, the same way the sheet does. Not as a second tool call, which would put a mechanical detail in the model's hands for no gain.

### D9 — Delete ships last

Create is recoverable by deleting. Edit is recoverable by editing back. Delete is recoverable by nothing, and combined with recurrence scope it has the widest blast radius in the surface. It ships in phase 3, behind a card that names the row and the scope explicitly.

## Risks / Trade-offs

- **A wrong row deleted.** Mitigated by D2 (ids only from finds), D4 (scope never model-chosen), D9 (ships last), and a card that shows the row's identifying fields rather than just its name.
- **The model narrates a save that did not happen.** Mitigated by D3's ordering and the rewritten rule 8. This is the failure the original rule existed to prevent and it must be tested directly, not assumed.
- **Latency.** Three hops is three sequential round trips, each with its own model call. Caching (D7) cuts input cost but not round-trip count. Partly why find tools are cheap and unconfirmed.
- **Cap accounting.** Per-turn metering is a real loosening of a real limit. The hop ceiling is what bounds it.
- **Prompt bloat.** Tool definitions are input tokens on every request, including the majority of turns that use no tool. Keep schemas terse; revisit if `in_tokens` moves materially.

## Migration Plan

Phased, each phase shippable and independently useful.

- **Phase 1 — create.** Bills, receivables, set-asides. Ships the client loop, the find tools, the confirm-card variants, per-turn metering, the hop ceiling, and the rule 8 rewrite. This alone covers the original ask ("add set-aside bills by looking at the budget page").
- **Phase 2 — edit, and budgets.** Edit for bills/receivables/set-asides; create and edit for budgets, including D8.
- **Phase 3 — delete.** All four entities, behind the strongest confirmation.

Nothing in phase 1 is reworked by phases 2 or 3; each adds tools to an existing loop.

## Open Questions

- Does the client send byte-identical `context` across hops of one turn? Decides whether the second cache breakpoint is worth placing (D7). Answerable from `cache_read` once phase 1 is live.
- Should a find tool that matches nothing return an empty list, or an error the model must handle? Empty list is simpler; an error may produce better "I couldn't find that" phrasing. Decide from observed behaviour in phase 1.
- Is 5 the right hop ceiling? Chosen as a starting value, not a measured one.
