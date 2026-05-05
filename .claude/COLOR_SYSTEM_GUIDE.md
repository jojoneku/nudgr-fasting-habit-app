# Color System Guide

## Architecture

The app now uses a **color scale system** with proper tiering, derived from Material Design 3 principles.

### Neutral (Grey) Scale — Foundation
- **grey-900** (0xFF212121): Background (darkest)
- **grey-800** (0xFF424242): Surface/Cards (elevated)
- **grey-700** (0xFF616161): SurfaceVariant (mid-tone, disabled states)
- **grey-600** (0xFF757575): SurfaceHigh (hover, focus)
- **grey-400** (0xFFBDBDBD): Text secondary (low emphasis)
- **grey-0** (0xFFFFFFFF): Text primary (high emphasis)

### Accent Color Scales
Each accent (Blue, Teal, Red, Green, Amber) has a complete scale from 50–900:

- **Blue Scale**: Sky blue family (hue ~210°)
  - Base: scale-500 (0xFF2196F3) → Primary action color
  
- **Teal Scale**: Mana teal/cyan (hue ~180°)
  - Base: scale-500 (0xFF00BCD4) → Accent color
  - scale-400 (0xFF26C6DA) → Secondary color
  
- **Red Scale**: Ember red (hue ~0°)
  - Base: scale-500 (0xFFF44336) → Danger/Error
  
- **Green Scale**: Forest green (hue ~120°)
  - Base: scale-500 (0xFF4CAF50) → Success
  
- **Amber Scale**: Warm amber (hue ~45°)
  - Base: scale-400 (0xFFFFCA28) → Gold/Warning

## Usage

### Light Mode (Future)
```dart
AppColorsLight.background  // grey-50
AppColorsLight.surface     // grey-0
AppColorsLight.primary     // Blue scale-800 (darkened for AA contrast)
```

### Dark Mode (Current)
```dart
AppColors.background       // grey-900 (darkest)
AppColors.surface          // grey-800 (elevated)
AppColors.surfaceVariant   // grey-700 (mid-tone)
AppColors.textPrimary      // white (high emphasis)
AppColors.textSecondary    // grey-400 (low emphasis)
AppColors.primary          // Blue scale-500
AppColors.accent           // Teal scale-500
AppColors.danger/error     // Red scale-500
AppColors.success          // Green scale-500
AppColors.gold             // Amber scale-400
```

## Contrast & Accessibility

- **Background → Surface**: grey-900 → grey-800 = sufficient visual hierarchy
- **Surface → Text**: grey-800 + white text = WCAG AAA (contrast ratio ~15:1)
- **Accent colors**: Tinted at 500/600 range for vibrancy without hallation effect on dark backgrounds
- All colors meet WCAG AA minimum (4.5:1) on their intended backgrounds

## Future Extensibility

All scales are complete (50–900) to enable:
- Hover/active states (use darker scale variants)
- Disabled states (use grey-700 or lighter)
- Subtle overlays (use lighter scales at reduced opacity)
- Light mode support (reverse the scale logic)
