## 1. Model — group ordering (land before UI)

- [x] 1.1 Reorder `BudgetGroupDef.defaultGroups` `sortOrder` to Living Expense=0, Savings=1,
      Variable/Optional=2, Non-Negotiables=3. `merge()` still lets stored overrides win (it copies
      `sortOrder` from stored). No existing test asserts the old order.

## 2. Presenter (additive, pure)

- [x] 2.1 Added pace getters to `BudgetPresenter`: `isCurrentMonth`, `monthElapsedFraction`,
      `isAheadOfPace` (reusing `percentUsed`). No date math in `build`.
- [x] 2.2 Added an ordered `budgetSections` view-model (+ `BudgetSection`/`BudgetSectionRow`): groups
      sorted by `sortOrder`, each carrying its rows (expense: category + budget + spent + transactions;
      savings: account + net contributed + account transactions) and section allocated/spent totals;
      empty groups omitted. Visual tokens left to the view (presenter stays Flutter-material-free).
- [x] 2.3 Unit tests in `test/presenters/budget_sections_test.dart`: pace getters (past = fully
      elapsed, future = 0 elapsed, current = live/ahead, over-spend = behind) and `budgetSections`
      ordering (Living → Savings → Variable; savings interleaved; empty Non-Neg dropped; over-budget
      row exposes `overBy`/`isOver`).

## 3. Per-budget card widget

- [x] 3.1 Added `lib/views/treasury/budget/budget_card.dart`: leading icon chip (`categoryIcon` +
      `resolveSliceColor` tint), name, spent / allocated (error color when over), `AppLinearProgress`
      + true %, an "Over by ₱x — trim next week" line when over, a "Goal reached" line when a savings
      goal is met, and a tap-to-expand transaction list (empty-state included). Savings rows use the
      flag/savings glyph and never read as "over".
- [x] 3.2 Removed `category_budget_tile.dart` (dead after 3.1); its only import was `budget_view.dart`.

## 4. Header + ring hero

- [x] 4.1 Replaced `_MonthSelector` with a title row: large "Budget" title (left) + a `_MonthSwitcher`
      pill ("June ▾") that opens an `AppActionSheet` month picker (2 ahead → 12 back) top-right; kept a
      manage-groups icon button (tune) beside it. Added `monthChipLabel` to `finance_format.dart`.
- [x] 4.2 Replaced `_SummaryBanner` with `_BudgetRingHero` (`AppRingProgress` spent% + SPENT /
      of-allocated + Ahead/Over-pace/Over-budget pill, current-month only). No safe-to-spend callout.

## 5. Wire the sections

- [x] 5.1 Render `budgetSections` as `_SectionBlock`s: section header (group name + `spent / allocated`)
      over a vertical list of `BudgetCard`s. Empty state, FAB, and add/edit-budget sheet flow retained.

## 6. Verification

- [ ] 6.1 `dart format` + `flutter analyze` clean. → **Not run in this environment (no Dart/Flutter
      toolchain).** Code was manually reviewed against the system-widget/model APIs; run before merge.
- [ ] 6.2 Presenter unit tests from 2.3 passing. → **Written but not executed here** (no toolchain);
      run `flutter test test/presenters/budget_sections_test.dart` locally/CI.
- [ ] 6.3 Manual smoke (dark + light): ahead-of-pace and over-budget states, savings interleaved,
      expand/collapse transactions, month switch to a past month (no pace pill), web Budget table still
      renders. → Deferred to a device/web session with the toolchain.
