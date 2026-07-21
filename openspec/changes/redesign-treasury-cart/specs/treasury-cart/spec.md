## ADDED Requirements

### Requirement: Price-state accents match the reference

The Cart tab SHALL colour each item's price state to match the Nudgr reference: confirmed prices
neutral, estimated (remembered) prices in the blue domain accent, and unpriced items in the danger
accent — read from theme tokens.

#### Scenario: Estimated price
- **WHEN** an item has a remembered (not-yet-confirmed) price
- **THEN** its subtitle ("~₱X · tap to confirm"), the running-total "~₱X est" chip, and its line total
  render in the blue domain accent

#### Scenario: Confirmed and unpriced
- **WHEN** an item's price is confirmed (or missing)
- **THEN** a confirmed price renders neutral and an unpriced item renders in the danger accent, as
  before

### Requirement: Cart behavior preserved

The redesign SHALL retain all Cart functionality.

#### Scenario: Cart intact
- **WHEN** the Cart tab is used
- **THEN** the running-total header + budget bar, −/+ quantity steppers, add/set-price/set-budget,
  finish-trip checkout (with optional ledger posting), trip history, clear, and swipe-to-remove +
  undo all behave as before
