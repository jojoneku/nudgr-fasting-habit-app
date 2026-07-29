## ADDED Requirements

### Requirement: Shared visual identity with the mobile Treasury

The Treasury web companion SHALL present the same visual identity as the redesigned mobile Treasury
module — the Nudgr palette, Plus Jakarta Sans text, monospaced tabular figures, domain-tinted icon
badges, and the hairline card treatment — while retaining desktop-appropriate layout (sidebar shell,
data tables, multi-column grids).

#### Scenario: Same skin, desktop layout
- **WHEN** a web page and its mobile counterpart are viewed side by side in the same theme mode
- **THEN** cards, figures, badges, and accents read as the same design system
- **AND** the web page keeps its sidebar, tables, and multi-column arrangement rather than adopting
  the phone layout

#### Scenario: Both theme modes
- **WHEN** the shell's theme toggle is switched between light and dark
- **THEN** every ported surface resolves its colors from `Theme.of(context)` / the app theme
  extension and renders correctly in both modes, with no hardcoded per-mode color

### Requirement: Monospaced tabular figures on web

The web companion SHALL render every currency, percentage, and count figure in the monospaced
tabular-figure treatment used by the mobile `AppNumberDisplay`, so digits do not shift position as
values change and figures read as the same type family across platforms.

#### Scenario: Figures do not jitter
- **WHEN** a displayed figure changes to a value with different digit widths
- **THEN** the surrounding layout does not shift, because the figures use tabular numerals

#### Scenario: Applied across surfaces
- **WHEN** any of the stat tiles, mini-stats, data-table amount columns, or chart axis labels render
  a numeric value
- **THEN** that value uses the shared web numeric treatment rather than the default body or headline
  text style

### Requirement: Net-worth hero on the web dashboard

The web dashboard SHALL lead with a net-worth hero matching the mobile hero's composition — the
net-worth figure, a signed month-over-month momentum pill, a "±₱X this month" line, and a sparkline
of the net-worth trend — proportioned for a desktop-width card.

#### Scenario: Hero shows net worth and momentum
- **WHEN** the presenter reports a net worth and at least two net-worth trend points
- **THEN** the hero shows the net-worth figure, a trend pill with the signed month-over-month
  percentage, the "±₱X this month" line, and a sparkline of `netWorthTrend()`

#### Scenario: Sparse history degrades gracefully
- **WHEN** fewer than two net-worth trend points are available
- **THEN** the hero still shows the current net-worth figure and omits, rather than errors on, the
  sparkline and the percentage pill

#### Scenario: Shared sparkline implementation
- **WHEN** the web hero and the mobile hero both render a sparkline
- **THEN** both use the same shared painter rather than duplicate implementations

### Requirement: Cashflow bars on the web dashboard

The web dashboard's cash-flow card SHALL show paired income and expense bars for the current month,
sized relative to the larger of the two flows and each labelled with its amount, matching the mobile
cashflow strip.

#### Scenario: Bars are proportional to the dominant flow
- **WHEN** the current month has income and/or expenses
- **THEN** the dominant flow's bar fills the track and the other is drawn in proportion to it
- **AND** the income bar uses the success accent and the expense bar the danger accent

#### Scenario: Existing card content is preserved
- **WHEN** the bars are added
- **THEN** the card's existing mini-stats (Income, Expenses, Net Flow, Savings Rate) and its
  spent-percentage progress bar remain

### Requirement: Conversational financial advice on web

The web companion SHALL provide the Money Mentor financial advisor, with the behaviors defined by
the `ai-financial-advisor` capability, in a desktop-appropriate docked panel rather than a draggable
bottom sheet.

#### Scenario: Advisor is reachable
- **WHEN** a signed-in user opens the web companion at desktop width
- **THEN** a Money Mentor destination is available in the shell sidebar
- **AND** selecting it opens a docked advisor panel

#### Scenario: Same advisor behavior as mobile
- **WHEN** the user converses with the advisor on web
- **THEN** the advice is grounded in the same live Treasury snapshot, cites figures under the same
  anti-hallucination contract, and offers the same structured financial-position diagnostic as the
  mobile advisor

#### Scenario: Conversation history and memory are shared
- **WHEN** a user holds an advisor conversation on one platform and opens the advisor on the other
- **THEN** the conversation history and the learned advisor memory are the same, having ridden the
  existing sync domains with no new storage keys

#### Scenario: In-conversation logging still confirms before committing
- **WHEN** the advisor proposes logging an expense on web
- **THEN** the proposal is validated against live accounts and categories and routed through the
  existing confirm-before-commit pipeline; no write occurs without explicit user confirmation

#### Scenario: Graceful degradation
- **WHEN** the cloud AI endpoint is unavailable, rate-limited, or the user is signed out
- **THEN** the panel surfaces the same failure states the mobile advisor does and never fabricates
  a response

### Requirement: Receipt-photo logging on web

The web companion SHALL let a user log an expense from a receipt image, feeding the same
confirm-before-commit pipeline the typed Quick Add uses.

#### Scenario: Drag-and-drop a receipt
- **WHEN** the user drops a receipt image onto the receipt surface
- **THEN** the image is read into a pending expense whose amount is the receipt total and whose
  description is the merchant, presented for confirmation before any write

#### Scenario: File-picker fallback
- **WHEN** the user prefers not to drag, or drag-and-drop is unavailable
- **THEN** a file picker offers the same path

#### Scenario: Scan failures are surfaced in place
- **WHEN** the scan returns not-a-receipt, rate-limited, a network error, a server error, or
  unavailable
- **THEN** that outcome is surfaced on the receipt surface itself and no transaction is written

#### Scenario: Nutrition is not reachable from web
- **WHEN** the web receipt surface is built
- **THEN** it offers only the expense path and does not depend on the nutrition presenter or the
  meal-logging branch

### Requirement: Web bundle excludes mobile-only platform dependencies

Adding the advisor and receipt surfaces SHALL NOT introduce any dependency that cannot compile for
the web target.

#### Scenario: Web build succeeds
- **WHEN** `flutter build web -t lib/main_web.dart` is run after these surfaces are wired
- **THEN** the build succeeds

#### Scenario: No mobile-only transitive imports
- **WHEN** the transitive imports of `lib/main_web.dart` are inspected
- **THEN** they include no notification, on-device-model, local food-database, health, or
  home-widget dependency, and no `dart:io` import
