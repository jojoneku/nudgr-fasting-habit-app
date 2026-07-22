## MODIFIED Requirements

### Requirement: Docked quick-log bar stays pinned
The quick-log bar SHALL stay pinned to the bottom of the Hub — it does not scroll away with the
card content — and SHALL operate in two modes from a single bar. In its collapsed state it
continues routing short typed input to nutrition vs. ledger as today (inline quick-log). Tapping or
expanding the bar SHALL open the conversational financial advisor over the Hub without navigating to
a separate screen. Collapsing the advisor SHALL return the bar to its pinned collapsed state.

#### Scenario: Stays put while scrolling
- **WHEN** the Hub card content is scrolled
- **THEN** the quick-log bar remains fixed at the bottom of the screen

#### Scenario: Inline quick-log preserved
- **WHEN** the user types a short logging phrase (e.g. "coffee 120") in the collapsed bar and sends
- **THEN** it routes to the ledger/nutrition quick-log pipeline exactly as before, without opening the advisor

#### Scenario: Expand into the advisor
- **WHEN** the user taps or expands the bar
- **THEN** the conversational financial advisor opens over the Hub and the bar's input drives the conversation

#### Scenario: Collapse back
- **WHEN** the user dismisses or collapses the advisor
- **THEN** the bar returns to its pinned collapsed quick-log state at the bottom of the Hub
