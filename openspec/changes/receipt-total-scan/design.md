## Context

The ledger add-transaction flow (`add_transaction_sheet.dart`, opened from
`ledger_view.dart`) already collects amount/date/description/account/category and
owns the save path via `LedgerPresenter`. `image_picker` is installed. There is
no OCR engine yet (the grocery cart only *reserves* `ItemSource.ocr`). The
combined worktree also builds **Flutter web**, where Google ML Kit does not run.

## Goals / Non-Goals

**Goals:**
- One-tap receipt → prefilled Add Transaction sheet (total + date + merchant).
- Pure, unit-tested extraction logic decoupled from the OCR engine.
- Strictly on-device; nothing uploaded.
- Mobile-only without breaking the web build.

**Non-Goals:**
- Full-document OCR, line items, receipt storage, auto-categorize, auto-commit,
  barcode, or any backend/cloud call.

## Decisions

- **Engine: `google_mlkit_text_recognition` (on-device).** Free, private, no
  backend, good at printed receipts. *Alternatives:* cloud vision (rejected —
  the user explicitly wants no document upload and no backend change); Tesseract
  (rejected — heavier, worse on receipts).
- **Split pure parser from the OCR engine.** `lib/utils/receipt_parser.dart`
  takes `List<String>` OCR lines and returns `{total, date?, merchant?}`. This
  is the risky, valuable core and is fully unit-testable with sample receipts,
  with **zero** native dependency. The `ReceiptScannerService` only does
  image_picker + ML Kit → lines, then calls the parser. *Alternative:* parse
  inside the service (rejected — untestable, couples logic to a mobile plugin).
- **Total heuristic.** Rank keyword lines: `amount due` / `grand total` /
  `total due` / `total sales` > `total` (excluding `subtotal`, `total items`,
  `total qty`). Take the monetary value on/near the matched line; ignore
  `cash`/`tender`/`change`. Fallback: the largest plausible monetary value.
  Money regex handles PH formatting (`1,234.00`, optional `₱`/`P`).
- **Date & merchant are best-effort.** Date: common patterns (`MM/DD/YY`,
  `YYYY-MM-DD`, `DD Mon YYYY`, `Mon DD, YYYY`). Merchant: first meaningful line
  near the top (skip pure numbers / `official receipt` / `TIN` / addresses).
  Absence never blocks prefill.
- **Mobile-only isolation.** ML Kit is imported only in `ReceiptScannerService`
  and the scan-button wiring, which are reached only from the mobile ledger. The
  web ledger (`web_ledger_page.dart`) never imports them, so the web build never
  references ML Kit. The pure `receipt_parser.dart` stays platform-neutral (safe
  to import anywhere, including tests).
- **Prefill via existing sheet params.** Pass detected values as initial values
  into `add_transaction_sheet`; reuse its normal save path. *Alternative:* a
  bespoke confirm screen (rejected — duplicates the sheet, breaks "review then
  save" familiarity).
- **Two entry points, one core.** The ledger add-transaction and the grocery
  Finish-trip/checkout both call the same `ReceiptScannerService` + `parseReceipt`;
  they differ only in where the result lands (Add Transaction sheet vs the cart's
  confirmed trip total + log-to-ledger amount). Grocery uses only `total` (+date)
  and never touches cart line items — line-item extraction is the separate
  `grocery-receipt-line-items` change.
- **Speed.** On-device avoids the cloud food-photo round-trip entirely; capture
  at reduced resolution (`image_picker maxWidth`/`imageQuality`) and recognize
  async with an immediate spinner so the shot feels responsive.

## Risks / Trade-offs

- [Wrong total picked (subtotal/cash/VAT)] → keyword ranking + exclusions +
  fallback; and the value is always shown for review before save.
- [Messy/low-contrast receipts OCR poorly] → prefill is best-effort; on low
  confidence the sheet opens with amount empty + a note, never blocking manual
  entry.
- [ML Kit breaks the web build] → keep all ML Kit imports out of web-compiled
  code; add a build check for web after wiring. Pure parser has no native deps.
- [Native binary size / permissions] → ML Kit text recognition is a modest add;
  camera permission requested lazily on first scan.

## Migration Plan

1. Add `google_mlkit_text_recognition`; `flutter pub get`. Add camera permission
   strings (iOS `Info.plist`, Android manifest).
2. Implement `receipt_parser.dart` (pure) + thorough unit tests first.
3. Implement `ReceiptScannerService` (image_picker + ML Kit → lines → parser).
4. Add "Scan receipt" to the mobile ledger add-transaction entry; prefill the
   Add Transaction sheet.
5. Verify Android + iOS run, and that `flutter build web` still compiles;
   `dart format` + `flutter analyze` clean.

Rollback: remove the scan button + service + dependency; `receipt_parser.dart`
is inert pure code. No data/schema touched.

## Open Questions

- Amount sign: default detected total to an **expense** (outflow)? (Lean: yes —
  receipts are purchases; user can flip.)
- Locale for dates/currency: assume PH/`en` first, keep patterns permissive.
