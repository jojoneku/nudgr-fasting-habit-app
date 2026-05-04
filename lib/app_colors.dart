import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NEUTRAL (GREY) SCALE — Base for all tiering
// ─────────────────────────────────────────────────────────────────────────────
// Derived from Material grey scale, used as foundation for all surfaces
class _GreyScale {
  static const Color grey0 = Color(0xFFFFFFFF); // brightest
  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E); // base reference
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121); // darkest
  static const Color grey950 = Color(0xFF0A0A0A);
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCENT SCALES — Derived from base colors via lightness/saturation
// ─────────────────────────────────────────────────────────────────────────────
class _BlueScale {
  // Sky blue family, derived from hue ~210
  static const Color scale50 = Color(0xFFE3F2FD);
  static const Color scale100 = Color(0xFFBBDEFB);
  static const Color scale200 = Color(0xFF90CAF9);
  static const Color scale300 = Color(0xFF64B5F6);
  static const Color scale400 = Color(0xFF42A5F5);
  static const Color scale500 = Color(0xFF2196F3); // base
  static const Color scale600 = Color(0xFF1E88E5);
  static const Color scale700 = Color(0xFF1976D2);
  static const Color scale800 = Color(0xFF1565C0);
  static const Color scale900 = Color(0xFF0D47A1);
}

class _TealScale {
  // Mana teal/cyan family, derived from hue ~180
  static const Color scale50 = Color(0xFFE0F2F1);
  static const Color scale100 = Color(0xFFB2DFDB);
  static const Color scale200 = Color(0xFF80CBC4);
  static const Color scale300 = Color(0xFF4DB6AC);
  static const Color scale400 = Color(0xFF26C6DA);
  static const Color scale500 = Color(0xFF00BCD4); // base
  static const Color scale600 = Color(0xFF00ACC1);
  static const Color scale700 = Color(0xFF0097A7);
  static const Color scale800 = Color(0xFF00838F);
  static const Color scale900 = Color(0xFF006064);
}

class _RedScale {
  // Ember red family, derived from hue ~0
  static const Color scale50 = Color(0xFFFFEBEE);
  static const Color scale100 = Color(0xFFFFCDD2);
  static const Color scale200 = Color(0xFFEF9A9A);
  static const Color scale300 = Color(0xFFE57373);
  static const Color scale400 = Color(0xFFEF5350);
  static const Color scale500 = Color(0xFFF44336); // base
  static const Color scale600 = Color(0xFFE53935);
  static const Color scale700 = Color(0xFFD32F2F);
  static const Color scale800 = Color(0xFFC62828);
  static const Color scale900 = Color(0xFFB71C1C);
}

class _GreenScale {
  // Forest green family, derived from hue ~120
  static const Color scale50 = Color(0xFFE8F5E9);
  static const Color scale100 = Color(0xFFC8E6C9);
  static const Color scale200 = Color(0xFFA5D6A7);
  static const Color scale300 = Color(0xFF81C784);
  static const Color scale400 = Color(0xFF66BB6A);
  static const Color scale500 = Color(0xFF4CAF50); // base
  static const Color scale600 = Color(0xFF43A047);
  static const Color scale700 = Color(0xFF388E3C);
  static const Color scale800 = Color(0xFF2E7D32);
  static const Color scale900 = Color(0xFF1B5E20);
}

class _AmberScale {
  // Warm amber family, derived from hue ~45
  static const Color scale50 = Color(0xFFFFF8E1);
  static const Color scale100 = Color(0xFFFFECB3);
  static const Color scale200 = Color(0xFFFFE082);
  static const Color scale300 = Color(0xFFFFD54F);
  static const Color scale400 = Color(0xFFFFCA28);
  static const Color scale500 = Color(0xFFFFC107); // base
  static const Color scale600 = Color(0xFFFFB300);
  static const Color scale700 = Color(0xFFFFA000);
  static const Color scale800 = Color(0xFFFF8F00);
  static const Color scale900 = Color(0xFFFF6F00);
}

