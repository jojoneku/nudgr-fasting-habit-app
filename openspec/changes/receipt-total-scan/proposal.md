## Why

Typing a store purchase into the ledger means reading the receipt and manually
copying the total (and often the date). A one-tap "scan receipt" that reads the
**total, date, and merchant** off a photo and prefills the Add Transaction sheet
removes that friction while keeping the user in control (they review before
saving). The grocery cart already reserves an `ItemSource.ocr` for this class of
feature; this change delivers the first real on-device OCR use.

## What Changes

- Add a **"Scan receipt"** action to the ledger's add-transaction entry (camera
  or gallery via the already-installed `image_picker`).
- Run **on-device** text recognition (Google ML Kit) on the photo — nothing is
  uploaded.
- Extract, best-effort: the **total amount**, the **date**, and the **merchant**
  name, via a pure, testable receipt-parsing utility.
- **Prefill** the existing Add Transaction sheet (amount, date, description =
  merchant) for the user to review, adjust (account/category), and save. Nothing
  is auto-committed.
- Add the **same scan at the grocery cart's Finish trip / checkout** to capture
  the actual receipt **total** (and date) as the confirmed trip total and to
  prefill the "log to ledger" amount — reusing the identical on-device engine
  and parser, just a second entry point.
- On-device OCR is **mobile-only**; the Flutter web build must be unaffected
  (the scanner lives in mobile-only code; web shows no scan button).

## Capabilities

### New Capabilities
- `receipt-scan`: Capture a receipt image and extract the total, date, and
  merchant on-device, then prefill the Add Transaction sheet for review. Covers
  image capture, ML Kit text recognition (mobile-only), the pure total/date/
  merchant parser, and the prefill hand-off.

### Modified Capabilities
<!-- None: the Add Transaction sheet and its save path are unchanged; scanning
     only pre-populates fields the user can already edit. -->

## Non-goals

- Not full-document OCR / receipt archival — only the fields needed to fill a
  transaction / trip total (total, date, merchant). No image storage beyond what
  the transaction flow already does.
- **Line-item extraction into grocery cart items is out of scope here** and is
  deferred to a separate change (`grocery-receipt-line-items`). This change only
  reads the receipt **total** for the grocery entry point.
- No cloud OCR / backend changes; strictly on-device.
- No auto-categorization by merchant and no auto-commit — the user reviews and
  saves.
- No web support for scanning (ML Kit is mobile-only); web ledger/cart unchanged.
- Barcode scanning stays out of scope (the cart's reserved `barcode` source).

## Impact

- **Dependency**: add `google_mlkit_text_recognition` (Android/iOS only).
  `image_picker` is already present.
- **Permissions**: camera usage string — `NSCameraUsageDescription` (iOS);
  `CAMERA` (Android) if launching the camera.
- **Code**:
  - New pure util `lib/utils/receipt_parser.dart` (OCR lines → {total, date?,
    merchant?}) — no I/O, fully unit-tested.
  - New mobile-only `ReceiptScannerService` (services/) wrapping `image_picker`
    + ML Kit, injected.
  - A "Scan receipt" affordance on the ledger add-transaction entry that prefills
    the existing Add Transaction sheet.
  - A "Scan receipt" affordance at the grocery cart Finish trip / checkout that
    sets the confirmed trip total and prefills the ledger-log amount.
- **Platforms**: mobile only; web build must stay green (no ML Kit import in
  web-compiled code).
- **Fast by design**: on-device (no upload round-trip, unlike the cloud food
  photo), reduced capture resolution, async processing with immediate feedback.
