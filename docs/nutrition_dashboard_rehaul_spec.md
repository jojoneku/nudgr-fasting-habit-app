# Nutrition Dashboard Rehaul Spec

## Overview

Rehauling `NutritionHistoryScreen` into a **goal-aware dashboard** that adapts its
scoring, labels, and visual language to the user's selected body-composition goal:
**Cut**, **Maintain**, **Lean gain**, or **Recomp**. The current screen shows the
same static signals regardless of intent — a calorie surplus is "bad" for a cutter
but neutral for a lean-gainer. This spec fixes that.

The body measurements feature (waist, etc.) is out of scope here and will plug into
the recomp detection logic as a follow-up spec.

---

## User Story

As a user tracking nutrition, I want the history dashboard to interpret my data
through the lens of my current goal — so that "on track" actually means something
relevant to whether I'm cutting, maintaining, lean gaining, or recomping, rather
than showing me a generic calorie score that may not match what I'm trying to do.

---

## Goal Definitions & Scoring Logic

### Goal types (TdeeProfile.goal values)

| Value | Display name | Calorie target | Protein target |
|---|---|---|---|
| `'cut'` | Cut (−N kcal) | TDEE − 300 (or custom) | 2.2 g/kg |
| `'maintain'` | Maintain | TDEE | 1.8 g/kg |
| `'bulk'` | Lean gain (+N kcal) | TDEE + 250 (or custom) | 2.0 g/kg |
| `'recomp'` *(new)* | Recomp | TDEE (maintenance) | 2.4 g/kg |

### On-track thresholds (7-day rolling average)

| Goal | On track | Too aggressive | Too high | Not enough surplus | Low protein |
|---|---|---|---|---|---|
| Cut | avg ∈ [target−100, target+100] + protein ≥ 70 % | avg < target−200 | avg > target+100 | — | protein hit rate < 50 % |
| Maintain | avg ∈ [target−100, target+100] | — | avg > target+150 | avg < target−150 | protein hit rate < 40 % |
| Lean gain | avg ∈ [target−100, target+150] + protein ≥ 70 % | — | avg > target+200 | avg < target−100 | protein hit rate < 60 % |
| Recomp | avg ∈ [target−150, target+100] + protein ≥ 80 % | avg < target−200 | avg > target+200 | — | protein hit rate < 65 % |

### Possible recomp detection (Cut goal only)

When all three hold simultaneously:
1. Calorie avg is within the Cut on-track band (deficit is happening)
2. Weight trend is `stable` (≤ 0.1 kg/week change over last 14 entries)
3. At least 14 weight log entries exist

→ status becomes `possibleRecomp` with the message:
*"Weight stable despite deficit — if you're training, this may be recomp. Body
measurements would confirm."*

### Weight trend direction

Computed from the last 14 `WeightEntry` records:
- Split into two halves of 7; compare their averages.
- `down` if Δ < −0.1 kg (half-period avg)
- `up` if Δ > +0.1 kg
- `stable` otherwise
- `insufficient` if fewer than 4 entries exist

---

## Data Model

### TdeeProfile changes (no new file — update existing `lib/models/tdee_profile.dart`)

```dart
// Add 'recomp' as a valid goal value.
// Keep 'bulk' stored in JSON for backward compat; display as 'Lean gain'.

String get goalDisplayName => switch (goal) {
  'cut' => 'Cut',
  'bulk' => 'Lean gain',
  'recomp' => 'Recomp',
  _ => 'Maintain',
};

// Updated targetCalories — recomp == maintenance
int get targetCalories {
  final adj = calorieAdjustment;
  if (adj != null) return (tdee + adj).clamp(500, 99999);
  return switch (goal) {
    'cut' => tdee - 300,
    'bulk' => tdee + 250,
    'recomp' => tdee, // same as maintain, different protein target
    _ => tdee,
  };
}

// Updated protein — recomp is highest
int get suggestedProteinG {
  final multiplier = switch (goal) {
    'cut' => 2.2,
    'bulk' => 2.0,
    'recomp' => 2.4,
    _ => 1.8, // maintain
  };
  return (weightKg * multiplier).round();
}

// Updated goalLabel — shows display name + delta
String get goalLabel {
  final delta = targetCalories - tdee;
  if (delta == 0) return goalDisplayName;
  final sign = delta > 0 ? '+' : '';
  return '$goalDisplayName ($sign$delta kcal)';
}
```

### New value object: `lib/models/dashboard_status.dart`

