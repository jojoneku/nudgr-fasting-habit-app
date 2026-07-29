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

- [x] 2.1 Add `lib/views/web/widgets/web_number.dart` — a numeric text widget with size variants for
  the hero, tile, mini-stat, and table-cell cases, plus a `webNumericStyle()` helper for adding
  tabular figures to an existing theme style. → **Correction:** `AppTextStyles.numeric` is **Plus
  Jakarta Sans with `FontFeature.tabularFigures`**, not JetBrains Mono (that is
  `AppTextStyles.mono`, which figures never use). Web already loads Plus Jakarta Sans, so parity was
  a missing font *feature*, not a missing font — and the "JetBrains Mono web font cost" risk in
  design.md does not apply.
- [x] 2.2 Route figures through it: `web_stat_tile.dart` value, `_MiniStat` in
  `web_dashboard_page.dart`, `web_data_table.dart` numeric columns, and `web_charts.dart` axis
  labels (3 sites). → The table applies it once in `_BodyRow` for `numeric` columns, so every
  existing table inherits it with no call-site changes.
- [x] 2.3 Retint `WebStatTile`'s icon badge from the neutral `onSurface@5%` square to the
  domain-tinted badge (`color@14%`, `AppRadii.sm`, 32px), matching `AppIconBadge`. Added an
  `iconColor` param so a tile can carry a domain accent on the badge without recolouring its figure;
  falls back to `valueColor`, then `primary`, mirroring `AppIconBadge`'s chain.
- [x] 2.4 Match `web_card.dart` to `AppCard.elevated`: 0.5px hairline at `outlineVariant@40%` plus
  the subtle elevation shadow.
- [x] 2.5 Promote `_SparklinePainter` out of `net_worth_hero.dart` into
  `lib/views/widgets/system/indicators/app_sparkline.dart`, exported from the design-system barrel.
  Mobile's hero now uses the shared `AppSparkline` and renders identically.
- [x] 2.6 Add `lib/views/web/widgets/web_net_worth_hero.dart` — gradient card, momentum pill,
  "±₱X this month" line, shared sparkline. Figure and sparkline sit side by side above 560px and
  stack below it. Mounted above `_PositionRow`; the old `WebStatTile(accent: true)` "Net Position"
  tile is replaced by a Net Cash Flow tile so the row keeps four and no figure is lost.
- [x] 2.7 Extend `_CashFlowCard` with paired income/expense bars sized to the larger flow, keeping
  the existing mini-stats and spent-percentage bar.
- [x] 2.8 Web widget tests → `test/views/web/web_design_system_test.dart`, 9 tests: tabular figures
  in both theme modes, `webNumericStyle` preserving its base, tinted badge, hero with/without trend
  history in both modes, and the narrow-width stacking path.
- [x] 2.9 Align the web Month-End Outlook projection accent with mobile — `appColors.success`
  instead of `cs.tertiary`. Mobile's `tertiary` is the teal `AppColors.accent` while web's is the
  green `move` token, so the shared token was needed for the identical figure to read identically.
- [x] 2.10 Verify `flutter build web --release -t lib/main_web.dart` still succeeds. → Green.

## 3. Advisor made platform-agnostic (shared)

- [x] 3.1 **Re-decided per design.md D1.** The extraction's three claimed compile blockers were
  disproved during Phase 2, leaving only a runtime constraint. Chose the optional-dependency route
  over extracting `FinanceAdvisorPresenter`: same behaviour, ~400 fewer lines of shipped advisor
  logic moved, materially lower regression risk on a live mobile feature. Spec delta rewritten to
  match.
- [x] 3.2 Make `fasting` optional in `AiCoachPresenter` and guard its three reads in the context
  builder — absent fasting reports "not fasting" and omits the elapsed figure and the goal, rather
  than defaulting the goal to 16h. `nutrition` was already optional and already guarded.
- [x] 3.3 Split `ai_chat_sheet.dart` into `AiChatSheet` (bottom-sheet container, unchanged public
  API and call sites) and a new public `AiChatBody` (the chat surface itself). Added
  `showDragHandle` and `allowModelDownload` flags for the container to set.
- [x] 3.4 Add a terminal `_CloudUnavailable` state for platforms with no on-device tier, so web
  never offers a model download it cannot perform.
- [x] 3.5 Fix `_SheetHeader` overflow at dock width — the title is now `Flexible` + ellipsised so it
  yields before the three trailing actions. It was sized for a full-width phone sheet.

## 4. AI surfaces on web

- [x] 4.1 Construct the advisor in `treasury_web_app.dart` with no fasting/nutrition presenter, an
  explicit `NullAiCoachService()` primary (so the on-device init path is never entered), and the
  existing `CloudAiCoachService` as fallback — now shared with the ledger rather than constructed
  twice. Disposed with the other presenters.
