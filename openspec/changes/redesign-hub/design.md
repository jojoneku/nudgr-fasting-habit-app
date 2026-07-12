## Context

`hub_screen.dart` is a `CustomScrollView`: a pinned `SliverAppBar` (greeting + settings), then a
`SliverReorderableList` over `hubPresenter.cardOrder` (`HubCardType.fasting/nutrition/activity/
treasury/quests/stats/weightLog/bodyMeasurements`), then a docked `_QuickLogBar`
(`bottomNavigationBar`). The fasting ring lives inside the fasting card (`AppRingProgress` size 80);
calories/steps are `AppLinearProgress` bars; Treasury is a 3-column summary + bill warning + chat;
Stats card exists but is never mounted (`HubCardType.stats => SizedBox.shrink()`). Domain colors +
ring track fills already exist (`context.appColors.fast/food/move` + `fastTrack/foodTrack/moveTrack`).

Hub v3 (locked-in) adds a three-ring Fast/Food/Move hero, a streak pill, an adaptive coaching line,
and a rich Finance card, over the same docked logger — and visually omits Activity-distance,
Nutrition-macros, and Stats (which we keep per project rule).

## Goals / Non-Goals

**Goals:**
- Mirror v3's structure and ring language using theme-aware tokens, both modes.
- Reuse `AppRingProgress`; extend it/`PartialRingPainter` for a full-circle + idle look **without**
  changing the default other screens depend on.
- Superset, not replacement: preserve Activity-distance, macros, and Stats as secondary cards.
- Keep card ordering/reorder and the docked quick-logger.

**Non-Goals:**
- Running the on-device LLM on Hub build (the coaching line is rules-based, see Decision 4).
- Redesigning the individual detail screens (fasting/nutrition/etc.) — this change is the Hub only.
- Bottom tab bar (v3 has none; navigation stays card + logger + existing routes).

## Decisions

**1. Layout: header pinned, hero + coaching scroll above the reorderable list.** Keep the pinned
`SliverAppBar` for greeting/date/streak/settings. Add `SliverToBoxAdapter`s for the three-ring hero
and the coaching line *before* the `SliverReorderableList`. The hero is not itself reorderable; the
existing drag list is untouched below it.
_Alternative:_ hero inside the SliverAppBar (scrolls away / collapses). Rejected for v1 — simpler and
less regression risk to keep the app bar as-is and add scrolling sliver content.

**2. Rings reuse `AppRingProgress`; painter gains an opt-in full-circle mode.** Add a
`gapFraction` parameter to `PartialRingPainter` (default = current `0.2`, so `timer_tab` /
`activity_screen` are byte-for-byte unchanged) and thread it through `AppRingProgress`. The hero
passes `gapFraction: 0` for full circles. **Idle** = `value: 0` + a glyph `center` + plain caption
(no painter change). **Over-goal Food** = `primaryColor: colorScheme.error`, `value: 1`, center
"+N OVER". A new `HubRingsHero` widget composes the three rings + captions and pulls from
Fasting/Nutrition/Activity presenters (all nullable-safe).

