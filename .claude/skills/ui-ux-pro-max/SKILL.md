---
name: ui-ux-pro-max
description: "UI/UX design intelligence for Flutter mobile. Includes 50+ styles, 161 color palettes, 57 font pairings, 161 product types, 99 UX guidelines, and 25 chart types. Adapted for the Solo Leveling RPG aesthetic of this intermittent fasting app. Actions: plan, build, create, design, implement, review, fix, improve, optimize, enhance, refactor, and check UI/UX code. Styles: glassmorphism, claymorphism, minimalism, brutalism, neumorphism, bento grid, dark mode, responsive, skeuomorphism, and flat design."
---

# UI/UX Pro Max - Design Intelligence (Flutter)

Comprehensive design guide for Flutter mobile applications. Contains 50+ styles, 161 color palettes, 57 font pairings, 161 product types with reasoning rules, 99 UX guidelines, and 25 chart types. Adapted for this project's **Solo Leveling RPG dark aesthetic**.

> **Stack:** Flutter (Dart 3+) — use `--stack flutter` for all stack-specific searches.
> **Script path:** `.claude/skills/ui-ux-pro-max/scripts/search.py`

## When to Apply

This Skill should be used when the task involves **UI structure, visual design decisions, interaction patterns, or user experience quality control**.

### Must Use

- Designing new screens (Home, Stats, Settings, Onboarding, etc.)
- Creating or refactoring widgets (buttons, cards, modals, bottom sheets, charts, etc.)
- Choosing color schemes, typography systems, spacing standards, or layout systems
- Reviewing UI code for user experience, accessibility, or visual consistency
- Implementing navigation structures, animations, or responsive behavior
- Making product-level design decisions (style, information hierarchy, brand expression)
- Improving perceived quality, clarity, or usability of interfaces

### Skip

- Pure backend logic / service layer changes
- Only involving storage or notification logic
- Performance optimization unrelated to the interface
- Infrastructure or DevOps work

**Decision criteria**: If the task will change how a feature **looks, feels, moves, or is interacted with**, this Skill should be used.

## Rule Categories by Priority

| Priority | Category | Impact | Key Checks (Must Have) | Anti-Patterns (Avoid) |
|----------|----------|--------|------------------------|------------------------|
| 1 | Accessibility | CRITICAL | Contrast 4.5:1, Semantic labels, Keyboard nav | Removing focus rings, Icon-only buttons without labels |
| 2 | Touch & Interaction | CRITICAL | Min size 44×44px, 8px+ spacing, Loading feedback | Reliance on hover only, Instant state changes (0ms) |
| 3 | Performance | HIGH | Lazy loading, Reserve space, Virtualize lists | Layout thrashing, Unnecessary rebuilds |
| 4 | Style Selection | HIGH | Match product type, Consistency, SVG icons (no emoji) | Mixing flat & skeuomorphic randomly, Emoji as icons |
| 5 | Layout & Responsive | HIGH | Mobile-first, Safe areas, No horizontal scroll | Horizontal scroll, Fixed px widths, Disable zoom |
| 6 | Typography & Color | MEDIUM | Base 16px, Line-height 1.5, Semantic color tokens | Text < 12px body, Gray-on-gray, Raw hex in widgets |
| 7 | Animation | MEDIUM | Duration 150–300ms, Motion conveys meaning | Decorative-only animation, Animating width/height |
| 8 | Forms & Feedback | MEDIUM | Visible labels, Error near field, Progressive disclosure | Placeholder-only label, Errors only at top |
| 9 | Navigation Patterns | HIGH | Predictable back, Bottom nav ≤5, Deep linking | Overloaded nav, Broken back behavior |
| 10 | Charts & Data | LOW | Legends, Tooltips, Accessible colors | Relying on color alone to convey meaning |

## Quick Reference

### 1. Accessibility (CRITICAL)

- `color-contrast` - Minimum 4.5:1 ratio for normal text (large text 3:1)
- `focus-states` - Visible focus rings on interactive elements (2–4px)
- `aria-labels` - Semantics widget with label for icon-only buttons
- `keyboard-nav` - Tab order matches visual order; full keyboard support
- `dynamic-type` - Support system text scaling; avoid truncation as text grows
- `reduced-motion` - Respect AccessibilityFeatures.disableAnimations
- `voiceover-sr` - Meaningful Semantics labels; logical reading order
- `escape-routes` - Provide cancel/back in modals and multi-step flows

### 2. Touch & Interaction (CRITICAL)

