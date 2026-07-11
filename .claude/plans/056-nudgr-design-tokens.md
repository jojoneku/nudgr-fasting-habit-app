# Plan 056 — Nudgr Design Token Migration

**Spec:** [docs/design_system_nudgr_spec.md](../../docs/design_system_nudgr_spec.md)
**Scope:** Replace the Material-grey token values with the prototype's canonical dark-first / derived-light system, add domain-semantic accents + a 5-tier text ramp + track/border tokens. One cohesive design-system change → **one PR** (`feat/nudgr-design-tokens`, base `dev`).

## Goal

Give the app the premium near-black dark identity and derived light palette the prototype specifies, and encode domain meaning into color (Fast/Food/Move/Bills/Treasury/Weight). Today's "dark mode" is washed-out mid-grey (`grey800 #424242` cards vs. spec `#1C1C20`); the light mode is generic Material grey. This closes both gaps without restructuring any screen.

**Key enabler:** widgets already consume *semantic* tokens — `context.appColors.{success,gold,orange,purple}` (132 uses / 32 files) and `colorScheme.{primary,secondary,tertiary,error}` (192 uses / 63 files). So this is a **value swap + extension expansion**, not a call-site rewrite. Existing extension field names are **kept** (re-pointed to new hues) for backward compatibility; new domain names are **added** as aliases.

---

## Conflict Check

| Check | Question | Finding |
|---|---|---|
| **File overlap** | Other plans editing `app_colors.dart` / `app_theme.dart`? | Plan 017 (UI design system overhaul) & 050 (Treasury web redesign) touched theme. Both merged. This supersedes 017's palette decisions. |
| **Model overlap** | New model class / storage key? | None — no persistence change. |
| **Presenter split** | Logic owned by another presenter? | None — pure theme. |
| **XP routing** | Calls `addXp()`? | No. |
| **HubScreen** | Unlocks a Hub card? | No. |
| **Supersedes** | Older plan redundant? | Palette portions of Plan 017 superseded (mark note in 017). |
| **Dependency order** | Must ship before? | None. Independent. |
| **Web parity** | Treasury web shares `buildDarkTheme`/`buildLightTheme`? | **Yes** — `app_theme.dart` is shared (Plan 042). Change flows to web automatically; verify web still reads tokens, not hardcoded hexes. |

---

## Affected Files

| File | Action | Layer |
|---|---|---|
| `lib/app_colors.dart` | Modify — replace scales with token values; expand `AppThemeExtension` | Tokens |
| `lib/views/app_theme.dart` | Modify — rewire `colorScheme` surface/text/outline slots both modes | Theme |
| `lib/utils/app_text_styles.dart` | Modify — add `mono` (JetBrains Mono) helper | Tokens |
| `lib/design_tokens_nudgr.dart` | Create — raw constants mirroring the spec (single source the two `AppColors*` read from) | Tokens |
| `test/theme/*` | Create — golden/contrast guard tests | Test |
| `.claude/plans/017-ui-design-system-overhaul.md` | Modify — add SUPERSEDED note on palette | Docs |

No widget files change unless a hardcoded `AppColors.X` is found in one (see Step 5 audit).

## Interface Definitions

