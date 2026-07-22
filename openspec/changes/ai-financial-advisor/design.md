# Design — AI Financial Advisor

## Context

The app already ships the fragments needed for a conversational financial advisor:

- **Chat UI** — `AiChatSheet` (`lib/views/widgets/ai_chat_sheet.dart`): a `DraggableScrollableSheet` with message list, bubbles, typing indicator, and input bar. Entry points are themed via `_entryMeta` keyed on `AiCoachEntryPoint`.
- **Chat presenter** — `AiCoachPresenter` (`lib/presenters/ai_coach_presenter.dart`): `ChangeNotifier` with `openSession(entryPoint)`, `send(text)`, streaming placeholder handling, 50-message trim, tier fallback (on-device primary + `cloudFallback`), and `_buildContext()` which snapshots `AiCoachContext`.
- **Cloud transport** — `CloudAiCoachService` (`lib/services/cloud_ai_coach_service.dart`): single JWT-authed endpoint (`AI_COACH_ENDPOINT` via `--dart-define`), `{op, payload}` request shape, typed error handling (401/403/429/transport). Backed by `backend/ai-coach/lambda_function.py` (Bedrock, per-user daily cap via Supabase `increment_ai_usage`).
- **Confirm-before-commit finance actions** — `LedgerPresenter.sendChatInput()` → classifier (`finance_classifier_parser.dart`) → `StepResolved`/`StepClarify`/`StepGiveUp`, rendered by `LedgerChatPanel`. Entities are validated against live accounts/categories; the client is the sole writer.
- **Read surface** — `TreasuryDashboardPresenter` exposes `forecastedNetBalance`, `netWorth`, `totalLiquidCash`, `categorySpendThisMonth`, `savingsRate`, `monthNetCashFlow`, `upcomingBills`, account rows, etc.
- **Hub bar** — `_QuickLogBar` in `lib/views/hub_screen.dart`, pinned as `bottomNavigationBar`, routing via `QuickLogRouter` to ledger/nutrition.

This change **unites and enriches** these, rather than building new infrastructure. The `hub` spec already documents the docked bar and is amended by a delta.

## Goals / Non-Goals

**Goals:**
- One dual-mode hub bar: inline quick-log (unchanged) + expand-to-advisor.
- Advisor that reasons over a rich, live financial snapshot and durable book *principles*.
- In-conversation expense logging reusing the existing confirm-before-commit pipeline.
- Persistent, synced conversation history + a small learned user-profile.
- Stronger model for advice; cheap model unchanged for parsing/logging.

**Non-Goals:**
- Budget edits / bill add / bill pay in chat (v2).
- Bundling copyrighted book text.
- Autonomous/silent writes.
- Real-time token streaming for cloud advice.
- Replacing on-device model or food AI pipelines.
- Investment/tax/legal/medical advice.

## Decisions

### D1 — Extend `AiCoachPresenter` with a `financeAdvisor` entry point (not a new presenter)
Add `AiCoachEntryPoint.financeAdvisor` and an `_entryMeta` entry (gold Treasury accent, Phosphor icon). The advisor is a session type on the existing presenter, reusing streaming, history trim, and tier logic.
- **Why:** Maximum reuse; the sheet + presenter already do 90% of the work.
- **Alternative considered:** A dedicated `FinancialAdvisorPresenter`. Rejected for v1 — duplicates streaming/history/error plumbing. Revisit if advisor behavior diverges materially (e.g. multi-turn action planning).
- **Consequence:** `AiCoachPresenter` gains a dependency on `LedgerPresenter` (for the logging hook). Injected via constructor at the `AppShell` composition root.

### D2 — Enrich `AiCoachContext` / `_buildContext()` with Treasury getters
Add fields for forecasted net balance, net worth, liquid cash, month net cash flow, savings rate, per-category **target/actual/remaining** for the top categories (not just spend — needed for the burn-rate diagnostic in D7), account balances, credit available/owed, and outstanding/upcoming bills, sourced from `TreasuryDashboardPresenter` (already injected). `toPromptSummary()` renders them compactly and pre-formatted (PHP, rounded) so the model reproduces figures rather than deriving them.
- **Why:** Advice quality is bounded by the data the model sees. Today only `monthBudget`/`monthSpent` flow through.
- **Trade-off:** Larger prompt → more tokens/cost. Mitigate by summarizing (top-N categories, rounded figures) rather than dumping raw transactions.

