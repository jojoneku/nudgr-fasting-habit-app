# Trends & Projections Spec

> Status: PLANNED — NOT IMPLEMENTED · Authored: June 10, 2026 · Plan: `.claude/plans/045-trends-and-projections.md`
> Related: [nutrition_dashboard_rehaul_spec.md](nutrition_dashboard_rehaul_spec.md), `BodyCompositionCalculator`

## Overview

The nutrition dashboard (`NutritionHistoryScreen`) answers *"am I on track this
week?"* via `dashboardStatus`, 7-day averages, and a two-halves weight trend. It
cannot answer the questions that keep a player engaged over months: *"how fast am
I actually losing?"*, *"when do I hit 70 kg?"*, *"is my real TDEE what the formula
says?"*

This spec adds a **Trends** layer: least-squares weight-change rate, a projected
goal-weight date with confidence band, 30-day calorie adherence, an **observed
TDEE** from energy balance (intake vs. weight delta), and protein hit-rate streaks
— framed in The System's RPG voice ("Projected level-up: 70.0 kg by Aug 12").
All math is pure and lives in `lib/utils/trend_math.dart`, following the
`BodyCompositionCalculator` extraction pattern (Plan 035/036). Presenters
delegate; views render.

## User Story

As a player on a cut, I want to see my real rate of loss, a projected date for my
goal weight, and whether my measured burn diverges from the formula — so the long
grind feels like a quest with an ETA instead of a number that wiggles daily.

## Trend Math Definitions

### Weight change rate (kg/week)

Least-squares regression of `weightKg` vs. days over the trailing **28-day
window** (≥ 5 entries spanning ≥ 10 days); falls back to **14 days** (≥ 4 entries
spanning ≥ 7 days); else `null`. Slope per-day × 7 → kg/week — irregular spacing
is handled naturally, no resampling. Also returns the **standard error of the
slope** for the confidence band.

### Goal projection

`(goalWeightKg − latestTrendWeight) / rate` → weeks remaining → projected date,
where `latestTrendWeight` is the regression value at the latest entry (smooths
water noise). Confidence band: recompute the ETA with `rate ± 1.96 × SE(rate)` →
earliest/latest dates; if the pessimistic rate crosses zero the band is
open-ended ("possibly later").

**No projection when:** goal is `maintain`/`recomp` (show **stability metrics**
instead — 28-day weight range, "Holding steady — ±0.4 kg over 4 weeks"); no
`goalWeightKg` set ("Set a goal weight" CTA); rate `null`, |rate| < 0.05 kg/week,
rate points away from the goal, or ETA > 18 months ("no reliable projection yet").

### Observed TDEE (energy balance)

Over the trailing 28 days: `observedTdee = avgDailyIntake −
(weightSlopeKgPerDay × 7700)`. Requires ≥ 14 logged days, logging consistency
≥ 80 % in the window, and a valid weight rate; else `null`. **Divergence flag**
when `|observedTdee − tdeeProfile.tdee| ≥ 200 kcal`: "Your data says you burn
~N kcal/day (formula says M). Consider adjusting your target." with a CTA to
`TdeeSetupScreen`. Informational only — never auto-adjusts.

### Calorie adherence (7 / 30-day rolling)

Fraction of *logged* days inside the goal's on-track band (same per-goal bands as
the dashboard rehaul spec). Unlogged days excluded from the denominator; always
shown next to logging consistency so 3 perfect logged days can't masquerade as a
perfect month.

### Protein hit-rate streaks

**Current** = consecutive days meeting the protein goal ending at the latest
logged day; **best** = longest run within the stored 90-day history.

## Data Model

### `lib/models/trend_insights.dart` (new value objects — never persisted)

```dart
class WeightRate   { double kgPerWeek; double standardError; int sampleCount; int windowDays; }
class GoalProjection {
  DateTime projectedDate; DateTime earliestDate;
  DateTime? latestDate;   // null = open-ended pessimistic bound
  double weeksRemaining;  double rateKgPerWeek;
}
class TdeeEstimate { int observedTdee; int formulaTdee; int divergenceKcal; bool isSignificant; }
class ProteinStreak { int current; int best; }
```

### `TdeeProfile` change (existing file)

Add `final double? goalWeightKg;` — nullable, round-trips through
`fromJson`/`toJson`, absent key reads as `null` (backward compatible). Edited in
`TdeeSetupScreen` (shown only for cut / lean-gain goals).

## Presenter API (`NutritionPresenter` — delegation only, no inline math)

