# Plan 051 — Web Ledger Spreadsheet Parity

Bring the Flutter web Ledger (`lib/views/web/pages/ledger/web_ledger_page.dart`) to
full parity with the Claude Design reference
(`docs/design/treasury-web-reference/ledger.jsx`): a Google-Sheets-style,
inline-editable transaction grid — not the current read-only daily feed.

## Goal

Replace the read-only grouped feed with an editable month grid that matches the
reference's identity: "edit your finances like a spreadsheet, inline."

## Reference anatomy (ledger.jsx)

1. **Toolbar** — `Filters & Sort` popover (Account, Category, Type segments, Date
   range, Sort) with an active-count badge; active-filter **chips**; search box;
   `+ Add Transaction`.
2. **Summary tiles** — Inflow / Outflow / Net Cash (icon chip + label + value).
3. **ChatQuickAdd** — NL entry card ("Grab 180 from gcash") with a small chat log.
4. **Editable table** — one flat month table, sticky header with **sortable**
   columns, columns: ☑ · Date · Account · Description · Category(dot) · Inflow ·
   Outflow · Running · Acct. Balance · Notes · ⌫. Inline cell editing, a draft
   **add-row** at the bottom (Enter commits), **bulk select + delete**, a band
   header showing month + totals + row count, and a footer hint.

## Architecture decisions

- **Running balance is global, computed once in the presenter** (matches the
  reference: `balById` over all txns; filtered rows just display their value).
  Add `LedgerPresenter.ledgerSpreadsheetRows` → records of
  `(txn, runningBalance, accountBalance)`.
  - `runningBalance`: reuse `ledgerRowsForMonth`'s chronological signed accumulation.
  - `accountBalance`: per-account balance immediately after each txn,
    reconstructed by **unwinding each account's current `balance` backward**
    (newest→oldest) across `_allTransactions`, liability-aware (same sign rule as
    `_applyBalanceDelta`). Keyed by txn id.
- **All transient filtering/sorting (account, category, type, date, search, sort)
  lives in the View** over the precomputed rows — running balances stay stable
  regardless of filter, exactly like the reference. No mutation of shared
  presenter filter state (`selectedAccountId`) → no cross-page side effects.
- **Display total aggregation** (Inflow/Outflow/Net over the *visible* rows) is
  done in the View — consistent with the existing `_DayTotals` precedent; it is
  folding already-derived numbers, not domain logic.
- **Transfers**: rows are **read-only inline** (editing one leg would desync the
  pair). Deleting a transfer removes **both legs** via a new presenter method
  `deleteTransactionOrGroup(id)`.
- **Inline amount editing**: a row's Inflow/Outflow cells are two views of the
  single `amount`+`type`. Editing the Inflow cell sets `type: inflow`; Outflow
  sets `type: outflow`; commit via `updateTransaction` (handles balance reversal).
- **Theme-aware only** — no hardcoded hex; read `Theme.of(context)`.

## Steps

1. **Presenter** (`ledger_presenter.dart`)
   - Add `_accountBalanceByTxnId` (private) — backward reconstruction map.
   - Add `ledgerSpreadsheetRows` getter.
   - Add `deleteTransactionOrGroup(String id)`.
2. **Page rewrite** (`web_ledger_page.dart`)
   - Toolbar: `Filters & Sort` `MenuAnchor` popover + chips + search + Add button.
   - Summary tiles (`_SumTile`).
   - `ChatQuickAdd` card → `presenter.sendChatInput`; reads
     `lastCommittedSummary` / `pendingFormPrefill` / `chatHardError`.
   - `_LedgerGrid`: horizontal scroll, fixed column widths, sortable header,
     editable body rows, draft add-row, bulk-select bar, footer hint.
   - Editable cells: `_TextCell`, `_AmountCell`, `_AccountCell`, `_CategoryCell`,
     `_DateCell`.
   - Keep the existing `_AddTransactionDialog`, extend it to accept an optional
     `ParsedTransaction` prefill (for ChatQuickAdd fallback).
3. **Verify** — `dart format`, `flutter analyze` on changed files.

## Out of scope

- Per-account historical opening balances beyond current-balance reconstruction.
- AI clarify flow on web (no on-device AI) — ChatQuickAdd commits when the
  rule-based parser fully resolves, else falls back to the prefilled form.
