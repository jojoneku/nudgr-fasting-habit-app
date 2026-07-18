## 1. Presenter (additive only)

- [x] 1.1 Add pure getters to `BudgetPresenter`: `isCurrentMonth`, `daysLeftInSelectedMonth`, `monthElapsedFraction`, `isAheadOfPace`, `safeToSpendPerDay` (reusing `percentUsed`/`totalRemaining`). Unit-test past/current/future month.

## 2. Pace hero + safe-to-spend

- [x] 2.1 Replace `_SummaryBanner` with `_BudgetPaceHero` (AppRingProgress % ring + SPENT / of-allocated + Ahead-of-pace / Over-pace / Over-budget pill) and a `_SafeToSpendCallout` (current-month only). Remove the dead `_SummaryBanner`.

## 3. Wire into the view

- [x] 3.1 Show the hero + callout in the header when budgets exist; keep the empty state, category/savings sections, month selector, manage-groups, and FAB unchanged.

## 4. Verification

- [x] 4.1 `dart format` + `flutter analyze` clean.
- [x] 4.2 Presenter unit tests for the pace getters (past = fully elapsed / 0 days, future = 0 elapsed, current = live safe-to-spend). 3 tests passing.
- [ ] 4.3 Live smoke on device/web in both themes (ahead / over-budget states). → Deferred with the other tabs' live smoke.
