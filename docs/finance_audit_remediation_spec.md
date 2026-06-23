# Finance/Treasury Audit Remediation Spec

## Overview

A full audit of the finance/treasury module (mobile + web) surfaced ~50 issues spanning
three classes: **wrong calculations** (money/date math in presenters), **mobile logging
friction** (the day-to-day entry flows), and **web data-entry speed** (the desktop ledger).

This spec is the master plan for remediating them. Work ships as **four independent PRs**
(one per batch, per the repo's one-PR-per-feature rule), sequenced correctness-first:

| Batch | Theme | Risk | PR branch |
|---|---|---|---|
| **A** | Finance math & date fixes (presenters) | Low (pure logic) | `fix/finance-math-corrections` |
| **B** | Mobile logging UX | Medium (UI) | `feat/finance-mobile-logging-ux` |
| **C** | Web data-entry speed (ledger grid) | Medium (UI/perf) | `feat/web-ledger-data-entry` |
| **D** | Polish (theme, scrollbars, overflow, Rule-1) | Low | `chore/finance-ui-polish` |

The transfer-pollution guard from PR #291/#295 is intact — all expense/income/category
aggregations correctly guard `transferGroupId == null`. The gaps remediated here are
isolated to savings-target math, credit/date logic, and UI/UX.

## User Story

As someone tracking money in The System, I want the numbers to be correct and the
logging flows to be fast, so that I trust the app enough to log every transaction —
and logging stays frictionless enough that I actually do.

---

## Batch A — Finance Math & Date Corrections

Pure presenter/model logic. Each fix is independently testable with a unit test.

### A1 — Liability self-payment corrupts balance `[Critical]`
- **File:** `lib/presenters/bills_receivables_presenter.dart:235-237`
- **Root cause:** The transfer-routing guard is `liability.isLiability && acct != bill.accountId`.
  If the user selects the **same** liability account as the funding account, it falls to the
  `else` branch and books a plain outflow — which `_applyBalanceDelta`'s liability sign-flip
  turns into *increasing* the owed balance, and double-counts as spend (the original charge
  already booked the expense).
- **Fix:** Reject (or no-op with a clear error) when `acct == bill.accountId` for a liability
  bill. A liability can never fund its own statement payment.
- **Test:** Pay a ₱2,000 card bill selecting the card itself → expect rejection, balance unchanged.

### A2 — Credit due-date day overflow `[High]`
- **File:** `lib/presenters/treasury_dashboard_presenter.dart:141-142`
- **Root cause:** `DateTime(now.year, now.month, day)` with `day` 29–31 silently rolls into
  the next month (e.g. `DateTime(2026, 2, 31)` → Mar 3).
- **Fix:** Clamp `day` to the target month's last day: `day.clamp(1, DateTime(year, month+1, 0).day)`.
  Apply to both the current-month and rolled-month branches.
- **Test:** `paymentDueDay = 31`, current month Feb → label computed against Feb 28/29.

### A3 — `isBillOverdue` ignores the bill's month `[High]`
- **File:** `lib/presenters/treasury_dashboard_presenter.dart:436`
- **Root cause:** `bill.dueDay < DateTime.now().day` compares only the day-of-month, so a
  future-month bill reads as overdue and a past-month bill reads as not-overdue.
- **Fix:** Only evaluate overdue when `bill.month == current month key`; mirror the already-correct
  `billStatus` logic in `bills_receivables_presenter.dart:125`.
- **Test:** Today June 20, a July bill due the 5th → not overdue.

### A4 — `hasBillImminent`/`imminentBill` month-boundary arithmetic `[High]`
- **File:** `lib/presenters/treasury_dashboard_presenter.dart:402-412`
- **Root cause:** `b.dueDay == today || b.dueDay == today+1` breaks on the last day of a month
  (`today+1` = 31/32 never matches) and ignores actual dates.
- **Fix:** Compute imminence from a real date difference (reuse the clamped-date helper from A2),
  imminent when `0 <= diffDays <= 1`.
- **Test:** On the 30th of a 30-day month, a bill due the 1st next month is imminent.

### A5 — Budget page vs Dashboard disagree on "saved this month" `[High]`
- **Files:** `lib/presenters/budget_presenter.dart:276-288` (`contributedTo`) vs
  `lib/presenters/treasury_dashboard_presenter.dart:268` (`monthSavingsContributions`)
- **Root cause:** `contributedTo` sums **gross** inflow legs into the target account (including
  transfer legs, never netting the matching outflow), while `monthSavingsContributions` nets
  in − out on locked accounts. Shuffling money between two savings accounts inflates the Budget
  page's total.
- **Fix:** Pick one definition (net in − out on the target account, transfer legs included since
  they represent real movement into/out of savings) and share a single helper used by both
  surfaces. Remove the dead `TransactionType.transfer` branch (transfers are never persisted
  with that type).
- **Test:** Transfer ₱3,000 between two savings-target accounts → net new savings = 0 on both surfaces.

### A6 — "Can I afford it?" double-subtracts budgeted bills `[High]`
- **File:** `lib/presenters/treasury_dashboard_presenter.dart:218-219, 483-493`
- **Root cause:** `forecastedNetBalance` subtracts an unpaid bill **and** the remaining budget of
  the same category, deducting one obligation twice.
- **Fix:** When subtracting `totalBudgetRemaining`, exclude categories already represented by an
  unpaid bill (or base the forecast on a single obligation source). Document the chosen model inline.
- **Test:** Rent ₱15k unpaid bill + ₱15k Rent budget, ₱0 spent → forecast deducts ₱15k, not ₱30k.

### A7 — Overpaid liability inflates available credit `[Medium]`
- **File:** `lib/models/finance/financial_account.dart:119-126`
- **Root cause:** `availableCredit = creditLimit − balance`; a negative (overpaid) balance makes
  available credit exceed the limit and utilization go negative.
- **Fix:** Clamp `currentPayable` at 0 for utilization/available-credit; treat a negative liability
  balance as a separate "credit balance" concept (not extra spendable credit).
- **Test:** Limit ₱50k, balance −₱2k → available credit = ₱50k, utilization = 0%.

### A8 — Recurring-receivable date drift `[Medium]`
- **File:** `lib/presenters/bills_receivables_presenter.dart:591-593`
- **Root cause:** `DateTime.parse("$month-${day}")` with day 30/31 into February silently rolls
  to March (e.g. `2026-02-31` → `2026-03-03`).
- **Fix:** Clamp the day to the target month's length before formatting.
- **Test:** Receivable expected on the 31st → February copy lands on Feb 28/29.

### A9 — `averageDailyOutflow` sentinel `[Low]`
- **File:** `lib/presenters/ledger_presenter.dart:143`
- **Root cause:** Returns `1.0` (₱1.00) for an empty month "to avoid division by zero."
- **Fix:** Return `0.0`; ensure callers guard or display "—".

---

## Batch B — Mobile Logging UX

Targets the highest-frequency entry flows. Read all colors from `Theme.of(context)`.

### B1 — Grocery "Add to cart" stuck disabled `[High, Bug]`
- **File:** `lib/views/treasury/grocery/add_cart_item_sheet.dart:47,144`
- **Fix:** Always `setState` in `_onNameChanged` (or attach a controller listener) so `_canSubmit`
  re-evaluates each keystroke, not only on a price-memory match.

### B2 — Grocery "Add & next" `[High, UX]`
- **File:** `add_cart_item_sheet.dart:60,113-138`
- **Fix:** Add a secondary "Add & next" action that keeps the sheet open, clears name/price,
  refocuses name, preserves the unit. Primary "Add to cart" still pops.

### B3 — Grocery swipe-delete undo `[High, Bug]`
- **File:** `lib/views/treasury/grocery/grocery_cart_view.dart:330-345`
- **Fix:** Show a SnackBar with "Undo" that re-adds the item (mirror the ledger delete pattern at
  `ledger_view.dart:933`).

### B4 — Can't log past-dated txn from chat bar `[High, UX]`
- **File:** `lib/views/treasury/ledger/ledger_view.dart:366-427`
- **Fix:** When a non-today date filter is active, allow logging with the selected date pre-filled
  instead of disabling the entire input bar.

### B5 — Account card truncation `[High, Bug]`
- **Files:** `lib/views/treasury/dashboard/treasury_dashboard_view.dart:187-208`,
  `dashboard/account_card_widget.dart:85`
- **Fix:** Remove the hardcoded `width: 140` (let the grid cell size it) or drop the grid to
  `crossAxisCount: 2`.

### B6 — Sub-44px primary/destructive actions `[High, A11y]`
- **Files:** `bills/bill_list_tile.dart:166-182`, `bills/receivable_list_tile.dart:128-143`,
  `bills/installment_list_tile.dart:120-130,154-204`
- **Fix:** Restore ≥44×44 hit areas for Mark Paid / Mark Received / installment delete / undo.

### B7 — Missing input formatters & validators `[Medium, Bug]`
- **Files:** `bills/add_bill_sheet.dart:135,149-161`, `add_receivable_sheet.dart:139`,
  `add_installment_sheet.dart:148,171`, `budget/add_budget_sheet.dart:243-245`,
  `shared/account_setup_view.dart:424-473`
- **Fix:** A shared single-decimal currency formatter + digit-only day field; accurate validation
  messages (reject 0/negative where invalid, e.g. goal target > 0).

### B8 — Dropdown `initialValue:` vs `value:` `[Medium, Bug]`
- **Files:** `add_receivable_sheet.dart:211,245`, `bills_receivables_view.dart:1247`
- **Fix:** Standardize on `value:` so dropdowns reflect later `setState` selection changes.

### B9 — Smart defaults & category clear `[Medium, UX]`
- **Fix:** Default the payment account to first/most-used across all add sheets (match
  `add_installment_sheet.dart:46`); add a "None"/toggle-off for category chips
  (`add_bill_sheet.dart:184`, `add_receivable_sheet.dart:186`, `add_transaction_sheet.dart:471`).

---

## Batch C — Web Data-Entry Speed

The desktop ledger is the core management surface; make it spreadsheet-fast.

### C1 — Virtualize the ledger grid `[High, Perf]`
- **File:** `lib/views/web/pages/ledger/web_ledger_page.dart:466-604,573`
- **Root cause:** Every row is a fully-stateful `_EditableRow` (controllers, focus nodes, full
  account+category dropdown item lists) built eagerly inside a `SingleChildScrollView`.
- **Fix:** Give the grid a bounded height with a `ListView.builder` body (windowed rows) and a
  pinned header; lazily build dropdown item lists.

### C2 — Keyboard cell traversal `[High, UX]`
- **Files:** `web_ledger_page.dart:2255,2401` (`_InlineText`/`_AmountCell` `_onFocus`)
- **Fix:** Enter = commit + move focus one row down in the same column; explicit
  `FocusTraversalOrder` so Tab walks Date→Account→Desc→Category→Inflow→Outflow; arrow-key cell nav.

### C3 — Re-focus after add `[High, UX]`
- **Files:** `web_ledger_page.dart:1471` (`_QuickAdd._send`), `:334` (`_commitDraft`)
- **Fix:** After a successful Quick Add / draft commit, `requestFocus` back to the first input for
  rapid consecutive entry.

### C4 — Vertical scrollbars + pinned header `[Medium, UX]`
- **Files:** all web page bodies (e.g. `web_ledger_page.dart:393`, `web_dashboard_page.dart:31`)
- **Fix:** Wrap page bodies in `Scrollbar(thumbVisibility: true)` (or set `ScrollbarTheme` in
  `web_theme.dart`); keep the grid header pinned (ties into C1).

### C5 — Setup tables overflow near breakpoint `[Medium, Layout]`
- **Files:** `lib/views/web/pages/setup/web_setup_page.dart:256,1101`
- **Fix:** Wrap the accounts + categories tables in the same `LayoutBuilder` + horizontal
  `SingleChildScrollView` + min-width pattern used by budget (`web_budget_page.dart:359`).

### C6 — Unify sort model `[Medium, Bug]`
- **Files:** `web_ledger_page.dart:231` (`_toggleHeaderSort`), `:697` (`_activeSortOption`)
- **Fix:** Single sort state shared by header clicks and the Filters popover; show a direction
  arrow in the active-sort chip; reflect header sort in the popover dropdown.

---

## Batch D — Polish

Theme correctness, accessibility, and Rule-1 (no calc/conditionals in `build()`).

- **D1** Hardcoded color tokens in widgets → `Theme.of(context)`:
  `ledger_view.dart:651` (`Colors.black` shadow → `colorScheme.shadow`),
  `account_setup_view.dart:656,667,699` (`Colors.white` swatch ring → luminance-based contrast).
  Verify `gold/success/purple/orange` resolve in `AppColorsLight`.
- **D2** Move in-`build` aggregations to presenter getters: `bills_receivables_view.dart:413-534`,
  `budgeted_expense_tile.dart:34`, `installment_list_tile.dart:43`, `budget_view.dart:45`,
  `dashboard/*` fold/firstWhere calls, `ledger_view.dart:883-905` (build id→object maps once).
- **D3** Web a11y/keyboard: `web_shell.dart:140` rail items not keyboard-focusable; register
  top-level shortcuts (`/` focus search, `N` add); add `Semantics`/tooltips to charts and the
  bills paid checkbox.
- **D4** Consistency: standardize row-action paradigm across web tables; unify month steppers
  (`web_ledger_page.dart:752` → reuse `WebMonthStepper`); standardize mobile date labels to
  `DateFormat('MMMM d, yyyy')`; one `AppMoneyField` component.
- **D5** Remove the web cart stub from production paths if unreachable (`web_cart_page.dart`);
  drop the dead `if (amount <= 0 && desc.isEmpty)` guard at `web_ledger_page.dart:336`.

---

## Storage
No new `StorageService` keys. All fixes operate on existing models/persistence.

## Edge Cases
- Paying a liability bill from the same liability account (A1).
- Due day 29–31 in short months (A2, A8).
- Bills in past/future months relative to "today" (A3, A4).
- Transfers between two savings-target accounts (A5).
- A bill whose category also has a budget (A6).
- Overpaid (negative-balance) liability accounts (A7).
- Empty month with zero outflow (A9).
- Brand-new grocery item with no price memory (B1).
- Web ledger with hundreds of rows in a heavy month (C1).

## Acceptance Criteria
- [ ] **A:** Unit tests cover A1–A9; Budget page and Dashboard report identical "saved this month".
- [ ] **A:** No liability balance can be increased by a bill payment; no double-counted forecast deductions.
- [ ] **B:** Grocery add button enables on any valid name; "Add & next" works; swipe-delete is undoable.
- [ ] **B:** Past-dated transactions can be logged from the chat bar; all primary actions ≥44×44.
- [ ] **B:** Account cards render without truncation on a 360px-wide screen.
- [ ] **C:** Ledger grid stays responsive with 500+ rows; Enter/Tab traverse cells; focus returns after add.
- [ ] **C:** Setup tables scroll horizontally below ~840px with no RenderFlex overflow.
- [ ] **D:** No hardcoded color tokens in finance widgets; both themes verified; `dart format` clean.
- [ ] Each batch ships as its own PR targeting `dev`.
