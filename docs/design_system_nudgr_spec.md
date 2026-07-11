# Nudgr Design System — Token Spec

**Status:** Draft · **Owner:** System Architect · **Source of truth:** `Nudgr Design Tokens` prototype export (dark canonical, light derived).

## Overview

Adopt the prototype's canonical token system as the app's single design-system source. It is **dark-first** (near-black premium surfaces) with a **derived light palette**, and introduces **domain-semantic accent colors** — one hue per module so a multi-module "life OS" stays scannable:

| Domain | Hue |
|---|---|
| Fast | Blue |
| Food | Teal |
| Move | Green |
| Bills | Orange |
| Treasury | Gold |
| Weight | Purple |

This supersedes the app's current Material-grey surface ramp (`_GreyScale`) and the two-tier text model. It does **not** change the dual-theme machinery (`SettingsPresenter.themeMode`, `buildDarkTheme`/`buildLightTheme` in `app_theme.dart`) — only the token *values* and the semantic tokens exposed to widgets.

> The `Nudgr Directions` doc (warm "Stillness" / cool "Focus" light concepts, Hanken Grotesk / Manrope) is an earlier exploration and is **not** adopted. The Tokens system owns both modes.

## Non-negotiable constraints (from CLAUDE.md)

- Widgets read from `Theme.of(context)` (`colorScheme.*`, `textTheme.*`) and `context.appColors` (the `AppThemeExtension`). Direct `AppColors.X` / `AppColorsLight.X` use stays confined to `app_colors.dart` + `app_theme.dart`.
- Every token ships a dark **and** a light value. Dark is canonical; light is derived maintaining contrast.
- Card elevation rule preserved: card on bg → `surfaceContainerLow`; card on card/sheet → `surfaceContainerHigh`.

## Token tables

### Surfaces (ascending elevation)

| Token | Dark | Light | Role | M3 ColorScheme slot |
|---|---|---|---|---|
| page | `#0A0A0B` | `#F0F0F5` | Scaffold / outermost shell | `surfaceContainerLowest`, `scaffoldBackgroundColor` |
| screen | `#131315` | `#FFFFFF` | Primary screen background | `surface` |
| sheet | `#171718` | `#F5F5FA` | Bottom sheets, modals | `surfaceContainer`, bottomSheet bg |
| card | `#1C1C20` | `#F0F0F6` | Cards, tiles, list items (on bg) | `surfaceContainerLow` |
| input | `#252628` | `#E4E4EA` | Inputs, set pills, card-on-card | `surfaceContainerHigh` |
| track | `#26262A` | `#E0E0E6` | Progress/macro bar & chart tracks | `surfaceContainerHighest` |
| shell | `#0E0E10` | `#E8E8EF` | Tab bar / persistent chrome | nav bar bg |
| elevated | `#141414` | `#FAFAFA` | Slightly raised surfaces | (helper only) |

### Borders

| Token | Dark | Light | M3 slot |
|---|---|---|---|
| border-inner | `#1E1E22` | `#E8E8EF` | `outlineVariant` (row dividers) |
| border-card | `#2A2A2E` | `#DCDCE3` | `outline` (card border) |
| border-sheet | `#2E2F31` | `#D4D4DC` | (extension) |

### Text (5 tiers)

| Token | Dark | Light | Slot |
|---|---|---|---|
| primary | `#F7F7F8` | `#1A1A1E` | `onSurface` |
| secondary | `#C9CDD3` | `#4A4E58` | `onSurfaceVariant` |
| tertiary | `#9A9FA8` | `#72767F` | extension `textTertiary` |
| muted | `#83878F` | `#8C9097` | extension `textMuted` |
| inactive | `#6A6E76` | `#B2B6BE` | extension `textInactive` |

### Domain accents

Format: **primary** (main), **light** (on-dark text variant / deep-for-light), **track** (dim fill behind ring/bar).

| Domain | primary D/L | light D/L | track D/L |
|---|---|---|---|
| Fast · Blue | `#2E90FA` / `#2E90FA` | `#5BAAF5` / `#1860C8` | `#1A2535` / `#D0E5FF` |
| Food · Teal | `#26C6DA` / `#0AACBF` | — | `#1A2826` / `#C8EEF4` |
| Move · Green | `#46BD6B` / `#2EA055` | `#6FCB8A` / `#1A7A3A` | `#152218` / `#C8EDD6` |
| Danger · Red | `#F6685E` / `#D84840` | `#FF8A80` / `#B83030` | — |
| Bills · Orange | `#FF8A4C` / `#D06010` | `#FFB37A` / `#A85020` | — |
| Treasury · Gold | `#FFCA28` / `#C89000` | — | — |
| Weight · Purple | `#926AFA` / `#6840D8` | — | — |

**Semantic mapping to `colorScheme`:** Fast→`primary`, Food→`tertiary`, Danger→`error`. The rest live on `AppThemeExtension` (see Interface below). Tint backgrounds use the domain hue at `.10–.16` alpha.

### Special surfaces (gradients)

| Token | Dark | Light |
|---|---|---|
| surface-treasury | `linear-gradient(155deg,#1B2A44,#172033 55%,#15171C)` | `linear-gradient(155deg,#EBF2FF,#F0F6FF 55%,#F8FAFF)` |
| surface-bills | `linear-gradient(155deg,#3A2417,#241813 70%,#15171C)` | `linear-gradient(155deg,#FFF4EE,#FFF8F4 70%,#FAFAFA)` |
| surface-card-gradient | `linear-gradient(160deg,#222325,#191919)` | `linear-gradient(160deg,#F5F5F8,#F0F0F4)` |
| overlay-backdrop | `rgba(0,0,0,.55)` | `rgba(0,0,0,.28)` |

### Account brand colors (static — identical in both modes)

`BPI #9B2C2C` · `GCash #1565C0` · `Maya #1B7A4B` · `Maribank #2A2566`

## Typography

- Body/UI: **Plus Jakarta Sans** — already the app default (`AppTextStyles`), no change.
- Numeric/mono: **JetBrains Mono** — *new*, for large timer/stat numerals where the prototype uses it. Optional in v1; add a `AppTextStyles.mono` helper.
- Radii: current `AppRadii` (sm8/md12/lg16/xl20/xxl28) already align with the prototype's 14–22px cards — no change.

## Accessibility

- Verify **AA (4.5:1)** for text-on-tint in light mode; the doc mandates replacing `*-light` accents with the deeper values in light mode for contrast — honor per-token light values above.
- Domain color is never the *only* signal (pair with icon/label) — colorblind safety.
- Preserve reduced-motion behavior; this spec changes color only.

## Web companion

The Treasury web build (`TreasuryWebApp`) previously used a separate "Pondr"
token set (`lib/views/web/design/web_theme.dart`). It is now **unified** onto
these Nudgr tokens: `buildWebDarkTheme`/`buildWebLightTheme` source every value
from `NudgrDark`/`NudgrLight` and inject `AppThemeExtension`, so web and mobile
share one identity. The web keeps a desktop-tuned light arrangement (grey page
`#F0F0F5` + white cards) and uses the spec's deep `fast-light` `#1860C8` as the
action/primary color for AA button contrast on white.

## Out of scope

- No layout, navigation, or component-structure changes (the Directions doc's fan-FAB / grid concepts are not part of this).
- No new screens.
