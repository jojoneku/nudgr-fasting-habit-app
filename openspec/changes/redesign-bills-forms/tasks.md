## 1. Shared sheet scaffolding (build first)

- [ ] 1.1 Add reusable pieces under `lib/views/treasury/shared/` (extending `sheet_fields.dart`): `SheetHeader` (grab handle + title + optional trailing), `SheetSegmentedToggle`, `SheetChipRow`, `SheetMonthStepper`, `SheetSaveButton` (blue + glow), `SheetDestructiveButton` (tonal red). Theme tokens only; 44px targets.
- [ ] 1.2 Add a due-day picker widget (`SheetDueDayField`) showing the ordinal ("15th") + caret, backed by an `int` 1–31.

## 2. New-entry sheet (Bill / Receivable)

- [ ] 2.1 Add `NewEntrySheet(mode, existing)` merging `AddBillSheet` + `AddReceivableSheet`: segmented *Bill to pay / Money owed me* toggle swapping field sets; preserve every field (bill: type, amount, due-day picker, pay-from, category chips, payment note, recurring; receivable: type, expected amount, expected date, account, category chips, recurring). Same presenter calls; toggle locked in edit mode.
- [ ] 2.2 Route the FAB's *Add Bill* / *Add Receivable* (and card long-press "Edit") to `NewEntrySheet` pre-set to the right mode. Remove the now-duplicated standalone sheets (or make them thin wrappers).

## 3. Installment sheet

- [ ] 3.1 Recompose `AddInstallmentSheet` onto the shared `SheetHeader` / `SheetChipRow` (month chips) / `SheetMonthStepper` (start month) — no behavior change (fields, auto-monthly, edit/delete all identical).

## 4. Budgeted set-aside sheet

- [ ] 4.1 Redress `_AddBudgetedExpenseSheet` in the shared chrome (header, labels, field boxes, category chips, Save/Delete), keeping name, allocated amount, type, note, fund-from account, category.

## 5. Mark / confirm sheets

- [ ] 5.1 Redress `_MarkBillPaidSheet`, `_MarkReceivedSheet`, `_MarkExpensePaidSheet`, `_MarkInstallmentPaidSheet` in the shared chrome with the big centered `₱` amount entry; keep all controllers, account pickers, "already in ledger" toggle, dates, and confirm logic.

## 6. Verification

- [ ] 6.1 `dart format` + `flutter analyze` clean.
- [ ] 6.2 Widget tests: `NewEntrySheet` (toggle swaps fields; Save calls add/update for the right type; edit opens locked in mode); `SheetSegmentedToggle` / `SheetChipRow` / `SheetMonthStepper` / `SheetDueDayField` behavior; each mark sheet still submits.
- [ ] 6.3 Regression: existing presenter tests still pass; every field/flow that existed before still exists (no field dropped).
- [ ] 6.4 Live smoke (both themes): add a bill, toggle to receivable and add one, edit each, add an installment, fund a set-aside, mark a bill paid.
