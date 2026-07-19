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

### Requirement: Unified New-entry sheet

A single FAB SHALL open one "New entry" sheet that creates any of the four types — **Bill · Receivable ·
Set-aside · Installment** — chosen by a type selector at the top; the sheet renders the chosen type's
full field set and Save routes to that type's create flow. Every field each type has today is preserved.

#### Scenario: One FAB, pick the type
- **WHEN** the user taps the FAB
- **THEN** the "New entry" sheet opens with a type selector (Bill / Receivable / Set-aside /
  Installment); selecting a type shows that type's fields below

#### Scenario: Create each type
- **WHEN** the user completes a type's fields and taps Save
- **THEN** the matching record is created via the existing flow for that type (bill, receivable,
  budgeted set-aside, or installment) with the same fields as before

#### Scenario: Editing is locked to its type
- **WHEN** the sheet is opened to edit an existing record (e.g. from a card's Edit)
- **THEN** it opens on that record's type with the type selector hidden/disabled, and Save updates that
  record (no converting one type into another)

#### Scenario: Due day is picked, not typed
- **WHEN** the user sets a bill's due day
- **THEN** it is chosen from a day picker shown as an ordinal (e.g. "15th"), stored as the same 1–31 value

### Requirement: Per-bill reminder

A bill SHALL support an optional "remind me N days before due" reminder, set from a toggle in the bill
fields and stored on the bill; enabling it schedules a per-bill notification and disabling / paying /
deleting the bill cancels it.

#### Scenario: Turn on a reminder
- **WHEN** the user enables "Remind me N days before" on a bill and saves
- **THEN** the bill stores the lead time and a per-bill reminder is scheduled for N days before its due
  date (subject to the global bills-reminder preference)

#### Scenario: Reminder cleared
- **WHEN** the user turns the reminder off, marks the bill paid, or deletes it
- **THEN** the bill's scheduled reminder is cancelled

#### Scenario: Old bills load without a reminder
- **WHEN** a bill saved before this change is loaded
- **THEN** it loads with no reminder set (the field is null-tolerant), unchanged

#### Scenario: Reminder is bill-only
- **WHEN** the type selector is on Receivable, Set-aside, or Installment
- **THEN** no reminder toggle is shown

### Requirement: Installment fields

The installment type (within the New-entry sheet) SHALL match the reference: name, credit/BNPL account,
total amount, a number-of-months chip selector (3 / 6 / 12 / 24 / Custom), an auto-computed monthly
payment, and a start-month stepper — with no change to the existing behavior.

#### Scenario: Create an installment
- **WHEN** the user enters a name, picks a credit/BNPL account, a total, a month count, and a start month
- **THEN** the monthly payment auto-computes and Save creates the installment via the existing flow

#### Scenario: Custom month count still works
- **WHEN** the user picks "Custom" and enters a month count
- **THEN** the monthly payment recomputes and the installment saves with that term

### Requirement: Set-aside fields

The set-aside type (within the New-entry sheet) SHALL adopt the shared chrome while keeping all its
fields: name, allocated amount, set-aside type, note, fund-from account, and category.

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
