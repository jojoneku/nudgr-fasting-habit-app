# Plan 045 — Trends & Projections (Nutrition + Weight Insights)

> Status: PLANNED — NOT IMPLEMENTED · Authored: June 10, 2026
> Spec: [docs/trends_projections_spec.md](../../docs/trends_projections_spec.md)

## Conflict Check

| Check | Finding |
|---|---|
| **File overlap** | `nutrition_history_screen.dart` is also touched by the body-measurements plan (`_MeasurementSection`) — additive sections, no collision. Plan 041 backlog reorders `NutritionPresenter` mutation methods; this plan adds read-only getters — disjoint. |
| **Model overlap** | None. `TdeeProfile` gains one nullable field; no plan owns that file currently. |
| **Presenter split** | Dashboard math already lives in `BodyCompositionCalculator` (Plan 035 A1 / 036). New math goes in a sibling util `TrendMath`, not back into the presenter. |
| **XP routing** | No `addXp` calls — read-only analytics. |
| **HubScreen** | Not touched. |
| **Supersedes** | Nothing. Extends nutrition_dashboard_rehaul (shipped). |
| **Dependency order** | None hard. Plays nicest after Plan 041's nutrition reorder, but order is irrelevant (no mutations here). |

## Goal

The dashboard says *whether* this week is on track; it can't say *how fast* or
*when*. Add a presenter-layer trends engine: least-squares weight-change rate,
projected goal-date with confidence band ("On pace to reach 70.0 kg by Aug 12 ·
Projected level-up"), observed TDEE from energy balance (with a divergence flag
vs. the Mifflin formula), 30-day calorie adherence, and protein streaks. Long
goals become quests with an ETA — that's the retention hook.

## Key findings (verified June 10, 2026)

- `sevenDayAvgCalories`, `proteinHitRate7d`, `weightTrendDirection`,
  `dashboardStatus` already exist and **delegate to
  `lib/utils/body_composition_calculator.dart`** (static, pure — Plan 035/036
  extraction). `TrendMath` must follow the same pattern; tests live at
  `test/utils/body_composition_calculator_test.dart` as the template.
- Existing weight trend is a crude two-halves average comparison
  (`BodyCompositionCalculator.weightTrend`) — direction only, no rate.
- **There is no goal weight anywhere in the codebase** (`goalWeight`/`targetWeight`
  grep: zero hits). `TdeeProfile` (weight/height/age/sex/activity/goal/adjustment)
  needs a nullable `goalWeightKg`; input UI belongs in
  `lib/views/nutrition/tdee_setup_screen.dart` (sole `TdeeProfile(` constructor
  site in views).
- **No fl_chart in pubspec.** Charts are hand-rolled `CustomPainter`s —
  `_CalorieTrendPainter` (line ~544) and `_WeightTrendPainter` (~1346) in
  `nutrition_history_screen.dart`; treasury does the same
  (`category_pie_chart_card`, `spending_analytics_card`). Reuse, don't add a dep.
- History retention: `saveNutritionLog` prunes at **90 days**
  (`local_storage_service.dart:408`) — comfortably covers 28/30-day windows.
  `_history` is ordered newest-first (`history.take(7)` idiom throughout).