```dart
enum GoalStatusLabel {
  onTrack,
  tooHigh,
  tooAggressive, // deficit deeper than recommended (cut only)
  notEnoughSurplus, // lean gain only
  lowProtein,
  possibleRecomp, // cut-compliant calories but weight is stable
  needsMoreData,
}

enum WeightTrendDirection { down, stable, up, insufficient }

class DashboardStatus {
  final GoalStatusLabel label;
  final String headline;  // "On track", "Too high", etc.
  final String detail;    // single-line context, e.g. "7-day avg 1,673 kcal · −287 vs target"
  const DashboardStatus({
    required this.label,
    required this.headline,
    required this.detail,
  });
}
```

---

## Presenter API

New getters to add to `NutritionPresenter` (no new file — extend existing presenter):

```dart
// ── Goal metadata ────────────────────────────────────────────────────────────

/// Active goal type string, or null when in simple mode without a TdeeProfile.
String? get activeGoal => _tdeeProfile?.goal;

/// Human-readable label, e.g. "Cut (−300 kcal)" or null in simple mode.
String? get goalLabel => _tdeeProfile?.goalLabel;

// ── Dashboard analytics ──────────────────────────────────────────────────────

/// 7-day rolling average calories (complete logged days only).
int get sevenDayAvgCalories {
  final days = history.take(7).where((l) => l.totalCalories > 0).toList();
  if (days.isEmpty) return 0;
  return (days.fold(0, (s, l) => s + l.totalCalories) / days.length).round();
}

/// Fraction of last 7 days where protein goal was met (0.0–1.0).
/// Returns null if no protein goal is set.
double? get proteinHitRate7d {
  final goal = _goals.proteinGrams;
  if (goal == null || goal <= 0) return null;
  final days = history.take(7).toList();
  if (days.isEmpty) return null;
  final hits = days.where((l) => l.totalProtein >= goal).length;
  return hits / days.length;
}

/// Logging consistency: fraction of last 7 days that have ≥1 entry.
double get loggingConsistency7d {
  final days = history.take(7).toList();
  if (days.isEmpty) return 0.0;
  return days.where((l) => l.totalCalories > 0).length / days.length;
}

/// Weight trend direction over the last 14 entries.
WeightTrendDirection get weightTrendDirection {
  if (_weightLog.length < 4) return WeightTrendDirection.insufficient;
  final entries = _weightLog.length >= 14
      ? _weightLog.sublist(_weightLog.length - 14)
      : _weightLog;
  final half = entries.length ~/ 2;
  final firstAvg =
      entries.sublist(0, half).fold(0.0, (s, e) => s + e.weightKg) / half;
  final secondAvg =
      entries.sublist(half).fold(0.0, (s, e) => s + e.weightKg) /
          (entries.length - half);
  final delta = secondAvg - firstAvg;
  if (delta < -0.1) return WeightTrendDirection.down;
  if (delta > 0.1) return WeightTrendDirection.up;
  return WeightTrendDirection.stable;
}

/// Computed goal status for the dashboard header card.
DashboardStatus get dashboardStatus {
  // Needs more data: fewer than 3 logged days
  final loggedDays = history.take(7).where((l) => l.totalCalories > 0).length;
  if (loggedDays < 3) {
    return const DashboardStatus(
      label: GoalStatusLabel.needsMoreData,
      headline: 'Needs more data',
      detail: 'Log at least 3 days to see your goal status',
    );
  }

  // Simple mode: no goal-aware scoring
  final profile = _tdeeProfile;
  if (profile == null || _goals.mode != TrackingMode.standard) {
    return DashboardStatus(
      label: GoalStatusLabel.onTrack,
      headline: 'Tracking active',
      detail: '7-day avg ${sevenDayAvgCalories} kcal',
    );
  }

  final avg = sevenDayAvgCalories;
  final target = profile.targetCalories;
  final phr = proteinHitRate7d;
  final delta = avg - target;
  final sign = delta >= 0 ? '+' : '';
  final detail = '7-day avg $avg kcal · ${sign}${delta} vs target';

  return switch (profile.goal) {
    'cut' => _cutStatus(avg, target, phr, detail),
    'bulk' => _leanGainStatus(avg, target, phr, detail),
    'recomp' => _recompStatus(avg, target, phr, detail),
    _ => _maintainStatus(avg, target, phr, detail),
  };
}

// ── Goal-aware label getters (for KPI tile labels) ───────────────────────────

/// Primary KPI label — the most important metric for the active goal.
String get primaryKpiLabel => switch (activeGoal) {
  'cut' => 'Average deficit',
  'bulk' => 'Surplus adherence',
  'recomp' => 'Calorie stability',
  _ => 'Calorie stability',
};

/// Secondary KPI label.
String get secondaryKpiLabel => switch (activeGoal) {
  'cut' => 'Protein compliance',
  'bulk' => 'Protein support',
  'recomp' => 'Protein compliance',
  _ => 'Protein consistency',
};

/// Weight trend label — what a given direction means for this goal.
String weightTrendLabel(WeightTrendDirection direction) =>
  switch ((activeGoal, direction)) {
    ('cut', WeightTrendDirection.down) => 'Trending down ↓',
    ('cut', WeightTrendDirection.stable) => 'Weight stable',
    ('cut', WeightTrendDirection.up) => 'Trending up ↑',
    ('bulk', WeightTrendDirection.up) => 'Trending up ↓',
    ('bulk', WeightTrendDirection.stable) => 'Weight stable',
    ('bulk', WeightTrendDirection.down) => 'Trending down ↓',
    _ => 'Weight stable',
  };
```

