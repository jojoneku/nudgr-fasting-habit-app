# Plan 017f — Activity Module Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Bring the activity (movement / steps) screen into the design system. Includes the permission gate.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/activity/activity_screen.dart` | Layout rewrite using `AppPageScaffold`, `AppCard`, `AppSection` |
| `lib/views/activity/activity_permission_screen.dart` | Empty-state-style permission ask using `AppEmptyState` + `AppPrimaryButton` |
| `lib/views/tabs/history_tab.dart` | If shared with activity history, migrate rows to `AppListTile` |

---

## UX Direction

### Activity Screen
- Hero card (`AppCard` elevated): today's headline metric — steps + active minutes
  - Big number via `AppNumberDisplay`
  - Sub-label: progress vs target ("8,420 of 10,000")
  - Below: `AppLinearProgress` ring or bar
- `AppSection` "Today's breakdown"
  - Row of three `AppStatPill`s: distance, calories burned, active minutes
- `AppSection` "This week"
  - Bar chart wrapped in `AppCard`; chart colors come from theme (primary + outlineVariant)
  - Below the chart: weekday labels in `labelSmall`
- `AppSection` "Recent sessions"
  - List of `AppListTile`s — each row is one tracked activity (walk / run / workout)

### Permission Screen
- `AppEmptyState` with icon, body explaining why permission is needed
- `AppPrimaryButton` "Grant access"
- `AppSecondaryButton` "Maybe later" (returns to hub)

### History Tab
- Grouped `AppListTile`s by week
- Section header per week using `AppSection`
- Tile shows date + total steps in DM Mono trailing

---

## Design-System Widgets Consumed

`AppPageScaffold` · `AppCard` · `AppSection` · `AppNumberDisplay` · `AppLinearProgress` · `AppStatPill` · `AppListTile` · `AppEmptyState` · `AppPrimaryButton` · `AppSecondaryButton`

---

## Acceptance Criteria

- [ ] Activity hero number renders in DM Mono via `AppNumberDisplay`
- [ ] No hardcoded chart colors — all read from `Theme.of(context)`
- [ ] Permission screen uses `AppEmptyState` (not custom layout)
- [ ] All session rows use `AppListTile`
- [ ] Both modes render correctly
- [ ] No all-caps text

---

## Out of Scope

- Activity tracking logic / sensor integration
- Adding new activity types
- Changing target / goal math
