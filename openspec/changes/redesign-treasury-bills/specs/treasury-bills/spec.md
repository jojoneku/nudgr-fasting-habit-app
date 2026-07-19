## ADDED Requirements

### Requirement: Due-soon hero

The Bills tab SHALL spotlight the most imminent unpaid bill in a hero card when one is due within a
week or overdue, styled per the Nudgr reference using theme tokens.

#### Scenario: A bill is due soon
- **WHEN** the selected month has an unpaid bill due within 7 days
- **THEN** a hero card shows a "Due in N days" (or "Due today"/"Due tomorrow") label, the bill name, a
  "{category} · due {date}" subtitle, and the amount, in the bills accent

#### Scenario: A bill is overdue
- **WHEN** the most imminent unpaid bill's due date has passed
- **THEN** the hero shows an "Overdue by N days" label and escalates to the danger accent + error icon

#### Scenario: Nothing due soon
- **WHEN** no unpaid bill is due within a week (all paid, or the next is far off)
- **THEN** the hero renders nothing and the rest of the Bills screen is unchanged

#### Scenario: Mark paid and edit
- **WHEN** the user taps the hero's Mark-paid or edit control
- **THEN** the existing mark-bill-paid sheet or edit-bill sheet opens for that bill

### Requirement: Existing bills screen preserved

The redesign SHALL retain every existing element of the Bills tab.

#### Scenario: Existing sections intact
- **WHEN** the Bills tab is shown
- **THEN** the month selector, Pending/Paid/Installments stats bar, credit-card cards, and the bills,
  receivables, set-asides, and installments sections all render and behave as before, with the FAB and
  all sheets unchanged
