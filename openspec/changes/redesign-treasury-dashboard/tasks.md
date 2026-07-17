## 1. Presenter (additive only)

- [ ] 1.1 Add pure computed getters for the hero's momentum if not already derivable — e.g. `netWorthMonthDelta` and `netWorthMonthDeltaPct` from `netWorthTrend()` — and a "days left in month" helper. No stored state, no behavior change. Verify existing dashboard getters/tests are untouched (`flutter test` green).

## 2. Shared dashboard widgets (extract before wiring)

- [ ] 2.1 Add a small net-worth sparkline `CustomPainter` (polyline + area fill) driven by a `List<double>`, degrading to a centered flat line for sparse/flat series. Smoke: render in isolation with 1, 2, and N points.
- [ ] 2.2 Build `net_worth_hero.dart` — gradient card with net-worth figure, signed trend pill, "±₱X this month" line, and the sparkline; theme-aware (dark canonical + derived light). Reads presenter getters only.
- [ ] 2.3 Build `cashflow_strip.dart` — month label + days-left, income bar (success) and expense bar (danger) sized to the larger flow, and "Projected spare" (`forecastedNetBalance`, danger when negative).
- [ ] 2.4 Build the accounts-list widget — per-account rows (icon badge, name, type subtitle, balance), liquid-cash section header, and a "+N more accounts" expander (threshold 3); tap opens the existing edit sheet.

## 3. Mobile dashboard composition

- [ ] 3.1 Rebuild the top of `treasury_dashboard_view.dart` to: header (greeting + "Treasury" + status pill), NET WORTH hero, cashflow strip, Accounts list. Wire the status pill via an optional param defaulting to a static "Synced" pill (no new sync plumbing). Keep the Add-account FAB.
- [ ] 3.2 Consolidate the now-duplicated net-worth surface (fold the redundant `MetricCardsGrid`/`CashSummaryBanner` net-worth tile) so the figure isn't shown twice adjacently.
- [ ] 3.3 Re-skin the retained cards to Nudgr tokens without changing content/behavior: metric grid, spending analytics, category pie, upcoming bills, budget overview, goals & savings, credit, held/external funds. Verify each card's data-guard (hidden/empty state) still fires as before.
- [ ] 3.4 Verify empty (no accounts) and loading states render per spec.

## 4. Web companion alignment

- [ ] 4.1 Audit `web_dashboard_page.dart` stat tiles, cards, charts, and accents against the shipped Nudgr tokens; adjust drifted colors/contrast (no structural change). Verify in both light and dark.

## 5. Verification

- [ ] 5.1 `dart format` + `flutter analyze` clean; `flutter test` green.
- [ ] 5.2 Manual smoke on mobile: dashboard with data, with no accounts, with sparse net-worth history; confirm every retained card present and tappable. Screenshot dark + light.
- [ ] 5.3 Manual smoke on web (`Full App (Chrome)` / treasury web): dashboard renders aligned to tokens in light + dark.
