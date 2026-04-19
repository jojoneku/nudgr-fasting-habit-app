# Plan 017 — UI Design System Overhaul: Modern M3 + HIG Taste

## Goal

Pivot the app's visual identity from Solo Leveling cyberpunk gaming aesthetic to a **modern, premium lifestyle app** — while keeping all gamification mechanics intact. Lock in Material 3 as the structural foundation, with Apple HIG–inspired spacing, motion restraint, and visual hierarchy. Support both **dark (default)** and **light modes**. Keep the existing color palette, adapting for both modes.

---

## Design Philosophy

### What Changes
| Before | After |
|---|---|
| Glow-heavy shadows, neon ring effects | Subtle elevation + M3 surface tint |
| All-caps RPG labels ("SYSTEM INTERFACE", "INITIATE FAST") | Sentence case with accent typography |
| Border-glow cards | Clean M3 elevated cards with surface tint |
| Solo Leveling language in navigation/headers | Neutral, lifestyle-app language |
| Dark-only forced | Dark default + light mode switchable |

### What Stays
- Color palette (cyan, teal, amber, red, green) — refined for both modes, not replaced
- Custom ring painter + radar chart — kept, just cleaned up (less glow)
- RPG mechanics (XP, levels, ranks, HP, streaks) — fully unchanged
- Overall structure (hub grid, stats view, feature screens)
- MVP architecture, ListenableBuilder pattern

---

## Typography Direction

Replace current type stack with:
- **`Plus Jakarta Sans`** — headings, body, labels (clean, modern, premium)
- **`DM Mono`** — numbers, timers, financial displays (replaces Roboto Mono, drop-in compatible)

Both are available on Google Fonts, already installed as a dependency.

---

## Color Token Strategy

### Dark Mode (keep existing palette, refine)
- Reduce glow alpha: 30% → 10–15% on all `MaskFilter.blur` effects
- Background: `#0A0E14`, Surface: `#1C2128` — no change
- Accent colors: no change (desaturated cyan/teal already right)

### Light Mode (new)
| Token | Value | Notes |
|---|---|---|
| Background | `#F8FAFC` | Warm slate white |
| Surface | `#FFFFFF` | Clean white |
| Surface Variant | `#EFF3F8` | Subtle section backgrounds |
| Primary | `#0288D1` | Darker cyan for legibility on white |
| Secondary | `#00838F` | Darker teal |
| Text Primary | `#0F1923` | Near-black (not pure black) |
| Text Secondary | `#4A5568` | Accessible grey |
| Error | `#D32F2F` | Darker red for light backgrounds |
| Success | `#388E3C` | Darker green |
| Gold | `#F9A825` | Darker amber |

Finance category palettes are data-viz colors — keep as-is (sufficient contrast with borders).

---

## Spacing System (HIG-taste)

```
xs:  4px   — icon padding, tight spacing
sm:  8px   — chip gap, between-row spacing
md:  16px  — card padding, horizontal page margin
lg:  24px  — section top margin
xl:  32px  — major vertical rhythm
xxl: 48px  — hero/display spacing
```

New file: `lib/utils/app_spacing.dart`

---

## Motion Tokens (HIG-restrained)

```
micro:   150ms  ease-out           — button/chip presses
appear:  200ms  ease-out           — card/chip enter (scale 0.97→1.0, opacity 0→1)
modal:   300ms  cubic(0.2,0,0,1)  — bottom sheet / dialog entrance (M3 standard)
page:    250ms  ease-in-out        — route transitions
```

**Remove:** pulsing glow animations, any animation > 400ms.

New file: `lib/utils/app_motion.dart`

---

## Phases

### Phase 1 — Design System Foundation (Token Layer)
> No screen changes. Lock in the token system.

| File | Action |
|---|---|
| `lib/utils/app_colors.dart` | Add `AppColorsLight` static class with light mode counterparts |
| `lib/utils/app_text_styles.dart` | Full rewrite: Plus Jakarta Sans + DM Mono, full M3 TypeScale mapping |
| `lib/utils/app_spacing.dart` | **Create** — spacing constants |
| `lib/utils/app_motion.dart` | **Create** — duration + curve constants |

---

### Phase 2 — Theme Wiring (ThemeData Layer)
> Wire both ThemeData objects and persistence.

| File | Action |
|---|---|
| `lib/views/fasting_app.dart` | Create `_darkTheme()` + `_lightTheme()` factories; wire themeMode from presenter |
| `lib/services/storage_service.dart` | Add `theme_mode` key + `getThemeMode` / `saveThemeMode` methods |
| `lib/presenters/settings_presenter.dart` | Add `themeMode` getter/setter |

**ThemeData components to customize in both modes:**
- `AppBarTheme` — no elevation, correct foreground
- `NavigationBarTheme` — active indicator, icon/label colors
- `CardTheme` — elevation 1, rounded 16px (not 32px), subtle shadow
- `FilledButton` / `OutlinedButton` / `TextButton`
- `ChipTheme` — compact, readable
- `InputDecorationTheme` — filled style, rounded
- `BottomSheetTheme` — drag handle, top radius 20px
- `DialogTheme` — rounded 24px