- [x] 4.2 Extend `WebShell` with an optional right dock region, placed outside the content
  `Expanded` so the page's own column/table layout keeps its width budget.
- [x] 4.3 Add `web_advisor_panel.dart` — collapsed 56px rail expanding to a 380px column, mounted by
  `_TreasuryWebHome` so the conversation survives navigation. The advisor session opens lazily on
  first expand. Contents are laid out at their final width inside a `ClipRect`/`OverflowBox` so the
  expand animation reveals rather than squeezes. Carries only a collapse control — the chat body's
  own header already supplies the Money Mentor identity and actions.
- [x] 4.4 Add `web_receipt_drop.dart` — drag-and-drop (via `desktop_drop`, which supports web) plus
  a file-picker fallback, compressing through `ImageCompressor` and calling
  `LedgerPresenter.logReceiptPhoto()`. Every `ReceiptScanOutcome` failure is surfaced in the dialog
  using the same wording as the mobile sheet. Reachable from a FAB above Quick Add on the Ledger.
- [x] 4.5 Verify `flutter build web --release -t lib/main_web.dart` after each step. → Green
  throughout.
- [x] 4.6 Tests → `test/views/web/web_advisor_panel_test.dart`, 9 tests: advisor builds/opens/sends
  with no fasting presenter (asserting the degraded context fields), dock collapse/expand/re-collapse
  and its widths, the no-download state, and the shell mounting the dock alongside the body.

## 5. Verification

- [x] 5.1 `dart format` + `flutter analyze` clean; `flutter test` green. → 1037 tests pass; `lib/` has
  no errors or warnings.
- [x] 5.2 `flutter build web --release -t lib/main_web.dart` succeeds. → Green. The earlier
  import-set check is retired: `dart2js.d` shows notification / food-db / fasting / nutrition are
  already in the bundle via `treasury_module_view`, so the real guarantee is that none of them is
  *constructed* on web (4.1), not that none is compiled.
- [x] 5.3 Live side-by-side in a real browser, both theme modes. → Ran a debug web build with
  `PREVIEW_SEED=true` under Chromium/Playwright and captured desktop dark, desktop light, the
  expanded dock, and the mobile fallback layout. Skin reads as one system; no overflow in any state.
  Found and fixed three real defects (5.7).
- [x] 5.4 Projection identical and identically labelled on both platforms. → Confirmed against the
  same seeded data: **₱-2,881.31** under "PROJ. MONTH-END CASH" in the web tile, the mobile tile, and
  the mobile cashflow strip, in the same danger accent.
- [x] 5.5 Advisor dock smoke on web. → Expands/collapses, mounts across destinations, and correctly
  shows the terminal "Money Mentor is unavailable" state with a disabled composer, since this build
  has no `AI_COACH_ENDPOINT`. A conversational round-trip still needs a build with the endpoint and a
  signed-in user.
- [x] 5.6 Harness caveat worth recording: Chromium could not fetch Google Fonts through the sandbox
  proxy, and the fallback metrics produced three phantom overflow reports plus blank text. Serving
  the fonts through the harness cleared all three — they were never real defects.
- [x] 5.7 Defects found only by rendering, all fixed:
  - Chart left-axis labels wrapped ("₱107." / "1k"). Tabular figures widened every digit past the
    48px reserve; now 60px plus a `FittedBox` backstop, in all three chart widgets.
  - The advisor dock title ellipsised to "Mone…" at 380px against four trailing controls. `AiChatBody`
    gained `showEntryLabel`; the dock prints the name in its own strip, where there is room.
  - The mobile cashflow strip wrapped `₱46,500.00` to two lines in a fixed 74px slot — pre-existing,
    but this change makes the strip the only home for the month in/out figures, so it now matters.
    The slot is a minimum width rather than a fixed one.
- [ ] 5.8 Still needs a device/endpoint this environment cannot provide: a real advisor conversation,
  a real browser drag-and-drop onto the receipt target (no test here exercises `desktop_drop`'s web
  path), and a mobile Money Mentor regression pass after the `AiChatSheet` split.
- [ ] 5.9 Decide whether `desktop_drop` (+6 transitive deps, added in 4.4) earns its place for one
  dialog, or whether the file-picker path alone suffices.

## 6. Open questions closed

- [x] 6.1 Does the cashflow strip need explicit month-in/month-out labels now the grid drops those
  tiles? → No. Rendered at phone width the arrow-marked bars with their amounts read unambiguously,
  and the strip already carries the projection line beneath them. The amount slot did need widening.
