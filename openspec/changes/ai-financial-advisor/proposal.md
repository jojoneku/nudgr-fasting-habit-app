## Why

Users can log money and food through the hub's docked bar, but they cannot *talk* to the app about their finances the way they could with an external tool (e.g. a Gemini gem wired to a spreadsheet). They want a place to confide financial worries and get grounded advice — "how is my overall positioning?", "can I afford this?", "should I spend on X?" — informed by their real, live Treasury data and by durable financial-literacy principles.

The plumbing for this already exists in fragments: a streaming chat presenter + sheet (`AiCoachPresenter` / `AiChatSheet`), a JWT-authed cloud AI transport (`CloudAiCoachService` → Bedrock Lambda), a confirm-before-commit finance action pipeline (`LedgerPresenter.sendChatInput` / `LedgerChatPanel`), and a rich read surface (`TreasuryDashboardPresenter`). This change unites and enriches those fragments into one conversational financial advisor rather than building anything net-new from scratch.

## What Changes

- **Upgrade the existing hub docked quick-log bar into a dual-mode "ask or log" bar.** Short logging phrases ("coffee 120") still quick-log inline exactly as today; tapping/expanding the bar opens the full conversational advisor over the hub. No new button, no new screen.
- **Add a finance-advisor entry point** to the existing `AiChatSheet` / `AiCoachPresenter` chat surface (new `AiCoachEntryPoint.financeAdvisor` with its own label/icon and system framing).
- **Ground advice in a defined persona + encoded principles**, adapted from the user's proven Gemini-gem prompt: a financial advisor / life strategist / behavioral coach for a young Filipino professional, drawing on *Broke Millennial*, *Financial Freedom*, *The Total Money Makeover*, *Atomic Habits* (identity-based habits), and *The Defining Decade* (identity capital), plus Filipino context (*utang na loob*). Principles only — no copyrighted book text is bundled, quoted, or shipped.
- **Enforce an anti-hallucination data contract**: the advisor may only cite figures present in the client-assembled snapshot, must cite each figure's source, must label inferences/absolutes, and must refuse (with a fixed phrase) when a figure is missing — never invent numbers. A structured four-part "financial position" diagnostic (Liquidity, Obligations, Burn Rate, Behavioral audit) is a defined behavior.
- **Enrich the advisor's financial context.** Extend `AiCoachContext` / `_buildContext()` beyond today's `monthBudget`/`monthSpent` to include `forecastedNetBalance`, `netWorth`, `totalLiquidCash`, `categorySpendThisMonth`, account balances, `savingsRate`, `monthNetCashFlow`, and `upcomingBills` from `TreasuryDashboardPresenter`.
- **Let the advisor log expenses in-conversation** through the *existing* confirm-before-commit pipeline (`LedgerPresenter.sendChatInput`). The AI only *proposes*; the client validates every entity against live accounts/categories and the user confirms before any write. The client remains the sole executor of mutations.
- **Persist and sync memory.** Save conversation history plus a small learned user-profile (goals, risk tolerance, facts the user shares) through `StorageService`, riding the existing sync domains so it follows the user across devices.
- **Use a stronger model for advice.** Route the advisor's reasoning op to a Sonnet-tier Bedrock model while keeping the cheap Haiku model for finance parsing/classification/logging. Add a new Lambda `op` for the advisor.

## Capabilities

### New Capabilities
- `ai-financial-advisor`: Conversational financial advisor — grounded advice from live Treasury data + encoded book principles, in-conversation expense logging via confirm-before-commit, and persistent synced chat history + learned user-profile memory.

### Modified Capabilities
- `hub`: The docked quick-log bar requirement changes from log-only to a dual-mode "ask or log" bar that expands into the advisor while preserving inline quick-logging behavior.

## Impact

- **UI**: `lib/views/hub_screen.dart` (`_QuickLogBar` → expandable dual-mode bar), `lib/views/widgets/ai_chat_sheet.dart` (new `financeAdvisor` entry meta).
- **Presenters**: `lib/presenters/ai_coach_presenter.dart` (finance-advisor session + expense-logging action hook), `lib/models/ai_coach_context.dart` (enriched context), reuse of `TreasuryDashboardPresenter`/`LedgerPresenter` getters and mutators. New presenter wiring in `lib/views/home_screen.dart` (`AppShell` composition root) → `HubScreen` via constructor injection.
- **Services**: `lib/services/cloud_ai_coach_service.dart` (new advisor op), `lib/services/storage_service.dart` (new keys for chat history + profile), sync-domain registration.
- **Models**: new persistence models for chat history and the learned user-profile.
- **Backend**: `backend/ai-coach/lambda_function.py` + `template.yaml` (new advisor `op`, stronger Bedrock model id, prompt with encoded principles); existing `increment_ai_usage` rate-limiting reused.
- **Spec**: `openspec/specs/hub/spec.md` updated via delta for the dual-mode bar.
- **Non-breaking**: quick-logging, food routing, and the current coach chat continue to work unchanged.

## Non-goals

- **Editing budgets or adding/paying bills in-conversation** — deferred to a v2. v1 writes are limited to logging expenses.
- **Bundling, quoting, or reproducing copyrighted book text** — only distilled principles live in the system prompt.
- **Autonomous or silent writes** — the AI never mutates data without an explicit user confirmation step.
- **Real-time token streaming for cloud advice** — cloud responses render as a single chunk today; switching the Lambda to a streaming transport is out of scope unless review shows it's required.
- **Replacing the on-device model or the food/nutrition AI pipelines** — those are untouched.
- **Investment/tax/legal financial advice or any medical advice** — the advisor stays within personal budgeting/cashflow guidance and keeps the existing safety guardrails.
