---
name: m3-hig
description: "Material 3 UI design skill with Apple HIG taste. Uses M3 as the structural foundation (ColorScheme, ThemeData, motion tokens) but customized deeply — no stock visuals. Borrows HIG-inspired spacing, motion restraint, and visual hierarchy. Dark mode default (Solo Leveling RPG aesthetic). Light mode supported as a distinct, premium identity. Use whenever building or reviewing UI."
---

# M3 × HIG — UI Design Intelligence

Material 3 as the **foundation**. Apple HIG as the **taste**. The System's RPG aesthetic as the **voice**.

> M3 gives us the structure. HIG gives us the restraint. The System gives us the soul.

**Always consult `/ui-ux-pro-max` in parallel** for product-type matching, color palette selection, typography pairings, UX guidelines, and accessibility checks. This skill narrows the design language; ui-ux-pro-max broadens the design intelligence.

---

## Philosophy

| Axis | Rule |
|------|------|
| **Foundation** | All UI is built on Material 3 — `ThemeData`, `ColorScheme`, M3 component APIs |
| **Customization** | No stock M3 visuals. Every visual property must be intentionally overridden |
| **HIG taste** | Borrow HIG spacing discipline, motion restraint, and hierarchy clarity — not Apple UI widgets |
| **RPG voice** | Dark default, light supported. Two moods, one brand. Atmosphere over decoration |
| **Theme duality** | Dark = Solo Leveling void aesthetic. Light = arcane scholar — bright, premium, still branded |

### What "HIG taste" means in practice

HIG (Apple Human Interface Guidelines) is not a set of widgets — it is a **philosophy**. Extract only these behaviors:

| HIG Principle | How We Apply It |
|---------------|-----------------|
| **Generous spacing** | 20dp side margins (not M3's 16dp default); 24dp+ between sections |
| **Motion restraint** | Animations are purposeful, never decorative. Short, sharp transitions |
| **Clarity before style** | Visible labels, legible contrast, unambiguous affordances |
| **Depth via blur** | `BackdropFilter` on sheets and overlays instead of opaque fills |
| **Hierarchy through scale** | Title/body ratio ≥ 2×. Weight contrast over color contrast |
| **Primary action singularity** | One dominant action per screen. Everything else recedes |

---

## Workflow

### Step 1 — Consult ui-ux-pro-max

Run the design system search for the current task:

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "health fitness gamified dark RPG mobile" --design-system -p "Fasting RPG"
```

Pull relevant guidance on: color palettes, typography, UX patterns, accessibility. This skill narrows; ui-ux-pro-max broadens.

### Step 2 — Apply M3 × HIG design decisions

Follow the sections below for theming, spacing, motion, and component patterns.

### Step 3 — Verify against the Pre-Delivery Checklist

Do not mark a UI task complete without running the checklist at the bottom of this file.

---

## Color System

### Principles

- **Dark default, light supported**: Dark mode is the primary experience (default `themeMode`). Light mode is a fully designed, distinct identity — not an afterthought.
- **Two moods, one brand**: The primary violet/purple brand color is the thread. Dark = neon on void. Light = rich ink on parchment. Same family, different atmosphere.
- **No raw hex in widgets**: All color references through `Theme.of(context).colorScheme.*` or `AppColors.*` tokens. Widgets must be theme-agnostic.
- **Custom seed**: Never rely on the M3 baseline purple. Both schemes are handcrafted.
- **Tonal discipline**: Use the full tonal palette — `primaryContainer`, `onPrimaryContainer`, `surfaceContainerHigh`, etc. Assign intentionally, not arbitrarily.

### Shared Color Roles (both themes)

| Role | Token | Purpose |
|------|-------|---------|
| Brand accent | `colorScheme.primary` | Primary actions, active states, accents |
| App background | `colorScheme.surface` | Root scaffold background |
| Card / panel | `colorScheme.surfaceContainerLow` | Cards, bottom sheets, dialogs |
| Elevated panel | `colorScheme.surfaceContainerHigh` | Input fills, chips, elevated cards |
| Body text | `colorScheme.onSurface` | Primary readable text |
| Secondary text | `colorScheme.onSurfaceVariant` | Metadata, placeholders, disabled |
| Danger | `colorScheme.error` | Destructive actions, validation errors |
| Success | Custom `AppColors.success` | XP gain, streak milestone, level-up |

---

### Dark Mode — Solo Leveling (Default)

**Identity**: The Void. Neon power lines in deep space. Solo Leveling dungeon aesthetic — oppressive blacks, violet neon, electric blue.

```dart
final darkColorScheme = ColorScheme.dark(
  brightness: Brightness.dark,
  primary: const Color(0xFF9D6FFF),           // neon violet
  onPrimary: const Color(0xFF1A0A40),
  primaryContainer: const Color(0xFF3D1F7A),
  onPrimaryContainer: const Color(0xFFD4AAFF),
  secondary: const Color(0xFF4FC3F7),          // electric blue
  onSecondary: const Color(0xFF001F2B),
  secondaryContainer: const Color(0xFF003A4D),
  onSecondaryContainer: const Color(0xFFB8E9FF),
  surface: const Color(0xFF0D0D0F),            // near-void
  onSurface: const Color(0xFFE8E8EE),
  surfaceContainerLowest: const Color(0xFF080809),
  surfaceContainerLow: const Color(0xFF15151A),
  surfaceContainer: const Color(0xFF1A1A22),
  surfaceContainerHigh: const Color(0xFF1E1E26),
  surfaceContainerHighest: const Color(0xFF252530),
  onSurfaceVariant: const Color(0xFF8C8CA0),
  outline: const Color(0xFF3A3A4A),
  outlineVariant: const Color(0xFF252530),
  error: const Color(0xFFCF6679),
  onError: const Color(0xFF2D0011),
  errorContainer: const Color(0xFF5C1A28),
  onErrorContainer: const Color(0xFFFFB3BE),
);
```

**Shadow rule (dark)**: `Colors.black.withOpacity(0.35)` — heavier shadows because the surface is already near-black.

**Milestone emphasis**: Use `primaryContainer` fills and a `primary`-tinted 2dp border on the relevant card. No glow.

---

### Light Mode — Arcane Scholar

**Identity**: The Guild Hall in daylight. Parchment warmth, rich indigo ink, gold trim. Premium and calm — still fantasy, not bubblegum. This isn't Material 3 blue-and-white; it's a mage's study.

```dart
final lightColorScheme = ColorScheme.light(
  brightness: Brightness.light,
  primary: const Color(0xFF5C35C9),           // deep violet — same brand, light-safe value
  onPrimary: const Color(0xFFFFFFFF),
  primaryContainer: const Color(0xFFEADDFF),  // soft lavender
  onPrimaryContainer: const Color(0xFF1E0063),
  secondary: const Color(0xFF0277BD),          // ocean blue
  onSecondary: const Color(0xFFFFFFFF),
  secondaryContainer: const Color(0xFFD6EEFF),
  onSecondaryContainer: const Color(0xFF001D32),
  surface: const Color(0xFFF6F5FF),            // soft white with violet undertone — not pure #FFF
  onSurface: const Color(0xFF1A1826),          // near-black with purple undertone
  surfaceContainerLowest: const Color(0xFFFFFFFF),
  surfaceContainerLow: const Color(0xFFEFEEFA), // very light lavender panel
  surfaceContainer: const Color(0xFFE9E7F5),
  surfaceContainerHigh: const Color(0xFFE3E1F0),
  surfaceContainerHighest: const Color(0xFFDDDBEB),
  onSurfaceVariant: const Color(0xFF4A4760),   // muted purple-slate for secondary text
  outline: const Color(0xFF7B7895),
  outlineVariant: const Color(0xFFCAC7E0),
  error: const Color(0xFFB3001B),
  onError: const Color(0xFFFFFFFF),
  errorContainer: const Color(0xFFFFDAD9),
  onErrorContainer: const Color(0xFF410007),
);
```

**Shadow rule (light)**: `Colors.black.withOpacity(0.08)` — very subtle; let the surface color carry the depth.

**No glow in light mode**: Glow effects don't read against bright surfaces. Use `primaryContainer` fills and `primary`-tinted borders for emphasis instead.

---

### Dual Theme Wiring (MaterialApp)

```dart
MaterialApp(
  // Dark is default; user can override via settings
  themeMode: ThemeMode.dark, // or ThemeMode.system / .light from user preference
  theme: AppTheme.light(),   // light ThemeData
  darkTheme: AppTheme.dark(), // dark ThemeData
)
```

```dart
// app_theme.dart
class AppTheme {
  static ThemeData dark() => ThemeData(
    colorScheme: darkColorScheme,
    // ... all overrides using dark scheme
  );

  static ThemeData light() => ThemeData(
    colorScheme: lightColorScheme,
    // ... all overrides using light scheme
  );
}
```

**Theme-agnostic widgets**: All component code must read from `Theme.of(context).colorScheme` — never hardcode colors or branch on `brightness` inside widgets. The theme does the work.

```dart
// GOOD — reads from active theme
color: Theme.of(context).colorScheme.surfaceContainerLow,

// BAD — breaks one of the themes
color: isDark ? const Color(0xFF15151A) : const Color(0xFFEFEEFA),
```

---

## Typography

### Principles

- Base M3 `TextTheme` as structure; override every style.
- HIG hierarchy: title-to-body weight/size ratio ≥ 2×.
- Monospaced numerals for timers, stats, XP counts (`fontFeatures: [FontFeature.tabularFigures()]`).
- Line heights: 1.2–1.35 for headings, 1.5–1.6 for body. Tighter than M3 defaults for a dense RPG panel feel.

### Type Scale

| M3 Role | Size | Weight | Line Height | Use |
|---------|------|--------|-------------|-----|
| `displayLarge` | 52sp | w700 | 1.15 | Level-up screens, hero numbers |
| `displaySmall` | 36sp | w600 | 1.2 | Section headers, XP milestones |
| `headlineMedium` | 28sp | w600 | 1.25 | Screen titles |
| `titleLarge` | 22sp | w600 | 1.3 | Card titles, sheet headers |
| `titleMedium` | 16sp | w600 | 1.35 | List section labels |
| `bodyLarge` | 16sp | w400 | 1.55 | Primary body text |
| `bodyMedium` | 14sp | w400 | 1.5 | Secondary body, descriptions |
| `labelLarge` | 14sp | w600 | 1.2 | Buttons, chips, CTAs |
| `labelSmall` | 11sp | w500 | 1.3 | Captions, metadata, timestamps |

### ThemeData TextTheme Override (Pattern)

```dart
textTheme: TextTheme(
  displayLarge: TextStyle(fontSize: 52, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -1.5),
  headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.5),
  titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.55),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
  labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4),
),
```

---

## Spacing & Layout

### Grid

- **Base unit**: 4dp
- **Content margin**: 20dp (HIG-standard, not M3's 16dp)
- **Section gap**: 24–32dp between distinct content sections
- **Component internal padding**: multiples of 4 — prefer 12, 16, 20, 24
- **List item height**: 56dp minimum (M3 ListTile default; keep it)

### HIG-Inspired Layout Rules

1. **Side margins are 20dp** — not 16dp. This one change dramatically improves breathing room.
2. **Between-section spacing is 24dp minimum** — groupings must breathe.
3. **Card internal padding is 20dp** — HIG content areas feel generous, not cramped.
4. **Top content starts 16dp below app bar** — don't crowd the bar.
5. **Bottom action area is bottom 30% of screen** — primary CTA always lives here.

### Safe Area

```dart
// Every root Scaffold
Scaffold(
  body: SafeArea(
    child: ...,
  ),
  // bottomNavigationBar handles its own safe area via NavigationBar widget
)
```

---

## Motion

### The HIG Restraint Rule

> If you can't explain *why* this animates, it shouldn't animate.

Animation serves communication:
- **State change**: show that something changed (opacity, scale)
- **Spatial navigation**: show where the user is going (slide, fade-through)
- **Feedback**: confirm a tap was received (ripple, scale pulse)
- **RPG moment**: reward a milestone (particle burst, scale pulse, color fill — purposeful, not decorative. No glow.)

### Duration Tokens

| Category | Duration | Curve | Use |
|----------|----------|-------|-----|
| Micro-interaction | 100–150ms | `Curves.easeOut` | Button press, toggle, ripple |
| State transition | 200–250ms | `Curves.easeInOut` | Tab switch, card expand |
| Screen transition | 300ms | M3 `Easing.emphasized` | Page push/pop |
| RPG moment | 350–500ms | Spring or `Curves.elasticOut` | Level-up, XP gain burst |
| Exit always | 60–70% of enter | `Curves.easeIn` | Dismiss, pop, hide |

### M3 Motion Tokens in Flutter

```dart
// M3 emphasized easing (HIG-compatible — not bouncy, purposeful)
static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