```dart
// === lib/design_tokens_nudgr.dart (new) — raw values, both modes ===
abstract final class NudgrDark {
  static const page = Color(0xFF0A0A0B);
  static const screen = Color(0xFF131315);
  static const sheet = Color(0xFF171718);
  static const card = Color(0xFF1C1C20);
  static const input = Color(0xFF252628);
  static const track = Color(0xFF26262A);
  static const shell = Color(0xFF0E0E10);
  static const borderInner = Color(0xFF1E1E22);
  static const borderCard = Color(0xFF2A2A2E);
  static const borderSheet = Color(0xFF2E2F31);
  static const textPrimary = Color(0xFFF7F7F8);
  static const textSecondary = Color(0xFFC9CDD3);
  static const textTertiary = Color(0xFF9A9FA8);
  static const textMuted = Color(0xFF83878F);
  static const textInactive = Color(0xFF6A6E76);
  // domain: primary / light / track
  static const fast = Color(0xFF2E90FA);      static const fastTrack = Color(0xFF1A2535);
  static const food = Color(0xFF26C6DA);      static const foodTrack = Color(0xFF1A2826);
  static const move = Color(0xFF46BD6B);      static const moveTrack = Color(0xFF152218);
  static const danger = Color(0xFFF6685E);
  static const bills = Color(0xFFFF8A4C);
  static const gold = Color(0xFFFFCA28);
  static const weight = Color(0xFF926AFA);
}
abstract final class NudgrLight { /* symmetric — light column of every spec table */ }

// Static, mode-independent
abstract final class AppAccountColors {
  static const bpi = Color(0xFF9B2C2C);
  static const gcash = Color(0xFF1565C0);
  static const maya = Color(0xFF1B7A4B);
  static const maribank = Color(0xFF2A2566);
}

// === AppThemeExtension additions (backward-compatible) ===
// KEEP: success, gold, orange, purple  (re-pointed to move/gold/bills/weight hues)
// ADD:
final Color fast, food, move, bills, treasury, weight;   // domain aliases
final Color fastTrack, foodTrack, moveTrack;             // ring/bar tracks
final Color textTertiary, textMuted, textInactive;       // extra text tiers
final Color borderSheet;
// success == move, gold == treasury, orange == bills, purple == weight (aliases)
```

## Implementation Order

1. [ ] Create `lib/design_tokens_nudgr.dart` with `NudgrDark` / `NudgrLight` / `AppAccountColors` from the spec tables (zero consumers yet).
2. [ ] Rewrite `AppColors` (dark) + `AppColorsLight` surfaces/text/accents to read from the new constants. Keep existing field names.
3. [ ] Expand `AppThemeExtension` with domain + track + text-tier + border fields; wire `dark`/`light` from the constants; keep `copyWith`/`lerp` exhaustive.
4. [ ] Rewire `app_theme.dart` `colorScheme` in both builders: surface ramp (Lowest→Highest per spec), `onSurface`/`onSurfaceVariant`, `outline`/`outlineVariant`, nav bar + sheet backgrounds.
5. [ ] Audit for hardcoded `AppColors.X`/`AppColorsLight.X` inside widgets (`grep`); replace any with `Theme.of(context)` / `context.appColors` reads.
6. [ ] Add `AppTextStyles.mono` (JetBrains Mono via `google_fonts`); apply to hero timer/stat numerals (optional, low-risk, can be a follow-up).
7. [ ] Tests + manual verification (below).

## RPG Impact
None — color only. XP, levels, streaks, notifications unchanged.

## Risks
- **App-wide blast radius.** Every screen re-themes at once. Mitigation: values-only change behind existing semantic tokens; verify via preview on representative screens (Hub, Fasting timer, Nutrition, Treasury dashboard, a bottom sheet, Settings) in **both** modes.
- **Treasury web** shares the theme — a regression hits web too. Mitigation: run web build (`localhost:8090`) and spot-check.
- **Contrast regressions**, esp. light-mode text-on-tint. Mitigation: contrast guard test + honor per-token light values.
- **Hardcoded hexes** hiding in widgets/charts (fl_chart series colors, custom painters). Mitigation: Step 5 audit; charts should pull from `context.appColors` domain fields.
- **Washed vs. crushed blacks** on OLED — `#0A0A0B` page is intentional; ensure elevation steps stay distinguishable (card `#1C1C20` vs screen `#131315` is ~9 L* apart — OK).

## UX Verification
- [ ] Dark mode: page reads near-black, cards clearly elevated, 5 text tiers distinguishable.
- [ ] Light mode: matches derived palette; no muddy grey.
- [ ] Domain colors correct per module (Fast blue, Food teal, Move green, Bills orange, Treasury gold, Weight purple).
- [ ] Progress rings/bars use track tokens (dim, not pure black/white).
- [ ] All touch targets ≥ 44×44; no motion changes.
- [ ] Treasury web renders identically.

## Acceptance Criteria
- [ ] No widget references `AppColors.*`/`AppColorsLight.*` directly (only `app_colors.dart` + `app_theme.dart` do).
- [ ] `flutter analyze` clean; `dart format` applied.
- [ ] Dark & light both render the spec palette across the 6 representative screens.
- [ ] Contrast guard test passes (AA for body text both modes).
- [ ] Existing `context.appColors.{success,gold,orange,purple}` call sites still compile and render sensible hues.
