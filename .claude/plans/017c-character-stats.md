# Plan 017c — Character / Stats View Redesign

> Depends on **017** (tokens + theme) and **017W** (widget library) being merged.

## Goal

Keep all RPG mechanics — XP, level, rank, HP, attribute radar — but ditch the hexagonal cyberpunk surface for clean M3 surfaces, themed for both modes. The radar chart remains the visual centerpiece.

---

## Files Touched

| File | Action |
|---|---|
| `lib/views/stats_view.dart` | Full layout rewrite using design-system widgets |
| `lib/views/widgets/stat_radar_chart.dart` | Already parameterized in 017W Phase 6; verify both-mode rendering |
| `lib/views/widgets/level_up_overlay.dart` | Audit copy + motion timing; wrap action in `AppPrimaryButton` |

---

## UX Direction

### Page Chrome
- `AppPageScaffold.large(title: 'Character')` — collapsing large title (HIG pattern for top-level destination)

### Header Block
- `AppCard` (filled variant) at the top of the page
- Left: avatar / rank emblem (kept) — but as a clean tonal-filled circle, no glow
- Right (vertical stack):
  - Name + rank — `titleLarge` (sentence case)
  - Level — `labelLarge` low-emphasis
  - HP bar (`AppLinearProgress` with label "HP 87/100")
  - XP bar (`AppLinearProgress` with label "XP 230 / 400 → next level")

### Radar Section
- `AppSection` titled "Attributes"
- Chart wrapped in `AppCard` (elevated)
- Color params (fill/border/grid/label) sourced from theme — primary alpha for fill, `outlineVariant` for grid, `onSurfaceVariant` for labels

### Attribute Grid
- 2-column grid below the radar
- Each cell is a small `AppCard` with:
  - Attribute icon (filled-tonal container, 32×32)
  - Attribute name — `labelLarge`
  - Attribute value — `AppNumberDisplay` size `titleLarge`
  - Optional sub-line: "+2 this week"

### Streaks / Achievements Strip
- `AppSection` "Streaks"
- Horizontal scroll of `AppStatPill`s — current streak, best streak, perfect days, fasts completed

### Level-Up Overlay
- Polished copy in sentence case ("Level up!" not "LEVEL UP")
- Motion ≤ `AppMotion.modal` (300ms) entrance
- Continue button = `AppPrimaryButton`

---

## Design-System Widgets Consumed

`AppPageScaffold.large` · `AppSection` · `AppCard` · `AppLinearProgress` · `AppNumberDisplay` · `AppStatPill` · `AppPrimaryButton`

---

## Acceptance Criteria

- [ ] Hexagon rank badge replaced with clean tonal pill or circular emblem
- [ ] HP and XP bars use `AppLinearProgress` (not custom containers)
- [ ] Radar chart accepts color params; renders correctly in both themes
- [ ] Attribute grid uses `AppCard` cells; numeric values in DM Mono
- [ ] No all-caps labels
- [ ] Level-up overlay animation ≤ 400ms total
- [ ] No hardcoded colors in `stats_view.dart`

---

## Out of Scope

- RPG math changes (XP curve, attribute formulas — untouched)
- New attributes or rank tiers
- Avatar customization
