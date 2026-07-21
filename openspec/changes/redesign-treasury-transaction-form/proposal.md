## Why

The Ledger's **Add / Edit Transaction** sheet (`add_transaction_sheet.dart`) is the form users touch
most in Treasury — every logged expense, income, and transfer flows through it. It works but predates
the Nudgr reference form language (`docs/design-reference/Nutrition Focus Treasury.dc.html`,
Frame 6 · Add transaction): the reference leads with a **3-way Expense / Income / Transfer segmented
toggle**, a prominent `₱` amount, and reference **field boxes** (uppercase labels; account rows that
show a mini account badge + name + caret; a "CATEGORY (OPTIONAL)" picker box) — all on the same sheet
chrome (grab handle + bold title) used by the redesigned bill forms.

This change restyles the transaction sheet to that language using the **shared sheet kit** introduced
by `redesign-treasury-bill-forms`, **without changing any of its behavior** — transfers, reimbursables,
chat prefill, edit, and the "log on the filtered day" path all stay.

## What Changes

- **Type toggle → `SheetSegmentedToggle`** — a 3-way Expense / Income / Transfer control (expense=red,
  income=green, transfer=blue) replacing the current chips/selector; switching it swaps the
  type-specific fields (transfer shows From→To accounts; expense shows the reimbursable section).
- **Amount** becomes the prominent `₱`-prefixed emphasized field box (reference's large amount).
- **Account fields → `SheetAccountField`** (mini `AccountBadge` + name + caret, opening
  `showAccountPicker`): the "Account" for expense/income, and **From / To** accounts for transfer.
- **Category → a picker field box** labelled "CATEGORY (OPTIONAL)" (keeps tap-to-clear; opens a
  category picker consistent with the field boxes).
- **Date → `SheetPickerBox`** (reference caret box) instead of the current date control.
- **Sheet chrome** — grab handle + bold title ("New transaction" / "Edit transaction"), reference
  field labels/boxes throughout; Save pinned at the bottom.
- The **reimbursable** section (outflow only) and description/note keep their controls, restyled to
  the kit.

Non-breaking. **View-only** — no model/storage/presenter change; save still routes to
`addTransaction` / `addTransfer` / `updateTransaction` / `addReimbursableExpense` /
`deleteTransactionOrGroup` exactly as today.

## Retained (superset — nothing removed)

- Three types: expense (outflow), income (inflow), transfer.
- Amount, description, note, editable date.
- Account (from) + destination account for transfers.
- Category (optional; tap-to-clear).
- **Reimbursable** flag (outflow only) + "owed by" + expected-reimbursement date (loaded from the
  linked receivable when editing).
- **Chat prefill** (`ParsedTransaction`) and **edit** of an existing record, including transfer-group
  reconstruction (both legs) and the reimbursement-receivable link.
- **`initialDate`** — logging onto the currently-filtered day without clearing the filter.
- XP / stats side effects (owned by the presenter) unchanged.

## Non-goals

- **No presenter/model/storage change.** All create/edit/transfer/reimbursable logic and XP stay in
  the presenter; this is view/util only.
- **No new or removed fields.**
- **Not the chat input row** (already redesigned in `redesign-treasury-ledger`) and not the Manage
  Categories sheet (already redesigned there).
- **No data migration, no new dependencies.**

## Dependency

- Uses the **shared sheet kit** (`SheetHandle`, `SheetTitle`, `SheetSegmentedToggle`,
  `SheetAccountField`, `showAccountPicker`, `SheetPickerBox`, `SheetFieldLabel`, `sheetFieldDecoration`)
  added by `redesign-treasury-bill-forms`. Implement after both changes are on the combine branch (or
  land the kit first); the kit is intended to be shared, not duplicated.

## Capabilities

### New Capabilities
- `treasury-transaction-form`: The Ledger's Add/Edit Transaction sheet rendered in the reference form
  language — a 3-way Expense/Income/Transfer segmented toggle, a prominent `₱` amount, account/from-to
  fields as `SheetAccountField`, a category picker box, and a date picker box on the shared sheet
  chrome — preserving every field, the reimbursable flow, chat prefill, edit (incl. transfer groups),
  the initial-date path, and the routes to the existing presenter methods; theme-aware.

## Impact

- **Modified:** `lib/views/treasury/ledger/add_transaction_sheet.dart` (restyle to the kit; logic
  unchanged). Possibly small tweaks to the ledger view's sheet launcher if titles/handles move into
  the sheet.
- **Reuses (unchanged):** `LedgerPresenter`, `TransactionRecord`, the shared sheet kit, `AccountBadge`,
  `amount_input_formatter`, theme tokens.
- **Deps:** none new. **Risk:** medium — it's the busiest form with several branches (transfer,
  reimbursable, prefill, edit); mitigated by moving logic verbatim and widget tests per path.
