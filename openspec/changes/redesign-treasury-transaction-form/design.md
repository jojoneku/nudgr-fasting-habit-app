## Context

`add_transaction_sheet.dart` (~900 lines) is a `StatefulWidget` bottom sheet opened from the Ledger
(`AddTransactionSheet(presenter, existing, prefill, initialDate)`). It carries the most branching of
any Treasury form:

- **Type** `_type` ∈ {outflow, inflow, transfer}; the toggle drives which fields show.
- **Fields:** amount, description, note, date; account (`_selectedAccountId`); for transfers a
  destination (`_transferToAccountId`); category (`_selectedCategoryId`, optional).
- **Reimbursable** (outflow only): `_reimbursable`, `_owedBy`, and an expected-reimbursement date read
  back from the linked receivable when editing.
- **Sources:** `prefill` (a `ParsedTransaction` from chat), `existing` (edit — reconstructs a transfer
  from its two legs), and `initialDate` (log onto the filtered day).
- **Save:** transfer → `deleteTransactionOrGroup` (on edit) + `addTransfer`; reimbursable outflow →
  `addReimbursableExpense` (spawns a receivable) / reuse the linked id on edit; else
  `addTransaction` / `updateTransaction`. XP is awarded by the presenter.

It already uses `sheetFieldDecoration` in places but not the full reference kit; type selection and
account/date/category controls are Material widgets that diverge from the reference and the redesigned
bill forms.

## Reference form language

Same tokens as `redesign-treasury-bill-forms/design.md` (grab handle; 17px/w800 title; `#232327`/
`#202024` field boxes, radius 12, 1px `#2E2E33`; 10.5px tracked uppercase labels; `₱` amount box;
account row = 22px badge + name + caret; caret picker boxes). The Add-transaction frame adds a **3-way
type toggle** at the top and a prominent amount.

## Goals / Non-Goals

**Goals:** bring the transaction sheet to the reference feel with the shared kit; keep every field,
branch, default, and side effect; reuse (not fork) the kit.

**Non-Goals:** presenter/model/storage changes; new/removed fields; the chat input row or Manage
Categories (already redesigned); migrations.

## Decisions

- **3-way `SheetSegmentedToggle<TransactionType>`** with per-segment accents (expense=`cs.error`,
  income=`cs.tertiary`, transfer=`cs.primary`). On edit, keep it enabled — the current sheet already
  supports switching type on edit for non-transfers; transfers reconstruct from the group. (If edit-of-
  a-transfer proves fragile with the toggle enabled, lock it to transfer — decide during
  implementation; default is to preserve today's behavior.)
- **Account, From, To → `SheetAccountField` + `showAccountPicker`.** Transfer shows two account fields
  (From / To); a From==To selection keeps whatever guard the presenter/save already applies. No "none"
  option (a transaction needs an account) — `allowNone: false`.
- **Category → a `SheetPickerBox`** labelled "Category (optional)" opening a category picker
  (expense vs income list by type); selecting the active one again clears it (preserve tap-to-clear).
  Reuse the category badge/`resolveCategoryBadge` from the ledger redesign for the picker rows.
- **Date → `SheetPickerBox`** with a calendar trailing icon → `showDatePicker`.
- **Amount** is the emphasized `₱` field box (reference's large amount); keep `amountInputFormatters`
  and the `> 0` validator.
- **Reimbursable section** stays a switch (outflow only) + "owed by" field + expected-date picker box,
  restyled; all reimbursement-receivable wiring preserved.
- **View/util only.** Every save branch, id generation, prefill mapping, transfer-group edit, and the
  `initialDate` path move verbatim.

## Risks / Trade-offs

- **[Busiest form, many branches]** → port logic verbatim; add widget tests for: expense save, income
  save, transfer save (two legs), reimbursable save (receivable spawned), edit of each, and prefill
  open.
- **[Type toggle on edit]** → preserve current behavior; if a transfer edit misbehaves with the toggle
  enabled, lock the toggle for transfer edits (documented above).
- **[Kit dependency across branches]** → the kit lives on the bill-forms branch; sequence the merges
  (kit first) so the transaction form compiles against it on the combine branch.

## Migration Plan

None — view-only. Rollback is reverting `add_transaction_sheet.dart`. No data/storage effect; saved
transactions, transfers, and reimbursements are identical.

## Open Questions

- Should the category picker graduate to a shared `showCategoryPicker` (reused by bills + budget)?
  Proposed later; keep the picker general.
