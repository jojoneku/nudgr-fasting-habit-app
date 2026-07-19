## 1. Shared sheet form kit

- [x] 1.1 Added reference sheet building blocks to `sheet_fields.dart`: `SheetHandle`, `SheetTitle`,
  `SheetSegmentedToggle` (accent-filled selected segment), `SheetAccountField` (mini `AccountBadge` +
  name + caret) — on top of the existing `SheetPickerBox`/`SheetFieldLabel`/`sheetFieldDecoration`.
  All theme-aware.
- [x] 1.2 Field boxes standardized on radius 12 / `bg-input` (`SheetPickerBox` height 48;
  `sheetFieldDecoration` padded to match); the legacy receivable date box (56/rad 8) is now a
  `SheetPickerBox`.
- [x] 1.3 Account picker bottom-sheet (`showAccountPicker` → `AccountChoice`): list via `AccountBadge`
  with a nullable "None" / "Ask me when received" option. Reused by every account field.

## 2. Unified New-entry sheet (Bill + Receivable)

- [x] 2.1 Created `entry_sheet.dart` with a `SheetSegmentedToggle` Bill / Receivable `_kind`
  (bills-orange vs receivable-green accent); one `Form`.
- [x] 2.2 Common fields: name, amount (`₱`, emphasized), category (tap-select/clear), account
  (`SheetAccountField`), recurring switch + recurrence picker.
- [x] 2.3 Bill-only fields: bill type (7-type chip group), due day (1–31), payment note — carried over
  `_resolvePaymentNote` auto-statement handling verbatim; default account to first.
- [x] 2.4 Receivable-only fields: receivable type (4), expected date (`SheetPickerBox` → date picker),
  destination account with the "Ask me when received" (null) option.
- [x] 2.5 Save routes to `addBill`/`updateBill` or `addReceivable`/`updateReceivable` by `_kind`;
  edit opens locked to the entry's kind (toggle disabled). All validators + defaults preserved.
- [x] 2.6 Entry points (`_showAddBillSheet`/`_showAddReceivableSheet` in `bills_receivables_view.dart`)
  now open `entry_sheet.dart` with the initial kind; `add_bill_sheet.dart` / `add_receivable_sheet.dart`
  deleted.

## 3. Installment sheet

- [x] 3.1 Restyled `add_installment_sheet.dart` account field to `SheetAccountField` + `showAccountPicker`
  (with a "Required" inline error preserving the old validator's intent); handle/title/labels/months
  chip-picker/start-month stepper/note unchanged; no logic change.

## 4. Verification

- [ ] 4.1 `dart format` + `flutter analyze` clean; widget tests (bill save, receivable save, edit
  opens locked to kind, installment save). → Runs on CI (no local Flutter in the authoring env).
  Logic ported verbatim; balances/imports/constructor names hand-verified. Widget tests to be added
  where they can be executed (mocked `StorageService`).
- [ ] 4.2 Live smoke (dark + light): add a bill, add a receivable via the toggle, edit each, add an
  installment; verify account picker, date picker, recurrence, and category clear all still work.
  → Deferred to device/emulator run.
