# Plan 017 — Design Tokens + ThemeData (Foundation)

> Blocks **017W** (widget library), which blocks **017a–017h** (page plans).

## Goal

Lock in the **token layer** and **dual-mode `ThemeData`** for the visual overhaul. No widgets, no page changes — purely the foundation that 017W (widget library) and the page plans will consume.

When 017 is merged, the app continues to render identically. The change is internal: token files exist, both `ThemeData` factories are wired, theme persistence works.

---

## Why a Tokens-Only Plan

Splitting tokens from the widget library and from page work yields:

- **Smaller, reviewable PRs** — token changes are easy to verify; widgets and pages each get their own focus.
- **Light mode for free downstream** — once tokens + ThemeData are right, every primitive built in 017W reads from them.
- **Cheaper iteration** — adjusting a radius / spacing / motion duration means editing one file, not chasing usages.

---

## Design Philosophy

M3 is the **structural foundation** (ColorScheme, ThemeData, motion tokens, component contracts). HIG is the **taste layer** that shapes how those pieces feel — surface contrast over elevation for grouping, generous breathing room, spring-based motion, weight-driven typographic hierarchy.

| Before | After |
|---|---|
| Glow-heavy shadows, neon ring effects | Subtle elevation + M3 surface tint |
| All-caps RPG labels | Sentence case with accent typography |
| Border-glow cards | Filled cards with surface contrast (HIG grouping) — elevation reserved for true lift |
| Solo Leveling language in chrome | Neutral, lifestyle-app language (in page plans) |
| Dark-only forced | Dark default + light mode switchable |
| Cubic-only motion | Spring curves on appearances; cubics still used for layout transitions |
| Color/size for hierarchy | Type **weight** (semibold) for hierarchy where possible |

**What stays:** color palette (refined), custom painters (parameterized in 017W), RPG mechanics, MVP architecture.

### HIG influence (concrete)

| HIG signature | Where it lands |
|---|---|
| Filled cards as default; elevated for true lift | `flex_color_scheme` overridden — `cardElevation: 0`, surface contrast does the grouping |
| Generous section rhythm (~20pt) | `AppSpacing.mdGenerous = 20` token added; sections use it |
| Spring motion on appearances | `AppMotion.spring` curve preset added |
| Semibold for hierarchy | `AppTextStyles.titleMedium`+ pinned at `w600`, body stays `w400` |
| Inset grouped lists | Provided by `AppListTile.insetGrouped` in 017W |
| Action sheets for choices | Provided by `AppActionSheet` in 017W |
| Large titles that collapse | Provided by `AppPageScaffold.large()` in 017W |

---

## Package Additions

| Package | Why |
|---|---|
| `flex_color_scheme` | Generates M3 light + dark `ThemeData` with all component sub-themes pre-configured. Cuts ~70% of hand-rolled `*Theme` config. Any specific override stays explicit. |

Add to `pubspec.yaml` in Phase 2.

---

## Phase 1 — Token Layer

> Pure constants. No widgets, no theming yet.

| File | Action |
|---|---|
| `lib/utils/app_colors.dart` | Add `AppColorsLight` static class mirroring the existing dark palette |
| `lib/utils/app_text_styles.dart` | Full rewrite — Plus Jakarta Sans (text) + DM Mono (numerics with `tabularFigures` enabled), full M3 type scale. **Weight discipline:** `display*` w700, `headline*` w700, `title*` w600 (HIG hierarchy via weight), `body*` w400, `label*` w500 |
| `lib/utils/app_spacing.dart` | **Create** — `xs 4 / sm 8 / md 16 / mdGenerous 20 / lg 24 / xl 32 / xxl 48`. `mdGenerous` is the HIG-rhythm token used between sections and around hero blocks |
| `lib/utils/app_motion.dart` | **Create** — durations: `micro 150ms / appear 200ms / modal 300ms / page 250ms`. Curves: `easeOut`, `easeInOut`, `decelerate`, **`spring`** (custom `Cubic(0.32, 0.72, 0, 1)` — settled HIG-feel; use on entrances) |
| `lib/utils/app_radii.dart` | **Create** — `sm 8 / md 12 / lg 16 / xl 20 / xxl 28 / pill StadiumBorder` |
| `lib/utils/app_elevation.dart` | **Create** — `level0..level3` (0/1/3/6) for M3 elevation steps |

### Light mode palette (new in `AppColorsLight`)

| Token | Value |
|---|---|
| Background | `#F8FAFC` |
| Surface | `#FFFFFF` |
| Surface Variant | `#EFF3F8` |
| Primary | `#0288D1` |
| Secondary | `#00838F` |
| Text Primary | `#0F1923` |
| Text Secondary | `#4A5568` |
| Error | `#D32F2F` |
| Success | `#388E3C` |
| Gold | `#F9A825` |

Finance category colors stay as-is (used as fills with borders).

---

## Phase 2 — ThemeData Wiring

> Both modes wired and switchable. Persistence added. Driven by `flex_color_scheme`.

