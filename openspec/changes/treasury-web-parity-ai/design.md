## Context

The web companion is not a separate app. `lib/main_web.dart` boots `TreasuryWebApp`, which builds
the same seven Treasury presenters the mobile `AppShell` does and hands them to either the desktop
`WebShell` (≥ `WebBreakpoints.rail`) or, below that width, the mobile `TreasuryModuleView` verbatim.
Every figure on both platforms comes from the same presenter getters. That makes parity work almost
entirely view-layer — with one exception, the advisor presenter, which is where the real design
decisions live.

Three constraints shape everything below:

1. **Web-unsafe platform services must never be *constructed* on web.** An earlier draft of this
   said the web bundle excludes mobile-only plugins because nothing imports them; that is false —
   see D1. `fasting_presenter`, `nutrition_presenter`, `notification_service`, and `food_db_service`
   are all already compiled into the web bundle and the build is green. The real rule is narrower and
   about runtime: never *instantiate* a notification service, a sqflite database, or the on-device
   model on web.
2. **MVP architecture** (CLAUDE.md): no calculations or conditionals in `build()`; RPG/finance math
   lives only in presenters; constructor injection only.
3. **Theme-aware colors only.** Widgets read `Theme.of(context)` / `context.appColors`. Direct
   `AppColors`/`AppColorsLight` token use is confined to theme construction.

## Goals / Non-Goals

**Goals:**
- Web reads as the same product as the redesigned mobile Treasury — same figures, same type, same
  badges, same card weight — while keeping desktop information density.
- The Money Mentor and receipt logging work on web with **one** implementation shared with mobile.
- One name for one number: the month-end projection is labelled and decomposed identically on both
  platforms.

**Non-Goals:**
- Restructuring web page layouts (sidebar, tables, column grids all stay).
- Any change to finance math or to `TreasuryDashboardPresenter`.
- Bringing nutrition/fasting/on-device AI to web.

## Decisions

### D1 — Make the coach's non-finance dependencies optional (not a separate presenter)

`AiCoachPresenter` is a multi-domain coach: it serves six `AiCoachEntryPoint`s and its constructor
takes `stats`, `fasting` (**required**), `nutrition`, `treasury`, `budget`, `installments`, `ledger`,
`storage`, and two services. Its `_buildContext()` reads fasting and nutrition state for the
non-finance entry points.

> **Corrected during Phase 2 (2026-07-29).** An earlier draft of this decision claimed three *hard
> compile* blockers — `FastingPresenter` → `flutter_local_notifications`, `NutritionPresenter` →
> `food_db_service` (`dart:io` + `sqflite`), and `OnDeviceAiCoachService` → `flutter_gemma`. That was
> wrong, and measurement disproved it:
>
> - Reading `.dart_tool/flutter_build/*/dart2js.d` after a successful `flutter build web` shows
>   `fasting_presenter.dart`, `nutrition_presenter.dart`, `notification_service.dart`, and
>   `food_db_service.dart` are **already in the web bundle today** — reached via
>   `treasury_web_app.dart` → `treasury_module_view.dart`, which imports `NutritionPresenter` for its
>   optional mobile-web parameter. The build is green regardless.
> - Temporarily importing `AiCoachPresenter` and `AiChatSheet` from `lib/main_web.dart` and running
>   `flutter build web --release` **succeeds**. `flutter_gemma` also ships a web implementation and is
>   already an auto-registered web plugin.
>
> Compiling is therefore not the constraint, and the bundle-bloat argument is moot because those
> libraries are already shipped.

The real constraints are runtime and architectural:

| Constraint | Detail |
|---|---|
| `FastingPresenter` construction | Required ctor arg, and `_init()` calls `NotificationService().init()` + `requestPermissions()` — platform channels with no web implementation. Constructing the coach on web means constructing this. |
| `NutritionPresenter` construction | Requires a `FoodDbService` (sqflite + `path_provider`), which cannot open a database on web. |
| Layering | A finance-only surface should not need the fasting and nutrition presenters to answer a question about money. |

This collapsed the case for a full extraction: making `fasting` and `nutrition` optional and
guarding the context builder clears the same runtime constraints for a fraction of the work.

