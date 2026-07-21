<!-- ⚠️ SUPERSEDED by redesign-treasury-budget-cards. This pace-hero spec delta was
     not shipped; the canonical Budget requirements live in that change. The ring
     hero + on-pace pill survive, but the safe-to-spend callout was dropped. This
     delta is retained for history and should NOT be synced into the main specs. -->

## ADDED Requirements

### Requirement: Pace-ring budget hero

The Budget tab SHALL lead with a pace hero showing the percentage of the total budget spent, the
spent and allocated amounts, and a pace status, styled per the Nudgr reference using theme tokens.

#### Scenario: Spent ring and figures
- **WHEN** the selected month has budgets
- **THEN** the hero shows a ring at the spent-of-allocated percentage, the SPENT amount, and
  "of {allocated}"

#### Scenario: Ahead of pace
- **WHEN** the selected month is the current month and spending is at or under the elapsed-month pace
- **THEN** the hero shows an "Ahead of pace" pill in the success accent

#### Scenario: Over pace or over budget
- **WHEN** spending is above the elapsed-month pace (or exceeds the allocation)
- **THEN** the pill reads "Over pace" (or "Over budget") and the ring/pill use the danger accent

#### Scenario: Non-current month
- **WHEN** the selected month is not the current calendar month
- **THEN** the pace pill and the safe-to-spend callout are omitted (they only apply to the in-progress
  month)

#### Scenario: No budgets
- **WHEN** the selected month has no budgets
- **THEN** the hero is not shown and the existing empty state is displayed

### Requirement: Safe-to-spend callout

The Budget tab SHALL show, for the current month, a callout with the remaining budget spread across
the days left in the month.

#### Scenario: Safe to spend per day
- **WHEN** the current month has remaining budget and days left
- **THEN** a callout shows "Safe to spend · N days left" and the remaining budget divided by the days
  left, expressed as a per-day amount

### Requirement: Existing budget sections preserved

The redesign SHALL retain the category-group and savings sections and all budget interactions.

#### Scenario: Sections intact
- **WHEN** the Budget tab is shown with budgets
- **THEN** the per-group category budget tiles (with spent/allocated bars) and the savings/goals
  section render and behave as before, with the month selector, manage-groups action, and add-budget
  FAB unchanged
