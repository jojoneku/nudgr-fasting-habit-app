## 1. Shared sheet form kit

- [ ] 1.1 Add reference sheet building blocks (in `sheet_fields.dart` or a new `sheet_kit.dart`):
  `SheetHandle`, `SheetTitle`, `SheetSegmentedToggle` (accent-filled selected segment),
  `SheetPickerField` (label + 52px bordered box + trailing caret), `SheetAccountField` (mini
  `AccountBadge` + name + caret). All theme-aware.
- [ ] 1.2 Standardize the field box: height ~52, radius 12, `bg-input`, 1px border; fold the legacy
  receivable date box (56/rad 8) into `SheetPickerField`.
- [ ] 1.3 Account picker bottom-sheet (list of accounts via `AccountBadge`; supports a nullable
  "Ask me when received" / "None" option). Reused by every account field.

## 2. Unified New-entry sheet (Bill + Receivable)

- [ ] 2.1 Create `entry_sheet.dart` with a `SheetSegmentedToggle` Bill / Receivable `_kind`
  (bills-orange vs receivable-green accent); one `Form`.
- [ ] 2.2 Common fields: name, amount (`₱`, emphasized), category (tap-select/clear), account
  (`SheetAccountField`), recurring switch + recurrence picker.
- [ ] 2.3 Bill-only fields: bill type (7-type chip group), due day (1–31), payment note — carry over
  `_resolvePaymentNote` auto-statement handling verbatim; default account to first.
- [ ] 2.4 Receivable-only fields: receivable type (4), expected date (`SheetPickerField` → date
  picker), destination account with the "Ask me when received" (null) option.
- [ ] 2.5 Save routes to `addBill`/`updateBill` or `addReceivable`/`updateReceivable` by `_kind`;
  edit opens locked to the entry's kind (toggle disabled). Preserve all validators + defaults.
- [ ] 2.6 Update entry points (FAB / section "+" in `bills_receivables_view.dart`) to open
  `entry_sheet.dart` with the initial kind; remove `add_bill_sheet.dart` / `add_receivable_sheet.dart`.

## 3. Installment sheet

- [ ] 3.1 Restyle `add_installment_sheet.dart` to the kit (handle/title already present): align labels,
  field boxes, `SheetAccountField`, months chip-picker, start-month stepper, note. No logic change
  (name, account required, total, months 3/6/12/24 + custom, monthly auto-compute + manual override,
  start month, note).

## 4. Verification

- [ ] 4.1 `dart format` + `flutter analyze` clean; widget tests: bill save, receivable save, edit
  opens locked to kind, installment save — each produces the same model object as the old sheets.
- [ ] 4.2 Live smoke (dark + light): add a bill, add a receivable via the toggle, edit each, add an
  installment; verify account picker, date picker, recurrence, and category clear all still work.
