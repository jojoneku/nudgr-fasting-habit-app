## Why

Nudgy can talk about your money and it can log an expense, but it cannot act on anything else. Ask it to set aside ₱3,000 for braces, add next month's internet bill, or fix a budget it just told you was wrong, and the only honest answer it can give is "open the Bills page." The advisor's own system prompt enforces this (rule 8: *"You CANNOT create, edit or delete transactions, bills, budgets or accounts"*), and that rule exists for a good reason — a user who believes Nudgy saved something will not go and save it themselves.

This is not an oversight. Plan 058 merged logging into the advisor chat and drew the line explicitly in §9:

> "Bills, goals, set-asides, receivables — Nudgy still can't create those. That's the tool-calling agent, a separate change with its own OpenSpec proposal."

This is that change.

The gap is now the most visible seam in the product. The advisor already *reads* everything it would need: the snapshot carries budget by group, set-asides itemised funded vs allocated, outstanding bills with due labels, and receivables with expected dates. It can tell you exactly which set-aside you are short on and then cannot create it. The reading half is done; only the writing half is missing.

Every mutator this needs already exists and is already the owner's: `BillsReceivablesPresenter` (`addBill`, `updateBill`, `deleteBill`, `addReceivable`, `updateReceivable`, `deleteReceivable`, `addBudgetedExpense`, `updateBudgetedExpense`, `deleteBudgetedExpense`) and `BudgetPresenter` (`setBudget`, `removeBudget`, `addGroup`, `deleteGroup`, `setBudgetRecurring`). This change is an adapter over existing domain logic, not new domain logic.

## What Changes

- **Add Bedrock tool use to the `adviseFinance` op.** The Lambda gains a `tools` array and returns `tool_use` blocks; the client sends `tool_result` blocks back on the next request. `stop_reason == "tool_use"` becomes a first-class outcome alongside `end_turn` and `max_tokens`.
- **Execute the tool loop on the client, not the server.** The Lambda is stateless with respect to user data — its only outbound call is the Supabase `increment_ai_usage` RPC, and every figure it sees arrives in `payload["context"]`. It therefore *cannot* execute these tools. Flutter runs the loop against its own presenters. This is a constraint, and it is also the design: each hop is its own HTTP request with its own 30s budget, so a multi-hop conversation never fights the API Gateway integration timeout.
- **Add read/search tools alongside write tools.** `findBills`, `findReceivables`, `findSetAsides`, `findBudgets` resolve a phrase to actual rows before any mutation is proposed. Without these, edit and delete are guesswork against ids the model cannot see.
- **Every write is a proposal, never a write.** A `tool_use` for a mutating tool produces a confirm card in `ChatPhase.reviewing`; the user commits. Tool calling and confirm-before-commit compose — the tool call is how the model *expresses* an intent, the card is what *executes* it.
- **Surface recurrence scope on the card.** `applyToFuture` is a parameter on every bill and receivable mutator and it is the highest-blast-radius value in the surface: `applyToFuture: true` on a delete removes a recurring series across every future month. The model never chooses it silently; it is an explicit control the user sees and sets.
- **Rewrite advisor rule 8.** It becomes false as written. The reason behind it survives in a new form: Nudgy proposes, and must not claim anything is saved until the confirmation returns.
- **Meter per user turn, not per model call.** `_DAILY_CAP = 100` counts Bedrock invocations through `increment_ai_usage`. A four-hop tool conversation would burn four of a hundred, so a normal day of use would hit the cap. Rate limiting moves to one count per user-initiated turn.
- **Enable Bedrock prompt caching.** A tool loop resends the full history and an already-large system prompt on every hop. Plan 058 §9 notes the prompt is already ordered for caching and only needs enabling; the `cache_read` field on the `adviseFinance` `cost_line` gives the before/after measurement.

## Capabilities

### New Capabilities
- `nudgy-finance-actions`: Nudgy proposes and, on confirmation, performs create/edit/delete on bills, receivables, set-asides and budgets, through a client-executed tool loop with confirm-before-commit and explicit recurrence scope.

### Modified Capabilities
- `ai-financial-advisor`: rule 8 changes from "you cannot mutate" to "you propose; never claim it is done until the confirmation returns." Rate limiting changes from per-model-call to per-user-turn. `stop_reason == "tool_use"` is added as a handled outcome.

## Impact

- **Backend**: `backend/ai-coach/lambda_function.py` — tool definitions, `tools` on the advisor `invoke_model` call, `tool_use` handling, per-turn metering, `cache_control` breakpoints; `backend/ai-coach/template.yaml` — no new parameters expected, but the advisor token budget interacts with tool-loop hops.
- **Services**: `lib/services/cloud_ai_coach_service.dart` — `adviseFinance` must carry tool definitions out and tool results back; its current contract returns a bare `String` and needs a richer result type.
- **Presenters**: `lib/presenters/ai_coach_presenter.dart` — the tool loop and its termination conditions; `BillsReceivablesPresenter` and `BudgetPresenter` gain no new mutators but become the executors. Wiring goes in `lib/presenters/treasury_presenters.dart` per CLAUDE.md #9, not in the shells.
- **Views**: a confirm-card variant per entity, extending the pattern in `lib/views/widgets/finance/entry_review_card.dart`.
- **Models**: a tool-call/tool-result model pair, and a proposal model per entity.
- **Non-breaking**: expense logging, food routing, and plain advisory answers all keep their current behaviour. A conversation that triggers no tool is byte-for-byte the request shape it is today.

## Non-goals

- **Accounts and transactions.** Account create/edit/delete is out; transaction editing stays a form trip. Logging already has its own pipeline and this change does not touch it.
- **Autonomous or silent writes.** There is no configuration in which Nudgy writes without an explicit confirmation. This is not a preference to be relaxed later.
- **Batch mutators.** `deleteBills`, `deleteReceivables`, `deleteBudgetedExpenses` and the `markXPaid` batch variants stay page-only. A chat line that resolves to "these nine rows" is precisely where a wrong match becomes expensive.
- **Custodian and sub-accounts** stay excluded from chat, per Plan 026 §4 and `docs/chat_logging_coverage.md` §3.
- **On-device tool calling.** Gemma is not a candidate; this path is cloud-only, as the advisor already is.
- **Server-side tool execution.** Structurally impossible while the data lives on the device, and undesirable even if it were not.
- **Streaming.** The advisor stays a blocking call. Streaming is a separate change and is only worth doing alongside a Lambda Function URL.
