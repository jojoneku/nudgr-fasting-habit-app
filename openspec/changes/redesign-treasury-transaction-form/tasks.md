## 1. Sheet chrome + type toggle

- [~] 1.1 Grab handle + title — **N/A here**: the sheet is launched via `AppBottomSheet.show(title:…)`,
  which already provides the handle + title chrome; adding them in-sheet would duplicate it.
- [x] 1.2 Replaced the type selector with a 3-way `SheetSegmentedToggle<TransactionType>` (inflow=green,
  outflow=red, transfer=blue); the existing per-type field-swapping is unchanged. Removed the old
  `_TypeButton`.

## 2. Fields → reference kit

- [x] 2.1 Amount already the emphasized `₱` field box (`sheetFieldDecoration(emphasize: true)`) — kept.
- [x] 2.2 Account and From / To (transfer) now `SheetAccountField` + `showAccountPicker` (badge + name +
  caret; `allowNone: false`). The required-account check moved from the dropdown validator to a
  submit-time SnackBar ("Select an account" / "Select a destination account").
- [ ] 2.3 Category as a picker box — **kept as chips** (deliberate): the existing tap-to-select /
  tap-to-clear chip group shows all options at once and is lower-risk; same choice bills-page made.
- [x] 2.4 Date — kept the existing compact `_DatePickerRow` (already a reference-style caret/box row).
- [x] 2.5 Description + note already use `sheetFieldDecoration` — kept.

## 3. Reimbursable section (outflow only)

- [x] 3.1 Kept as-is (already uses the field decoration; outflow-only; loads the expected date from the
  linked receivable on edit). No logic touched.

## 4. Preserve all behavior

- [x] 4.1 Save branches untouched: transfer (`deleteTransactionOrGroup` + `addTransfer`), reimbursable
  outflow (`addReimbursableExpense` / reuse linked id), else `addTransaction` / `updateTransaction`.
- [x] 4.2 Chat `prefill`, `existing` edit (incl. transfer-group reconstruction), and the `initialDate`
  path all unchanged (the reskin only touched two presentational widgets + a guard message).

## 5. Verification

- [ ] 5.1 `dart format` + `flutter analyze` + tests → **CI** (no local Flutter toolchain). Balances,
  imports, kit-symbol definitions, and constructor names hand-verified; no widget test drives the
  sheet so none is affected.
- [ ] 5.2 Live smoke (dark + light): log expense/income/transfer; edit each; reimbursable flow;
  category clear; date pick; account picker; log onto a filtered past day. → Deferred to device.

## Notes

This was a **contained reskin in place** (not a rewrite): only `_TypeToggle` and `_AccountDropdown`
changed presentationally, plus a submit-guard SnackBar. All state, `_submit` branching, prefill/edit,
and the reimbursable flow are byte-for-byte the same. Category/date/reimbursable kept their current
(already field-box-styled) controls to avoid risk on the busiest form. The shared sheet kit
(`SheetSegmentedToggle`, `SheetAccountField`, `showAccountPicker`) was added to this branch's
`sheet_fields.dart`.
