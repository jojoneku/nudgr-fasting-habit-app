## 1. Sheet chrome + type toggle

- [ ] 1.1 Add grab handle + bold title ("New transaction" / "Edit transaction") via the shared
  `SheetHandle` / `SheetTitle`.
- [ ] 1.2 Replace the type selector with a 3-way `SheetSegmentedToggle<TransactionType>` (expense=red,
  income=green, transfer=blue); switching swaps the type-specific fields.

## 2. Fields → reference kit

- [ ] 2.1 Amount as the emphasized `₱` field box (keep `amountInputFormatters` + `> 0` validator).
- [ ] 2.2 Account (expense/income) and From / To (transfer) as `SheetAccountField` + `showAccountPicker`
  (`allowNone: false`).
- [ ] 2.3 Category as a `SheetPickerBox` "Category (optional)" opening a category picker (expense vs
  income by type; reuse `resolveCategoryBadge`); preserve tap-to-clear.
- [ ] 2.4 Date as a `SheetPickerBox` (calendar icon) → `showDatePicker`.
- [ ] 2.5 Description + note fields restyled to the kit.

## 3. Reimbursable section (outflow only)

- [ ] 3.1 Restyle the reimbursable switch + "owed by" field + expected-reimbursement date picker;
  preserve loading the expected date from the linked receivable on edit.

## 4. Preserve all behavior

- [ ] 4.1 Save branches verbatim: transfer (`deleteTransactionOrGroup` on edit + `addTransfer`),
  reimbursable outflow (`addReimbursableExpense` / reuse linked id on edit), else
  `addTransaction` / `updateTransaction`.
- [ ] 4.2 Chat `prefill` mapping, `existing` edit (incl. transfer-group reconstruction), and the
  `initialDate` (log-on-filtered-day) path all unchanged.

## 5. Verification

- [ ] 5.1 `dart format` + `flutter analyze` clean; widget tests: expense save, income save, transfer
  save (two legs), reimbursable save (receivable spawned), edit of each, prefill open — each produces
  the same records as today.
- [ ] 5.2 Live smoke (dark + light): log expense/income/transfer; edit each; reimbursable flow;
  category clear; date pick; log onto a filtered past day.