**Decision (Phase 3): optional dependencies.** `fasting` becomes nullable — `nutrition` already was —
and the three fasting reads in the context builder degrade honestly: absent fasting reports "not
fasting", omits the elapsed figure, and omits the goal rather than letting the formatter's `?? 16`
default invent a 16-hour target that the user never set. Web constructs the coach with neither
presenter, an explicit `NullAiCoachService()` primary so the on-device init path is never entered,
and the cloud service as fallback.

The options considered:

- **Conditional imports / stub files.** Rejected: it would spread `kIsWeb` branching and
  `_stub.dart` shadow files across the presenter layer to serve one entry point, and every future
  nutrition or fasting field added to `_buildContext()` becomes a new web landmine.
- **Make `fasting`/`nutrition` nullable in place.** Originally rejected as insufficient, on the
  reasoning that nullability fixes the constructor but not the imports "which are what break the
  compile". That reasoning does not survive the measurement above — nothing breaks the compile — so
  this option is **live again** and is now the cheaper of the two.
- **Extract the finance-advisor path into its own presenter. → rejected once its premise failed.**
  It is still the tidier layering, and worth revisiting if the coach grows further. But it would have
  relocated ~400 lines of shipped advisor logic — conversation store, memory, context assembly, the
  confirm-before-commit hand-off — to reach behaviour the optional-dependency route reaches in a
  handful of lines. On a live mobile feature that trade is not worth the regression risk.

Storage keys, sync domains, the Lambda `op`, and the `AdvisorProfile` model are untouched either way,
so existing conversations and memory load with no migration.

### D2 — `AiChatSheet` narrows to an interface, and web gets its own container

`AiChatSheet` itself is web-safe (`image_picker` has a web implementation), so the *chat body* is
reusable. But a draggable bottom sheet is the wrong container on a 1440px desktop.

Decision: extract the chat body into a public `AiChatBody` widget. Mobile keeps `AiChatSheet` as the
bottom-sheet container around it; web adds `WebAdvisorPanel`, a docked right-hand column around the
same body. One chat implementation, two containers appropriate to their platform.

`AiChatBody` takes three container-driven flags: `showDragHandle` (a bottom-sheet affordance),
`allowModelDownload` (false on web, which has no on-device tier to download), and `showEntryLabel`
(false in the dock, where the label competes with four trailing controls and ellipsises to "Mone…" —
the dock prints the name in its own strip instead).

The mobile `AiChatSheet` continues to accept the other entry points via `AiCoachPresenter`
unchanged — only the `financeAdvisor` case routes through the new body.

**The web panel is a persistent dock, not a page.** `WebShell` gains a third region — a collapsed
rail on the right that expands to a ~380px advisor column, mounted across every destination rather
than replacing the body on its own. This is the point of the advisor on desktop: asking "can I
afford this?" while actually looking at the Bills table beats navigating away from the data to ask
about it. Mobile's bottom sheet already works this way — it opens *over* the screen you were on.

Consequences, accepted:

- It is the one exception to D4's "don't touch `WebShell`". The change is additive — a new optional
  right region alongside the existing sidebar and topbar — and the sidebar, topbar, and body
  contracts are unchanged.
- It costs horizontal room on the wide data-table pages (Ledger, Bills), so the dock **defaults to
  collapsed** and its expanded state persists per session. The dock takes its width from the shell,
  never from the page's internal layout, so nothing is clipped or hidden behind it and the page never
  scrolls horizontally. Page-level responsive grids *do* reflow to fewer columns while it is open —
  verified live, and correct: the content genuinely has less room.
- Below `WebBreakpoints.rail` the web falls back to `TreasuryModuleView`, which has no dock — mobile
  web keeps the mobile bottom sheet, as it should.

The advisor presenter is therefore owned by `_TreasuryWebHome`, not by a page, so conversation state
survives navigation between destinations.

### D3 — Receipt scanning: a web-only sheet over the existing presenter method

`LedgerPresenter.logReceiptPhoto(bytes, mimeType, note)` already takes raw bytes, already prefers
the cloud tier (`_cloudAi ?? _ai`), and already seeds the confirm-before-commit chat pipeline. No
presenter work is needed.

