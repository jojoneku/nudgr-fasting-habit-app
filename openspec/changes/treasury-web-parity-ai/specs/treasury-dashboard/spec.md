## MODIFIED Requirements

### Requirement: Month outlook forecast decomposition

The Dashboard SHALL present the month-end outlook as a decomposition of the projection — upcoming
bills, money to receive, unfunded set-asides, and the projected month-end cash — using the same tile
set, the same labels, and the same underlying getters on mobile and web.

The projected month-end cash figure SHALL be `forecastedNetBalance`, which nets current liquid cash
and incoming receivables against unpaid bills, unfunded budgeted set-asides, and the remaining
monthly category budget. It SHALL be shown unconditionally, whether or not the user has budgets set.

Raw `endingCash` SHALL NOT be presented as the dashboard's headline month-end figure, because it
does not reserve the remaining budget the user still intends to spend and is therefore read as a
projection it is not.

#### Scenario: Four-tile decomposition
- **WHEN** the month outlook section is shown
- **THEN** it presents upcoming unpaid bills, pending receivables, remaining budgeted set-asides,
  and projected month-end cash

#### Scenario: Projection is always visible
- **WHEN** the user has no budgets set for the current month
- **THEN** the projected month-end cash tile is still shown, rather than being replaced by another
  metric

#### Scenario: Same name for the same number
- **WHEN** the projected month-end cash figure is shown on mobile and on web
- **THEN** both derive it from `forecastedNetBalance` and label it identically
- **AND** each tile's sub-copy states what the figure deducts

#### Scenario: Negative projection is signalled
- **WHEN** the projected month-end cash is below zero
- **THEN** it renders in the danger accent

#### Scenario: No change to finance math
- **WHEN** this requirement is implemented
- **THEN** `forecastedNetBalance`, `endingCash`, `totalBudgetRemaining`, `budgetedExpensesRemaining`,
  and every other presenter getter retain their existing definitions and existing tests

#### Scenario: Month inflow and outflow are not duplicated
- **WHEN** the month outlook no longer carries month-in and month-out tiles
- **THEN** those two figures remain visible in the cashflow strip's income and expense bars, which
  already label both amounts
