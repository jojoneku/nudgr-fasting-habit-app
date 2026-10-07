# Plan 061 — Nudgy Seamless Tool Expansion

**Goal:** Expand Nudgy's tool capabilities across Finance and Health coaching so everyday requests ("I paid Meralco", "Jana paid me back", "Pay my BPI card", "Delete that duplicate Grab expense", "Can I afford this?", "Start my 16h fast") resolve seamlessly into clear, user-reviewed confirm cards rather than hitting conversational dead-ends.

---

## 1. Problem & Context

Currently, Nudgy's tool catalogue (`lib/utils/finance_tool_catalogue.dart`) only supports:
- **Reads:** `findBills`, `findReceivables`, `findSetAsides`, `findBudgets`, `findInstallments`, `findTransactions`
- **Creates:** `addBill`, `addReceivable`, `addSetAside`, `logTransactions`, `addInstallment`

Every other common workflow is a dead-end:
1. **Settlement is missing:** Stating "I paid my electric bill" or "Alex paid me back" produces advice or an erroneous duplicate log entry instead of settling the tracked bill or receivable.
2. **Card payment is missing in tools:** While quick-log regex has `_tryPayCredit`, Nudgy's AI tool layer has no `payCredit` tool.
3. **Corrections force a form trip:** If a user makes a typo or logs a duplicate transaction/bill, Nudgy cannot propose an edit or deletion, forcing the user out of the flow to find the entry manually.
4. **Advisory is heuristic:** When asked "Can I afford ₱4,000?", Nudgy guesses from a clipped snapshot instead of calling `canAfford()`.
5. **Cross-module disconnect:** In the Fasting screen, Nudgy cannot start or terminate the timer.

---

## 2. Core Architectural & Security Guardrails

All proposed tools strictly preserve the system's security and architecture rules:

1. **The Model Cannot Autonomously Write:**
   - Every mutating tool builds a `PendingFinanceAction` (or hands off to `EntryReviewCard`).
   - Mutations execute **only** when the user taps confirm on the review card.
2. **Strict Invariant: No `applyToFuture` on Schemas:**
   - Recurring series scope remains exclusively on the UI confirm card (`_ScopeChoice`), never exposed to model parameters.
3. **Strict Invariant: No Hallucinated IDs:**
   - `create` tools never accept IDs.
   - `update` and `delete` tools strictly require an ID that was previously surfaced by a `find*` read tool in the conversation.
4. **Strict Invariant: No Type-Flipping on Edit:**
   - `editTransaction` cannot convert `outflow` ↔ `inflow` (that is a reversal, requiring delete + re-log).
5. **Dual-Theme & UX:**
   - All confirm cards and buttons support dark and light themes using `Theme.of(context)`. Touch targets ≥ 44×44 dp.

---

## 3. Phased Implementation Plan

### Phase 1: High-Priority Finance Actions ("I Paid Something")
*Addresses the most frequent dead-ends.*

1. **`markBillPaid` Tool:**
   - **Kind:** `AiToolKind.update`
   - **Input:** `{ id: string, paidDate?: string, account?: string }` (requires prior `findBills`).
   - **Execution:** Calls `BillsReceivablesPresenter.markBillPaid()`.
   - **Review Card:** Title: *"Mark bill as paid"*, Details: Bill name, amount, paid date, account. Action button: *"Mark Paid"*.

2. **`markReceivableReceived` Tool:**
   - **Kind:** `AiToolKind.update`
   - **Input:** `{ id: string, receivedAmount?: number, receivedDate?: string, account?: string }` (requires prior `findReceivables`).
   - **Execution:** Calls `BillsReceivablesPresenter.markReceivableReceived()` which atomically logs the offsetting inflow.
   - **Review Card:** Title: *"Settle receivable"*, Action button: *"Mark Received"*.

3. **`payCredit` Tool:**
   - **Kind:** `AiToolKind.create`
   - **Input:** `{ creditAccount: string, fromAccount?: string, amount: number, date?: string, note?: string }`.
   - **Execution:** Calls `BillsReceivablesPresenter.quickPayCard()` / `LedgerPresenter.addTransfer()`.
   - **Review Card:** Title: *"Pay Credit Card"*, Details: Card name, funding account, amount. Action button: *"Confirm Payment"*.

