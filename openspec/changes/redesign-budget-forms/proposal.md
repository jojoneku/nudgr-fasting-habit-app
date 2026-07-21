## Why

The Budget tab was redesigned to per-budget cards, but its **Set / Edit Budget** sheet still used the
pre-Nudgr look — a `DropdownButtonFormField` category picker and a plain `TextFormField` amount — which
no longer matches the reference (`Nutrition Focus Treasury.dc.html`, "Set budget" frame) or the Bills
forms already redesigned on `redesign-bills-page`. The reference shows uppercase field labels over
bordered "field boxes", a category **picker box**, an emphasized ₱ **BUDGET AMOUNT**, and BUDGET GROUP
/ BUDGET TYPE selectors.

This is a **restyle** of the budget entry sheet to the shared Nudgr sheet-field language — same fields,
same logic, new look — reusing the same `sheet_fields.dart` primitives the Bills forms use so the two
read as one system.

## What Changes

- Adopt the **consolidated `sheet_fields.dart` kit** verbatim from the other treasury redesign branches
  (`redesign-bills-page`, `redesign-ledger-page`, `redesign-bills-forms` all carry the identical
  407-line file) — `SheetFieldLabel`, `sheetFieldDecoration`, `SheetPickerBox`, plus `SheetHandle`,
  `SheetTitle`, `SheetSegmentedToggle`, `SheetAccountField`, and `showAccountPicker`. Its dependencies
  `account_badge_widget.dart` and `utils/account_badge.dart` are brought in byte-identical too, so every
  treasury branch shares the same field kit and the files merge cleanly.
- Restyle `add_budget_sheet.dart` onto the kit: a category / savings-account **picker box** opening a
  bottom-sheet list (with a "New category…" row preserving the create-category flow), an emphasized ₱
  **Budget amount** field, and BUDGET GROUP / BUDGET TYPE selectors under uppercase labels. Preselected
  (edit-from-card) mode shows the locked target in a read-only box.
- All budget logic is unchanged: `setBudget`, category creation, expense↔savings crossing (which resets
  the picked target), validation, and remove-budget.

## Non-goals

- **No presenter/model/storage change** and no new budget concepts.
- **Not the bills / ledger / account forms** — those live on `redesign-bills-page`. This branch is
  Budget only.
- **Manage-groups sheet** is left as-is — it is a management list, not a field form, and already matches
  the system style.

## Capabilities

### New Capabilities
- `treasury-budget-forms`: The Set / Edit Budget sheet in the shared Nudgr sheet-field language —
  uppercase labels, a category/account picker box (with create-category), an emphasized ₱ amount, and
  group/type selectors — preserving all existing budget fields and behavior; theme-aware.

### Modified Capabilities
<!-- None. -->

## Impact

- **New (consolidated kit, identical to the other treasury branches):**
  `lib/views/treasury/shared/sheet_fields.dart`, `lib/views/treasury/shared/account_badge_widget.dart`,
  `lib/utils/account_badge.dart`.
- **Modified:** `lib/views/treasury/budget/add_budget_sheet.dart` (restyle only).
- **Reuses:** `AppSegmentedControl`, `AppPrimaryButton`, `AppDestructiveButton`, `amount_input_formatter`,
  `category_colors`, `finance_format`, theme tokens.
- **Deps:** none new. **Risk:** low — a view restyle preserving field-for-field parity. Not
  compile-verified in this environment (no Flutter toolchain); run `flutter analyze` + a smoke first.