`photo_log_sheet.dart` cannot be reused: it imports `NutritionPresenter` and `food_photo_sheet.dart`
for its meal branch. Web gets `web_receipt_drop.dart` — a receipt-only dialog with drag-and-drop
plus a file-picker fallback, which is the better desktop interaction regardless. Compression reuses
`ImageCompressor` (`flutter_image_compress`, web-supported); if its web path proves unreliable, the
fallback is to skip client-side compression on web and let the Lambda's existing size limits apply,
since desktop uploads are not bandwidth-constrained the way mobile ones are.

### D4 — Skin parity is five primitives, not a page rewrite

The redesign's identity lives in a handful of primitives, and the web pages already compose
correctly. Changing the primitives propagates the skin across all 18 web files without touching
page layout:

| Primitive | Change | Reaches |
|---|---|---|
| `web_number.dart` (new) | Plus Jakarta Sans tabular figures, matching `AppTextStyles.numeric` | every figure on every page |
| `web_stat_tile.dart` | domain-tinted icon badge; figures via `WebNumber` | dashboard, budget, bills, history |
| `web_card.dart` | 0.5px hairline @40% + `AppCard.elevated` shadow | every card |
| `web_net_worth_hero.dart` (new) | gradient + momentum pill + sparkline | dashboard |
| `_CashFlowCard` | paired income/expense bars | dashboard |

The sparkline painter is the one piece of genuine duplication. `_SparklinePainter` is private to
`net_worth_hero.dart`; it gets promoted to a shared widget both heroes use rather than copied.

**Explicitly not changed:** `WebShell`'s sidebar, `WebDataTable`'s structure, the two-column content
grid, and the web-specific breakpoint logic. Web should look like the same *product*, not like a
phone. (D2's advisor dock adds a new optional right region to `WebShell` — the one sanctioned
exception, additive and leaving the sidebar/topbar/body contracts intact.)

### D5 — Fix the projection at the label layer, and only there

The investigation finding is that `forecastedNetBalance` is already shared and already subtracts
`totalBudgetRemaining` (`treasury_dashboard_presenter.dart:756`), including the
`_unpaidBillBudgetOverlap` credit-back that prevents double-deducting a bill that also has a
category budget. Mobile uses it in `cashflow_strip.dart` ("Projected spare") and
`metric_cards_grid.dart` ("FORECAST"); web uses it for "Proj. Month-End Cash". Same number, three
names.

The defect is that mobile's grid leads with `endingCash` under the label **ENDING CASH** — a figure
that legitimately does not deduct budget — while the tile that does deduct it is named FORECAST and
is hidden entirely when `hasBudget` is false. Two adjacent figures, neither named what it is.

**Confirmed requirement:** every forward-looking month-end figure the mobile dashboard shows must
deduct the remaining monthly budget. That is the outcome this decision delivers.

Decision: change `MetricCardsGrid`'s tile set to web's decomposition (Upcoming Bills · To Receive ·
Budget & Savings Due · Proj. Month-End Cash), render the projection unconditionally, and give every
tile sub-copy naming what it deducts. `MONTH IN` / `MONTH OUT` move into the cashflow strip's
existing bars, which already show exactly those two figures — removing a genuine duplication rather
than growing the grid.

After this change, **no mobile surface presents a forward-looking month-end figure that skips the
remaining budget.** The two that remain — the grid's Proj. Month-End Cash and the cashflow strip's
"Projected spare" — are both `forecastedNetBalance`, and the Hub card
(`treasury_hub_card.dart:94`) already used it.

**Rejected — changing the `endingCash` getter itself to subtract remaining budget.** It reaches the
same on-screen outcome by a worse route:

- It would make `endingCash` and `forecastedNetBalance` numerically identical, leaving two names for
  one concept — the exact confusion this change exists to remove.
- It would break `_unpaidBillBudgetOverlap`, whose correctness depends on the two being distinct:
  the overlap credit-back is documented as "an unpaid bill is already subtracted via `endingCash`",
  and folding budget into `endingCash` would double-deduct any bill whose category also carries a
  budget.
- `endingCash` is a *historical* quantity as well as a current one — `MonthlySummary.endingCash`
  freezes it per month and drives History's "Ending Cash Trend"
  (`web_history_page.dart:321`). Deducting a current-month budget from a settled month's closing
  balance is simply wrong.