4. **Refactor `FinanceProposalCard` Action Buttons:**
   - Update `PendingFinanceAction` to accept an optional `confirmLabel` (e.g., `'Mark Paid'`, `'Confirm Payment'`, defaulting to `'Add it'`) and `confirmIcon`.

---

### Phase 2: Live Reads & Affordability Advisory

1. **`findAccounts` Tool:**
   - **Kind:** `AiToolKind.read`
   - **Input:** `{ query?: string, type?: "liquid" | "liability" | "savings" | "all" }`
   - **Execution:** Queries live `LedgerPresenter.accounts` to return exact balances, limits, and available credit.

2. **`checkAffordability` Tool:**
   - **Kind:** `AiToolKind.read`
   - **Input:** `{ amount: number, account?: string }`
   - **Execution:** Invokes `TreasuryDashboardPresenter.canAfford(amount, accountId: ...)`, returning the exact tier (`yes`, `tight`, `no`), spare amount, and formatted verdict sentence.

3. **Update `findTransactions` to Surface IDs:**
   - Modify `_findTransactions` in `FinanceActionsExecutor` so each row includes `id=${t.id}` (mirroring `findBills`), enabling subsequent edits and deletions.

---

### Phase 3: Safe Transaction & Record CRUD

1. **`editTransaction` Tool:**
   - **Kind:** `AiToolKind.update`
   - **Input:** `{ id: string, description?: string, amount?: number, date?: string, category?: string, account?: string, note?: string }`
   - **Execution:** Updates transaction via `LedgerPresenter.updateTransaction()`.
   - **Review Card:** Shows diff view (old vs new fields). Action button: *"Save Changes"*.

2. **`deleteTransaction` Tool:**
   - **Kind:** `AiToolKind.delete`
   - **Input:** `{ id: string }`
   - **Execution:** Deletes transaction via `LedgerPresenter.deleteTransactionOrGroup()`.
   - **Review Card:** Explicit warning card: *"Permanently delete transaction: [Details]. This will adjust your balances."* Action button: *"Delete Entry"* (styled with danger theme color).

3. **`editBill` & `deleteBill` Tools:**
   - Update and delete plans for bills with prior ID lookup.

4. **`editReceivable` & `deleteReceivable` Tools:**
   - Update and delete plans for receivables.

---

### Phase 4: Health & Lifestyle Coaching Tools

1. **`startFast` & `endFast` Tools:**
   - Connect `AiCoachPresenter` with `FastingPresenter` to trigger fast sessions or finish with XP computation.
2. **`queryNutrition` Tool:**
   - Live query for macro totals, goals, and calories remaining for any date.
3. **`logFood` Tool:**
   - Formalize the food-logging pipeline as a registered tool.

---

### Phase 5: Deferred Tools
- `editSetAside`, `deleteSetAside`, `findBudgetGroups`.

---

## 4. Verification & Testing Strategy

1. **Catalogue Invariant Tests (`test/models/finance_tool_catalogue_test.dart`):**
   - Assert `applyToFuture` is absent from all new tool schemas.
   - Assert `id` is required for update/delete tools and absent from create tools.
   - Assert read tools have `mutates == false` and write tools have `mutates == true`.
2. **Executor Unit Tests (`test/presenters/finance_actions_executor_test.dart`):**
   - Test proposal generation and execution for `markBillPaid`, `markReceivableReceived`, `payCredit`.
   - Test transaction edit and delete flows with ledger balance verification.
   - Test decline path returns `AiToolResult.declined` with zero side-effects.
3. **Widget & Proposal Card Tests (`test/views/finance_proposal_card_test.dart`):**
   - Test custom confirm labels ("Mark Paid", "Delete Entry") and confirm actions.
   - Test both light and dark theme styling.
4. **Integration Verification:**
   - Run `dart analyze lib test` (0 errors required).
   - Run `flutter test` across all relevant suites.
