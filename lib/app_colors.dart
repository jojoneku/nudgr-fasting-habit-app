import 'package:flutter/material.dart';

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
