## 1. Shared field kit

- [x] 1.1 Adopt the consolidated `sheet_fields.dart` (full 407-line kit) + `account_badge_widget.dart`
      + `utils/account_badge.dart`, byte-identical to the other treasury redesign branches, so the kit
      is shared and merges cleanly.

## 2. Restyle the Set / Edit Budget sheet

- [x] 2.1 Category / savings-account picker box + bottom-sheet list (with a "New category…" row that
      keeps the create-category dialog). Preselected mode shows a locked read-only box.
- [x] 2.2 Emphasized ₱ Budget amount field via `sheetFieldDecoration(emphasize: true)`.
- [x] 2.3 BUDGET GROUP / BUDGET TYPE under `SheetFieldLabel` using the kit's `SheetSegmentedToggle`
      (full labels, no truncation); keep the expense↔savings crossing reset. Preserve `setBudget`,
      validation, and remove-budget.
- [x] 2.4 Shorten the default group names so they fit the segmented toggle and match the reference's
      short chips: Living Expense→Living, Savings / Goals→Savings, Variable / Optional→Variable,
      Non-Negotiables→Essentials (IDs unchanged; user renames still win via `merge`).
- [x] 2.5 Manage-groups sheet: the savings-group subtitle now reads a role descriptor ("Savings group")
      derived from `isSavings` instead of the hardcoded "Savings / Goals" name.

## 3. Verification

- [ ] 3.1 `dart format` + `flutter analyze` clean. → Not run here (no Flutter toolchain); run before merge.
- [ ] 3.2 Manual smoke (dark + light): set a new expense budget, create a category from the picker, edit
      an existing budget from a card, switch group to Savings (target resets, savings accounts listed),
      remove a budget.
