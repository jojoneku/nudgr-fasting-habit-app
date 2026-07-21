## Context

`receipt-total-scan` introduces an on-device `ReceiptScannerService` (image →
ML Kit → text lines) and a pure `receipt_parser.dart` that reads the total/date/
merchant. The grocery cart (`grocery_cart_view.dart`, `CartPresenter`,
`cart_item.dart`) already models items with a name, price, qty/unit, a
confirmed/estimate price state, and a reserved `ItemSource.ocr`. This change
adds per-line-item extraction on top of the same scanner, feeding a review step
that appends confirmed rows as cart items.

## Goals / Non-Goals

**Goals:**
- Turn a scanned grocery receipt into candidate cart items on-device.
- Make review mandatory and forgiving (OCR is fuzzy); reconcile to the total.
- Reuse the `receipt-total-scan` engine/parser; keep the web build green.

**Non-Goals:**
- No cloud OCR/backend, no general table parser, no barcode.
- Not a replacement for the total capture; it complements it.
- No auto-confirm — nothing enters the cart without the user's OK.

## Decisions

- **Extend the pure parser, don't fork it.** Add `parseReceiptLineItems(lines)`
  to (or beside) `receipt_parser.dart`, returning `List<ReceiptLineItem>{name,
  qty?, unit?, price?}`. Pure and unit-testable with sample receipts, no native
  dep. The scanner service simply calls it in addition to `parseReceipt`.
  *Alternative:* a separate parser module (rejected — duplicates tokenizing and
  the exclusion rules for total/subtotal/tax/tender lines).
- **Line model & exclusions.** A line is a candidate item when it has a name-ish
  token and a trailing money value and is NOT a keyword line (`subtotal`, `total`,
  `amount due`, `vat`/`tax`, `cash`/`tender`, `change`, `qty`, `items`). Quantity
  patterns (`12`, `5kg`, `0.8 kg`, `x2`) captured when present.
- **Mandatory review sheet.** A dedicated review sheet lists candidate rows
  (editable name/qty/price, per-row discard) with a running sum vs the scanned
  total. Confirming appends kept rows via `CartPresenter` as
  `ItemSource.ocr`, price state = confirmed. *Alternative:* add directly then let
  the user clean up (rejected — dumps fuzzy rows into the real cart).
- **Reuse total capture.** The same scan yields both the total (for
  reconciliation / trip total) and the item candidates, so the user scans once.
- **Mobile-only isolation.** Line-item parsing lives with the pure parser
  (platform-neutral, testable), while the ML Kit call stays in the mobile-only
  `ReceiptScannerService`; the web cart never imports it.

## Risks / Trade-offs

- [Per-item OCR is unreliable — wrong names/prices, split/merged lines] →
  mandatory editable review + total reconciliation surfaces mistakes before
  anything is added; rows are never auto-committed.
- [Qty/unit formats vary wildly] → qty/unit are best-effort; a row with just
  name+price is still valid, quantity defaults to 1.
- [Scope creep toward a full receipt parser] → strictly grocery receipts, items
  only; totals/tax handled by `receipt-total-scan`.
- [Web build breakage] → no ML Kit import in web-compiled code; the parser is
  pure. Verify `flutter build web` after wiring.

## Migration Plan

1. Land `receipt-total-scan` first (or together) — this depends on its scanner.
2. Add `parseReceiptLineItems` + `ReceiptLineItem` to the pure parser; unit-test.
3. Extend `ReceiptScannerService` to also return line-item candidates.
4. Add the review sheet; wire "confirm" → `CartPresenter` append (`ItemSource.ocr`).
5. Add the entry point from the grocery cart's scan flow (mobile-only).
6. Verify Android/iOS run + `flutter build web`; `dart format` + `analyze` clean.

Rollback: remove the review sheet + line-item parsing + entry point. Total
capture (`receipt-total-scan`) and the cart are unaffected.

## Open Questions

- Reconcile-to-total: just display the delta, or offer to add an "unaccounted"
  adjustment row? (Lean: display only for v1.)
- Qty semantics for weighted goods (e.g. "0.8 kg"): store as qty=0.8, unit="kg"
  vs qty=1 priced line? (Lean: qty+unit when a unit is detected.)
