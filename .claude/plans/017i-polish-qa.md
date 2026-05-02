# Plan 017i — Cross-cutting Polish, Transitions & QA

> Depends on **017a–017h** being merged. The final pass.
> All foundation (017), widgets (017W), and pages (017a–017h) must be in.

## Goal

Lock in the global feel — page transitions, motion timing audit, accessibility checks, light-mode QA across every screen. Catch the leftovers that escape per-page plans.

---

## Scope

### 1. Page Transitions
- Verify `PageTransitionsTheme` is set in both `_darkTheme()` and `_lightTheme()` (017 should have done this; confirm)
- Default Android slide replaced with `ZoomPageTransitionsBuilder` (HIG-adjacent settled feel)
- Bottom-sheet entrance: `AppMotion.modal` (300ms) with **`AppMotion.spring`** curve (HIG)
- Dialog entrance: scale + fade ≤ 200ms with `AppMotion.spring`
- Action sheet entrance: same as bottom sheet

### 2. Motion Audit
Walk every screen and verify:
- No animation > 400ms (hard cap)
- Micro-interactions in 150–250ms
- **Appearances use `AppMotion.spring`** — no bouncy elastics, no overshoot
- Layout/transition motion uses `easeInOut` or `decelerate` — never `easeIn` alone (HIG: enter fast, settle slow)
- No looping / pulsing / breathing animations
- Hero ring transitions ≤ 250ms

### 3. Accessibility
- WCAG AA contrast ratio on all text/background pairs in **both** modes
- Tool: run `flutter run --profile` + `Semantics` debugger or use a contrast plugin
- Verify `Semantics` labels on icon-only buttons (back, close, FAB, search)
- Touch target audit: every interactive element ≥ 44×44px
- Dynamic text size: app shouldn't break at 130% system font scale
- Reduced motion: respect `MediaQuery.disableAnimations` for non-essential animations

### 4. Light Mode QA Pass
- Walk each module (hub, fasting, stats, nutrition, quests, activity, treasury, settings)
- Verify:
  - No invisible text (e.g. white-on-white)
  - No hardcoded dark surfaces leaking through
  - Charts and finance category fills remain legible (borders present where needed)
  - Custom painters render correctly (rings, radar, calendar heatmap)
- Capture screenshots side-by-side dark/light for the README or design doc

### 5. Copy / Language Audit
- Final sweep for residual all-caps and RPG-inflected chrome that escaped page plans
- Acceptable to keep: rank names, attribute names, level-up text content (these are *content*, not chrome)
- Not acceptable: section headers, button labels, navigation labels in all-caps

### 6. Performance Smoke
- Cold-start frame budget unchanged after font / theme additions
- `GoogleFonts` does **not** add a network call at runtime (verify by toggling airplane mode after install)
- No jank when toggling theme mode at runtime

---

## Acceptance Criteria

- [ ] `PageTransitionsTheme` set for Android in both modes (`ZoomPageTransitionsBuilder`)
- [ ] All appearance animations use `AppMotion.spring`; no bouncy elastics anywhere
- [ ] Type weight hierarchy verified: `title*` w600, `body*` w400 — no fake-bold via color/size shifts
- [ ] No animation in the app exceeds 400ms
- [ ] WCAG AA contrast on all text in both modes
- [ ] All icon-only buttons have `Semantics` labels
- [ ] Reduced-motion respected for non-essential animations
- [ ] All custom painters render correctly in light mode
- [ ] No residual all-caps in chrome (titles, buttons, nav)
- [ ] Theme toggle at runtime is jank-free
- [ ] Side-by-side dark/light screenshots captured for every module

---

## Risks

| Risk | Mitigation |
|---|---|
| Custom painter regressions in light mode missed during page plans | Dedicated QA pass here |
| `disableAnimations` breaks essential UX (e.g. timer ring still needs to advance) | Apply only to decorative animations |
| Page transition change breaks deep-link flows | Test via app links / push notifications |

---

## Non-Goals

- Adding new screens or features
- Refactoring presenters or services
- Changing data persistence
