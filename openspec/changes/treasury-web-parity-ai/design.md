## Context

The web companion is not a separate app. `lib/main_web.dart` boots `TreasuryWebApp`, which builds
the same seven Treasury presenters the mobile `AppShell` does and hands them to either the desktop
`WebShell` (≥ `WebBreakpoints.rail`) or, below that width, the mobile `TreasuryModuleView` verbatim.
Every figure on both platforms comes from the same presenter getters. That makes parity work almost
entirely view-layer — with one exception, the advisor presenter, which is where the real design
decisions live.

Three constraints shape everything below:

1. **The web bundle is defined by transitive imports.** `flutter build web -t lib/main_web.dart`
   compiles only what that entrypoint reaches. Mobile-only plugins (`flutter_local_notifications`,
   `sqflite`, `path_provider`, `health`, `home_widget`, `flutter_gemma`) stay out today *because
   nothing on the web path imports them*. Any new web wiring must preserve that property — an
   accidental `dart:io` import fails the build outright, not gracefully.
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

### D1 — Extract `FinanceAdvisorPresenter` rather than making `AiCoachPresenter` web-safe

`AiCoachPresenter` is a multi-domain coach: it serves six `AiCoachEntryPoint`s and its constructor
takes `stats`, `fasting` (**required**), `nutrition`, `treasury`, `budget`, `installments`, `ledger`,
`storage`, and two services. Its `_buildContext()` reads fasting and nutrition state for the
non-finance entry points. Three hard web blockers follow:

| Dependency | Reached via | Why it fails on web |
|---|---|---|
| `FastingPresenter` (required ctor arg) | `notification_service.dart` | `flutter_local_notifications` has no web impl |
| `NutritionPresenter` (unconditional import) | `food_db_service.dart` | `dart:io` + `sqflite` — compile error, not a runtime stub |
| `OnDeviceAiCoachService` (unconditional import) | `flutter_gemma` | pulls the on-device model stack into a static web bundle |

Three options were considered:

- **Conditional imports / stub files.** Rejected: it would spread `kIsWeb` branching and
  `_stub.dart` shadow files across the presenter layer to serve one entry point, and every future
  nutrition or fasting field added to `_buildContext()` becomes a new web landmine.
- **Make `fasting`/`nutrition` nullable in place.** Rejected as insufficient — nullability fixes the
  constructor but not the *imports*, which are what break the compile. Removing the imports means
  removing the code that uses them, which is the extraction anyway, done less cleanly.
- **Extract the finance-advisor path into its own presenter. → CHOSEN.**

`FinanceAdvisorPresenter` owns exactly what the `financeAdvisor` entry point needs: the advisor
context builder (the `isAdvisor` branch of `_buildContext()`, ~`ai_coach_presenter.dart:801-889`),
the conversation store and its cap/archive logic, `AdvisorProfile` memory, and the
confirm-before-commit hand-off to `LedgerPresenter.sendChatInput`. Its dependencies are
`TreasuryDashboardPresenter`, `BudgetPresenter`, `InstallmentPresenter`, `LedgerPresenter`,
`StorageService`, and an injected `AiCoachService` — all already on the web path.

`AiCoachPresenter` keeps its other five entry points and **delegates** `financeAdvisor` to the new
presenter, so mobile and web run the same advisor code. This is a move-and-delegate refactor: the
storage keys, sync domains, Lambda `op`, and `AdvisorProfile` model are untouched, so existing
advisor conversations and memory survive with no migration.

**Risk:** the extraction touches a presenter with substantial behavior. Mitigation — a
characterization test asserting the extracted presenter produces a byte-identical advisor context
for a fixed fixture, run before and after the move.

### D2 — `AiChatSheet` narrows to an interface, and web gets its own container

`AiChatSheet` itself is web-safe (`image_picker` has a web implementation), so the *chat body* is
reusable. But a draggable bottom sheet is the wrong container on a 1440px desktop.

Decision: extract the chat body into a `FinanceAdvisorChat` widget parameterized by
`FinanceAdvisorPresenter`. Mobile keeps `AiChatSheet` as the bottom-sheet container around it; web
adds `WebAdvisorPanel`, a docked right-hand column (~380px, collapsible) around the same body. One
chat implementation, two containers appropriate to their platform.

The mobile `AiChatSheet` continues to accept the other entry points via `AiCoachPresenter`
unchanged — only the `financeAdvisor` case routes through the new body.

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
| `web_number.dart` (new) | JetBrains Mono tabular figures, matching `AppTextStyles.numeric` | every figure on every page |
| `web_stat_tile.dart` | domain-tinted icon badge; figures via `WebNumber` | dashboard, budget, bills, history |
| `web_card.dart` | 0.5px hairline @40% + `AppCard.elevated` shadow | every card |
| `web_net_worth_hero.dart` (new) | gradient + momentum pill + sparkline | dashboard |
| `_CashFlowCard` | paired income/expense bars | dashboard |

The sparkline painter is the one piece of genuine duplication. `_SparklinePainter` is private to
`net_worth_hero.dart`; it gets promoted to a shared widget both heroes use rather than copied.

**Explicitly not changed:** `WebShell`'s sidebar, `WebDataTable`'s structure, the two-column content
grid, and the web-specific breakpoint logic. Web should look like the same *product*, not like a
phone.

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

Decision: change `MetricCardsGrid`'s tile set to web's decomposition (Upcoming Bills · To Receive ·
Budget & Savings Due · Proj. Month-End Cash), render the projection unconditionally, and give every
tile sub-copy naming what it deducts. `MONTH IN` / `MONTH OUT` move into the cashflow strip's
existing bars, which already show exactly those two figures — removing a genuine duplication rather
than growing the grid.

**Rejected:** changing `endingCash` to subtract remaining budget. It would make `endingCash` and
`forecastedNetBalance` the same getter, break `_unpaidBillBudgetOverlap`'s stated contract ("an
unpaid bill is already subtracted via `endingCash`"), and invalidate
`treasury_dashboard_parity_test.dart`. The getter is correct; only its billing on screen was wrong.

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
- **JetBrains Mono web font cost.** Adds a font fetch to first paint. Accepted: `google_fonts`
  already ships Plus Jakarta Sans on web, so this is one more request on an already-warm path, and
  tabular figures are the single largest contributor to "these look like different apps".
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

## Open Questions

- Should `WebAdvisorPanel` be reachable from every web page (a persistent dock, so you can ask about
  a bill while looking at the Bills table) or only from its own sidebar destination? A persistent
  dock is the stronger desktop experience but costs a layout change in `WebShell`, which D4
  otherwise leaves alone. Defaulting to the sidebar destination for this change.
- Does the mobile cashflow strip need `MONTH IN`/`MONTH OUT` numeric labels added when the grid
  drops those tiles, or are the existing bar amount labels sufficient? Leaning sufficient — they
  already print both figures — but worth a look on device.