- It would invalidate `treasury_dashboard_parity_test.dart` and `finance_audit_fixes_test.dart`,
  which assert the current definitions.

`endingCash` therefore survives as an input to `forecastedNetBalance` and as History's per-month
closing balance — but stops being shown as a headline, which is where it misled.

### D6 — Sequencing: projection → skin → AI

Ordered smallest-blast-radius first, so each lands and verifies independently:

1. **Projection labels** — one mobile widget, one widget test. No web changes, no presenter changes.
2. **Skin parity** — five web primitives. Purely additive/visual; no data path touched.
3. **AI pipeline** — the presenter extraction plus two new web surfaces. Largest and riskiest, and
   it benefits from the skin work already being in place so the new panel is styled correctly on
   arrival.

## Risks / Trade-offs

- **Advisor extraction regressing mobile.** Highest risk in the change. Mitigated by the
  characterization test in D1 and by delegation (mobile's entry point and sheet keep their public
  shape).
- **Web bundle bloat from an accidental import.** A stray `NutritionPresenter` or `dart:io` import
  fails `flutter build web`. Mitigated by adding the web build to the verification step for every
  AI-phase task, not just at the end.
- ~~**JetBrains Mono web font cost.**~~ Does not apply. `AppTextStyles.numeric` is Plus Jakarta Sans
  with `FontFeature.tabularFigures`, not a mono face, and web already loads that family for its whole
  text theme — parity costs no additional font fetch.
- **`flutter_image_compress` web reliability.** Unverified on this project's web target; D3 states
  the fallback.
- **Users notice `ENDING CASH` disappearing.** It is a real figure some people read. The projection
  tile's sub-copy names its deductions explicitly, and `endingCash` remains available in the History
  tab's ending-cash trend, so the number is not lost — only demoted from a slot where its name
  misled.

## Migration Plan

No data migration. All three phases are view-layer or refactor-in-place:

- Storage keys, sync domains, and the `AdvisorProfile` model are unchanged by D1, so existing
  advisor conversations and memory load as-is after the extraction.
- No presenter getter changes signature or semantics, so `test/presenters/` stays green throughout;
  a failure there indicates the change exceeded its scope.
- Each phase is independently shippable and independently revertible.

## Resolved Questions

- **Advisor placement — persistent dock (decided).** `WebAdvisorPanel` mounts across every web
  destination rather than living on its own page, so the advisor is available while looking at the
  data it is being asked about. `WebShell` gains an additive right region; the dock defaults to
  collapsed. See D2. (Verified live: the dock takes its width from the shell, so the page never
  scrolls horizontally or hides content behind it — though the page's own responsive grids do reflow
  to fewer columns, which is correct, not a regression.)
- **Mobile month-end figures deduct remaining budget (decided).** Confirmed as a requirement. Met
  by promoting `forecastedNetBalance` to the grid's headline rather than by redefining `endingCash`
  — the getter change would double-deduct via `_unpaidBillBudgetOverlap` and corrupt History's
  per-month closing balances for the same on-screen result. See D5.

- **Cashflow strip labels (decided).** No extra `MONTH IN`/`MONTH OUT` labels. Rendered at phone
  width, the arrow-marked bars with their amounts read unambiguously and the strip already carries
  the projection line beneath them. The amount slot did need widening, though — a six-figure inflow
  wrapped inside the old fixed 74px box.

- **Keep `desktop_drop` (decided).** Its real-drop path is sound; drag-and-drop is the interaction
  the dialog exists for; and the alternative — hand-rolled `package:web` interop — would reintroduce
  the conditional imports D1 rejected, in a file that must still analyse for mobile. Two caveats are
  recorded rather than fixed, because both live in the third-party plugin:
  its handler does `item.webkitGetAsEntry()!` and merely `debugPrint`s on failure, so (a) no
  synthetic drop can ever exercise it, making the path untestable in CI, and (b) dragging non-file
  content throws inside the plugin, silently. Our side compensates: the file picker is a first-class
  path, and a `MouseRegion.onExit` clears the highlight the plugin would otherwise strand.

## Open Questions

- None outstanding. The only unverified behaviour is the advisor's live network leg, which needs an
  `AI_COACH_ENDPOINT` build plus a signed-in Supabase user (see tasks 5.12).
