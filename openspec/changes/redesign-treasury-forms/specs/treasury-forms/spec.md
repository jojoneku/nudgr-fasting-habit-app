## ADDED Requirements

### Requirement: Shared Treasury form language
All Treasury entry/edit forms SHALL use one shared, theme-aware form language: a segmented type toggle
at the top when the form has a primary mode/type; UPPERCASE tracked field labels above each input; a
large ₱-prefixed amount field; select fields shown as a `label · value ▾` row that opens a bottom-sheet
picker; a single-select chip row for finite choices; a read-only display for auto-computed values; an
icon toggle row (icon · title · helper · switch); and a primary Save button. Every interactive element
MUST meet the ≥44×44px touch target and MUST read correctly in both dark and light themes (no hardcoded
per-mode colors).

#### Scenario: Consistent field styling
- **WHEN** any Treasury form renders a field
- **THEN** it uses an uppercase tracked label above the input drawn from the shared kit, identical
  across forms

#### Scenario: Select opens a picker
- **WHEN** the user taps a select field (e.g. account, due day)
- **THEN** a bottom-sheet picker of the options opens and the chosen value updates the field

#### Scenario: Theme-aware
- **WHEN** the app is in light mode or dark mode
- **THEN** every form control renders legibly using theme tokens, with no dark-only or light-only colors

### Requirement: No loss of existing form fields or behavior
The restyle SHALL preserve every field, option, validation, and submit behavior that each form has
today. No field may be removed; fields the reference omits MUST remain available (e.g. under a "More
options" section). No new persistence is introduced by this change.

#### Scenario: Field parity after restyle
- **WHEN** a form is migrated to the shared kit
- **THEN** every input, selector, toggle, and validation present before the migration is still present
  and functions the same on save

#### Scenario: Reference-omitted fields retained
- **WHEN** the reference shows fewer fields than the current form (e.g. bill category, payment note,
  recurrence)
- **THEN** those fields remain reachable in the redesigned form rather than being dropped

### Requirement: Add transaction form
The Add/Edit Transaction form SHALL lead with an Expense / Income / Transfer segmented toggle, then a ₱
amount field, a description field, a category select, and an account select, styled in the shared kit.
The existing date, transfer-target, and reimbursable controls MUST remain.

#### Scenario: Transaction type toggle
- **WHEN** the user switches between Expense, Income, and Transfer
- **THEN** the form shows the fields appropriate to that type (e.g. transfer target for Transfer) and
  keeps entered values where they still apply

### Requirement: Add account form
The Add/Edit Account form SHALL present a TYPE chip row (Bank / eWallet / Cash / Savings / Credit), a
name field, a ₱ starting-balance field, and color selection, styled in the shared kit. When the type is
Credit, the form MUST reveal the credit details (credit limit and due day) as it does today.

#### Scenario: Credit details are conditional
- **WHEN** the account type is set to Credit
- **THEN** the credit limit and due-day fields appear; for non-credit types they are hidden

### Requirement: Combined bill / receivable entry form
Adding a bill or a receivable SHALL use one combined entry sheet with a Bill-to-pay / Money-owed-me
toggle at the top. Shared fields (name, ₱ amount, account select, and due-day or expected-date select)
render once; the type-specific fields swap with the toggle. The bill mode MUST retain bill type,
category, payment note, and recurring/recurrence; the receivable mode MUST retain receivable type,
category, and expected date — grouped under "More options" so the core stays clean. Both existing entry
points MUST open this sheet with the toggle pre-set.

#### Scenario: Toggle swaps the type-specific fields
- **WHEN** the user switches the entry between Bill-to-pay and Money-owed-me
- **THEN** the shared fields keep their values and the type-specific block (bill-only vs receivable-only
  fields) swaps accordingly

#### Scenario: Editing an existing bill opens in bill mode
- **WHEN** the user edits an existing bill (or receivable)
- **THEN** the combined sheet opens with the correct mode pre-selected and all of that entry's fields
  populated, including those under "More options"

#### Scenario: Advanced fields preserved
- **WHEN** the user creates a bill with a category, payment note, and monthly recurrence
- **THEN** those values save exactly as before the redesign

### Requirement: Add installment form
The Add/Edit Installment form SHALL present a name field, a credit/BNPL account select, a ₱ total-amount
field, a months chip row (3 / 6 / 12 / 24 / Custom), and an auto-computed monthly-payment read-only
display, styled in the shared kit. Choosing Custom MUST allow entering a specific month count. The
existing note and start-month controls MUST remain, and the auto-monthly (total ÷ months, unless
manually overridden) behavior MUST be preserved.

#### Scenario: Months chip updates auto monthly
- **WHEN** the user picks a month count and has not manually overridden the monthly amount
- **THEN** the monthly-payment display recomputes as total ÷ months

#### Scenario: Custom month count
- **WHEN** the user selects Custom
- **THEN** a numeric field accepts a specific month count and feeds the auto-monthly calculation

### Requirement: Mark-as-paid sheet
The mark-as-paid sheets (bill, expense, installment) SHALL lead with a context entity header (icon ·
name · subtitle · billed amount), then a ₱ actual-amount-paid field defaulted to the billed amount, a
paid-from account select, and a "log to ledger" toggle, styled in the shared kit. Marking paid MUST
behave exactly as it does today.

#### Scenario: Actual amount defaults to billed
- **WHEN** the mark-as-paid sheet opens
- **THEN** the actual-amount-paid field is pre-filled with the billed amount and can be edited (e.g.
  partial payment)

#### Scenario: Paid-from account
- **WHEN** the user selects the paid-from account and confirms
- **THEN** the item is marked paid using the current behavior, recording the actual amount and account