---

### Phase 3 — Hub Screen + Navigation
> First thing users see. High impact.

| File | Action |
|---|---|
| `lib/views/tabs/hub_screen.dart` | Remove "SYSTEM INTERFACE" header; redesign module cards: clean M3 elevated cards (icon + label + badge). Keep 2-col grid. |
| `lib/views/fasting_app.dart` | NavigationBar: clean labels, refined active indicator |

**Hub card redesign direction:** Replace border-glow cards with M3 `Card` (elevation 1) + `surfaceTint`. Icon in a filled container. Module name in `titleMedium`. Locked state: reduced opacity + lock icon overlay.

---

### Phase 4 — Fasting Timer Screen
> Core loop. Most-used screen.

| File | Action |
|---|---|
| `lib/views/fasting/fasting_tab.dart` (+ related) | Modernize layout; reduce ring glow to subtle shadow; rename "INITIATE FAST" → "Start Fast"; clean button hierarchy; polish protocol card |
| `lib/views/fasting/painters/partial_ring_painter.dart` | Reduce `MaskFilter.blur` opacity; accept color params (no hardcoded AppColors) |

---

### Phase 5 — Stats / Character View
> Keep RPG mechanics, modernize the surface.

| File | Action |
|---|---|
| `lib/views/character/stats_view.dart` | Modernize rank display: hexagon badge → clean pill chip; clean HP/XP bars; radar chart stays but wrapped in M3 surface card; attribute grid gets cleaner label/value layout |
| Radar chart painter | Accept color params for theme-awareness |

---

### Phase 6 — Supporting Screens
> Bring Nutrition, Quests, Activity, Treasury into the system.

| Files | Action |
|---|---|
| `lib/views/nutrition/*` | Apply spacing tokens, new card style, typography |
| `lib/views/quests/*` | Clean list/card layouts, remove RPG-heavy header labels |
| `lib/views/activity/*` | Apply spacing + card system |
| `lib/views/treasury/*` | Apply card + typography system (financial displays → DM Mono confirmed) |

---

### Phase 7 — Polish + QA
- Add HIG-taste page transitions (subtle fade-through or shared-axis, not default Android slide)
- Light mode QA pass: verify every screen
- Accessibility check: WCAG AA contrast on all text pairs
- Touch target audit: all interactive elements ≥ 44×44px
- Animation timing audit: no animation > 400ms

---

## Interface Definitions

### StorageService (new additions)
```dart
static const String kThemeMode = 'theme_mode'; // 'dark' | 'light' | 'system'

Future<ThemeMode> getThemeMode();
Future<void> saveThemeMode(ThemeMode mode);
```

### SettingsPresenter (new additions)
```dart
ThemeMode get themeMode;

Future<void> setThemeMode(ThemeMode mode);
```

> **Decided:** Theme toggle lives in the Settings screen. No hub-level access.

### Custom Painters (new interface)
```dart
// Pass colors as constructor params so Views inject theme-aware values
// instead of reading AppColors directly inside the painter
PartialRingPainter({
  required Color primaryColor,
  required Color trackColor,
  double glowOpacity = 0.12, // reduced from current ~0.30
  ...
})

StatRadarChart({
  required Color fillColor,
  required Color borderColor,
  required Color gridColor,
  required Color labelColor,
  ...
})
```

---

## Risks & Edge Cases

| Risk | Mitigation |
|---|---|
| Custom painters use hardcoded `AppColors.*` | Pass colors as constructor params (Phase 4 + 5) |
| Finance category colors too light for light mode text | Used as fill colors with border — acceptable; revisit in Phase 7 QA |
| Adding Plus Jakarta Sans increases first load | Use `GoogleFonts.plusJakartaSansTextTheme()` batch approach, not per-widget |
| RPG labels deeply embedded ("Days Since Awakening", rank names) | This plan covers **visual** modernization only — content language is a separate product decision, defer to user |
| `useMaterial3: true` already set | Good — no flag change needed, just fix ThemeData values |

---

## Acceptance Criteria

- [ ] Both dark and light `ThemeData` defined and switchable at runtime
- [ ] Theme preference persisted across app restarts
- [ ] No hardcoded colors in View files — all via `Theme.of(context)` or AppColors tokens
- [ ] Plus Jakarta Sans + DM Mono applied across all screens
- [ ] Hub module cards: no glow borders, M3 card style
- [ ] Fasting ring: glow ≤ 15% opacity, layout clean
- [ ] All touch targets ≥ 44×44px
- [ ] All animations within 150–300ms (hard cap 400ms)
- [ ] Light mode: WCAG AA contrast on all text/background pairs
- [ ] Navigation bar: no RPG-styled labels
- [ ] Custom painters accept color params (no internal AppColors references)

---

## Non-Goals for This Plan
- Changing RPG mechanics (XP math, leveling, streaks — untouched)
- New features or screens
- Backend/data layer changes (except themeMode persistence)
- Icon set redesign
- Full RPG language rebrand (product decision, separate conversation)

---

*Plan 017 — ready for approval. Phase 1 can start immediately after alignment.*
