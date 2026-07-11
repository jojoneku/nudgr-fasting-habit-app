import 'package:flutter/material.dart';
import 'design_tokens_nudgr.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC COLOR TOKENS — Nudgr design system (see docs/design_system_nudgr_spec.md)
// ─────────────────────────────────────────────────────────────────────────────
// Raw values live in design_tokens_nudgr.dart (NudgrDark / NudgrLight). These
// classes are the semantic layer app_theme.dart maps into the M3 ColorScheme.
// Widgets NEVER read AppColors/AppColorsLight directly — they read
// Theme.of(context) (colorScheme.*, textTheme.*) and context.appColors.

// ─────────────────────────────────────────────────────────────────────────────
// LIGHT MODE — derived palette (near-white, deeper accents for AA contrast)
// ─────────────────────────────────────────────────────────────────────────────
class AppColorsLight {
  // ── SURFACES (ascending elevation) ──────────────────────────────────────
  static const Color page = NudgrLight.page; // deepest well / scaffold shell
  static const Color background = NudgrLight.screen; // scaffold / screen base
  static const Color sheet = NudgrLight.sheet; // bottom sheets, modals
  static const Color shell = NudgrLight.shell; // tab bar chrome
  static const Color surface = NudgrLight.card; // cards, tiles, list items
  static const Color surfaceVariant = NudgrLight.input; // inputs, card-on-card
  static const Color surfaceHigh = NudgrLight.track; // tracks / highest

  // ── BORDERS ────────────────────────────────────────────────────────────
  static const Color borderCard = NudgrLight.borderCard;
  static const Color borderInner = NudgrLight.borderInner;

  // ── ACCENT COLORS ─────────────────────────────────────────────────────────
  static const Color primary = NudgrLight.fast; // Fast · Blue
  static const Color accent = NudgrLight.food; // Food · Teal
  static const Color secondary = NudgrLight.food;

  static const Color danger = NudgrLight.danger;
  static const Color success = NudgrLight.move;
  static const Color gold = NudgrLight.gold;

  // ── TEXT ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = NudgrLight.textPrimary;
  static const Color textSecondary = NudgrLight.textSecondary;

  static const Color error = NudgrLight.danger;
  static const Color neutral = NudgrLight.textTertiary;

  // ── GLOWS (for shadows/effects) ───────────────────────────────────────────
  static const Color accentGlow = Color(0x2D0AACBF); // accent @ ~18%
  static const Color successGlow = Color(0x2D2EA055); // success @ ~18%
  static const Color dangerGlow = Color(0x2DD84840); // danger @ ~18%
}