- `touch-target-size` - Min 44×44pt (iOS) / 48×48dp (Android); use GestureDetector hitSlop
- `touch-spacing` - Minimum 8px gap between touch targets
- `loading-buttons` - Disable button during async; show CircularProgressIndicator
- `error-feedback` - Clear error messages near problem
- `gesture-conflicts` - Avoid horizontal swipe on main content; prefer vertical scroll
- `press-feedback` - InkWell / InkResponse ripple on tap
- `haptic-feedback` - HapticFeedback for confirmations; avoid overuse
- `safe-area-awareness` - MediaQuery.of(context).padding; SafeArea widget for notch/gesture bar
- `swipe-clarity` - Swipe actions must show clear affordance

### 3. Performance (HIGH)

- `lazy-loading` - Lazy load non-hero widgets via visibility checks
- `virtualize-lists` - ListView.builder / SliverList for 50+ items
- `main-thread-budget` - Keep per-frame work under ~16ms for 60fps
- `progressive-loading` - Shimmer placeholders instead of blocking spinners >1s
- `input-latency` - Keep input latency under ~100ms for taps/scrolls
- `tap-feedback-speed` - Visual feedback within 100ms of tap
- `const-widgets` - Use `const` constructors to reduce rebuilds
- `repaint-boundary` - RepaintBoundary for complex animated widgets

### 4. Style Selection (HIGH)

- `style-match` - Match style to product type (search `--design-system`)
- `consistency` - Use same style across all screens
- `no-emoji-icons` - Use Material Icons or custom SVG icons, not emojis
- `color-palette-from-product` - Choose palette from product/industry
- `platform-adaptive` - Respect platform idioms (iOS HIG vs Material)
- `dark-mode-pairing` - Design light/dark variants together
- `primary-action` - Each screen should have only one primary CTA; bottom 30% of screen

### 5. Layout & Responsive (HIGH)

- `mobile-first` - Design for 375px first, then scale up
- `safe-area` - SafeArea widget wraps all root scaffolds
- `spacing-scale` - Use 4pt/8dp incremental spacing system
- `z-index-management` - Consistent elevation scale for cards, sheets, modals
- `fixed-element-offset` - Bottom nav must reserve safe padding for underlying content
- `scroll-behavior` - Avoid nested scroll regions that interfere with main scroll
- `orientation-support` - Keep layout readable in landscape mode
- `visual-hierarchy` - Size, spacing, contrast — not color alone

### 6. Typography & Color (MEDIUM)

- `line-height` - Use 1.5–1.75 for body text
- `font-scale` - Consistent type scale (12 14 16 18 24 32 sp)
- `color-semantic` - ThemeData color tokens (primary, secondary, error, surface)
- `color-dark-mode` - Dark mode uses desaturated/lighter tonal variants
- `number-tabular` - Monospaced figures for timers, counters, data
- `whitespace-balance` - Use whitespace to group related items; avoid clutter

### 7. Animation (MEDIUM)

- `duration-timing` - 150–300ms micro-interactions; complex ≤400ms; avoid >500ms
- `transform-performance` - Animate transform/opacity only; avoid size/position
- `loading-states` - Shimmer or CircularProgressIndicator when loading >300ms
- `easing` - Curves.easeOut entering, Curves.easeIn exiting
- `spring-physics` - Prefer spring/physics curves for natural feel
- `exit-faster-than-enter` - Exit ~60–70% of enter duration
- `shared-element-transition` - Hero widget for visual continuity between screens
- `interruptible` - Animations must be interruptible by user tap
- `scale-feedback` - Subtle scale (0.95–1.05) on press for tappable cards/buttons
- `no-blocking-animation` - Never block user input during animation

### 8. Forms & Feedback (MEDIUM)

- `input-labels` - Visible InputDecoration label per input
- `error-placement` - Show error below the related field (errorText)
- `submit-feedback` - Loading then success/error state on submit
- `empty-states` - Helpful message and action when no content
- `toast-dismiss` - SnackBar auto-dismiss in 3–5s
- `confirmation-dialogs` - AlertDialog before destructive actions
- `progressive-disclosure` - Reveal complex options progressively
- `inline-validation` - Validate on unfocus; show error after user finishes input
- `input-type-keyboard` - TextInputType for correct mobile keyboard
- `undo-support` - SnackBar with "Undo" for destructive actions

### 9. Navigation Patterns (HIGH)

- `bottom-nav-limit` - BottomNavigationBar max 5 items; icons + labels
- `back-behavior` - WillPopScope / PopScope; predictable and consistent
- `tab-bar-ios` - iOS: bottom Tab Bar for top-level navigation
- `top-app-bar-android` - Android: AppBar with navigation icon
- `nav-state-active` - Current route visually highlighted in navigation
- `modal-escape` - showModalBottomSheet / showDialog with clear close affordance
- `state-preservation` - Restore scroll position and state on back navigation
- `gesture-nav-support` - Support iOS swipe-back; don't conflict with it
- `bottom-nav-top-level` - Bottom nav for top-level screens only

