## ADDED Requirements

### Requirement: Monthly savings rate

Each History month card SHALL surface the month's savings rate (net savings as a share of income),
matching the Nudgr reference's "N% saved".

#### Scenario: Month with income
- **WHEN** a month has positive income
- **THEN** its card shows "N% saved" where N is net savings ÷ income, rounded, tinted by whether net
  savings were positive

#### Scenario: Month with no income
- **WHEN** a month has no income
- **THEN** the savings-rate label is omitted (no divide-by-zero, no "0% saved" noise)

### Requirement: Existing history layout preserved

The redesign SHALL retain the History tab's structure and detail.

#### Scenario: Sections and detail intact
- **WHEN** the History tab is shown
- **THEN** the CURRENT MONTH · LIVE card and the CLOSED MONTHS list render as before, each card
  keeps its net-savings / ending-cash / bills / inflow / outflow figures, and tapping a card opens
  the monthly detail view unchanged
