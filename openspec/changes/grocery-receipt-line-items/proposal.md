> Builds on `receipt-total-scan` (shared on-device scanner + parser). Land that
> change first, or the two together.

## Why

`receipt-total-scan` reads a receipt's **total** into a transaction or grocery
trip total. A natural follow-up is to also read the receipt's **line items**
(name + price + qty) and add them to the grocery cart, so a finished shopping
trip can be reconstructed from the receipt instead of entered by hand. This is
deferred because per-item OCR is materially harder and less reliable than
reading a single labeled total.

## What Changes

- After a receipt scan in the grocery cart, parse individual line items
  (description, unit/qty, price) and let the user add/confirm them as cart items
  (`ItemSource.ocr`, already reserved in `cart_item.dart`).
- Provide a review step (the OCR is fuzzy): editable rows, easy discard, and a
  reconciliation against the scanned total.

## Capabilities

### New Capabilities
- `grocery-receipt-line-items`: Extract per-line items from a receipt image
  on-device and add them (after review) as grocery cart items.

### Modified Capabilities
<!-- Likely builds on receipt-scan; TBD when specced. -->

## Non-goals

- No cloud OCR / backend. Reuses the on-device engine from `receipt-total-scan`.
- Not a general document/table parser — grocery receipts only.
- Does not replace `receipt-total-scan`'s total capture; complements it.

## Impact

- Depends on `receipt-total-scan` (shared `ReceiptScannerService` + parser).
- New line-item parsing heuristics + a cart review UI. Real effort; scope and
  reliability to be assessed when this change is specced.
