## 1. Pure line-item parser (no native deps)

- [ ] 1.1 Add `ReceiptLineItem{name, qty?, unit?, price?}` and `parseReceiptLineItems(List<String> lines)` to `lib/utils/receipt_parser.dart`, excluding header/subtotal/total/tax/tender/change lines and capturing qty/unit patterns
- [ ] 1.2 Unit tests: multi-item receipts, qty/unit forms (`12`, `5kg`, `0.8 kg`, `x2`), unparseable price flagged (not dropped), keyword lines excluded

## 2. Scanner service extension

- [ ] 2.1 Extend `ReceiptScannerService` (from `receipt-total-scan`) to also return the line-item candidates from the same recognized text (single scan → total + items)

## 3. Review sheet

- [ ] 3.1 Build a review sheet listing candidate rows with editable name/qty/price and per-row discard
- [ ] 3.2 Show running sum of kept items vs the scanned total (reconciliation delta)
- [ ] 3.3 Widget test: edit a row, discard a row, and confirm only kept rows are returned

## 4. Cart wiring

- [ ] 4.1 On confirm, append kept rows to the cart via `CartPresenter` as `ItemSource.ocr` with a confirmed price, leaving existing items unchanged
- [ ] 4.2 Add the line-item scan entry point to the grocery cart scan flow (mobile-only; hidden on web)
- [ ] 4.3 Widget test: confirming the review appends OCR-sourced items and does not mutate pre-existing items

## 5. Verify

- [ ] 5.1 `dart format` + `flutter analyze` clean on changed files
- [ ] 5.2 Full test suite green; `flutter build web` succeeds
- [ ] 5.3 Manual smoke on a device: scan a grocery receipt, review/edit items, confirm; verify cart updates and total reconciliation reads correctly
