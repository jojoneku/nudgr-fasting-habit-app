## ADDED Requirements

### Requirement: Bills header with month·year picker

On the Bills tab the shared Treasury app bar SHALL show a left-aligned **"Bills"** title with a
**month + year picker** in its top-right actions; other tabs keep the centered `TREASURY` title.

#### Scenario: Title and picker on the Bills tab
- **WHEN** the Bills tab is active
- **THEN** the app bar title reads "Bills" (left-aligned) and a month·year picker pill (e.g. "Jun
  2026") appears at top-right showing the presenter's selected month

#### Scenario: Picking a month and year
- **WHEN** the user taps the picker and selects a different month and/or year
- **THEN** the selected month updates for both the bills and installment data and the list refreshes

#### Scenario: Other tabs unaffected
- **WHEN** any non-Bills Treasury tab is active
- **THEN** the app bar shows the centered `TREASURY` title with no month picker

### Requirement: Swipeable due-soon stack

The Bills tab SHALL present due-soon and overdue unpaid bills as a horizontally **swipeable stack** of
hero cards, reusing the due-soon card styling, shown only when at least one such bill exists.

#### Scenario: Multiple bills due soon
- **WHEN** more than one unpaid bill is overdue or due within 7 days
- **THEN** they appear as a swipeable stack (with page indicators) ordered soonest-first, each card
  offering Mark-paid and edit that open the existing sheets

#### Scenario: One bill due soon
- **WHEN** exactly one unpaid bill is overdue or due within 7 days
- **THEN** a single due-soon card is shown (no page indicators required)

#### Scenario: Nothing due soon
- **WHEN** no unpaid bill is overdue or due within 7 days
- **THEN** the stack renders nothing and the rest of the screen is unchanged

### Requirement: Coming-up timeline

The Bills tab SHALL show a **"Coming up"** timeline of the top 5 upcoming items merged across bills,
receivables, budgeted expenses, and installments, computed by the presenter.

#### Scenario: Mixed upcoming items
- **WHEN** the selected month has upcoming (unpaid/un-received) items across the four types
- **THEN** up to 5 are listed in a dot/line timeline, sorted soonest-first with undated items last;
  receivables (incoming) show a `+` amount in the success color, outflows show a neutral amount

#### Scenario: Nothing upcoming
- **WHEN** no unpaid/un-received items remain for the month
- **THEN** the "Coming up" section is hidden

### Requirement: Titled sections of Pay/Receive cards

The Bills tab SHALL render each type in a plain **titled section** (Bills, Receivables, Budgeted,
Installments) as a list of cards showing the item's **category icon**, name, amount, and date, with a
right-aligned **Pay** (or **Receive** for receivables) action.

#### Scenario: A bill card
- **WHEN** an unpaid bill is listed under "Bills"
- **THEN** its card shows the linked category's icon and color, the name, the amount, the due date,
  and a **Pay** button that opens the existing mark-bill-paid sheet

#### Scenario: A receivable card
- **WHEN** an un-received receivable is listed under "Receivables"
- **THEN** its card shows the linked category's icon/color, name, amount, expected date, and a
  **Receive** button that opens the existing mark-received sheet

#### Scenario: A settled item
- **WHEN** an item is paid or received
- **THEN** its card is dimmed and shows a check instead of the action button

#### Scenario: An empty section
- **WHEN** a type has no items for the selected month
- **THEN** the section shows an empty-state message in place of cards

## MODIFIED Requirements

### Requirement: Existing bills screen preserved

The redesign SHALL retain every existing Bills capability, re-homed per the new structure — no feature
is dropped.

#### Scenario: Stats and all types still present
- **WHEN** the Bills tab is shown
- **THEN** the Pending/Paid/Installments stat cards render, and the bills, receivables, budgeted, and
  installments all appear (in titled card sections), with the FAB and all mark-paid/received/edit
  sheets working as before

#### Scenario: Credit cards no longer on Bills
- **WHEN** the Bills tab is shown
- **THEN** credit-card balances are not listed here (they live on the Dashboard under Accounts); paying
  a credit-card statement bill still works from its bill card via the existing flow
