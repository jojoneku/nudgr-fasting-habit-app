> **⚠️ Superseded by [`redesign-treasury-budget-cards`](../redesign-treasury-budget-cards/tasks.md).**
> The pace-hero + safe-to-spend UI below was not shipped. What survives (in the cards design): the
> `isCurrentMonth` / `monthElapsedFraction` / `isAheadOfPace` / `percentUsed` getters and the ring
> hero + on-pace pill. What was dropped: `daysLeftInSelectedMonth`, `safeToSpendPerDay`, the
> `_SafeToSpendCallout`, and the `budget_pace_test.dart` unit tests (pace is now covered by
> `budget_sections_test.dart`).

## 1. Presenter (additive only)

- [~] 1.1 ~~Add pure getters `isCurrentMonth`, `daysLeftInSelectedMonth`, `monthElapsedFraction`, `isAheadOfPace`, `safeToSpendPerDay`.~~ Superseded: only `isCurrentMonth`, `monthElapsedFraction`, `isAheadOfPace` shipped (see cards design); `daysLeftInSelectedMonth`/`safeToSpendPerDay` dropped.

## 2. Pace hero + safe-to-spend

- [~] 2.1 ~~Replace `_SummaryBanner` with `_BudgetPaceHero` + `_SafeToSpendCallout`.~~ Superseded by the cards design's ring hero (no safe-to-spend callout).

## 3. Wire into the view

- [~] 3.1 ~~Show the hero + callout in the header.~~ Superseded by the per-budget cards layout.

## 4. Verification

- [~] 4.1 ~~`dart format` + `flutter analyze` clean.~~ Superseded; the cards design is analyze-clean.
- [~] 4.2 ~~Presenter unit tests for the pace getters (`budget_pace_test.dart`).~~ Superseded: `budget_pace_test.dart` removed; pace covered by `budget_sections_test.dart`.
- [ ] 4.3 Live smoke on device/web in both themes → tracked under the cards design.