### D3 — Backend: new `adviseFinance` op on a Sonnet-tier model
Add an `op: "adviseFinance"` to `lambda_function.py` that builds the principle-grounded system prompt and invokes a stronger Bedrock model id; the existing `classifyFinance` op keeps the Haiku-tier model. Reuse the JWT authorizer and `increment_ai_usage` rate limiting as-is. Client adds a corresponding method on `AiCoachService`/`CloudAiCoachService`.
- **Why:** Financial reasoning benefits from a stronger model; parsing does not, and parsing is high-frequency/cost-sensitive.
- **Alternative considered:** Reuse the existing `respond` op with a bigger model. Rejected — `respond` is the generic RPG coach; a separate op keeps prompts, token budgets, and model ids independently tunable.
- **Note:** Verify the chosen Sonnet-tier model is enabled in Bedrock region `ap-southeast-1`; otherwise pick the nearest available Sonnet id and record it in `template.yaml`.

### D4 — Expense logging reuses `LedgerPresenter.sendChatInput` verbatim
When the advisor detects a logging intent (or the user is clearly logging, not asking), route the text to `LedgerPresenter.sendChatInput(text)` and surface the existing resolved/clarify/give-up result inside the chat (reusing `LedgerChatPanel`'s states or an equivalent in-sheet renderer). The advisor model itself never emits a committed write.
- **Why:** The safety model (entity validation, confidence gating, confirm) already exists and is battle-tested. Don't fork it.
- **Decision — intent routing:** Keep the existing `QuickLogRouter` heuristic for the collapsed bar. Inside the expanded advisor, default to *advice*; treat input as a logging intent only when it matches the money-logging heuristic (amount + verb/keyword). Ambiguous cases stay in advice and the advisor can offer a "Log this?" affordance. This avoids accidental writes from advisory questions that mention amounts.

### D5 — Persistence: two new StorageService-backed stores, both synced
- **Chat history** — a capped list of `AdvisorMessage` (role, text, timestamp). Persisted under a new storage key; trimmed to a bounded length; user-clearable.
- **User-profile memory** — a small structured `AdvisorProfile` (goals, risk tolerance, freeform facts) updated when the user states durable facts. Persisted under a new key; user-viewable and clearable.
- Both register as **sync domains** (per the existing sync architecture) so they follow the user and survive sign-out per the established rules. Follow the flush-before-wipe pattern used for weight/body sync.
- **Why StorageService:** Non-negotiable persistence rule. No direct SharedPreferences in presenters.
- **Open point (see below):** How the profile is *updated* — model-proposed structured deltas vs. deterministic client extraction. Leaning model-proposed JSON on the `adviseFinance` response, validated client-side.

### D6 — Hub bar becomes dual-mode in place
`_QuickLogBar` gains a collapsed↔expanded state. Collapsed = today's behavior. Expanded opens the advisor surface (the `AiChatSheet` in `financeAdvisor` mode, or an inline expansion) anchored to the bar. The `hub` spec delta captures the requirement. Expansion animation stays within 150–400ms; touch targets ≥44px; primary input remains in the bottom 30%.
- **Why:** User chose "one bar, two modes." No new nav surface.
- **Alternative considered:** Separate advisor button/FAB or full screen — rejected by product decision.

### D7 — Advisor persona, knowledge base, and anti-hallucination contract
The advisor's system prompt encodes a defined persona and behavioral contract, adapted from the user's proven Gemini-gem prompt:

**Persona.** Dedicated financial advisor + life strategist + behavioral coach for a 23-year-old Filipino computer engineer on ~₱40k gross/month. Blends hard financial data, behavioral psychology, and developmental milestones. Frames 2026 as a critical "building year."

**Knowledge base (principles only — no bundled/quoted text):**
- Financial: *Broke Millennial*, *Financial Freedom*, *The Total Money Makeover*.
- Behavioral/developmental: *Atomic Habits* (identity-based habits, the 4 Laws — make savings obvious/attractive, make impulse spending invisible/difficult) and *The Defining Decade* (identity capital; reject procrastination; evaluate spending by whether it builds skills/connections/experiences).
- Filipino context: navigate *utang na loob* / family obligations respectfully; parental support is budgeted without compromising the emergency fund.

**Data source is the app, not Google Sheets.** The gem re-read two live spreadsheets each turn and parsed cells; that whole machinery is dropped. In this app the presenters *are* the source of truth and the client assembles a clean, exact snapshot per turn (D2). The model **never parses raw data**, which removes the gem's entire dirty-data failure mode. Each financial concept maps to a presenter getter:

| Concept | App source (presenter getter) |
|---|---|
| Total liquid cash | `TreasuryDashboardPresenter.totalLiquidCash` |
| Projected ending cash (after bills) | `forecastedNetBalance` |
| Outstanding / upcoming bills | `monthUnpaidBills` / `upcomingBills` |
| Budget target / actual / remaining | `totalBudgetAllocated` / `totalBudgetSpent` / `totalBudgetRemaining`; per-category via `categorySpendThisMonth` + `budgetFor` |
| Spending (transfers excluded) | `allTransactions` filtered on `transferGroupId == null` (the transfer-pollution guard we already enforce) |
| Credit available = unused capacity; user is a transactor | `totalCreditAvailable` / `totalCreditOwed` — not flagged as toxic unless a balance rolls over |
| Historical benchmark | prior-period aggregates from stored transactions (benchmark only; never used for current liquidity) |

**Anti-hallucination contract (kept, re-pointed at the snapshot):** cite the source of every figure (e.g. "from your forecast" / "Budget"); never invent, infer, or extrapolate a number that isn't in the snapshot; if a needed figure is absent say exactly *"I cannot verify this — that figure isn't in your current data."*; prefix behavioral guesses with `[Inference]` / `[Speculation]` / `[Unverified]`; label banned absolutes (*prevent, guarantee, will never, fixes, eliminates, ensures*) as `[Unverified]` unless mathematically certain; self-correct if a directive is broken. Because figures are computed client-side, the *client* also formats them (PHP, rounded) so the model reproduces rather than derives them.

**"Financial Position" diagnostic.** When the user asks for their financial position/analysis, the advisor returns a structured four-part diagnostic: (1) Liquidity — liquid cash vs. forecasted ending cash; (2) Obligations — remaining outstanding bills; (3) Burn Rate — top 2 categories where actual spend is closest to target; (4) Behavioral audit — one actionable tie to identity capital / identity-based finance. To support (3), the enriched context (D2) MUST carry per-category target/actual/remaining for the top categories, not just raw spend.

- **Why:** This persona + guardrail set is the user's battle-tested contract; it's what makes the advisor feel like *their* advisor rather than a generic chatbot. Encoding it verbatim-in-spirit (not the sheet mechanics) is the highest-leverage part of the feature.
- **Trade-off:** A long system prompt costs tokens every turn. Mitigate by keeping the persona/guardrails as a stable prefix (cache-friendly) and varying only the per-turn snapshot.

## Risks / Trade-offs

- **Accidental writes from advisory questions** ("can I afford ₱500 coffee?") misread as a log → Mitigation: in-advisor default is advice; logging requires the money heuristic; all writes still pass through explicit confirm (D4).
- **Cost/latency from stronger model + richer prompt** → Mitigation: separate op with its own token budget; summarized context (D2); existing daily cap enforced server-side.
- **Sonnet-tier model unavailable in `ap-southeast-1`** → Mitigation: verify at implementation; fall back to nearest available id and document it (D3).
- **Prompt-injection via stored profile / chat history** (user-entered facts flow back into the system prompt) → Mitigation: treat stored memory as data, not instructions; keep guardrails in the system prompt; validate any model-proposed profile deltas client-side (D5).
- **Privacy: financial detail leaves the device to Bedrock** → Mitigation: gate behind the existing cloud-AI opt-in and signed-in state; send summarized figures, not full transaction logs; no secrets in prompts.
- **Non-streaming cloud responses feel slow for longer advice** → Mitigation: typing indicator already exists; accept single-chunk render for v1 (explicit non-goal); revisit streaming transport only if UX testing demands it.
- **Copyright** → Mitigation: principles only in the system prompt; explicit refusal scenario for verbatim quotes.
- **Persona/guardrail drift** (Haiku-tier or a weaker model may ignore the anti-hallucination contract or the four-part diagnostic structure) → Mitigation: the Sonnet-tier model (D3) is chosen partly for instruction-following; keep the contract as a stable, testable prefix and cover it with scenarios (cite-source, refusal, labeled inference, banned absolutes).

## Migration Plan

1. Backend first: add `adviseFinance` op + model id to `lambda_function.py`/`template.yaml`, deploy the SAM stack, confirm the JWT authorizer + daily cap still pass. Backward-compatible (additive op).
2. Client: add the service method, enrich `AiCoachContext`, add the `financeAdvisor` entry point, wire the logging hook, add persistence stores + sync domains, then the dual-mode hub bar.
3. Feature-flag via the existing cloud-AI opt-in; ship dark + light.
4. Rollback: the op is additive and the bar's collapsed mode is unchanged, so reverting the client restores today's behavior; the backend op can remain deployed unused.

## Open Questions

- **Profile update mechanism** (D5): model-proposed structured deltas vs. deterministic client-side extraction. Lean model-proposed + client validation; confirm during implementation.
- **Advisor surface**: reuse `AiChatSheet` as a modal expansion vs. an inline expand-in-place of the bar. Both satisfy the spec; pick based on animation/keyboard-inset behavior during build.
- **Exact Sonnet-tier Bedrock model id** available in `ap-southeast-1`.
- **History cap length** and whether to summarize old turns into the profile when trimming.