---

## UI Requirements

### Layout (replaces current `_HistoryBody` column order)

```
┌─────────────────────────────────────────┐
│  _GoalStatusCard  (NEW — top card)      │  ← goal name + status badge + detail
├─────────────────────────────────────────┤
│  _SummaryRow (updated labels)           │  ← primary KPI / protein hit rate / log streak
├─────────────────────────────────────────┤
│  _CalorieTrendSection (target band)     │  ← existing chart + ±100 kcal band
├─────────────────────────────────────────┤
│  _GoalChecksSection (NEW)               │  ← protein, logging consistency, weight trend
├─────────────────────────────────────────┤
│  _MacroAveragesSection (unchanged)      │
├─────────────────────────────────────────┤
│  _WeightSection (unchanged)             │
├─────────────────────────────────────────┤
│  Recent Days (unchanged, move to bottom)│
└─────────────────────────────────────────┘
```

### `_GoalStatusCard` (new widget)

- Full-width card at the very top.
- **Line 1:** Goal name (bold) — e.g. "Cut (−300 kcal)" from `presenter.goalLabel`
  - If simple mode / no profile: "Custom goal"
- **Line 2:** 7-day average — "7-day avg 1,673 kcal"
- **Line 3:** Status badge — pill-shaped chip with icon + text. Colors:

| Status | Icon | Color |
|---|---|---|
| `onTrack` | `check_circle_outline` | `colorScheme.primary` |
| `tooHigh` | `arrow_upward` | `colorScheme.error` |
| `tooAggressive` | `warning_amber_outlined` | `colorScheme.error` |
| `notEnoughSurplus` | `arrow_downward` | `colorScheme.tertiary` |
| `lowProtein` | `warning_amber_outlined` | `colorScheme.tertiary` |
| `possibleRecomp` | `auto_awesome_outlined` | gold |
| `needsMoreData` | `hourglass_empty_outlined` | `colorScheme.onSurfaceVariant` |

- Micro-animation: status chip fades in (200 ms) on first build; no re-animation on repaint.

### `_SummaryRow` (updated — same 3 tiles, goal-aware labels)

| Tile | Cut | Maintain | Lean gain | Recomp |
|---|---|---|---|---|
| Tile 1 label | "Average deficit" | "Calorie stability" | "Surplus adherence" | "Calorie stability" |
| Tile 2 label | "Protein compliance" | "Protein consistency" | "Protein support" | "Protein compliance" |
| Tile 3 label | "Log streak" | "Log streak" | "Log streak" | "Log streak" |

- Tile 2 value: protein hit rate as `N/7 days` (e.g. "5/7 days"). If no protein goal is set, show "—".
- Tile 1 value: `|avg − target|` formatted as `−N kcal` (cut/recomp) or `+N kcal` (lean gain) or `±N kcal` (maintain).
- **Thumb zone:** tiles are 48 px tall minimum (touch target compliance).

### `_CalorieTrendSection` (updated painter)

Add a **target band** to `_CalorieTrendPainter`:
- Semi-transparent filled rect between `goalCalories − 100` and `goalCalories + 100`
  (clamped to chart bounds).
- Color: `barColor.withOpacity(0.10)`.
- Legend: add "Target band" entry alongside existing items.
- Bar color semantics change by goal:
  - **Cut / Recomp:** gold = within band or below target (deficit OK), error = above target+100.
  - **Lean gain:** gold = within band or above target (surplus OK), tertiary/amber = below target−100 (not enough), error = above target+200 (too much).
  - **Maintain:** gold = within band, error = outside band in either direction.

### `_GoalChecksSection` (new widget)

Three stacked check rows inside an `AppSection`:

1. **Protein target** — `N/7 days met`
   - Icon: `check_circle` (primary) if ≥ 70 %, `radio_button_unchecked` (onSurfaceVariant) otherwise
2. **Logging streak** — `N/7 days logged`
   - Icon: `check_circle` if ≥ 5/7, `radio_button_unchecked` otherwise