// ─────────────────────────────────────────────────────────────────────────────
// LIGHT MODE (Future) — Inverse of dark mode
// ─────────────────────────────────────────────────────────────────────────────
// Color tiering: grey-50 (background) → grey-0 (elevated surfaces)
// Text: dark greys for proper contrast on light backgrounds
class AppColorsLight {
  // ── SURFACES ──────────────────────────────────────────────────────────────
  // Strict tiering: background (lightest) → surface (white) → variant (light grey)
  static const Color background = _GreyScale.grey50; // Lightest (bg)
  static const Color surface = _GreyScale.grey0; // Elevated (cards)
  static const Color surfaceVariant = _GreyScale.grey100; // Mid-tone (disabled)
  static const Color surfaceHigh = _GreyScale.grey200; // Hover/focus states

  // ── ACCENT COLORS ─────────────────────────────────────────────────────────
  // Darkened for AA+ contrast on light backgrounds
  static const Color primary = _BlueScale.scale800; // Dark blue
  static const Color accent = _TealScale.scale800; // Dark teal
  static const Color secondary =
      _TealScale.scale700; // Even darker for better contrast

  static const Color danger = _RedScale.scale700; // Dark red
  static const Color success = _GreenScale.scale700; // Dark green
  static const Color gold = _AmberScale.scale600; // Dark amber

  // ── TEXT ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = _GreyScale.grey900; // Black (high emphasis)
  static const Color textSecondary =
      _GreyScale.grey600; // Dark grey (low emphasis)

  static const Color error = _RedScale.scale700; // Same as danger
  static const Color neutral = _GreyScale.grey500; // Base grey

  // ── GLOWS (for shadows/effects) ───────────────────────────────────────────
  static const Color accentGlow = Color(0x2D00ACC1); // accent @ 20%
  static const Color successGlow = Color(0x2D388E3C); // success @ 20%
  static const Color dangerGlow = Color(0x2DD32F2F); // danger @ 20%
}

// ─────────────────────────────────────────────────────────────────────────────
// DARK MODE (Default) — Solo Leveling RPG Aesthetic
// ─────────────────────────────────────────────────────────────────────────────
// Color tiering: grey-900 (background) → grey-800 (elevated surfaces)
// Accent colors: tinted to 500/600 range for vibrancy without hallation
class AppColors {
  // ── SURFACES ──────────────────────────────────────────────────────────────
  // Strict tiering ensures proper visual hierarchy and contrast
  static const Color background = _GreyScale.grey900; // Darkest (bg)
  static const Color surface = _GreyScale.grey800; // Elevated (cards)
  static const Color surfaceVariant =
      _GreyScale.grey700; // Mid-tone (disabled, tertiary)
  static const Color surfaceHigh = _GreyScale.grey600; // Hover/focus states

  // ── ACCENT COLORS ─────────────────────────────────────────────────────────
  // Tinted at 500-600 range: bright enough for vibrancy, toned enough for comfort
  static const Color primary = _BlueScale.scale500; // Sky Blue
  static const Color accent = _TealScale.scale500; // Mana Teal
  static const Color secondary =
      _TealScale.scale400; // Soft Cyan (slightly lighter)

  static const Color danger = _RedScale.scale500; // Ember Red
  static const Color success = _GreenScale.scale500; // Forest Green
  static const Color gold = _AmberScale.scale400; // Warm Amber

  // ── TEXT ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = _GreyScale.grey0; // White (high emphasis)
  static const Color textSecondary =
      _GreyScale.grey400; // Light grey (low emphasis)

  static const Color error = _RedScale.scale500; // Same as danger
  static const Color neutral = _GreyScale.grey500; // Base grey

  // ── GLOWS (for shadows/effects) ───────────────────────────────────────────
  // Used in TextStyle shadows or BoxDecoration for glow effects
  static const Color accentGlow = Color(0x4D00BCD4); // accent @ 30%
  static const Color successGlow = Color(0x334CAF50); // success @ 20%
  static const Color dangerGlow = Color(0x33F44336); // danger @ 20%
}
