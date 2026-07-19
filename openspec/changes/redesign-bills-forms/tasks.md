## 1. Shared sheet scaffolding (build first)

- [ ] 1.1 Add reusable pieces under `lib/views/treasury/shared/` (extending `sheet_fields.dart`): `SheetHeader` (grab handle + title + optional trailing), `SheetSegmentedToggle`, `SheetChipRow`, `SheetMonthStepper`, `SheetSaveButton` (blue + glow), `SheetDestructiveButton` (tonal red). Theme tokens only; 44px targets.
- [ ] 1.2 Add a due-day picker widget (`SheetDueDayField`) showing the ordinal ("15th") + caret, backed by an `int` 1–31.

## 2. Per-bill reminder (model + service + presenter)

- [ ] 2.1 Add additive `Bill.reminderDaysBefore` (`int?`, null = off) — field, `fromJson`/`toJson` (null-tolerant), `copyWith` (sentinel so it can be cleared).
- [ ] 2.2 `NotificationService`: add `scheduleBillReminder({billId, name, dueDate, daysBefore})` and `cancelBillReminder(billId)` (per-bill notification id).
- [ ] 2.3 `BillsReceivablesPresenter`: on `addBill`/`updateBill` (re)schedule or cancel the bill's reminder (gated by the global bills-reminder pref); cancel on `deleteBill` and on `markBillPaid`.

## 3. Unified New-entry sheet + single FAB

- [ ] 3.1 Add `NewEntrySheet(type, existing)` composing all four type bodies behind a top **type selector** (icon+label chip row: Bill / Receivable / Set-aside / Installment); scrollable; preserve every field of every type (incl. the bill due-day picker + reminder toggle). Same presenter calls per type; selector hidden/locked in edit mode.
- [ ] 3.2 FAB opens `NewEntrySheet` directly (create mode, default Bill); card long-press "Edit" opens it locked to that record's type. Fold the existing `AddBillSheet`/`AddReceivableSheet`/`AddInstallmentSheet`/budgeted body into the sheet (as per-type bodies or thin reuse).

## 4. Installment + budgeted bodies

- [ ] 4.1 Installment body: recompose onto shared `SheetChipRow` (month chips) / `SheetMonthStepper` (start month) — no behavior change (fields, auto-monthly, edit/delete identical).
- [ ] 4.2 Set-aside body: shared chrome, keeping name, allocated amount, type, note, fund-from account, category.

## 5. Mark / confirm sheets

- [ ] 5.1 Redress `_MarkBillPaidSheet`, `_MarkReceivedSheet`, `_MarkExpensePaidSheet`, `_MarkInstallmentPaidSheet` in the shared chrome with the big centered `₱` amount entry; keep all controllers, account pickers, "already in ledger" toggle, dates, and confirm logic.

## 6. Verification

- [ ] 6.1 `dart format` + `flutter analyze` clean.
- [ ] 6.2 Model/presenter tests: `Bill.reminderDaysBefore` round-trips through json/copyWith; presenter schedules on add/update and cancels on delete/mark-paid.
- [ ] 6.3 Widget tests: `NewEntrySheet` (type selector swaps field sets; Save calls the right add/update; edit opens locked to type; reminder toggle shows only for Bill); `SheetSegmentedToggle`/`SheetChipRow`/`SheetMonthStepper`/`SheetDueDayField`; each mark sheet still submits.
- [ ] 6.4 Regression: existing presenter tests pass; every field/flow that existed before still exists (no field dropped).
- [ ] 6.5 Live smoke (both themes): from the FAB pick each of the 4 types and create one; toggle a bill reminder; edit each type; mark a bill paid.