**3. Finance card reworked into `hub_finance_card.dart` (or a major `treasury_hub_card` rework).**
Hero = **`forecastedNetBalance`** (already exists, `treasury_dashboard_presenter.dart:540` — liquid
minus unfunded set-asides, unpaid bills, and remaining budget = the user's "forecasted ending cash
balance"); month-end may surface net-worth. Cashflow in/out bars from `monthTotalInflow/Outflow`;
savings-rate chip from `savingsRate`; bill countdown from `upcomingBills`. **No new getter needed.**
The existing monthly summary + embedded quick-log stay reachable.

**4. Coaching line is AI-generated, async and non-blocking.** Add a lightweight nudge method to
`AiCoachPresenter` (e.g. `hubNudge` string + `refreshHubNudge()`), driven by the existing coach
service from a compact state summary. It runs **off the build path**: the Hub shows the cached
last nudge (or a neutral fallback) immediately and updates when generation completes; failure keeps
the fallback. Mood tint derives from state (bill imminent/over-budget → urgent; goals met →
positive; else neutral). This satisfies "wire the real AI coach" without a synchronous LLM call on
build.
_Alternative:_ rules-based only. Rejected — user wants the real coach; rules-based logic remains as
the fallback string.

**5. Preserve omitted features as secondary cards.** Surface the **Stats/Character** card (remove
the `SizedBox.shrink()`; add to the base order, de-prioritised). Keep the **Nutrition macro** card
and the **Activity** card (steps feed the Move ring, but the card retains distance + macro detail).
They sit lower in the default order so the hero + Quests + Finance lead.

**6. Macro-split ring is a segmented donut, distinct from the progress rings.** A separate painter
(or a `segments` mode) draws 3 proportional arcs (protein/carbs/fat) summing to the full circle,
using the app's macro colors (protein blue, carbs gold, fat red — matching the Status Window). It
is a parts-of-a-whole visual, not progress-to-goal, so it reads differently on purpose.

**7. Hero slots are configurable with a no-fasting default.** The three slots resolve from a hero
config (persisted device/user pref via SettingsPresenter). Default config = Fast/Food/Move. If the
user doesn't fast (no fasting goal, or no fast ever started), slot 1 auto-resolves to the
macro-split ring; a settings screen lets the user override any slot. Keep the resolution logic in a
presenter/pure helper, not `build()`.

**8. Micro-actions reuse existing presenter methods; money actions confirm.** Mark-done →
`QuestPresenter.completeQuest`; inline weight/body entry → the existing weight/measurement save on
`NutritionPresenter`, revealed via local widget state (progressive disclosure, no new route);
pay-a-bill → the existing `BillsReceivablesPresenter.payBill(bill, accountId: …)` (which already
debits the ledger, or makes a transfer for credit cards, and defaults to `bill.accountId`), gated
behind a confirm sheet (`AppBottomSheet`) showing amount + a source-account selector. The selector
**reuses the app's existing Flutter account picker** — the same `DropdownButtonFormField<String>`
pattern used in `add_bill_sheet.dart` / `add_installment_sheet.dart` (using `initialValue`, **not**
the deprecated `value`, per Flutter ≥3.33) — preselected to `bill.accountId`. **No native/HTML
picker; no bespoke control.** One primary action per card; state updates immediately via
`notifyListeners`.
_Alternatives rejected:_ silent one-tap Pay (money mutations need a confirm); a custom inline
account list (the app already standardises on the dropdown-field picker — reuse it, don't reinvent).

## Risks / Trade-offs

- **Shared painter regression** (`PartialRingPainter` used by timer/activity) → make full-circle
  strictly opt-in via a defaulted `gapFraction`; visually verify timer + activity unchanged.
- **Busier-than-mockup screen** (superset keeps 3 extra features) → push preserved features below
  the fold via card order; the hero carries the glanceable summary.
- **Hero + reorderable coexistence** → hero is separate leading slivers, not list items; drag logic
  untouched. Verify reorder still works with leading content.
- **Optional-presenter nulls** → hero + cards must degrade (idle rings, hidden/empty cards); covered
  by a widget test with null Nutrition/Activity.
- **Over-goal ring semantics** → explicit "over" state (color flip + "+N OVER"), not a clamped bar.

## Migration Plan

Additive, non-breaking. Land in order: (1) painter `gapFraction` + verify timer/activity; (2)
`HubRingsHero` + idle/over states; (3) header streak pill + rules-based coaching line; (4) Finance
card rework + `safeToSpend` getter; (5) weight+body 2-up + surface Stats card + card-order tweak;
(6) wire hero/coaching into `hub_screen`; (7) verify (tests + both themes + browser preview).
Rollback = revert the branch; no persistence/schema changes.

## Resolved decisions (from review)

1. **Finance hero = `forecastedNetBalance`** (forecasted ending cash: liquid − set-asides − bills −
   remaining budget). Getter already exists — reuse it.
2. **Streak pill = nutrition log streak** (`NutritionPresenter.logStreak`).
3. **Coaching line = real AI coach**, generated async/off-build via `AiCoachPresenter` with a
   neutral fallback string (Decision 4).
4. **Preserved features = secondary cards** below Quests + Finance (Activity/distance,
   Nutrition/macros, Stats/Character).

## Open Questions

_None outstanding._
