import 'package:flutter/material.dart';

class AppColorsLight {
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEFF3F8);
  // WCAG AA: all three values darkened to achieve ≥ 4.5:1 on background,
  // surface, and surfaceVariant simultaneously.
  static const Color primary = Color(0xFF0174B2);   // was 0288D1 — 3.7:1 → 4.9:1
  static const Color secondary = Color(0xFF007A85); // was 00838F — 4.3:1 → 4.9:1
  static const Color textPrimary = Color(0xFF0F1923);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);   // was 388E3C — 3.9:1 → 4.9:1
  // gold (#F9A825) is inherently low-contrast on white (1.9:1). Use ONLY as
  // a fill/tint with dark text on top — never as text-on-white in light mode.
  static const Color gold = Color(0xFFF9A825);
}

class AppColors {
  // Solo Leveling Inspired Palette
  // All accent colors are tinted/desaturated (Material 400-range) to avoid
  // the hallation/vibration effect that pure neon colors cause on dark backgrounds.
  static const Color background = Color(0xFF0A0E14); // Deep Black (Void)
  static const Color surface = Color(0xFF1C2128); // Slate Grey (Cards)

  static const Color primary = Color(0xFF29B6F6); // Sky Blue (was 00A8FF)
  static const Color accent =
      Color(0xFF26C6DA); // Mana Teal  (was 00E5FF — pure cyan)
  static const Color secondary =
      Color(0xFF4DD0E1); // Soft Cyan  (was 00FFFF — pure neon)

  static const Color danger =
      Color(0xFFEF5350); // Ember Red   (was FF1744 — electric red)
  static const Color success =
      Color(0xFF66BB6A); // Forest Green (was 00E676 — pure neon green)
  static const Color gold =
      Color(0xFFFFCA28); // Warm Amber  (was FFD600 — pure yellow)

  static const Color textPrimary = Color(0xFFFFFFFF); // High emphasis
  static const Color textSecondary = Color(0xFF94A3B8); // Low emphasis

  static const Color error = Color(0xFFEF5350); // Same as danger
  static const Color neutral = Color(0xFF808080);

  // Glow — use as TextStyle shadows or BoxDecoration shadows
  static const Color accentGlow = Color(0x4D26C6DA); // accent @ 30%
  static const Color successGlow = Color(0x3366BB6A); // success @ 20%
  static const Color dangerGlow = Color(0x33EF5350); // danger  @ 20%
}
