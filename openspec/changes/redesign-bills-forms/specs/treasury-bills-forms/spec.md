## ADDED Requirements

### Requirement: Shared creation-sheet design language

Every Bills sheet SHALL use one shared design language matching the Nudgr reference: a bottom sheet
over the dimmed page with a grab handle and bold title, uppercase muted field labels over rounded
filled field boxes, segmented toggles, chip selectors, a month stepper, and a full-width blue **Save**
CTA (with a soft glow); edit sheets add a tonal-red destructive action. All colors come from theme
tokens (works in dark and light).

#### Scenario: Consistent chrome
- **WHEN** any Bills create/edit/confirm sheet opens
- **THEN** it shows the grab handle, a bold title, uppercase field labels over rounded field boxes, and
  a full-width blue Save/confirm button, styled from theme tokens (no hardcoded per-mode colors)

#### Scenario: Edit offers delete
- **WHEN** a sheet is opened to edit an existing record
- **THEN** it shows a tonal-red destructive action (Delete / Remove) beneath the primary button

### Requirement: New-entry sheet (Bill / Receivable)

Adding a bill or a receivable SHALL use a single "New entry" sheet with a segmented **Bill to pay /
Money owed me** toggle that swaps between the two field sets, preserving every field each type has today.

#### Scenario: Toggle between bill and receivable
- **WHEN** the user opens the new-entry sheet and switches the toggle
- **THEN** the fields swap between the bill set (name, amount, due day, pay-from account, category,
  payment note, recurring) and the receivable set (name, expected amount, expected date, account,
  category, receivable type, recurring), and Save creates the matching record

#### Scenario: Add a bill
- **WHEN** the user fills the bill fields and taps Save
- **THEN** a bill is created via the existing add-bill flow with the same fields as before

#### Scenario: Add a receivable
- **WHEN** the toggle is on "Money owed me", the user fills the fields and taps Save
- **THEN** a receivable is created via the existing add-receivable flow

#### Scenario: Editing is locked to its type
- **WHEN** the sheet is opened to edit an existing bill or receivable
- **THEN** it opens on that record's type with the toggle disabled, and Save updates that record

#### Scenario: Due day is picked, not typed
- **WHEN** the user sets a bill's due day
- **THEN** it is chosen from a day picker shown as an ordinal (e.g. "15th"), stored as the same 1–31 value

### Requirement: Add / edit installment sheet

The installment sheet SHALL match the reference: name, credit/BNPL account, total amount, a number-of-
months chip selector (3 / 6 / 12 / 24 / Custom), an auto-computed monthly payment, and a start-month
stepper — with no change to the existing behavior.

#### Scenario: Create an installment
- **WHEN** the user enters a name, picks a credit/BNPL account, a total, a month count, and a start month
- **THEN** the monthly payment auto-computes and Save creates the installment via the existing flow

#### Scenario: Custom month count still works
- **WHEN** the user picks "Custom" and enters a month count
- **THEN** the monthly payment recomputes and the installment saves with that term

### Requirement: Add / edit budgeted set-aside sheet

The budgeted set-aside sheet SHALL adopt the shared chrome while keeping all its fields: name,
allocated amount, set-aside type, note, fund-from account, and category.

#### Scenario: Create a set-aside
- **WHEN** the user fills the fields and taps Save
- **THEN** a budgeted expense is created via the existing flow with the same fields as before

### Requirement: Mark / confirm sheets

The mark-paid, mark-received, fund, and mark-installment-paid sheets SHALL adopt the shared chrome with
a large centered amount entry, preserving all current controls (amount, account picker, "already added
to ledger" option, set-aside destination, dates) and confirm logic.

#### Scenario: Mark a bill paid
- **WHEN** the user opens mark-paid, adjusts the amount/account/date, and confirms
- **THEN** the bill is marked paid via the existing flow (ledger entry / transfer unchanged)

#### Scenario: Amount is the focal control
- **WHEN** a mark/confirm sheet is shown
- **THEN** the amount is presented as a large centered `₱` figure, with the other controls beneath it
