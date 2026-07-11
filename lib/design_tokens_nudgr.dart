import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NUDGR DESIGN TOKENS — raw palette (single source of truth)
// ─────────────────────────────────────────────────────────────────────────────
// Mirrors docs/design_system_nudgr_spec.md exactly. Dark is canonical; light is
// derived maintaining contrast. Consumed ONLY by app_colors.dart, which maps
// these into the semantic `AppColors` / `AppColorsLight` / `AppThemeExtension`
// tokens that widgets read via Theme.of(context) / context.appColors.
//
// Do not read these directly from widgets — use the semantic tokens.

/// Dark-mode canonical values.
abstract final class NudgrDark {
  // ── Surfaces (ascending elevation) ──────────────────────────────────────
  static const Color page = Color(0xFF0A0A0B); // scaffold / deepest well
  static const Color shell = Color(0xFF0E0E10); // tab bar, persistent chrome
  static const Color screen = Color(0xFF131315); // primary screen background
  static const Color elevated = Color(0xFF141414); // slightly raised surface
  static const Color sheet = Color(0xFF171718); // bottom sheets, modals
  static const Color card = Color(0xFF1C1C20); // cards, tiles, list items
  static const Color input = Color(0xFF252628); // inputs, card-on-card
  static const Color track = Color(0xFF26262A); // progress/chart tracks

  // ── Borders ──────────────────────────────────────────────────────────────
  static const Color borderInner = Color(0xFF1E1E22); // row dividers
  static const Color borderCard = Color(0xFF2A2A2E); // card border
  static const Color borderSheet = Color(0xFF2E2F31); // sheet top border

  // ── Text (5 tiers) ─────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF7F7F8);
  static const Color textSecondary = Color(0xFFC9CDD3);
  static const Color textTertiary = Color(0xFF9A9FA8);
  static const Color textMuted = Color(0xFF83878F);
  static const Color textInactive = Color(0xFF6A6E76);

  // ── Domain accents (primary / light / track) ───────────────────────────────
  static const Color fast = Color(0xFF2E90FA);
  static const Color fastLight = Color(0xFF5BAAF5);
  static const Color fastTrack = Color(0xFF1A2535);

  static const Color food = Color(0xFF26C6DA);
  static const Color foodTrack = Color(0xFF1A2826);

  static const Color move = Color(0xFF46BD6B);
  static const Color moveLight = Color(0xFF6FCB8A);
  static const Color moveTrack = Color(0xFF152218);

  static const Color danger = Color(0xFFF6685E);
  static const Color dangerLight = Color(0xFFFF8A80);

  static const Color bills = Color(0xFFFF8A4C);
  static const Color billsLight = Color(0xFFFFB37A);

  static const Color gold = Color(0xFFFFCA28);
  static const Color weight = Color(0xFF926AFA);
}

/// Light-mode derived values (deeper accents for AA contrast on white).
abstract final class NudgrLight {
  // ── Surfaces ────────────────────────────────────────────────────────────
  static const Color page = Color(0xFFF0F0F5);
  static const Color shell = Color(0xFFE8E8EF);
  static const Color screen = Color(0xFFFFFFFF);
  static const Color elevated = Color(0xFFFAFAFA);
  static const Color sheet = Color(0xFFF5F5FA);
  static const Color card = Color(0xFFF0F0F6);
  static const Color input = Color(0xFFE4E4EA);
  static const Color track = Color(0xFFE0E0E6);

  // ── Borders ──────────────────────────────────────────────────────────────
  static const Color borderInner = Color(0xFFE8E8EF);
  static const Color borderCard = Color(0xFFDCDCE3);
  static const Color borderSheet = Color(0xFFD4D4DC);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1A1E);
  static const Color textSecondary = Color(0xFF4A4E58);
  static const Color textTertiary = Color(0xFF72767F);
  static const Color textMuted = Color(0xFF8C9097);
  static const Color textInactive = Color(0xFFB2B6BE);

  // ── Domain accents ─────────────────────────────────────────────────────────
  static const Color fast = Color(0xFF2E90FA); // same hue, still AA on white
  static const Color fastLight = Color(0xFF1860C8); // deep for light
  static const Color fastTrack = Color(0xFFD0E5FF);

  static const Color food = Color(0xFF0AACBF);
  static const Color foodTrack = Color(0xFFC8EEF4);

  static const Color move = Color(0xFF2EA055);
  static const Color moveLight = Color(0xFF1A7A3A);
  static const Color moveTrack = Color(0xFFC8EDD6);

  static const Color danger = Color(0xFFD84840);
  static const Color dangerLight = Color(0xFFB83030);

  static const Color bills = Color(0xFFD06010);
  static const Color billsLight = Color(0xFFA85020);

  static const Color gold = Color(0xFFC89000);
  static const Color weight = Color(0xFF6840D8);
}

/// Account brand colors — static, identical in both modes.
abstract final class AppAccountColors {
  static const Color bpi = Color(0xFF9B2C2C);
  static const Color gcash = Color(0xFF1565C0);
  static const Color maya = Color(0xFF1B7A4B);
  static const Color maribank = Color(0xFF2A2566);
}
