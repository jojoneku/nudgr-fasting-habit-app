# Plan 017b — Fasting Timer Screen Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Modernize the most-used screen in the app. Keep the ring + protocol mechanics intact, swap the cyberpunk glow surface for clean M3 + HIG-restrained motion. Pull every primitive from 017's library.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/tabs/timer_tab.dart` | Layout rewrite using `AppPageScaffold`, `AppCard`, `AppSection` |
| `lib/views/widgets/protocol_card.dart` | New visual built on `AppCard`; segmented protocol picker via `AppSegmentedControl` |
| `lib/views/widgets/partial_ring_painter.dart` | Already parameterized in 017W Phase 6; verify color params work for both themes |
| `lib/views/widgets/system/indicators/app_ring_progress.dart` | Already finalized in 017W; consume here |
| `lib/views/widgets/fast_completion_modal.dart` | Polish content layout inside the `AppDialog`/`AppBottomSheet` wrapper |
| `lib/views/widgets/refeeding_warning_sheet.dart` | Polish content layout inside `AppBottomSheet` wrapper |

---

## UX Direction

### Hero Ring
- `AppRingProgress` driving the existing painter
- Glow opacity ≤ 12% (already enforced in 017W Phase 6)
- Center stack:
  - Large timer in DM Mono via `AppNumberDisplay` — `displayMedium` size
  - Phase label below (`labelLarge`, low-emphasis): "Fed", "Fasting", "Approaching goal", "Goal reached"
  - Small secondary line: target time or % progress

### Action Row
- Primary action: `AppPrimaryButton` — "Start Fast" / "End Fast" (sentence case, replaces "INITIATE FAST")
- Secondary: `AppSecondaryButton` for "Edit start time" or "Adjust protocol"

### Protocol Card
- `AppCard` (filled variant)
- `AppSegmentedControl` for 16:8 / 18:6 / 20:4 / OMAD / Custom
- Compact details row: target hours, last completed
- Tap → bottom sheet (built on `AppBottomSheet`) for full protocol editor

### Stats Strip Below Ring
- Three `AppStatPill`s in a row: current streak, best streak, total fasts
- Spacing `md` between, `lg` above

### Completion Modal
- `AppDialog` with celebratory content, XP awarded, next-protocol suggestion
- Single primary action — "Done"

---

## Motion

- Ring sweep: existing tween, but capped at `AppMotion.appear` (200ms) on phase transitions
- Phase color change: 250ms ease-in-out
- **Remove** any pulsing or breathing animation
- Button press: `AppMotion.micro`

---

## Design-System Widgets Consumed

`AppPageScaffold` · `AppCard` · `AppSection` · `AppRingProgress` · `AppNumberDisplay` · `AppStatPill` · `AppPrimaryButton` · `AppSecondaryButton` · `AppSegmentedControl` · `AppBottomSheet` · `AppDialog`

---

## Acceptance Criteria

- [ ] No all-caps text anywhere on the screen
- [ ] Ring glow ≤ 12% opacity in both themes
- [ ] Timer renders in DM Mono, no layout shift on digit change
- [ ] Protocol switch is a single tap (no full-page navigation)
- [ ] Both completion modal and refeeding sheet read from theme — no hardcoded colors
- [ ] Animations within 150–300ms (hard cap 400ms)
- [ ] Light-mode legibility verified

---

## Out of Scope

- Protocol math / XP calc changes (presenter logic untouched)
- Adding new fasting protocols
- History list redesign (017f handles activity-style lists; history within fasting tab follows the same `AppListTile` pattern)
