## ADDED Requirements

### Requirement: Shared reference sheet form kit

The Bills creation/edit sheets SHALL render with a shared kit that matches the reference form
language, so every sheet looks and behaves consistently and stays theme-aware.

#### Scenario: Sheet chrome
- **WHEN** any bill-related creation/edit sheet opens
- **THEN** it shows a centered grab handle, a bold sheet title, small uppercase field labels over
  bordered field boxes (radius 12, `bg-input`), `₱`-prefixed amount boxes, and trailing carets on
  picker boxes — all colors resolved from the theme (correct in dark and light)

#### Scenario: Account field
- **WHEN** a sheet shows an account field
- **THEN** it renders a mini account badge + account name + a caret, and tapping it opens an account
  picker list (including a "None"/"Ask me when received" option where applicable) — not a bare
  Material dropdown

### Requirement: Unified New-entry sheet (Bill or Receivable)

Creating or editing a bill or a receivable SHALL use one sheet with a Bill / Receivable segmented
toggle, preserving every field and behavior of the previous two separate sheets.

#### Scenario: Toggle switches the type-specific fields
- **WHEN** the user opens the New-entry sheet and toggles Bill vs Receivable
- **THEN** the accent and the type-specific fields switch — Bill shows bill type, due day, and payment
  note; Receivable shows receivable type, expected date, and destination account — while shared
  fields (name, amount, category, account, recurring + recurrence) stay

#### Scenario: Create a bill
- **WHEN** the user fills the sheet as a Bill and saves
- **THEN** a `Bill` is created via the existing presenter method with the same fields, defaults
  (account defaults to the first), validation (amount > 0, due day 1–31), auto-statement note
  handling, and recurrence as the old Add Bill sheet

#### Scenario: Create a receivable
- **WHEN** the user fills the sheet as a Receivable and saves
- **THEN** a `Receivable` is created via the existing presenter method with the same fields
  (incl. expected date and the "Ask me when received" nullable destination account) and validation as
  the old Add Receivable sheet

#### Scenario: Edit is locked to kind
- **WHEN** the user edits an existing bill or receivable
- **THEN** the sheet opens on that entry's kind with the toggle disabled (a bill cannot be converted
  into a receivable), pre-filled with its values, and saving updates the same record

#### Scenario: Entry point pre-selects kind
- **WHEN** the user taps the bill "+" vs the receivable "+" entry point
- **THEN** the New-entry sheet opens with the corresponding kind pre-selected

### Requirement: Installment sheet in the kit

The Installment creation/edit sheet SHALL adopt the shared kit while preserving its fields and
computations.

#### Scenario: Installment styling + behavior
- **WHEN** the user opens the Installment sheet
- **THEN** it uses the kit's handle, title, labels, field boxes, account field, months chip-picker
  (3/6/12/24 + custom), start-month stepper, and note — and the monthly payment still auto-computes
  from total ÷ months, remains manually overridable, and account stays required

### Requirement: No behavioral or data change

The redesign SHALL be view-only.

#### Scenario: Saved records unchanged
- **WHEN** a bill, receivable, or installment is created or edited through the redesigned sheets
- **THEN** the persisted model is identical to what the pre-redesign sheets produced (no model,
  storage, validation, recurrence, or mark-paid/received behavior change)
