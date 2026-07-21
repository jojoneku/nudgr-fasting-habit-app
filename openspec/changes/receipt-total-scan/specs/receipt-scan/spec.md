## ADDED Requirements

### Requirement: Capture a receipt and prefill a transaction

The system SHALL let the user scan a receipt (camera or gallery) from the
ledger add-transaction entry, extract the total, date, and merchant on-device,
and open the Add Transaction sheet prefilled with those values for review. The
transaction SHALL NOT be committed automatically.

#### Scenario: Successful scan prefills the sheet

- **WHEN** the user taps "Scan receipt" and selects a legible receipt photo
- **THEN** on-device text recognition runs and the Add Transaction sheet opens
  with the amount set to the detected total, the date set to the detected date
  (when found), and the description set to the merchant (when found)
- **AND** the user can edit any field and must explicitly save to commit

#### Scenario: Total not confidently detected

- **WHEN** the scan cannot confidently determine a total
- **THEN** the sheet still opens (amount left empty or best guess), a brief note
  indicates the total was not detected, and the user can enter it manually

### Requirement: On-device total/date/merchant extraction

The system SHALL determine the total by preferring lines labeled as the payable
total (e.g. "TOTAL", "AMOUNT DUE", "TOTAL DUE", "GRAND TOTAL", "TOTAL SALES")
over subtotals, and SHALL ignore tendered/change/subtotal lines; when no labeled
total is found it MAY fall back to the largest plausible monetary value. Date
and merchant extraction are best-effort and SHALL NOT block prefill when absent.

#### Scenario: Labeled total is preferred over subtotal and cash

- **WHEN** a receipt contains "SUBTOTAL 1,180.00", "TOTAL 1,234.00",
  "CASH 1,500.00", "CHANGE 266.00"
- **THEN** the extracted total is 1,234.00 (not the subtotal, cash, or change)

#### Scenario: Merchant and date are optional

- **WHEN** the receipt has no parseable date or merchant
- **THEN** the amount is still prefilled and the date/description are left to the
  user without any error

### Requirement: Capture the trip total in the grocery cart

The system SHALL offer the same on-device receipt scan at the grocery cart's
Finish trip / checkout, using it to capture the receipt **total** (and date) as
the confirmed trip total and to prefill the amount when the trip is logged to
the ledger. Scanning here SHALL reuse the same engine and parser and SHALL NOT
add or modify cart line items (line-item extraction is a separate change).

#### Scenario: Scan sets the confirmed trip total at checkout

- **WHEN** the user taps "Scan receipt" at Finish trip and selects a legible
  receipt photo
- **THEN** the detected total becomes the confirmed trip total and prefills the
  log-to-ledger amount for review, without changing any cart line items

#### Scenario: Scan does not touch cart items

- **WHEN** a receipt is scanned in the grocery cart
- **THEN** only the total (and optionally date) is used; existing cart items and
  their prices are left unchanged

### Requirement: Mobile-only, web build unaffected

On-device receipt scanning SHALL be available only on mobile platforms, and its
code SHALL NOT be compiled into or break the Flutter web build; the web ledger
SHALL remain unchanged and show no scan affordance.

#### Scenario: No scan control on web

- **WHEN** the app runs on the web (Treasury web)
- **THEN** no receipt-scan control is shown and the web build compiles without
  referencing the ML Kit dependency

#### Scenario: Camera permission denied

- **WHEN** the user denies camera permission
- **THEN** the app shows a brief, non-blocking message and the manual Add
  Transaction flow remains fully usable