// Page transitions using M3 tokens
PageTransition(
  duration: const Duration(milliseconds: 300),
  reverseDuration: const Duration(milliseconds: 200),
  type: PageTransitionType.fade, // or custom FadeThrough
)
```

### HIG Motion Anti-Patterns (Do Not)

- No bouncy springs on utility UI (only RPG milestone moments earn elasticity)
- No width/height animation — animate `transform` and `opacity` only
- No animations > 500ms except RPG celebration moments
- No looping decorative animations that block reading
- Respect `MediaQuery.of(context).disableAnimations`

```dart
// Always check before animating
final reduceMotion = MediaQuery.of(context).disableAnimations;
final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 250);
```

---

## Component Patterns

### Cards — The System Panel

```dart
Container(
  margin: const EdgeInsets.symmetric(horizontal: 20),
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: colorScheme.outlineVariant, width: 1),
    // HIG-influenced: subtle shadow rather than M3 tonal elevation
    // Shadow weight adapts to theme: dark = heavier, light = subtle
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(
          Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.08,
        ),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: child,
)
```

### Buttons

```dart
// Primary CTA — Filled, full-width, bottom area
FilledButton(
  onPressed: onPressed,
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),  // tall, prominent
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: theme.textTheme.labelLarge,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  ),
  child: child,
)

