## ADDED Requirements

### Requirement: Category-specific transaction icons

The Ledger transaction row SHALL render a representative icon for each entry, inferred from the
category, so the list matches the Nudgr reference's per-category iconography.

#### Scenario: Known category name
- **WHEN** a non-transfer transaction's category name matches a known keyword (e.g. "Groceries",
  "Food", "Transport", "Salary")
- **THEN** the row's leading badge shows the corresponding Material glyph (cart, fork-knife, car,
  briefcase) in the category's color

#### Scenario: Unknown category name
- **WHEN** a category name matches no keyword
- **THEN** the badge shows a sensible per-type fallback glyph (income vs expense) rather than an
  error or a blank icon

#### Scenario: Transfer entry
- **WHEN** the transaction is an internal transfer
- **THEN** the badge shows the transfer (swap) glyph, unchanged from today

#### Scenario: Row behavior preserved
- **WHEN** the redesigned row is shown
- **THEN** its title, category·account subtitle with the account color dot, signed/colored amount,
  tap-to-edit, long-press actions, and swipe/undo delete all behave exactly as before

### Requirement: Theme-aware ledger rows

The Ledger rows SHALL read all colors from the theme so they render correctly in dark and light.

#### Scenario: Theme correctness
- **WHEN** the app theme is dark or light
- **THEN** the badge, icon, text, and amount colors read from `Theme.of(context)` / the app color
  extension, never from hardcoded per-mode tokens