// ─────────────────────────────────────────────────────────────────────────────
// DARK MODE (Default) — Solo Leveling RPG aesthetic, premium near-black
// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  // ── SURFACES (ascending elevation) ──────────────────────────────────────
  static const Color page = NudgrDark.page; // #0A0A0B deepest well
  static const Color background = NudgrDark.screen; // #131315 scaffold / screen
  static const Color sheet = NudgrDark.sheet; // #171718 bottom sheets, modals
  static const Color shell = NudgrDark.shell; // #0E0E10 tab bar chrome
  static const Color surface = NudgrDark.card; // #1C1C20 cards, tiles
  static const Color surfaceVariant =
      NudgrDark.input; // #252628 inputs, card-on-card
  static const Color surfaceHigh = NudgrDark.track; // #26262A tracks / highest

  // ── BORDERS ────────────────────────────────────────────────────────────
  static const Color borderCard = NudgrDark.borderCard;
  static const Color borderInner = NudgrDark.borderInner;

  // ── ACCENT COLORS ─────────────────────────────────────────────────────────
  static const Color primary = NudgrDark.fast; // Fast · Blue
  static const Color accent = NudgrDark.food; // Food · Teal
  static const Color secondary = NudgrDark.food;

  static const Color danger = NudgrDark.danger;
  static const Color success = NudgrDark.move;
  static const Color gold = NudgrDark.gold;

  // ── TEXT ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = NudgrDark.textPrimary;
  static const Color textSecondary = NudgrDark.textSecondary;

  static const Color error = NudgrDark.danger;
  static const Color neutral = NudgrDark.textTertiary;

  // ── GLOWS (for shadows/effects) ───────────────────────────────────────────
  static const Color accentGlow = Color(0x4D26C6DA); // accent @ 30%
  static const Color successGlow = Color(0x3346BD6B); // success @ 20%
  static const Color dangerGlow = Color(0x33F6685E); // danger @ 20%
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME EXTENSION — domain-semantic tokens not covered by M3 ColorScheme
// ─────────────────────────────────────────────────────────────────────────────
// Domain colors: Fast/Food/Move/Bills/Treasury/Weight. Legacy aliases
// (success/gold/orange/purple) are retained and re-pointed to the new hues so
// existing call sites (context.appColors.*) keep working unchanged.
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    // Legacy aliases (kept for backwards compatibility)
    required this.success,
    required this.gold,
    required this.orange,
    required this.purple,
    // Domain accents
    required this.fast,
    required this.food,
    required this.move,
    required this.bills,
    required this.treasury,
    required this.weight,
    // Ring / bar track fills
    required this.fastTrack,
    required this.foodTrack,
    required this.moveTrack,
    // Extra text tiers
    required this.textTertiary,
    required this.textMuted,
    required this.textInactive,
    // Extra border
    required this.borderSheet,
  });

  // Legacy aliases → success == move, gold == treasury, orange == bills,
  // purple == weight.
  final Color success;
  final Color gold;
  final Color orange; // == bills (energy / heat / warning)
  final Color purple; // == weight (RPG advanced / ketosis)

  // Domain accents
  final Color fast; // Blue
  final Color food; // Teal
  final Color move; // Green
  final Color bills; // Orange
  final Color treasury; // Gold
  final Color weight; // Purple

  // Track fills (dim background behind ring arcs / progress bars)
  final Color fastTrack;
  final Color foodTrack;
  final Color moveTrack;

  // Text tiers beyond onSurface / onSurfaceVariant
  final Color textTertiary;
  final Color textMuted;
  final Color textInactive;

  final Color borderSheet;

  static const dark = AppThemeExtension(
    success: NudgrDark.move,
    gold: NudgrDark.gold,
    orange: NudgrDark.bills,
    purple: NudgrDark.weight,
    fast: NudgrDark.fast,
    food: NudgrDark.food,
    move: NudgrDark.move,
    bills: NudgrDark.bills,
    treasury: NudgrDark.gold,
    weight: NudgrDark.weight,
    fastTrack: NudgrDark.fastTrack,
    foodTrack: NudgrDark.foodTrack,
    moveTrack: NudgrDark.moveTrack,
    textTertiary: NudgrDark.textTertiary,
    textMuted: NudgrDark.textMuted,
    textInactive: NudgrDark.textInactive,
    borderSheet: NudgrDark.borderSheet,
  );

  static const light = AppThemeExtension(
    success: NudgrLight.move,
    gold: NudgrLight.gold,
    orange: NudgrLight.bills,
    purple: NudgrLight.weight,
    fast: NudgrLight.fast,
    food: NudgrLight.food,
    move: NudgrLight.move,
    bills: NudgrLight.bills,
    treasury: NudgrLight.gold,
    weight: NudgrLight.weight,
    fastTrack: NudgrLight.fastTrack,
    foodTrack: NudgrLight.foodTrack,
    moveTrack: NudgrLight.moveTrack,
    textTertiary: NudgrLight.textTertiary,
    textMuted: NudgrLight.textMuted,
    textInactive: NudgrLight.textInactive,
    borderSheet: NudgrLight.borderSheet,
  );

  @override
  AppThemeExtension copyWith({
    Color? success,
    Color? gold,
    Color? orange,
    Color? purple,
    Color? fast,
    Color? food,
    Color? move,
    Color? bills,
    Color? treasury,
    Color? weight,
    Color? fastTrack,
    Color? foodTrack,
    Color? moveTrack,
    Color? textTertiary,
    Color? textMuted,
    Color? textInactive,
    Color? borderSheet,
  }) =>
      AppThemeExtension(
        success: success ?? this.success,
        gold: gold ?? this.gold,
        orange: orange ?? this.orange,
        purple: purple ?? this.purple,
        fast: fast ?? this.fast,
        food: food ?? this.food,
        move: move ?? this.move,
        bills: bills ?? this.bills,
        treasury: treasury ?? this.treasury,
        weight: weight ?? this.weight,
        fastTrack: fastTrack ?? this.fastTrack,
        foodTrack: foodTrack ?? this.foodTrack,
        moveTrack: moveTrack ?? this.moveTrack,
        textTertiary: textTertiary ?? this.textTertiary,
        textMuted: textMuted ?? this.textMuted,
        textInactive: textInactive ?? this.textInactive,
        borderSheet: borderSheet ?? this.borderSheet,
      );

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      success: Color.lerp(success, other.success, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      fast: Color.lerp(fast, other.fast, t)!,
      food: Color.lerp(food, other.food, t)!,
      move: Color.lerp(move, other.move, t)!,
      bills: Color.lerp(bills, other.bills, t)!,
      treasury: Color.lerp(treasury, other.treasury, t)!,
      weight: Color.lerp(weight, other.weight, t)!,
      fastTrack: Color.lerp(fastTrack, other.fastTrack, t)!,
      foodTrack: Color.lerp(foodTrack, other.foodTrack, t)!,
      moveTrack: Color.lerp(moveTrack, other.moveTrack, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textInactive: Color.lerp(textInactive, other.textInactive, t)!,
      borderSheet: Color.lerp(borderSheet, other.borderSheet, t)!,
    );
  }
}

extension AppThemeExtensionContext on BuildContext {
  AppThemeExtension get appColors =>
      Theme.of(this).extension<AppThemeExtension>() ?? AppThemeExtension.dark;
}
