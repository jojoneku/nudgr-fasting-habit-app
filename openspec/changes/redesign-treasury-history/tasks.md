## 1. Model (additive, pure)

- [x] 1.1 Add `double? get savingsRate` to `MonthlySummary` (`netSavings / totalInflow`, null when no income). Unit-test positive / zero-income / negative.

## 2. Surface in the card

- [x] 2.1 Show "N% saved" in `MonthlySummaryCard`'s header (current + closed), tinted by net-savings sign, omitted when null.

## 3. Verify existing layout

- [x] 3.1 Confirm the CURRENT MONTH · LIVE + CLOSED MONTHS sections, per-card figures, and tap-through to the monthly detail view are unchanged.

## 4. Verification

- [x] 4.1 `dart format` + `flutter analyze` clean.
- [x] 4.2 Model unit tests for `savingsRate` (3 cases passing).
- [ ] 4.3 Live smoke on device/web in both themes. → Deferred with the other tabs' live smoke.