### 10. Charts & Data (LOW)

- `chart-type` - Match chart type to data (trend → line, comparison → bar)
- `color-guidance` - Accessible color palettes; avoid red/green-only pairs
- `legend-visible` - Always show legend near the chart
- `tooltip-on-interact` - GestureDetector tap showing exact values
- `responsive-chart` - Charts reflow/simplify on small screens
- `empty-data-state` - Meaningful empty state when no data

---

## How to Use This Skill

### Prerequisites

Check Python is installed:
```bash
python3 --version || python --version
```

Install if needed (Windows):
```powershell
winget install Python.Python.3.12
```

---

### Step 1: Analyze User Requirements

Extract from user request:
- **Product type**: Gamified health/fitness, RPG aesthetic, solo player progression
- **Target audience**: Adults tracking fasting; motivating, dark, immersive
- **Style keywords**: dark mode, RPG, Solo Leveling, gamified, neon accent
- **Stack**: Flutter

### Step 2: Generate Design System (REQUIRED)

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<product_type> <keywords>" --design-system [-p "Project Name"]
```

**Example for this app:**
```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "health fitness gamified dark RPG mobile" --design-system -p "Fasting RPG"
```

### Step 2b: Persist Design System

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<query>" --design-system --persist -p "Fasting RPG"
```

Creates:
- `design-system/MASTER.md` — Global Source of Truth
- `design-system/pages/` — Screen-specific overrides

### Step 3: Supplement with Detailed Searches

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --domain <domain> [-n <max_results>]
```

| Need | Domain | Example |
|------|--------|---------|
| Product type patterns | `product` | `--domain product "health fitness gamified"` |
| More style options | `style` | `--domain style "dark mode RPG neon"` |
| Color palettes | `color` | `--domain color "gaming dark purple"` |
| Font pairings | `typography` | `--domain typography "futuristic bold"` |
| Chart recommendations | `chart` | `--domain chart "progress timeline streak"` |
| UX best practices | `ux` | `--domain ux "animation accessibility"` |
| App interface a11y | `web` | `--domain web "accessibilityLabel touch safe-areas"` |

### Step 4: Flutter Stack Guidelines

```bash
python3 .claude/skills/ui-ux-pro-max/scripts/search.py "<keyword>" --stack flutter
```

---

## This App's Design Constraints

Always apply these on top of the skill's general guidance:

| Constraint | Rule |
|---|---|
| **Aesthetic** | Solo Leveling dark RPG — deep blacks, purple/blue neons, sharp edges |
| **Touch targets** | ≥ 44×44px always (from CLAUDE.md) |
| **Primary actions** | Bottom 30% of screen (from CLAUDE.md) |
| **Animations** | 150–300ms micro; ≤ 400ms max (from CLAUDE.md) |
| **State** | No logic in build(); delegate to `presenter.someGetter` |
| **Colors** | Use ThemeData tokens; never raw hex in widgets |

---

## Pre-Delivery Checklist

### Visual Quality
- [ ] No emojis used as icons (use Material Icons or custom SVG)
- [ ] All icons from a consistent icon family and style
- [ ] Pressed-state visuals do not shift layout bounds or cause jitter
- [ ] Semantic ThemeData color tokens used (no ad-hoc hardcoded hex)

### Interaction
- [ ] All tappable elements provide InkWell/InkResponse pressed feedback
- [ ] Touch targets meet minimum size (≥44×44pt iOS, ≥48×48dp Android)
- [ ] Micro-interaction timing 150–300ms with native-feeling easing
- [ ] Disabled states are visually clear and non-interactive
- [ ] Semantics labels set for icon-only controls

### Light/Dark Mode
- [ ] Primary text contrast ≥4.5:1 in dark mode
- [ ] Secondary text contrast ≥3:1 in dark mode
- [ ] Dividers/borders distinguishable against dark backgrounds
- [ ] Modal scrim opacity 40–60% black

### Layout
- [ ] SafeArea wraps root scaffold; notch/gesture bar respected
- [ ] Scroll content not hidden behind fixed/sticky bars
- [ ] Verified on 375px (small phone) in portrait and landscape
- [ ] 8dp spacing rhythm maintained across components

### Accessibility
- [ ] All meaningful icons have Semantics labels
- [ ] Color is not the only indicator
- [ ] Reduced motion (AccessibilityFeatures.disableAnimations) supported
- [ ] Dynamic text size supported without layout breakage
