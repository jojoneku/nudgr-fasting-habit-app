## ADDED Requirements

### Requirement: Title + month-dropdown header
The Budget tab SHALL present a large "Budget" title with a month-switcher control top-right. The
switcher MUST show the selected month (e.g. "June") with a dropdown affordance and, when tapped, MUST
open a month picker letting the user jump to another month. Manage-groups MUST remain reachable from
the header. The control MUST meet the ≥44×44px touch target.

#### Scenario: Header shows title and current month
- **WHEN** the Budget tab opens on the current month
- **THEN** a "Budget" title is shown with a month control displaying that month and a dropdown caret

#### Scenario: Switching months via the dropdown
- **WHEN** the user taps the month control and selects a different month
- **THEN** the selected month updates and the hero + budget sections recompute for that month

#### Scenario: Manage groups still reachable
- **WHEN** the user opens the manage-groups control from the header
- **THEN** the manage-groups sheet appears (unchanged behavior)

### Requirement: Spent-vs-budgeted ring hero
The Budget tab SHALL lead with a ring hero showing the percentage of the total allocation spent, the
SPENT amount, and the total allocated ("of ₱x"). For the current month it MUST also show an on-pace
pill reading "Ahead of pace", "Over pace", or "Over budget". The ring and pill MUST escalate to the
danger accent when spending exceeds the allocation. The hero MUST be hidden when no budgets exist so
the empty state carries the screen. The tab MUST NOT show a "safe to spend" callout.

#### Scenario: On-track current month
- **WHEN** total spent is at or under the month's elapsed pace for the current month
- **THEN** the ring shows the spent percentage and an "Ahead of pace" pill in the non-danger accent

#### Scenario: Over budget
- **WHEN** total spent exceeds total allocated
- **THEN** the ring and pill render in the danger accent and the pill reads "Over budget"

#### Scenario: Past or future month omits pace
- **WHEN** a non-current month is selected
- **THEN** the ring and figures still render but no pace pill is shown

#### Scenario: No safe-to-spend on this screen
- **WHEN** the Budget tab is displayed for any month
- **THEN** no "safe to spend / day" callout is present

### Requirement: One card per budget with category identity
Each budget SHALL render as its own card (not rows in a shared group card). An expense budget card
MUST show the category's icon in a color chip (the same icon and color used for that category
elsewhere in Treasury), the category name, the spent and allocated amounts, and a progress bar with a
percentage. When spending exceeds the allocation the card MUST indicate the overage (e.g. "Over by
₱x") and render the amount/bar in the danger accent. A savings/goal budget card MUST show the target
name, contributed vs goal, and progress, treating meeting-or-exceeding the goal as success (not over).

#### Scenario: Expense budget card shows icon, spend, and progress
- **WHEN** a category has a budget for the selected month
- **THEN** its card shows the category icon+color, name, spent / allocated, and a progress bar with %

#### Scenario: Over-budget card
- **WHEN** a category's spend exceeds its allocation
- **THEN** the card shows an overage indicator and renders the amount and bar in the danger accent

#### Scenario: Savings goal card
- **WHEN** a savings/goal budget exists for the selected month
- **THEN** its card shows contributed / goal and progress, and meeting the goal is shown as met (not over)

### Requirement: Budget sections grouped and ordered by type
Budgets SHALL be grouped by budget group and rendered in the order Living Expense, Savings, Variable /
Optional, Non-Negotiables, with any custom groups following. The savings group MUST appear in this
order (interleaved), not forced to the end. A group with no budgets for the selected month MUST be
omitted. Each rendered section MUST show the group name and its spent / allocated total. A user's
custom group ordering (via manage-groups) MUST take precedence over the default order.

#### Scenario: Default section order
- **WHEN** budgets exist across the built-in groups
- **THEN** sections appear in the order Living Expense, Savings, Variable / Optional, Non-Negotiables

#### Scenario: Empty groups are hidden
- **WHEN** a group has no budgets for the selected month
- **THEN** that group's section is not rendered

#### Scenario: User ordering wins
- **WHEN** the user has reordered groups via manage-groups
- **THEN** the sections follow the user's order rather than the default

### Requirement: Expandable transactions per budget
Each budget card SHALL allow expanding to reveal that budget's transactions for the selected month and
collapsing to hide them. When expanded with no transactions the card MUST show an empty indication.

#### Scenario: Expand to view transactions
- **WHEN** the user expands a budget card that has transactions this month
- **THEN** the card reveals those transactions with description, date, and signed amount

#### Scenario: Expand with no transactions
- **WHEN** the user expands a budget card with no transactions this month
- **THEN** the card shows an empty "no transactions" indication
