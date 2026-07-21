## 1. Pure parser first (no native deps)

- [ ] 1.1 Add `lib/utils/receipt_parser.dart`: `parseReceipt(List<String> lines) → ReceiptScan{total, date?, merchant?}`, with money/date regexes and the total keyword-ranking + exclusion heuristic
- [ ] 1.2 Unit tests with several real-shaped PH receipts (labeled total vs subtotal/cash/change; VAT lines; missing date/merchant; `₱`/`P`/no-symbol; thousands separators)

## 2. Dependency & platform setup

- [ ] 2.1 Add `google_mlkit_text_recognition` to `pubspec.yaml`; `flutter pub get`
- [ ] 2.2 Add camera permission strings (iOS `NSCameraUsageDescription`; Android `CAMERA`)
- [ ] 2.3 Confirm `flutter build web` still compiles (ML Kit not referenced in web-compiled code)

## 3. Scanner service (mobile-only I/O)

- [ ] 3.1 Add `ReceiptScannerService` in `lib/services/`: pick/capture image (`image_picker`) → ML Kit `TextRecognizer` → lines → `parseReceipt`; expose a status (`unavailable`/`denied`/`ok`) + result
- [ ] 3.2 Guard so the service and its ML Kit import are never reached from web-compiled code

## 4. Ledger wiring + prefill

- [ ] 4.1 Add a "Scan receipt" affordance to the mobile ledger add-transaction entry (hidden on web)
- [ ] 4.2 On a successful scan, open the existing Add Transaction sheet prefilled: amount = total (as an expense), date = detected date, description = merchant; leave account/category to the user
- [ ] 4.3 Handle low-confidence total (sheet opens, amount empty + brief note) and camera-permission-denied (non-blocking message; manual flow intact)
- [ ] 4.4 Widget test: a stubbed scan result prefills the sheet correctly and does not auto-commit

## 5. Grocery cart entry point (total only)

- [ ] 5.1 Add a "Scan receipt" affordance at the grocery cart Finish trip / checkout (hidden on web)
- [ ] 5.2 On a successful scan, set the confirmed trip total from the detected total and prefill the log-to-ledger amount; do NOT add or modify cart line items
- [ ] 5.3 Widget test: a stubbed scan sets the trip total and leaves cart items unchanged

## 6. Performance

- [ ] 6.1 Capture at reduced resolution (`image_picker` `maxWidth`/`imageQuality`) and recognize asynchronously with an immediate spinner so the shot feels responsive

## 7. Verify

- [ ] 7.1 `dart format` + `flutter analyze` clean on changed files
- [ ] 7.2 Full test suite green; `flutter build web` succeeds
- [ ] 7.3 Manual smoke on a device: scan a real receipt in both the ledger and grocery entry points; confirm prefill/trip-total and that saving is a deliberate step
