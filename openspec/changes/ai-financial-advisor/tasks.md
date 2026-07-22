## 1. Backend — advisor op + stronger model

- [x] 1.1 Add an `adviseFinance` op to `backend/ai-coach/lambda_function.py` that builds the persona + principle-grounded system prompt (advisor/life-strategist/behavioral-coach persona; principles from *Broke Millennial*, *Financial Freedom*, *The Total Money Makeover*, *Atomic Habits*, *The Defining Decade*; Filipino/utang-na-loob context; no copyrighted text) and invokes a Sonnet-tier Bedrock model. Encode the anti-hallucination contract (cite-source, no invented numbers, labeled inferences/absolutes, fixed refusal phrase) and the four-part "financial position" diagnostic structure as a stable, cache-friendly prompt prefix. See design D7.
- [x] 1.2 Add the advisor model id + token budget as parameters in `backend/ai-coach/template.yaml`, keeping `classifyFinance`/`respond` on the Haiku-tier model. **Verified in Bedrock `ap-southeast-1` (2026-07-22): Sonnet 4.5 `global.anthropic.claude-sonnet-4-5-20250929-v1:0` is access-granted & invocable → chosen. Sonnet 5 NOT granted on the account.**
- [x] 1.3 **Provisioned the live `food-coach-handler` function (hand-managed; no CFN stack exists):** merged `ADVISOR_MODEL_ID`/`ADVISOR_MAX_TOKENS` env vars (all Supabase keys preserved) + added additive inline IAM policy `AdvisorBedrockInvoke` for the Sonnet profile. JWT authorizer + `increment_ai_usage` are reused unchanged. **The `adviseFinance` code deploys via CI (`deploy_lambda`) when the PR merges — not via SAM.**
- [ ] 1.4 After CI deploys the merged code: curl the `adviseFinance` op with a valid Bearer token to confirm a grounded response, and confirm the cap still returns 429.

## 2. Persistence + models (before UI)

- [x] 2.1 Add an `AdvisorMessage` model (role, text, timestamp) and an `AdvisorProfile` model (goals, risk tolerance, freeform facts) in `lib/models/`, immutable with `fromJson`/`toJson`.
- [x] 2.2 Add StorageService keys + read/write methods for capped advisor chat history and the advisor profile (through the abstract `StorageService` interface only). **History reuses `AiChatMessage.toJson`; local-only for now (no `_markDirty`).**
- [ ] 2.3 **DEFERRED (needs a new `SyncDomain` + Supabase table + manual DB migration):** register advisor history + profile as sync domains (flush-before-wipe) for cross-device sync. Local persistence works today; this adds cloud sync.
- [x] 2.4 Unit-test round-trip persistence (save → load → equality) and history trimming/clearing.

## 3. Service layer — advisor request

- [x] 3.1 Add an advisor method to the `AiCoachService` interface (`lib/services/ai_coach_service.dart`) and implement it in `CloudAiCoachService` (`op: "adviseFinance"`), reusing the JWT token provider and typed error handling (401/403/429/transport). Return canned/unavailable in `NullAiCoachService`; no-op or cloud-fallback in `OnDeviceAiCoachService` (advisor requires cloud).
- [x] 3.2 Extend `AiCoachContext` (`lib/models/ai_coach_context.dart`) with forecasted net balance, net worth, total liquid cash, month net cash flow, savings rate, top category spend, account balances, and upcoming bills; render them compactly (PHP, rounded, top-N) in `toPromptSummary()`.
- [x] 3.3 Unit-test `toPromptSummary()` produces a bounded, PHP-formatted summary from a sample context.

## 4. Presenter — advisor session + logging hook

- [x] 4.1 Add `AiCoachEntryPoint.financeAdvisor` and extend `AiCoachPresenter._buildContext()` to populate the enriched Treasury fields (inject `TreasuryDashboardPresenter`, already available).
- [x] 4.2 Advisor `send()` calls `adviseFinance`; history is loaded on session open + persisted after each turn; the user-curated profile is injected each turn. **Design open-question resolved: profile is USER-CURATED (deterministic), not model-delta extracted — auto-extraction is a deferred enhancement.**
- [ ] 4.3 Add an in-conversation logging hook: detect a money-logging intent (amount + verb/keyword heuristic; default to advice when ambiguous) and route to `LedgerPresenter.sendChatInput(text)`, surfacing the existing resolved/clarify/give-up result. No direct writes from the advisor model.
- [x] 4.4 Inject `LedgerPresenter` into `AiCoachPresenter` via its constructor; construct in `AppShell._AppShellState.initState()` (`lib/views/home_screen.dart`) and pass down to `HubScreen` (constructor injection, no locators).
- [ ] 4.5 Presenter tests: advisory turn calls the advisor op; logging intent routes to the ledger pipeline and does not commit without confirm; out-of-scope mutation (budget/bill) is refused; availability/cap/offline states surface correct messages.

## 5. UI — dual-mode hub bar + advisor surface

- [x] 5.1 Add a `financeAdvisor` entry to `_entryMeta` in `lib/views/widgets/ai_chat_sheet.dart` (gold Treasury accent, Phosphor icon, advisor label).
- [x] 5.2 Convert `_QuickLogBar` (`lib/views/hub_screen.dart`) to dual-mode: collapsed = today's inline quick-log (unchanged routing); tap/expand opens the advisor surface anchored to the bar; collapse returns to pinned collapsed state. Keep it pinned as `bottomNavigationBar`.
- [ ] 5.3 Render the in-conversation expense confirm/clarify (reuse `LedgerChatPanel` states or an in-sheet equivalent) so logging inside the advisor uses the same confirm-before-commit UX.
- [x] 5.4 Add a memory/profile view where the user can see and clear stored facts and clear conversation history.
- [x] 5.5 Verify UI rules: no logic in `build()`, theme-aware colors only (dark + light), touch targets ≥44px, expand/collapse animation 150–400ms, input stays in bottom 30%.

## 6. Spec sync, docs, and QA

- [ ] 6.1 Widget test: expanding the bar opens the advisor; a short logging phrase in the collapsed bar routes to quick-log without opening the advisor.
- [ ] 6.2 Guardrail QA (prompt-level): verify the advisor cites the source of each figure, refuses a missing figure with the exact fixed phrase, labels `[Inference]`/`[Unverified]` claims, excludes transfers from spending, and does not flag paid-in-full credit as toxic debt.
- [ ] 6.3 "Financial position" QA: the four-part diagnostic (Liquidity, Obligations, Burn Rate top-2-vs-target, Behavioral audit) renders with cited figures.
- [ ] 6.4 Manual smoke on device (dark + light): positioning question, affordability question, in-chat expense log with confirm, refusal of a budget-edit request, daily-cap and offline messaging, history persists across restart, profile remembers a stated goal.
- [ ] 6.5 Run `dart format` + `flutter analyze` clean.
- [ ] 6.6 On archive, sync the `hub` delta into `openspec/specs/hub/spec.md` and add the new `ai-financial-advisor` capability spec to `openspec/specs/`.
