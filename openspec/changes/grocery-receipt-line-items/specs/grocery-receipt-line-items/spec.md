## ADDED Requirements

### Requirement: Extract line items from a grocery receipt

The system SHALL, from a receipt scanned in the grocery cart, extract candidate
line items on-device — each with a name and a price, and quantity/unit when
present — using the shared scanner from `receipt-total-scan`. Header, tax,
subtotal, total, tender, and change lines SHALL be excluded from the items.

#### Scenario: Items parsed from a receipt

- **WHEN** the user scans a grocery receipt listing "EGGS 12 114.00",
  "RICE 5KG 260.00", "COOKING OIL 189.00", plus SUBTOTAL/VAT/TOTAL/CASH/CHANGE
- **THEN** the candidate items are Eggs, Rice, and Cooking oil with their prices
  (and qty/unit where detected), and the SUBTOTAL/VAT/TOTAL/CASH/CHANGE lines are
  not treated as items

#### Scenario: Unparseable price is flagged, not dropped silently

- **WHEN** a line's price cannot be parsed confidently
- **THEN** the row is still surfaced in review with an empty/flagged price for
  the user to fill or discard, rather than being silently omitted

### Requirement: Mandatory review before adding items

Because receipt OCR is fuzzy, the system SHALL present the extracted items in an
editable review step and SHALL add nothing to the cart until the user confirms.
The review SHALL allow editing name/qty/price, discarding rows, and SHALL show a
reconciliation between the summed item prices and the receipt's detected total.

#### Scenario: User reviews then confirms

- **WHEN** the extracted items are shown in the review step
- **THEN** the user can edit or discard any row, and only on explicit confirm are
  the kept rows added to the cart

#### Scenario: Reconciliation against the scanned total

- **WHEN** the summed item prices differ from the receipt's detected total
- **THEN** the review shows the difference so the user can spot a missed or
  mis-read item before confirming

### Requirement: Confirmed items become cart items tagged as OCR

The system SHALL add each confirmed row to the grocery cart as a cart item with
its price marked confirmed and its source set to `ItemSource.ocr`, without
altering items already in the cart.

#### Scenario: Items added with OCR source

- **WHEN** the user confirms the reviewed items
- **THEN** each is appended to the cart with `ItemSource.ocr` and a confirmed
  price, and existing cart items are unchanged

### Requirement: On-device, mobile-only, web build unaffected

Line-item extraction SHALL run on-device only, reuse the `receipt-total-scan`
engine, and SHALL NOT be compiled into or break the Flutter web build; the web
cart SHALL remain unchanged with no line-item scan affordance.

#### Scenario: No line-item scan on web

- **WHEN** the app runs on the web
- **THEN** no line-item scan control is shown and the web build compiles without
  referencing the ML Kit dependency