| File | Action |
|---|---|
| `pubspec.yaml` | Add `flex_color_scheme: ^7.x` (latest stable) |
| `lib/views/fasting_app.dart` | Replace any inline `ThemeData()` with `_darkTheme()` / `_lightTheme()` factories built via `FlexThemeData.dark()` / `.light()`; wire `themeMode` from `SettingsPresenter` |
| `lib/services/storage_service.dart` | Add `kThemeMode` key + `getThemeMode()` / `saveThemeMode(ThemeMode)` |
| `lib/presenters/settings_presenter.dart` | Add `themeMode` getter + `setThemeMode(ThemeMode)` |

### `flex_color_scheme` configuration (key settings)

- `colors:` derived from `AppColors` / `AppColorsLight` (we feed our palette in, not a generated seed)
- `useMaterial3: true`
- `subThemesData: FlexSubThemesData(`
  - `defaultRadius: AppRadii.lg` (16)
  - `inputDecoratorRadius: AppRadii.md` (12)
  - `cardRadius: AppRadii.lg` (16)
  - **`cardElevation: 0`** — HIG default; cards group via surface contrast, not shadow. Pages can opt-in to elevation per-card via `AppCard(variant: elevated)`
  - `bottomSheetRadius: 20`
  - `dialogRadius: AppRadii.xxl` (28)
  - `appBarBackgroundSchemeColor: SchemeColor.surface`
  - `bottomNavigationBarMutedUnselectedIcon: true`
  - `chipRadius: AppRadii.sm`
  - `snackBarRadius: AppRadii.md`
  - `snackBarBehavior: SnackBarBehavior.floating`
  - `)`
- `appBarStyle: FlexAppBarStyle.surface, appBarElevation: 0`
- `tabBarStyle: FlexTabBarStyle.flutterDefault`

### Page transitions (HIG-flavored)

- `pageTransitionsTheme:` use `ZoomPageTransitionsBuilder` (Android) — settled, HIG-adjacent. Avoid the default sliding `OpenUpwardsPageTransitionsBuilder`.
- Bottom sheet entrance / dialog entrance use `AppMotion.spring` curve (300ms / 200ms respectively).

### Manual overrides on top of `flex_color_scheme`

After the base ThemeData is generated, override:
- `textTheme:` injected from `AppTextStyles` (Plus Jakarta Sans + DM Mono via `google_fonts`)
- `extensions:` add `ThemeExtension` for any tokens flex doesn't carry (custom motion durations, glow opacity)

---

## Phase 3 — Theme Persistence

| Concern | Implementation |
|---|---|
| Persistence | `StorageService.saveThemeMode(ThemeMode)` stores `'system' | 'light' | 'dark'` strings |
| Default | `ThemeMode.system` on first launch (M3 best practice — respects OS) |
| Hot-swap | `SettingsPresenter` is a `ChangeNotifier`; `fasting_app.dart` rebuilds on `themeMode` change — no app restart |
| **No UI in 017** | The Settings UI for the toggle is built in **017h**. For dev / testing of light mode in the meantime, expose a temporary debug menu or test from device theme settings |

---

## Acceptance Criteria

- [ ] Token files (colors / type / spacing / motion / radii / elevation) created
- [ ] `flex_color_scheme` added to `pubspec.yaml`
- [ ] Both dark and light `ThemeData` defined via `FlexThemeData.*` + manual overrides
- [ ] App switches mode at runtime via `SettingsPresenter.setThemeMode`
- [ ] Theme preference persisted via `StorageService` and restored on cold start
- [ ] `useMaterial3: true` (verified)
- [ ] No visual regressions on any existing screen — app looks unchanged
- [ ] No hardcoded colors / radii / spacings / durations introduced in this plan's changes
- [ ] `AppTextStyles` registered as `ThemeData.textTheme` and applied app-wide

---

## Out of Scope (covered by other plans)

- Reusable widget library — **017W**
- Migration of existing widgets in `lib/views/widgets/` — **017W Phase 6**
- Page redesigns — **017a–017h**
- Page transitions / motion audit / accessibility QA — **017i**
- Settings UI for theme toggle — **017h**
- Custom painter parameterization — **017W Phase 6**
- RPG content language changes — handled in each page plan

---

## Risks

| Risk | Mitigation |
|---|---|
| `flex_color_scheme` opinions don't fit our palette | Feed exact `AppColors` values; manually override any sub-theme it gets wrong |
| Plus Jakarta Sans bloats first frame | Use `GoogleFonts.plusJakartaSansTextTheme()` once at theme level; verify with airplane-mode test that fonts are bundled, not fetched |
| Light mode contrast on finance category colors | Used as fills with borders — acceptable; revisit in 017i QA |
| ThemeMode hot-swap rebuilds entire tree | Acceptable; `MaterialApp` rebuild is cheap relative to gain |

---

## Plans That Build On 017

| Plan | Depends On |
|---|---|
| 017W | 017 |
| 017a–017h | 017 + 017W |
| 017i | 017a–017h |

---

*Plan 017 — tokens + theme only. Phase 1 can start immediately after alignment.*
