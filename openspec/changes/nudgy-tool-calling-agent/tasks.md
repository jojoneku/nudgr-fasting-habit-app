## 1. Contracts and models (before anything calls them)

- [x] 1.1 Define the tool catalogue in one place shared by client and backend intent: name, description, JSON schema, and whether it mutates. Phase 1 set: `findBills`, `findReceivables`, `findSetAsides`, `findBudgets`, `addBill`, `addReceivable`, `addSetAside`. `applyToFuture` MUST NOT appear in any schema (design D4). Behaviour is `AiToolKind` (read/create/update/destroy), not a bool, so it maps onto MCP annotations (design D11). *Verify: a unit test asserts no schema contains `applyToFuture`, that every mutating tool takes an `id` or is a create, and that `toMcpJson()`/`toRequestJson()` agree on name, description and schema for every tool in the catalogue.*
- [x] 1.2 Add `AiToolCall` (id, name, input map) and `AiToolResult` (id, ok, summary, error) models in `lib/models/`, immutable with `fromJson`/`toJson`. *Verify: round-trip unit test.*
- [ ] 1.3 Add a `FinanceActionProposal` sealed type with one variant per entity, carrying the parsed tool input plus the resolved row for edits. *Verify: unit test constructing each variant from a representative tool input.*
- [x] 1.4 Change the `adviseFinance` service contract from `Stream<String>` to a result carrying either text or tool calls, plus the assistant turn to replay. Update `NullAiCoachService` and the on-device path to the new type. *Verify: existing advisor tests compile and pass unchanged in behaviour.*

## 2. Backend — tool use on `adviseFinance`

- [x] 2.1 Send `tools` on the advisor `invoke_model` call and return `tool_use` blocks in the response body alongside text. Handle `stop_reason == "tool_use"` as a first-class outcome next to `end_turn` and the `max_tokens` case already handled. *Verify: stubbed-Bedrock check asserting a `tool_use` response is passed through with its id and input intact.*
- [x] 2.2 Accept `tool_result` blocks on the request and replay them into `bedrock_messages` in the shape Bedrock expects. *Verify: stubbed check asserting a replayed turn produces a well-formed messages array.*
- [x] 2.3 Meter per user turn: accept a turn id, call `increment_ai_usage` on a turn's first hop only, pass later hops through (design D5). *Verify: stubbed check asserting three hops of one turn produce one RPC call, and that a fresh turn id produces another.*
- [x] 2.4 Extend the `cost_line` with `hop=` and `tools=` so loop behaviour is visible in logs, alongside the `in_tokens`/`out_tokens`/`latency_ms`/`cache_read` fields already there.
- [x] 2.5 Rewrite advisor rule 8 in `_ADVISOR_SYSTEM_PREFIX` per design D3: propose, never claim a save before its confirmation returns. Keep the reasoning sentence that explains why. *Verify: assert the new text is present and the old absolute prohibition is gone.*
- [ ] 2.6 Enable prompt caching with a breakpoint after `_ADVISOR_SYSTEM_PREFIX`. Leave the second breakpoint unplaced until `cache_read` data exists (design D7). *Verify: `cache_read` is non-zero on the second hop of a live turn.*

## 3. Presenter — the loop and the executors

- [x] 3.1 Implement the client tool loop in `AiCoachPresenter`: send, receive tool calls, execute, send results, repeat. Enforce the hop ceiling and the no-progress termination (design D6). *Verify: unit test with a scripted service driving 1-hop, 3-hop, and ceiling-exceeded conversations.*
- [x] 3.2 Implement the find tools against `BillsReceivablesPresenter` and `BudgetPresenter` read surfaces, executing with no confirmation. *Verify: unit tests for exact match, multiple matches, and no match.*
- [x] 3.3 Route mutating tool calls into `ChatPhase.reviewing` as a pending proposal rather than executing them. *Verify: unit test asserting no mutator is called when a mutating tool call arrives.*
- [x] 3.4 On confirmation, call the owning presenter's mutator and return the real outcome as the tool result; on decline, return a decline result (design D3, CLAUDE.md #8). *Verify: unit tests for both paths, asserting the tool result reflects the actual outcome and that no local copy is written.*
- [x] 3.5 Wire the new dependencies in `lib/presenters/treasury_presenters.dart`, not in `home_screen.dart` or `treasury_web_app.dart` (CLAUDE.md #9). *Verify: both shells compile with no new wiring of their own.*

## 4. UI — confirm cards

- [x] 4.1 **Revised:** no new shell was extracted. `AdvisorLogCard` already IS the shared shell (container chrome plus a body switch), so the proposal card slots into it as one more body. Extracting a parallel abstraction would have added a layer without removing one. *Verified: existing entry-review widget tests still pass.*
- [x] 4.2 Bill and receivable proposal cards, including the recurrence-scope control with its consequence stated and the narrow default (design D4). *Verify: widget test asserting the scope control exists, defaults narrow, and that confirming passes the user's choice through.*
- [x] 4.3 Set-aside proposal card, including type (`savings`/`goal`/`sinkingFund`/`gift`/`other`) and destination account. *Verify: widget test.*
- [x] 4.4 Theme-aware colours read from `Theme.of(context)` in every new card, both modes (CLAUDE.md #7). *Verify: widget test rendering each card in dark and light.*

## 5. End-to-end and guardrails

- [ ] 5.1 End-to-end test: "set aside ₱3,000 a month for braces" produces a proposal, confirmation writes through `addBudgetedExpense`, and the reply does not claim a save before confirmation. *Verify: this is the headline scenario; it must fail on today's code.*
- [ ] 5.2 Guardrail test: a pending or declined proposal never produces text asserting the write happened (design D3, the failure old rule 8 existed to prevent). *Verify: scripted conversation asserting the assistant text.*
- [ ] 5.3 Regression: a conversation that triggers no tool produces the same request shape and behaviour as today. *Verify: existing advisor tests, plus an assertion that no tool-related fields alter a no-tool request.*
- [ ] 5.4 Live smoke after CI deploys: run a real turn, confirm the loop completes, `cache_read` is non-zero on hop 2, and the daily count increments by one.

## 6. Phase 2 — edit, and budgets

- [ ] 6.1 Add `updateBill`, `updateReceivable`, `updateSetAside` tools and their edit cards, each requiring an id from a find.
- [ ] 6.2 Add `setBudget` and budget-group tools with their cards.
- [ ] 6.3 A chat-created savings budget offers its matching set-aside, at parity with `add_budget_sheet.dart:125` (design D8). *Verify: test asserting both surfaces produce the same offer.*

## 7. Phase 3 — delete

- [ ] 7.1 Add delete tools for all four entities, each requiring an id from a find.
- [ ] 7.2 Delete confirmation card naming the row's identifying fields and the recurrence scope explicitly, with the narrow default (design D9). *Verify: widget test asserting the row is identified by more than its name, and that scope is never pre-widened.*
- [ ] 7.3 Guardrail test: a delete proposal whose find returned multiple candidates cannot be confirmed without a disambiguation step.
