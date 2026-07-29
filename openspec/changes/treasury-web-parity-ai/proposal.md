## Why

The Treasury redesign (July 2026: `redesign-treasury-dashboard`, `-ledger`, `-bills`, `-budget`,
`-history`, `-cart`) reskinned the mobile module onto the Nudgr design system and gave it a set of
signature moves — the NET WORTH gradient hero with its sparkline, the cashflow strip, tinted
domain icon badges, and monospaced tabular figures. The web companion (`lib/views/web/`, Plans
050–052) predates all of it. Its *palette* is already unified — `web_theme.dart` builds from the
same `NudgrDark`/`NudgrLight` tokens and the same Plus Jakarta Sans — but none of the redesign's
visual signatures reached it, so the two surfaces read as cousins rather than one product.

Separately, the web is missing the AI pipeline. Half of it is already there: `TreasuryWebApp`
injects `CloudAiCoachService` into `LedgerPresenter`, and the web ledger's Quick Add FAB
(`web_ledger_page.dart`) does one-shot natural-language logging through Bedrock. What is absent is
the **Money Mentor** conversational advisor (shipped on mobile via `ai-financial-advisor`) and
**receipt-photo logging** (shipped via `receipt-total-scan`). Both are the AI features users
actually reach for when sitting at a desk with a month of statements open.

Neither gap is a data problem. Web and mobile share every presenter, so this is view-layer work
plus one presenter decomposition.

Finally, an honest-numbers defect surfaced while scoping this. Both platforms compute the month-end
projection from the *same* getter — `TreasuryDashboardPresenter.forecastedNetBalance`, which already
subtracts `totalBudgetRemaining`. The math is not divergent. What diverges is **what each platform
puts in front of the user**:

- Web's "Month-End Outlook" shows four tiles that decompose the forecast — Upcoming Bills, To
  Receive, Budget / Savings Due, and **Proj. Month-End Cash** (`forecastedNetBalance`).
- Mobile's "Month Outlook" grid (`metric_cards_grid.dart`) leads with **ENDING CASH**
  (`endingCash` — liquid + receivables − unpaid bills, **no** budget deduction) and renders the
  `FORECAST` tile *only* `if (presenter.hasBudget)`; otherwise slot four becomes Liabilities.

So a mobile user with budgets set sees a prominent "Ending Cash" figure that looks like the
projection but does not reserve the budget they still intend to spend, sitting beside a differently
named tile that does. The two platforms report the same math under labels that mean different
things. This change aligns the surfacing, not the arithmetic.

## What Changes

### A. Skin parity on web

Port the redesign's signature moves to the web design system. Desktop layout is preserved — this is
the *skin*, not a phone layout stretched wide.

- **Monospaced tabular figures.** Introduce a web numeric text treatment matching
  `AppTextStyles.numeric` (JetBrains Mono, tabular figures) and route every currency/percentage
  figure in `WebStatTile`, `_MiniStat`, `WebDataTable`, and the chart axis labels through it.
  Today's plain `headlineSmall`/`bodySmall` figures jitter as digits change and read as a different
  type family from mobile.
- **Net-worth hero.** Add `WebNetWorthHero` — the gradient card, momentum pill, "±₱X this month"
  line, and sparkline from `net_worth_hero.dart`, re-proportioned for a desktop-width card.
  Replaces the flat `WebStatTile(accent: true)` "Net Position" tile.
- **Cashflow bars.** Extend the existing `_CashFlowCard` with the paired income/expense bars sized
  to the larger flow, mirroring `CashflowStrip`. The card's existing mini-stats and
  spent-percentage bar stay.
- **Tinted domain icon badges.** `WebStatTile`'s 28px `onSurface@5%` neutral square becomes the
  redesign's domain-tinted badge (`color@12–14%`, `AppRadii.sm`), matching `AppIconBadge`.
- **Card treatment.** `WebCard`'s 1px `outlineVariant@50%` border becomes the redesign's 0.5px
  hairline at 40% plus the subtle elevation shadow from `AppCard.elevated`.

### B. AI pipeline on web

