## 1. Shared field kit

- [x] 1.1 Add `lib/views/treasury/shared/sheet_fields.dart` with `SheetFieldLabel`,
      `sheetFieldDecoration`, `SheetPickerBox` (byte-identical to the Bills-page kit's shared parts).

## 2. Restyle the Set / Edit Budget sheet

- [x] 2.1 Category / savings-account picker box + bottom-sheet list (with a "New category…" row that
      keeps the create-category dialog). Preselected mode shows a locked read-only box.
- [x] 2.2 Emphasized ₱ Budget amount field via `sheetFieldDecoration(emphasize: true)`.
- [x] 2.3 BUDGET GROUP / BUDGET TYPE under `SheetFieldLabel`, still `AppSegmentedControl`; keep the
      expense↔savings crossing reset. Preserve `setBudget`, validation, and remove-budget.

## 3. Verification

- [ ] 3.1 `dart format` + `flutter analyze` clean. → Not run here (no Flutter toolchain); run before merge.
- [ ] 3.2 Manual smoke (dark + light): set a new expense budget, create a category from the picker, edit
      an existing budget from a card, switch group to Savings (target resets, savings accounts listed),
      remove a budget.
