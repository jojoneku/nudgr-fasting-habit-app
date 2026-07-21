## ADDED Requirements

### Requirement: Reference transaction sheet

The Ledger's Add/Edit Transaction sheet SHALL render in the reference form language on the shared
sheet kit, preserving every field and behavior.

#### Scenario: Sheet chrome + type toggle
- **WHEN** the sheet opens
- **THEN** it shows a grab handle, a bold title, and a 3-way Expense / Income / Transfer segmented
  toggle (expense red, income green, transfer blue), with reference field boxes and uppercase labels
  below — all theme-aware in dark and light

#### Scenario: Type toggle swaps fields
- **WHEN** the user selects Transfer
- **THEN** the sheet shows From and To account fields (and hides the reimbursable section); selecting
  Expense shows the account + the reimbursable section; Income shows the account without it

#### Scenario: Account fields
- **WHEN** an account, From, or To field is shown
- **THEN** it renders a mini account badge + name + caret and opens the account picker; a transaction
  always requires an account (no "none" option)

#### Scenario: Amount, category, date
- **WHEN** the user edits the fields
- **THEN** the amount is a prominent `₱` box (validated `> 0`), the category is an optional picker box
  that clears when its selection is tapped again, and the date is a picker box opening a date picker

### Requirement: Behavior preserved

The redesign SHALL be view-only — every create/edit/transfer/reimbursable path is unchanged.

#### Scenario: Create by type
- **WHEN** the user saves an expense, income, or transfer
- **THEN** the record(s) are created via the existing presenter methods (`addTransaction` /
  `addTransfer`), identical to the pre-redesign sheet (transfers write both legs)

#### Scenario: Reimbursable expense
- **WHEN** the user marks an outflow reimbursable and saves
- **THEN** the linked reimbursement receivable is spawned (and the "owed by" + expected date persist)
  exactly as before; the section is available only for outflows

#### Scenario: Edit an existing record
- **WHEN** the user edits a transaction (including a transfer or a reimbursable)
- **THEN** the sheet pre-fills from the record — reconstructing a transfer from its two legs and
  loading the expected reimbursement date from the linked receivable — and saving updates the same
  record(s) via the existing update/replace logic

#### Scenario: Chat prefill and filtered-day logging
- **WHEN** the sheet is opened from a chat `ParsedTransaction` prefill, or with an `initialDate`
- **THEN** the fields pre-fill from the prefill, and a new transaction is dated to `initialDate` so it
  can be logged onto the currently-filtered day without clearing the filter

#### Scenario: No data change
- **WHEN** any transaction, transfer, or reimbursable is created or edited through the redesigned sheet
- **THEN** the persisted records and XP/stats side effects are identical to the pre-redesign sheet