// Secondary — Outlined
OutlinedButton(
  style: OutlinedButton.styleFrom(
    minimumSize: const Size(44, 44),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    side: BorderSide(color: colorScheme.outline),
  ),
  child: child,
)
```

### Bottom Sheet (HIG-influenced: blur + generous padding)

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        color: colorScheme.surfaceContainerLow.withOpacity(0.95),
        padding: EdgeInsets.fromLTRB(
          20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child,
          ],
        ),
      ),
    ),
  ),
)
```

### App Bar (HIG taste: no M3 colored surface tint)

```dart
appBarTheme: AppBarTheme(
  backgroundColor: colorScheme.surface,  // flat, no tint
  surfaceTintColor: Colors.transparent,  // kill M3's default tint scroll behavior
  elevation: 0,
  scrolledUnderElevation: 0,
  titleTextStyle: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
  iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
),
```

### Navigation Bar (M3 NavigationBar, customized)

```dart
navigationBarTheme: NavigationBarThemeData(
  height: 72,
  backgroundColor: colorScheme.surfaceContainerLow,
  surfaceTintColor: Colors.transparent,
  indicatorColor: colorScheme.primaryContainer,
  labelTextStyle: WidgetStateProperty.resolveWith((states) {
    final active = states.contains(WidgetState.selected);
    return textTheme.labelSmall?.copyWith(
      color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );
  }),
),
```

### Input Fields

```dart
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: colorScheme.surfaceContainerHigh,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: colorScheme.primary, width: 2),
  ),
  labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
),
```

### Chip

```dart
chipTheme: ChipThemeData(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  side: BorderSide(color: colorScheme.outlineVariant),
  backgroundColor: colorScheme.surfaceContainerHigh,
  labelStyle: textTheme.labelSmall,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
),
```

### Divider

```dart
dividerTheme: DividerThemeData(
  color: colorScheme.outlineVariant,
  thickness: 1,
  space: 1,
),
```

---

## Elevation & Depth

M3 uses `surfaceTintColor` to show elevation. This app **disables tint elevation** and uses shadow + opacity instead (HIG-style depth via blur, not color wash).

**Rule**: Kill `surfaceTintColor` at the ThemeData level:

```dart
ThemeData(
  // ...
  // Disable M3's default tint-based elevation
  cardTheme: CardThemeData(surfaceTintColor: Colors.transparent),
  dialogTheme: DialogThemeData(surfaceTintColor: Colors.transparent),
  bottomSheetTheme: BottomSheetThemeData(surfaceTintColor: Colors.transparent),
)
```

Use `boxShadow` for elevation and `BackdropFilter` for overlay depth.

---

## RPG Aesthetic Constraints

These override general M3/HIG defaults and are non-negotiable for both themes:

