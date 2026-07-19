## 1. Presenter (additive only)

- [x] 1.1 Add pure computed getters for the hero's momentum if not already derivable — e.g. `netWorthMonthDelta` and `netWorthMonthDeltaPct` from `netWorthTrend()` — and a "days left in month" helper. No stored state, no behavior change. Verify existing dashboard getters/tests are untouched (`flutter test` green). → Added `netWorthMonthDelta`, `netWorthMonthDeltaPct`, `daysLeftInMonth`.

## 2. Shared dashboard widgets (extract before wiring)

- [x] 2.1 Add a small net-worth sparkline `CustomPainter` (polyline + area fill) driven by a `List<double>`, degrading to a centered flat line for sparse/flat series. → `_SparklinePainter` in `net_worth_hero.dart`.
- [x] 2.2 Build `net_worth_hero.dart` — gradient card with net-worth figure, signed trend pill, "±₱X this month" line, and the sparkline; theme-aware (dark canonical + derived light). Reads presenter getters only.
- [x] 2.3 Build `cashflow_strip.dart` — month label + days-left, income bar (success) and expense bar (danger) sized to the larger flow, and "Projected spare" (`forecastedNetBalance`, danger when negative).
- [x] 2.4 Build the accounts-list widget — per-account rows (icon badge, name, type subtitle, balance), liquid-cash section header, and a "+N more accounts" expander (threshold 3); tap opens the existing edit sheet. → `dashboard_accounts_list.dart`.

## 3. Mobile dashboard composition

- [x] 3.1 Rebuild the top of `treasury_dashboard_view.dart` to: header (greeting + status pill), NET WORTH hero, cashflow strip, Accounts list. Static "Synced" pill (no new sync plumbing). Kept the Add-account FAB. (Title stays on the module app bar.)
- [x] 3.2 Consolidate the duplicated net-worth surface — removed the redundant `CashSummaryBanner` (net worth → hero, liquid cash → accounts header). Kept `MetricCardsGrid` (unique Ending Cash / Forecast), moved below accounts.
- [x] 3.3 Re-skin the retained cards to Nudgr tokens. → Audited: retained cards and web dashboard already read theme tokens via the design system (no hardcoded colors found); no rework needed.
- [x] 3.4 Verify empty (no accounts) and loading states render per spec. → Loading indicator + empty-accounts card retained; covered by view logic and widget test.

## 4. Web companion alignment

- [x] 4.1 Audit `web_dashboard_page.dart` stat tiles, cards, charts, and accents against the shipped Nudgr tokens. → Already token-driven (colorScheme.* + resolveSliceColor by brightness); no hardcoded colors, no drift found.

## 5. Verification

- [x] 5.1 `dart format` + `flutter analyze` clean; `flutter test` green. → analyze clean (only pre-existing lint infos in untouched files); redesign widget test passes.
- [x] 5.2 Widget-test smoke: dashboard renders hero + strip + accounts; overflow expander expands. → `treasury_dashboard_redesign_test.dart` (2 tests passing).
- [ ] 5.3 Manual/live smoke on device + web in both themes; capture dark + light screenshots. → Pending a live run (web-server preview renders blank in this pane; defer to device/Edge run).
