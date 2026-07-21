## 1. Shared sheet scaffolding

- [~] 1.1 Shared chrome: the reference field chrome already lives in `sheet_fields.dart` (`SheetFieldLabel` + `sheetFieldDecoration`), reused by every sheet; the new `NewEntrySheet` adds the grab-handle + title + **type selector** chip row. The full named-widget extraction (SheetHeader/SegmentedToggle/ChipRow/MonthStepper/SaveButton) was **not** done — not needed for the feel; sheets stay consistent via `sheet_fields`. **Deferred (optional polish).**
- [x] 1.2 Due-day picker: the bill's due day is now a dropdown of ordinals ("15th") backed by an `int` (replaces the free-text 1–31 field).

## 2. Per-bill reminder (model + service + presenter)

- [x] 2.1 Additive `Bill.reminderDaysBefore` (`int?`, null = off) — field, `fromJson`/`toJson` (null-tolerant), `copyWith` (sentinel to clear); carried onto recurring copies.
- [x] 2.2 `NotificationService.scheduleBillReminder({billId, billName, dueDate, daysBefore})` + `cancelBillReminder(billId)` (dedicated id range 5000–5999; one-shot N-days-before-due; past-time no-op).
- [x] 2.3 `BillsReceivablesPresenter`: `_syncBillReminder` on `addBill`/`updateBill` (gated by cached global pref); cancel on `deleteBill` and `markBillPaid`.

## 3. Unified New-entry sheet + single FAB

- [x] 3.1 `NewEntrySheet` composes all four type bodies behind a top **type selector** (icon+label chip row: Bill / Receivable / Set-aside / Installment); scrollable; every field of every type preserved (incl. bill due-day picker + reminder toggle); same presenter calls per type.
- [x] 3.2 FAB opens `NewEntrySheet` directly (create, default Bill). Card "Edit" opens the type-specific sheet (inherently locked to type) — each now includes the reference chrome + (bill) the reminder toggle. **Note:** edit uses the standalone typed sheet rather than the unified sheet locked — same "locked to type" effect, lower risk.

## 4. Installment + budgeted bodies

- [x] 4.1 Installment sheet gains an `embedded` mode (keeps its month chips + start-month stepper; behavior identical).
- [x] 4.2 Budgeted set-aside sheet **extracted** to `add_budgeted_expense_sheet.dart` (public) with an `embedded` mode; all fields kept + settled-state preserved on edit.

## 5. Mark / confirm sheets

- [ ] 5.1 Big centered `₱` amount redress of the mark/fund sheets. **Deferred** — they already use the shared `sheet_fields` chrome and all logic is intact; the centered-amount restyle is cosmetic and left for a follow-up.

## 6. Verification

- [ ] 6.1 `dart format` + `flutter analyze` clean. → **Not run (no SDK here).** Reviewed manually; balance-checked.
- [x] 6.2 Model/presenter tests: `bill_reminder_test.dart` (json round-trip, back-compat null, copyWith set/keep/clear); presenter test — `addBill` persists `reminderDaysBefore`. **Not executed here.**
- [x] 6.3 Widget test: `new_entry_sheet_test.dart` — type selector swaps the embedded form (bill→receivable→installment→set-aside). **Not executed here.**
- [ ] 6.4 Regression: existing presenter tests should still pass (changes are additive; edit now *preserves* paid/received state instead of resetting it — an incidental fix). Needs a run.
- [ ] 6.5 Live smoke (both themes): from the FAB pick each of the 4 types and create one; toggle a bill reminder; edit each type; mark a bill paid.