| Constraint | Dark (Solo Leveling) | Light (Arcane Scholar) |
|---|---|---|
| Background | `#0D0D0F` — near-void, not pure black | `#F6F5FF` — soft white with violet undertone, not pure `#FFF` |
| Primary accent | Neon violet `#9D6FFF` | Deep violet `#5C35C9` |
| Secondary accent | Electric blue `#4FC3F7` | Ocean blue `#0277BD` |
| Card surface | `surfaceContainerLow` `#15151A` | `surfaceContainerLow` `#EFEEEFA` |
| Card radius | 12–16dp — rounded but architectural | Same |
| Border on cards | Always — 1dp `outlineVariant` | Always — 1dp `outlineVariant` |
| Typography weight | Bold titles w600–w700, regular body | Same — weight contrast is brand, not mode |
| Milestone emphasis | `primaryContainer` fill + `primary` 2dp border on card. No glow. | Same |
| Shadow weight | `Colors.black.withOpacity(0.35)` | `Colors.black.withOpacity(0.08)` |
| Icon style | Consistent family — `Icons.*` (outlined) or custom SVG. No mixing | Same |
| Scrim / modal overlay | `Colors.black.withOpacity(0.6)` | `Colors.black.withOpacity(0.4)` |

---

## Integration with `ui-ux-pro-max`

| Need | Which skill |
|------|-------------|
| M3 component API + override patterns | This skill (m3-hig) |
| Product type analysis | `ui-ux-pro-max --domain product` |
| Color palette selection | `ui-ux-pro-max --domain color` |
| Font pairing decisions | `ui-ux-pro-max --domain typography` |
| Chart/data viz type | `ui-ux-pro-max --domain chart` |
| Accessibility checks | Both — `ui-ux-pro-max` priority rules first |
| Animation timing review | This skill (motion section) |
| UX pattern review | `ui-ux-pro-max` rule categories |

When both apply, **this skill wins on M3 component implementation**; **ui-ux-pro-max wins on accessibility, product reasoning, and UX patterns**.

---

## Pre-Delivery Checklist

### Theme Integrity
- [ ] No raw hex values in widget trees — all colors via `colorScheme.*` or `AppColors.*`
- [ ] `surfaceTintColor: Colors.transparent` set on card, dialog, bottom sheet themes
- [ ] Custom `TextTheme` applied — not M3 default typography
- [ ] `scrolledUnderElevation: 0` set on AppBar to prevent M3 tint on scroll

### HIG Spacing
- [ ] Side margins are 20dp (not 16dp)
- [ ] Section gaps are ≥ 24dp
- [ ] Card internal padding is 20dp
- [ ] Touch targets are ≥ 44×44dp with `hitTestBehavior` or `hitSlop` where needed

### Motion Restraint
- [ ] All animations checked for "why does this animate?" justification
- [ ] No animation > 300ms for UI state (RPG celebrations may go to 500ms)
- [ ] `MediaQuery.of(context).disableAnimations` respected
- [ ] Exit animations are shorter than enter (60–70%)
- [ ] Only `transform` and `opacity` animated — no width/height animation

### Visual Hierarchy
- [ ] One primary CTA per screen, in bottom 30%
- [ ] Title-to-body type ratio ≥ 2× in size or weight
- [ ] Color is not the only differentiator — size/weight/position also carry meaning
- [ ] Onboarding and empty states have a clear focal point

### Accessibility (from ui-ux-pro-max)
- [ ] Text contrast ≥ 4.5:1 (normal text), ≥ 3:1 (large/bold)
- [ ] Icon-only buttons have `Semantics` labels
- [ ] Dynamic text scaling does not break layout
- [ ] Color is not sole indicator of state

### Theme Duality (Light + Dark)
- [ ] Both `theme:` and `darkTheme:` are wired in `MaterialApp` — `themeMode: ThemeMode.dark` as default
- [ ] No widget branches on `brightness` — all color reads are via `colorScheme.*` tokens
- [ ] Light mode background is `#F6F5FF`, not pure white and not generic grey
- [ ] Neither mode uses glow effects — milestone emphasis is `primaryContainer` fill + `primary` border
- [ ] Card shadow opacity in light mode is ≤ 0.08 (subtle); dark mode is ≤ 0.35
- [ ] Modal scrim is 60% black (dark) / 40% black (light)
- [ ] Contrast verified in both modes: ≥ 4.5:1 body text, ≥ 3:1 large text

### RPG Aesthetic
- [ ] Dark: background is near-void (`#0D0D0F`), not pure black and not generic grey
- [ ] Light: background is violet-tinted white (`#F6F5FF`), not pure `#FFFFFF`
- [ ] Cards have 1dp border (`outlineVariant`) in both modes
- [ ] No emoji used as icons
- [ ] No glow effects in either mode — milestone cards use `primaryContainer` fill + `primary` 2dp border
- [ ] Font weights are high-contrast between heading and body levels in both modes
