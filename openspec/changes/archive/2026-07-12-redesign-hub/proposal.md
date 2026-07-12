## Why

The Hub is the app's home screen and the anchor of the Nudgr redesign. Today it's a
drag-reorderable stack of full-width cards with no at-a-glance hero: the fasting ring is buried
inside the fasting card, calories and steps are separate progress bars, and there's no streak or
coaching cue. The locked-in reference (**Hub v3** — the ring version) leads with a **three-ring
Fast/Food/Move hero**, a one-line adaptive coach nudge, a streak pill, and a richer Finance card,
over the existing docked quick-logger.

This is a **restyle + additive** change: we mirror v3's structure and ring language while keeping
every current capability. v3 visually drops Activity-distance, Nutrition-macros, and the
Stats/Character card — per project rule we **keep** those (as secondary cards), so the redesigned
Hub is a superset of the mockup, not a replacement.

## What Changes

- Add a **three-ring hero** at the top of the Hub — Fast (countdown), Food (kcal), Move (steps) —
  as separate full-circle rings with center value + caption, using domain accents
  (blue/teal/green) and per-domain track fills; Food ring flips to danger + "OVER" when over goal;
  each ring shows an idle/empty state (track + glyph) when its source hasn't started.
- Add a **streak pill** (flame + count) and keep the greeting/date + settings gear in the header.
- Add an **adaptive coaching line** — one sentence + XP, with a mood tint (neutral/urgent/positive).
- **Restyle & expand the Finance card**: safe-to-spend (or month-end net-worth) hero, in/out
  cashflow bars, savings-rate chip, and a "coming up" bill-countdown list — reusing existing
  treasury getters plus a small number of new computed getters.
- Pair **Weight + Body** into a compact 2-up row; keep Quests card (minor restyle); keep the docked
  quick-log bar and drag-to-reorder for the card stack below the hero.
- **Preserve** (not in v3, must not be removed): the Activity card (distance/km), the Nutrition
  macro breakdown (P/C/F), and the Stats/Character card — surfaced as secondary cards.
- Extend the ring widget/painter with a full-circle (no-gap) mode + idle rendering **without**
  changing the default behavior other screens rely on (timer, activity).
- Make the hero slots **configurable** and add a **macro-split ring** (proportional P/C/F) that
  auto-replaces the Fast slot for users who don't fast, with a manual override.
- Add **Hub micro-actions**: mark-quest-done, tap-to-log inline weight/body entry, and pay-a-bill
  (with a required amount + account confirm — never a silent money mutation).
- Keep the docked quick-log bar **pinned** to the bottom (it already is, as a `bottomNavigationBar`).

Non-breaking. No existing card, presenter, or navigation is removed; card-order/reorder is retained.

## Capabilities

### New Capabilities
- `hub`: The Hub home screen — header (greeting/date/streak/settings), the three-ring
  Fast/Food/Move hero (values, idle states, over-goal state, domain colors), the adaptive coaching
  line, the card stack and its ordering/reorder, the rich Finance card, the Weight+Body pairing,
  preservation of Activity/Nutrition-macros/Stats, and graceful degradation when optional
  presenters are absent.

### Modified Capabilities
<!-- None at the spec level. Ring-widget/painter and treasury getter additions are implementation
     details; `onboarding` is unaffected. openspec/specs/ has no existing `hub` capability. -->

## Impact

- **New:** `lib/views/widgets/hub/hub_rings_hero.dart` (three-ring hero) and a coaching-line widget;
  possibly `hub_finance_card.dart` (or a major rework of `treasury_hub_card.dart`).
- **Modified:** `lib/views/hub_screen.dart` (header + pinned hero above the reorderable list);
  `lib/views/widgets/hub/*` (restyle cards; pair weight+body); `lib/views/widgets/partial_ring_painter.dart`
  + `app_ring_progress.dart` (opt-in full-circle + idle/caption, default unchanged);
  `lib/presenters/hub_presenter.dart` (surface Stats; hero data plumbing);
  `lib/presenters/treasury_dashboard_presenter.dart` / `budget_presenter.dart` (safe-to-spend getter);
  a streak source and an AI-nudge getter (see design Open Questions).
- **Reuses (unchanged):** `AppRingProgress`, `FastingPresenter`, `NutritionPresenter`,
  `ActivityPresenter`, `TreasuryDashboardPresenter`, `QuestPresenter`, `AuthPresenter`,
  `QuickLogRouter`, the docked quick-log bar.
- **Deps:** none new (Phosphor/fonts remain the separate design-token effort; Material icons used).
- **Risk:** `PartialRingPainter` is shared with timer/activity — the full-circle change must be
  opt-in; verify no regression there.