3. **Weight trend** — label from `presenter.weightTrendLabel(direction)`
   - Icon: goal-aware
     - Cut: down = `check_circle`, stable = `auto_awesome` (possible recomp), up = `error`
     - Lean gain: up = `check_circle`, stable = `info`, down = `error`
     - Maintain / Recomp: stable = `check_circle`, down/up = `info`
   - If `insufficient`: show "Not enough data — log weight in Weight Log"

### States

| State | Trigger | Shown |
|---|---|---|
| Loading | `presenter.history` empty on first build | `CircularProgressIndicator` centred |
| Empty | No logs at all | `AppEmptyState` unchanged |
| Simple mode | `activeGoal == null` | Tiles show generic labels; `_GoalStatusCard` shows "Custom goal" |
| Standard mode | `tdeeProfile != null` | Full goal-aware layout |

### Glanceability

The goal status card must communicate status in < 1 second. Status chip is always
visible without scrolling. No information critical to "am I on track?" should be
below the fold on a standard 6″ screen.

### Micro-animations

- Status chip: fade-in on first render, 200 ms, `Curves.easeOut`. No re-animation.
- Goal check rows: none — static icons are sufficient.
- Chart band: static (drawn by painter, no animation needed).

---

## RPG Mechanics

No new XP events introduced in this spec. The dashboard is read-only analytics.

Existing XP events that feed into displayed data (unchanged):
- Calorie goal met: XP awarded in `StatsPresenter` (unchanged)
- Log streak: shown in Tile 3 (unchanged)

Future hook: when body measurements spec lands, a confirmed recomp week could award
bonus XP (tracked in that spec).

---

## Storage

No new `StorageService` keys. All data is computed from existing persisted state:
- `NutritionGoals` (existing)
- `TdeeProfile` (existing — add 'recomp' as valid goal value, backward compat maintained)
- `DailyNutritionLog` history (existing)
- `WeightEntry` log (existing)

`DashboardStatus` is a derived value computed in the presenter; never persisted.

---

## Edge Cases

- **Simple mode user:** No TdeeProfile → `activeGoal == null` → generic labels, no
  goal status card scoring. Show "Set up Standard Mode to unlock goal tracking."
  subtext in the status card.
- **Recomp goal, stable weight:** Weight stable is expected and positive. Do NOT show
  "Off track." Show "Weight holding — protein compliance is the key metric."
- **Cut + stable weight (possible recomp):** Only flag `possibleRecomp` after 14+
  weight entries, not after 1–2 stable weeks (could be water/glycogen noise).
- **No protein goal set:** Tile 2 and `_GoalChecksSection` protein row show "—" and
  "No protein goal set." Do not compute a hit rate of 0 % (would be misleading).
- **`calorieAdjustment` override:** Custom delta is reflected correctly in `targetCalories`
  and `goalLabel` (already handled in `TdeeProfile`). Dashboard uses `effectiveGoal`
  which already delegates to `targetCalories`.
- **< 3 logged days:** `needsMoreData` status. No scoring shown — avoids misleading
  averages from 1–2 days of data.
- **Lean gain, weight trend up fast (> 0.5 kg/week):** Weight check row shows
  "Gaining fast — consider reducing surplus" even if calories are in band.

---

## Acceptance Criteria

- [ ] `TdeeProfile` accepts `'recomp'` as a valid `goal` value with correct calorie
      target (TDEE), protein suggestion (2.4 g/kg), and label ("Recomp")
- [ ] `DashboardStatus` model and `WeightTrendDirection` enum exist in
      `lib/models/dashboard_status.dart`
- [ ] `NutritionPresenter` exposes: `sevenDayAvgCalories`, `proteinHitRate7d`,
      `loggingConsistency7d`, `weightTrendDirection`, `dashboardStatus`,
      `primaryKpiLabel`, `secondaryKpiLabel`, `goalLabel`
- [ ] `_GoalStatusCard` renders goal name, 7-day avg, and status chip; chip color
      matches the status table above
- [ ] `_SummaryRow` Tile 1 and Tile 2 labels change based on `activeGoal`
- [ ] `_CalorieTrendSection` painter draws a ±100 kcal translucent band around the
      goal line and legend reflects it
- [ ] Bar color semantics in the chart are inverted for lean gain (above target =
      gold, not error)
- [ ] `_GoalChecksSection` renders protein, logging, and weight trend rows with
      correct icons per goal
- [ ] Recomp goal: weight trend row says "Weight holding — protein compliance is the
      key metric" when trend is stable
- [ ] Cut goal: `possibleRecomp` status fires only when calories are in-band AND
      weight is stable AND weight log has ≥ 14 entries
- [ ] Simple mode / no TdeeProfile: dashboard degrades gracefully with generic labels,
      no crash
- [ ] No `AppColors.*` tokens hardcoded in any new widget — all colors from
      `Theme.of(context)`
- [ ] All touch targets ≥ 44 × 44 px
