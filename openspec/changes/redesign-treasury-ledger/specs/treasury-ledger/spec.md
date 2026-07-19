## ADDED Requirements

### Requirement: Category-specific transaction icons

The Ledger transaction row SHALL render a representative icon for each entry, taken from the
category's chosen icon when set and otherwise inferred from the category name, so the list matches the
Nudgr reference's per-category iconography.

#### Scenario: User-chosen category icon
- **WHEN** a non-transfer transaction's category has an explicitly chosen catalog icon
- **THEN** the row's leading badge shows that icon in the category's color

#### Scenario: Known category name (no explicit icon)
- **WHEN** the category has no explicit icon but its name matches a known keyword (e.g. "Groceries",
  "Food", "Transport", "Salary")
- **THEN** the badge shows the corresponding heuristic Material glyph (cart, fork-knife, car,
  briefcase) in the category's color

#### Scenario: Unknown category name
- **WHEN** a category has no explicit icon and its name matches no keyword
- **THEN** the badge shows a sensible per-type fallback glyph (income vs expense) rather than an
  error or a blank icon

#### Scenario: Transfer entry
- **WHEN** the transaction is an internal transfer
- **THEN** the badge shows the transfer (swap) glyph, unchanged

#### Scenario: Row behavior preserved
- **WHEN** the redesigned row is shown
- **THEN** its title, subtitle, amount, tap-to-edit, long-press actions, and swipe/undo delete all
  behave exactly as before

### Requirement: Settable category icons

Users SHALL be able to choose a category's icon from a fixed catalog in the Manage Categories sheet,
and the choice SHALL persist without a data migration.

#### Scenario: Pick an icon
- **WHEN** the user opens the icon picker for a category (on the add form or an existing category) and
  selects a catalog icon
- **THEN** the choice is saved to the category and every Ledger row for that category shows the chosen
  icon

#### Scenario: Auto (name-derived) option
- **WHEN** the user selects the "Auto" option
- **THEN** the category stores the auto sentinel and its rows render the name-heuristic glyph

#### Scenario: Legacy category, no migration
- **WHEN** a category created before the picker existed is displayed (its stored icon is not a catalog
  key)
- **THEN** it renders via the name heuristic with no error and no migration step

### Requirement: Reference header and controls layout

The Ledger SHALL present a `Ledger` title row, then a single controls row with the Filter & sort pill
and the month/year pill in line, then the cash-flow strip — matching the reference.

#### Scenario: Header arrangement
- **WHEN** the Ledger tab is shown
- **THEN** the `Ledger` title is left-aligned on its own row, and below it the Filter & sort pill (left)
  and the month/year pill (right) sit on one row

#### Scenario: Controls behavior preserved
- **WHEN** the user taps the Filter & sort pill or the month/year pill
- **THEN** the existing Filter & sort sheet / month-grid popover open, and the day filter remains
  inside the Filter & sort sheet

#### Scenario: Ledger owns the top (no duplicate title)
- **WHEN** the Ledger tab is active in the Treasury module
- **THEN** the module's shared "TREASURY" app bar is hidden so the Ledger's own "Ledger" title is the
  only top title, and the Ledger content still clears the status bar

#### Scenario: Controls never overflow
- **WHEN** the screen is narrow and a filter is active with a long month label
- **THEN** the Filter & sort pill label ellipsizes rather than overflowing the row

### Requirement: Segmented cash-flow strip

The Ledger SHALL show a single segmented IN / OUT / NET card fed by the month's filtered totals.

#### Scenario: Strip values and colors
- **WHEN** the month has income and expenses
- **THEN** the strip shows IN (green), OUT (red), and NET (blue) in three equal columns, with NET
  carrying a `+`/`−` prefix and turning red when the month is in deficit

### Requirement: "No background" transaction rows

The Ledger rows SHALL render without a per-row card fill, with the category identity carried by the
colored icon and the subtitle showing the account.

#### Scenario: Row composition
- **WHEN** a transaction row is shown
- **THEN** it has no card background, a color-tinted category icon badge, the description as title, the
  account name as subtitle, and a semantically-colored amount (expense red, income green, transfer
  neutral grey)

#### Scenario: Account-less transaction
- **WHEN** a transaction has no account
- **THEN** the subtitle falls back to the category name so it is never blank

### Requirement: Chat logging retained

The Ledger SHALL keep its chat/AI transaction logging, restyled to the reference, without voice input.

#### Scenario: Chat logging works
- **WHEN** the user types a transaction into the chat input and sends
- **THEN** the existing parse/clarify/commit flow runs and the input pill and send button use the
  taller reference styling; no voice/microphone affordance is present

### Requirement: Theme-aware ledger rows

The Ledger SHALL read all colors from the theme so it renders correctly in dark and light.

#### Scenario: Theme correctness
- **WHEN** the app theme is dark or light
- **THEN** the header, strip, badges, icons, text, and amounts read from `Theme.of(context)` / the app
  color extension, never from hardcoded per-mode tokens
