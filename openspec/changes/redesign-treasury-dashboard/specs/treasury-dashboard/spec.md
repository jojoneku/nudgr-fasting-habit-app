## ADDED Requirements

### Requirement: Dashboard header with greeting and sync status

The Treasury Dashboard SHALL present a header with a greeting line, the "Treasury" title, and a
sync-status pill, styled per the Nudgr dark reference using theme tokens (no hardcoded per-mode
colors).

#### Scenario: Header renders with synced state
- **WHEN** the Dashboard tab is shown and local data is in sync
- **THEN** the header shows a greeting line, the "Treasury" title, and a "Synced" pill in the
  success accent

#### Scenario: No new sync plumbing
- **WHEN** the header is built
- **THEN** it reads existing sync/connection state only and introduces no new sync service, storage
  key, or network call

### Requirement: Net worth hero

The Dashboard SHALL lead with a NET WORTH hero card showing the current net worth, its
month-over-month momentum, the amount changed this month, and a sparkline of the net-worth trend.

#### Scenario: Hero shows net worth and momentum
- **WHEN** the presenter reports a net worth and at least two months of net-worth trend
- **THEN** the hero shows the net-worth figure, a trend pill with the signed month-over-month
  percentage, a "±₱X this month" line, and a sparkline of `netWorthTrend()`

#### Scenario: Sparkline degrades with sparse history
- **WHEN** fewer than two net-worth trend points are available
- **THEN** the hero still shows the current net-worth figure and omits (rather than errors on) the
  sparkline and the percentage pill

#### Scenario: Negative momentum
- **WHEN** net worth fell versus the previous month
- **THEN** the trend pill and "this month" line render in the danger accent with a downward
  indicator

### Requirement: Cashflow strip

The Dashboard SHALL show a cashflow strip for the current month with income and expense bars and a
"Projected spare" total.

#### Scenario: Income and expense bars
- **WHEN** the current month has income and/or expenses
- **THEN** the strip shows an income bar (success accent) and an expense bar (danger accent) sized
  relative to the larger of the two, each labeled with its amount

#### Scenario: Projected spare
- **WHEN** the strip is shown
- **THEN** it displays the current month label, the days remaining in the month, and a "Projected
  spare" value from `forecastedNetBalance` in the domain accent (danger when negative)

### Requirement: Accounts list

The Dashboard SHALL show a glanceable Accounts section listing liquid accounts, with total liquid
cash and a way to reveal additional accounts, tap an account to edit it, and add a new account.

#### Scenario: Account rows
- **WHEN** the user has liquid accounts
- **THEN** each account renders as a row with an icon badge, name, type subtitle, and balance, and
  the section header shows total liquid cash

#### Scenario: Overflow expander
- **WHEN** the user has more liquid accounts than the collapsed threshold
- **THEN** a "+N more accounts" control is shown that expands to reveal the remaining accounts

#### Scenario: Add and edit accounts preserved
- **WHEN** the user taps an account row or the Add-account action
- **THEN** the existing edit-account sheet or add-account sheet opens unchanged

#### Scenario: No accounts
- **WHEN** the user has no accounts
- **THEN** an empty state with an "Add Account" action is shown instead of the accounts list

### Requirement: Retained analytics stack preserved and re-skinned

The Dashboard SHALL keep every capability present before the redesign — re-skinned to Nudgr tokens —
even where the reference does not depict it.

#### Scenario: Retained cards present
- **WHEN** the Dashboard is shown with data
- **THEN** the metric grid, spending analytics, category breakdown, upcoming bills, budget overview,
  goals & savings, credit section, and held/external funds continue to render with their existing
  data and interactions, styled with theme tokens

#### Scenario: Conditional cards honor their data guards
- **WHEN** a retained card has no data (e.g. no bills, no budget, no credit accounts)
- **THEN** that card is hidden or shows its existing empty state exactly as before the redesign

### Requirement: Loading and theme correctness

The Dashboard SHALL show a loading state while data loads and SHALL render correctly in both dark and
light themes.

#### Scenario: Loading
- **WHEN** the presenter reports `isLoading`
- **THEN** a loading indicator is shown instead of the dashboard body

#### Scenario: Theme-aware colors
- **WHEN** the app theme is dark or light
- **THEN** all dashboard surfaces, text, and accents read from `Theme.of(context)` / the app color
  extension and never from hardcoded dark-only or light-only tokens inside widgets

### Requirement: Web companion parity

The web Treasury dashboard SHALL present the same information architecture (net position, month-end
outlook, accounts, net-worth trend, and the analytics cards) aligned to the shipped Nudgr tokens.

#### Scenario: Web dashboard aligned to tokens
- **WHEN** the web Treasury dashboard is shown
- **THEN** its stat tiles, cards, charts, and accents read from the shared web design system / theme
  tokens and match the Nudgr reference's contrast relationships in both light and dark