```dart
WeightRate? get weightRate;            // TrendMath.weightRate(weightLog)
GoalProjection? get goalProjection;    // null for maintain/recomp/no-goal/unreliable
TdeeEstimate? get observedTdeeEstimate;
double? get calorieAdherence30d;       // null when < 10 logged days in window
int get thirtyDayAvgCalories;
ProteinStreak? get proteinStreak;      // null when no protein goal set
double? get weightStability28d;        // max−min kg in window; maintain/recomp metric
String? get projectionHeadline;        // RPG copy, e.g. "Projected level-up: 70.0 kg by Aug 12"
```

`projectionHeadline` composes the user-facing sentence — presenter owns copy,
view stays dumb.

## UI Requirements

### `_TrendsSection` — new section in `NutritionHistoryScreen`

Inserted between `_GoalChecksSection` and `_MacroAveragesSection` (the screen is
already the analytics home; no new route). Built with the existing custom-painter
chart pattern (`_CalorieTrendPainter` / `_WeightTrendPainter` — there is **no**
fl_chart dependency; do not add one).

1. **Projection card** — `projectionHeadline` (titleMedium) + rate line
   ("−0.42 kg/week over 28 days") + confidence range ("Aug 3 – Sep 1") in
   `onSurfaceVariant`. Gold accent (`context.appColors.gold` theme extension) on
   the date — this is the "level-up" moment.
2. **Weight trajectory mini-chart** — reuse `_WeightTrendPainter` data, add a
   dashed regression line and (when projecting) a faint extension to the goal
   line. Static, painter-drawn, no animation.
3. **Observed TDEE row** — "Observed burn ~2,340 kcal/day · formula 2,100" with
   `warning_amber_outlined` when `isSignificant` + "Review target" tertiary
   button → `TdeeSetupScreen`. Hidden entirely when `null`.
4. **Adherence + streak row** — two tiles ≥ 48 px tall: "30-day adherence 78 %",
   "Protein streak 6 days · best 11".

### States

| State | Trigger | Shown |
|---|---|---|
| Locked | < 4 weight entries and < 10 logged days | Hint row: "Log weight 2–3× a week to unlock projections" |
| Stability | goal ∈ {maintain, recomp} | Stability copy + range chip, no projection |
| No goal weight | cut/bulk without `goalWeightKg` | Rate + "Set a goal weight" CTA |
| Full | data thresholds met | All four rows |

Headline readable in < 1 s. Projection card fades in once (200 ms,
`Curves.easeOut`); charts static. Theme-aware colors only — no hardcoded
`AppColors.*` in widgets.

## RPG Mechanics & Storage

Read-only analytics — **no new XP events**; the RPG flavor is linguistic
("Projected level-up"). Future hook (out of scope): a one-time "Projection
fulfilled" achievement when `latestWeight` crosses `goalWeightKg`.

No new `StorageService` keys. `TdeeProfile` JSON gains optional `goalWeightKg`.
The 90-day nutrition-log prune and existing weight log fully cover the 28-day
windows. All trend values are derived, never persisted.

## Edge Cases

- **Sparse weigh-ins (1×/week):** 28-day window with ≥ 5 entries still regresses
  fine; below thresholds the section locks rather than showing a junk slope.
  Same-day duplicate weigh-ins need no dedupe — regression uses all points.
- **Goal weight already passed** (lost more than planned): `projectionHeadline`
  says "Goal reached — set a new target?".
- **Bulk goal:** projection works symmetrically (positive rate toward a higher goal).
- **Observed TDEE during rapid water swings** (first cut week): the 14-day minimum
  and 28-day window dampen this; copy says "~estimated" — never authoritative.
- **Simple mode (no TdeeProfile):** rate + streaks still render; projection, TDEE,
  and adherence rows hidden.
- **Backfilled weight entries:** regression keys off `loggedAt`, so backdated
  entries (Plan 037 pattern) slot in correctly on next repaint.

## Acceptance Criteria

- [ ] `TrendMath` is pure/static, side-effect-free, and unit-tested (Given-When-Then)
- [ ] `weightRate` returns null below data thresholds; never extrapolates from 2 points
- [ ] Projection date + confidence band correct for cut and bulk; absent for
      maintain/recomp (stability metrics shown instead)
- [ ] Observed TDEE requires ≥ 14 logged days at ≥ 80 % consistency; divergence
      flag fires only at ≥ 200 kcal
- [ ] `NutritionPresenter` exposes only delegating getters — zero math in the view,
      zero math inline in the presenter
- [ ] `goalWeightKg` round-trips and old persisted profiles load unchanged
- [ ] Trends section renders all four states; touch targets ≥ 44×44 px;
      no animation > 400 ms; theme-aware colors only
