## 1. Month-end projection surfacing (mobile)

- [x] 1.1 Rework `lib/views/treasury/dashboard/metric_cards_grid.dart` to web's four-tile
  decomposition: Upcoming Bills (`monthUnpaidBills`), To Receive (`pendingReceivables`),
  Budget / Savings Due (`budgetedExpensesRemaining`), Proj. Month-End Cash
  (`forecastedNetBalance`). Drop the `hasBudget` gate so the projection always renders; drop the
  `MONTH IN` / `MONTH OUT` tiles (both already appear in the cashflow strip's bars). Keep the
  tinted icon-badge tile treatment. No presenter changes. → Rows now wrap in `IntrinsicHeight` so a
  pair stays level when a label or sub-line wraps.
- [x] 1.2 Add sub-copy to each tile naming what it deducts, matching web's wording
  ("Unpaid this month", "Money owed to you", "Set-asides still to fund",
  "After bills, budget & savings"). Rename the section from "Month Outlook" to "Month-End Outlook"
  to match web. → Used web's exact label strings, including "Budget / Savings Due".
- [x] 1.3 Colour the projection by sign (danger when negative), matching web's
  `valueColor` behaviour. → Positive uses `appColors.success`, not `colorScheme.tertiary`: mobile's
  `tertiary` is `AppColors.accent` (teal), whereas web's is the green `move` token. `appColors.success`
  is the same green on both platforms.
- [x] 1.4 Rename the cashflow strip's "Projected spare" to "Proj. month-end cash" and switch its
  positive accent from blue to the same success green. It renders the identical
  `forecastedNetBalance` figure, so leaving it under a second name and a third colour next to the
  new grid would have reproduced the exact confusion this phase removes. Recorded as a MODIFIED
  requirement in the `treasury-dashboard` delta.
- [x] 1.5 Update `test/views/treasury/dashboard/treasury_dashboard_redesign_test.dart` for the new
  tile set; add cases asserting the projection renders with no budgets, and that the grid shows the
  budget-deducted figure rather than raw ending cash. → 3 new tests. The deduction assertion is
  scoped to `MetricCardsGrid` because the fixture's net worth coincidentally equals its ending cash,
  which the hero legitimately shows.
- [x] 1.6 Verify `test/presenters/treasury_dashboard_parity_test.dart` and
  `test/presenters/finance_audit_fixes_test.dart` are untouched and green — a failure here means the
  change leaked into presenter math. → Both unmodified; full suite green (1019 tests).

## 2. Web skin primitives

- [ ] 2.1 Add `lib/views/web/widgets/web_number.dart` — a numeric text widget matching
  `AppTextStyles.numeric` (JetBrains Mono, tabular figures), with size variants covering the tile
  value, mini-stat, and table-cell cases.
- [ ] 2.2 Route figures through it: `web_stat_tile.dart` (value), the `_MiniStat` / `_StatGrid`
  helpers in `web_dashboard_page.dart`, `web_data_table.dart` amount columns, and `web_charts.dart`
  axis labels.
- [ ] 2.3 Retint `WebStatTile`'s icon badge from the neutral `onSurface@5%` square to the redesign's
  domain-tinted badge (`color@12–14%`, `AppRadii.sm`), matching `AppIconBadge`.
- [ ] 2.4 Match `web_card.dart` to `AppCard.elevated`: 0.5px hairline at `outlineVariant@40%` plus
  the subtle elevation shadow. Verify no page regresses visually at the two-column breakpoint.
- [ ] 2.5 Promote `_SparklinePainter` out of `lib/views/treasury/dashboard/net_worth_hero.dart` into
  a shared widget, leaving mobile's hero rendering identically.
- [ ] 2.6 Add `lib/views/web/widgets/web_net_worth_hero.dart` — gradient card, momentum pill,
  "±₱X this month" line, shared sparkline; desktop proportions. Replace the
  `WebStatTile(accent: true)` "Net Position" tile in `_PositionRow`.
- [ ] 2.7 Extend `_CashFlowCard` in `web_dashboard_page.dart` with paired income/expense bars sized
  to the larger flow, keeping the existing mini-stats and spent-percentage bar.
- [ ] 2.8 Web widget tests: hero renders with and without trend history; stat tile renders tabular
  figures. Verify both theme modes.

## 3. Advisor extraction (shared)

- [ ] 3.1 Write a characterization test capturing the advisor context `AiCoachPresenter` builds for
  a fixed Treasury fixture, so the extraction can be proven behavior-preserving.
- [ ] 3.2 Add `lib/presenters/finance_advisor_presenter.dart` — move the `isAdvisor` context builder,
  conversation store (including cap/archive), `AdvisorProfile` memory, and the
  `LedgerPresenter.sendChatInput` hand-off. Dependencies limited to treasury/budget/installments/
  ledger/storage plus an injected `AiCoachService`. Same storage keys, same sync domains, same
  Lambda op.
- [ ] 3.3 Delegate `AiCoachPresenter`'s `financeAdvisor` entry point to the new presenter; remove
  the now-unreachable advisor code. Confirm the other five entry points are untouched.
- [ ] 3.4 Re-run 3.1 against the extracted presenter — contexts must match.
- [ ] 3.5 Extract the chat body from `lib/views/widgets/ai_chat_sheet.dart` into a
  `FinanceAdvisorChat` widget parameterized by `FinanceAdvisorPresenter`; keep `AiChatSheet` as
  mobile's bottom-sheet container around it. Verify the Hub's Money Mentor entry point still opens
  and behaves identically.
- [ ] 3.6 Update `lib/views/home_screen.dart` to construct and inject the new presenter.

## 4. AI surfaces on web

- [ ] 4.1 Construct `FinanceAdvisorPresenter` in `lib/views/web/treasury_web_app.dart` with the
  existing `CloudAiCoachService`; add its dispose to the shell teardown.
- [ ] 4.2 Extend `WebShell` with an optional right dock region — collapsed rail that expands to a
  ~380px column — leaving the sidebar, topbar, and body contracts unchanged. The dock overlays the
  content area rather than reflowing it, so `_ContentColumns` and `WebDataTable` keep their
  arrangement when it is open.
- [ ] 4.3 Add `lib/views/web/widgets/web_advisor_panel.dart` wrapping `FinanceAdvisorChat`, styled
  to the web design system, mounted by `_TreasuryWebHome` (not by a page) so the conversation
  survives navigation. Default collapsed; persist the expanded state for the session.
- [ ] 4.4 Add `lib/views/web/widgets/web_receipt_drop.dart` — drag-and-drop plus file-picker,
  compressing via `ImageCompressor` and calling `LedgerPresenter.logReceiptPhoto()`. Surface each
  `ReceiptScanOutcome` failure in place. Expose it from the Ledger page alongside Quick Add.
- [ ] 4.5 Verify `flutter build web -t lib/main_web.dart` succeeds after each of 4.1–4.4, not only
  at the end — an accidental mobile-only import fails the build outright.
- [ ] 4.6 Confirm advisor conversations and memory started on one platform appear on the other
  (existing sync domains, no new keys).
- [ ] 4.7 Verify the dock at the two-column breakpoint and on the widest tables (Ledger, Bills):
  expanding it must not collapse `_ContentColumns` or trigger horizontal scroll on the page body.

## 5. Verification

- [ ] 5.1 `dart format` + `flutter analyze` clean; `flutter test` green.
- [ ] 5.2 `flutter build web -t lib/main_web.dart` succeeds; inspect the transitive import set for
  notification / sqflite / gemma / health / home_widget / `dart:io`.
- [ ] 5.3 Side-by-side check of mobile and web dashboards in both theme modes — figures, badges,
  card weight, and hero read as one design system.
- [ ] 5.4 Confirm the projection figure is identical on both platforms for the same data, and
  identically labelled.
- [ ] 5.5 Manual smoke: advisor conversation on web, receipt drop on web, mobile Money Mentor
  regression after the extraction.