- **Extract `FinanceAdvisorPresenter`.** `AiCoachPresenter` cannot compile for web: it *requires* a
  `FastingPresenter` (→ `notification_service`) and imports `NutritionPresenter`
  (→ `food_db_service` → `dart:io` + `sqflite`) and `OnDeviceAiCoachService` (→ `flutter_gemma`).
  Extract the `financeAdvisor` path — the advisor context builder, conversation store, and
  `AdvisorProfile` memory — into a presenter depending only on treasury/budget/installments/ledger/
  storage plus an injected `AiCoachService`. Mobile's Money Mentor delegates to the same presenter,
  so there is one implementation, not a web fork.
- **Add a Money Mentor surface on web.** A docked right-hand `WebAdvisorPanel` (desktop-appropriate
  where a draggable bottom sheet is not) with conversation history, the advisor-memory editor, and
  the confirm-before-commit log cards — the same behaviors `AiChatSheet` exposes on mobile. New
  sidebar destination in `treasury_web_app.dart`.
- **Add receipt scanning on web.** `LedgerPresenter.logReceiptPhoto()` is already cloud-only and
  web-clean. `photo_log_sheet.dart` cannot be reused (it imports `NutritionPresenter` for the meal
  branch), so add a receipt-only web variant with drag-and-drop plus a file picker, feeding the
  same confirm-before-commit pipeline.

### C. Month-end projection surfacing

- **Rework mobile's Month Outlook** (`metric_cards_grid.dart`) to mirror web's decomposition:
  Upcoming Bills · To Receive · Budget & Savings Due · **Proj. Month-End Cash**. The projection
  tile renders unconditionally (not gated on `hasBudget`), and raw `endingCash` stops being the
  headline figure.
- **Align labels and sub-copy across both platforms** so the same number carries the same name, and
  each tile states what it does and does not deduct.
- **No math changes.** `forecastedNetBalance`, `endingCash`, and every other getter keep their
  current definitions and existing tests.

## Capabilities

### New Capabilities
- `treasury-web`: The desktop Treasury companion's own requirements — visual parity with the
  mobile Nudgr skin, and the web surfaces for conversational financial advice and receipt logging.

### Modified Capabilities
- `treasury-dashboard`: The Month Outlook requirement changes from "Ending Cash + conditional
  Forecast" to an unconditional four-tile forecast decomposition matching the web.
- `ai-financial-advisor`: The advisor becomes platform-agnostic — its presenter no longer depends on
  fasting/nutrition, and the capability is available on web as well as mobile.

## Impact

- **UI (web)**: new `lib/views/web/widgets/web_number.dart`, `web_net_worth_hero.dart`,
  `web_advisor_panel.dart`, `web_receipt_drop.dart`; modified `web_card.dart`, `web_stat_tile.dart`,
  `web_data_table.dart`, `web_charts.dart`, `web_dashboard_page.dart`, `treasury_web_app.dart`
  (new destination + advisor wiring).
- **UI (mobile)**: `lib/views/treasury/dashboard/metric_cards_grid.dart` (tile set + labels);
  `lib/views/widgets/ai_chat_sheet.dart` (accepts the narrower presenter).
- **Presenters**: new `lib/presenters/finance_advisor_presenter.dart`;
  `lib/presenters/ai_coach_presenter.dart` delegates its `financeAdvisor` path to it.
  `TreasuryDashboardPresenter` is **untouched**.
- **Composition roots**: `lib/views/home_screen.dart` and `lib/views/web/treasury_web_app.dart`.
- **Tests**: web widget tests for the new surfaces; a mobile widget test asserting the Month Outlook
  tile set; a presenter test asserting the extracted advisor builds the same context as today.
- **Non-breaking**: every existing presenter getter, storage key, sync domain, and Lambda `op` is
  unchanged. Mobile advisor behavior is a delegation refactor, not a rewrite.

## Non-goals

- **Changing any finance math.** `forecastedNetBalance` and friends keep their definitions; this
  change only alters which figures are labelled what, and where.
- **A phone-shaped web layout.** Web keeps its sidebar shell, data tables, and multi-column grids;
  only the skin converges.
- **Nutrition, fasting, quests, activity, or the on-device model on web.** Out of scope, and the
  presenter extraction exists precisely so they stay out of the web bundle.
- **New AI capabilities.** No new Lambda `op`, no new model tier, no new advisor behaviors — the web
  gets the advisor that already ships on mobile.
- **Editing budgets or paying bills in-conversation.** Still deferred, per `ai-financial-advisor`.
- **Reworking the web Ledger's existing Quick Add.** It already works; it is not part of this change.
