## Context

`add_budget_sheet.dart` is shown via `AppBottomSheet.show` (which owns the "Set/Edit Budget" title). It
picks a category (or savings/goal account when the group is Savings), an amount, a budget group, and a
budget type, then calls `presenter.setBudget`. The Bills forms on `redesign-bills-page` established a
shared `sheet_fields.dart` (uppercase `SheetFieldLabel`, `sheetFieldDecoration`, `SheetPickerBox`,
plus AccountBadge-based account pickers).

## Goals / Non-Goals

**Goals:** match the reference "Set budget" frame and the Bills forms' field language; keep every field
and behavior; reuse the same primitives so the branches merge cleanly.

**Non-Goals:** logic changes; the bills/ledger/account forms; a manage-groups redesign.

## Decisions

- **Trim the shared kit for this branch.** `sheet_fields.dart` here contains only `SheetFieldLabel`,
  `sheetFieldDecoration`, and `SheetPickerBox` — byte-identical to the Bills-page versions. The
  AccountBadge-coupled `SheetAccountField`/`showAccountPicker` are omitted because they pull in
  `account_badge_widget.dart` and a `+253`-line `utils/account_badge.dart` that live on the Bills
  branch; the budget form doesn't need account badges. Keeping the three shared primitives identical
  means a later merge with Bills is a trivial superset resolution, not a content conflict.
- **Category/account selection = `SheetPickerBox` + bottom-sheet list.** Replaces the two
  `DropdownButtonFormField`s. A leading "New category…" row in the expense picker preserves the
  create-category flow (same `_showCreateCategoryDialog`). Savings mode lists `savingsTargets`.
- **Emphasized amount.** `sheetFieldDecoration(..., emphasize: true)` gives the reference's blue-bordered
  ₱ amount; a large titleLarge text style matches the frame.
- **Group/Type stay `AppSegmentedControl`.** They already model a small fixed choice set and match the
  reference's chip rows; only their labels move to `SheetFieldLabel`. Group labels stay truncated to 8
  chars to fit four segments.
- **Preselected (edit-from-card) mode** shows the locked target in a non-tappable `SheetPickerBox` with a
  lock icon instead of the old `_CategoryDisplay` card.

## Risks / Trade-offs

- **[Duplicated sheet_fields across branches]** → mitigated by keeping the shared primitives byte-identical
  so the merge is a no-op/superset, not a conflict.
- **[Picker loses inline "required" validation]** → `setBudget` is still guarded (a null target shows the
  existing "Select a category" snackbar), so behavior is preserved.

## Migration Plan

View restyle + one new shared file. No data migration. Rollback restores the dropdown-based sheet.

## Open Questions

- Later: fold the AccountBadge-based `SheetAccountField` in once the Bills branch merges, so the savings
  account picker shows account badges too.