- `WeightEntry` = `{id, weightKg, loggedAt}`; weight log is append-ordered,
  synced (PR #185).

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/utils/trend_math.dart` | Create | Utils |
| `lib/models/trend_insights.dart` | Create | Model |
| `lib/models/tdee_profile.dart` | Modify (`goalWeightKg`) | Model |
| `lib/presenters/nutrition_presenter.dart` | Modify (delegating getters) | Presenter |
| `lib/views/nutrition/nutrition_history_screen.dart` | Modify (`_TrendsSection`) | View |
| `lib/views/nutrition/tdee_setup_screen.dart` | Modify (goal-weight field) | View |
| `test/utils/trend_math_test.dart` | Create | Test |
| `test/models/tdee_profile_test.dart` | Create/extend (json round-trip) | Test |

No `StorageService` changes — `TdeeProfile` already persists as a JSON blob.

## Interface Definitions

```dart
// ── lib/utils/trend_math.dart — pure, static, side-effect-free ──
abstract final class TrendMath {
  /// Least-squares slope over the trailing 28d window (≥5 entries spanning
  /// ≥10d), falling back to 14d (≥4 entries spanning ≥7d), else null.
  static WeightRate? weightRate(List<WeightEntry> log, {DateTime? now});

  /// Null for maintain/recomp, missing goalWeightKg, |rate| < 0.05 kg/wk,
  /// wrong-direction rate, or ETA > 18 months. Band from ±1.96·SE(slope).
  static GoalProjection? projectGoal({
    required List<WeightEntry> log,
    required double goalWeightKg,
    required String goal,            // TdeeProfile.goal
    DateTime? now,
  });

  /// avgIntake − slopeKgPerDay·7700 over 28d. Null below ≥14 logged days
  /// at ≥80% consistency, or when weightRate is null.
  static TdeeEstimate? observedTdee({
    required List<DailyNutritionLog> history,
    required List<WeightEntry> log,
    required int formulaTdee,
    DateTime? now,
  });

  static int rollingAvgCalories(List<DailyNutritionLog> history, int days);
  static double? calorieAdherence(
      List<DailyNutritionLog> history, TdeeProfile profile, int days);
  static ProteinStreak? proteinStreak(
      List<DailyNutritionLog> history, int proteinGoalG);
  static double? weightStability(List<WeightEntry> log, {int windowDays = 28});
}

// ── NutritionPresenter — delegation only ──
WeightRate? get weightRate;
GoalProjection? get goalProjection;
TdeeEstimate? get observedTdeeEstimate;
double? get calorieAdherence30d;
int get thirtyDayAvgCalories;
ProteinStreak? get proteinStreak;
double? get weightStability28d;
String? get projectionHeadline;   // RPG copy lives in the presenter, not build()

// ── TdeeProfile ──
final double? goalWeightKg;       // nullable, json-optional, copyWith support
```

Value objects (`WeightRate`, `GoalProjection`, `TdeeEstimate`, `ProteinStreak`)
are defined in the spec — derived, never persisted, no `toJson`.

## Implementation Order

1. [ ] **Model:** `trend_insights.dart` value objects; `TdeeProfile.goalWeightKg`
       (json round-trip + backward compat — absent key → null).
2. [ ] **Utils:** `TrendMath` with the six functions above. Pass `now` explicitly
       for testability (house pattern from `BodyCompositionCalculator`).
3. [ ] **Tests first-class:** `trend_math_test.dart` — Given-When-Then groups:
       regression slope/SE against hand-computed fixtures, sparse-data fallbacks,
       null-thresholds, maintain/recomp suppression, wrong-direction rate, TDEE
       divergence boundary (199 vs 200 kcal), protein streak with gap days.
4. [ ] **Presenter:** delegating getters + `projectionHeadline` copy composer.
       No `notifyListeners` changes — all derived from already-notified state.
5. [ ] **View:** `_TrendsSection` (private class, same file, between
       `_GoalChecksSection` and `_MacroAveragesSection`): projection card,
       regression-line overlay on the weight mini-chart (extend
       `_WeightTrendPainter` with an optional dashed trend line), observed-TDEE
       row with "Review target" → `TdeeSetupScreen`, adherence/streak tiles.
       Four states per spec (locked / stability / no-goal-weight / full).
6. [ ] **TdeeSetupScreen:** optional "Goal weight (kg)" field, shown for
       cut/bulk; validate sane range (30–300 kg); persists via existing
       `saveTdeeProfile` path.
7. [ ] **Verify:** `flutter analyze`, `dart format` (check before push),
       existing nutrition/dashboard tests green.

## RPG Impact

- XP awarded: **none** — read-only analytics.
- Level/streak affected: no. Protein *streak* here is display-only and distinct
  from the XP-paying log streak (Plan 037 ledger untouched).
- Notifications: none.
- Flavor: projection copy uses "Projected level-up" framing; gold accent on the
  projected date.

## Risks

- **Junk projections erode trust** (the feature's whole value is credibility).
  Mitigated by hard thresholds + confidence band + 18-month ETA cutoff; when in
  doubt the section says "no reliable projection yet" instead of guessing.
- **Observed TDEE is sensitive to unlogged days** (intake undercount inflates
  apparent burn... downward). The ≥80 % consistency gate is the guard; copy always
  hedges ("~", "estimated").
- **`nutrition_history_screen.dart` is already ~1,700 lines.** Acceptable to add
  one more private section per house style; if it crosses ~2,200 lines, extract
  sections to `lib/views/nutrition/widgets/` in a follow-up — don't block this plan.
- **7700 kcal/kg is a simplification** — fine for a divergence *flag*; never use
  it to auto-adjust targets.

## UX Verification

- [ ] No calculations/conditionals in `build()` — all via presenter getters
- [ ] Touch targets ≥ 44×44 px (tiles ≥ 48 px; "Review target" full-height)
- [ ] Projection card fade-in 200 ms; nothing > 400 ms; charts static
- [ ] Theme-aware colors only (gold via `context.appColors`, never `AppColors.*`)
- [ ] Glanceable: headline answers "when do I get there?" in < 1 s

## Acceptance Criteria

- [ ] All spec acceptance criteria pass
- [ ] `TrendMath` has zero imports from presenters/views/services
- [ ] Old persisted `TdeeProfile` JSON (no `goalWeightKg`) loads without error
- [ ] Maintain/recomp users never see a goal-date projection
- [ ] `flutter analyze` + `dart format` clean; full test suite green
