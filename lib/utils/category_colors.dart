import 'package:flutter/material.dart';

/// Curated 10-color palettes — muted/tinted for dark backgrounds.
/// Expense uses warm tones; income uses cool tones so they're always
/// visually distinct from each other at a glance.
const List<String> kExpensePalette = [
  '#EF9A9A', // soft red
  '#FFCC80', // warm amber
  '#80CBC4', // teal
  '#CE93D8', // lavender
  '#F48FB1', // rose
  '#FFE082', // golden
  '#9FA8DA', // periwinkle
  '#BCAAA4', // warm brown
  '#80DEEA', // cyan mist
  '#A5D6A7', // soft green
];

const List<String> kIncomePalette = [
  '#A5D6A7', // soft green
  '#80DEEA', // cyan mist
  '#80CBC4', // teal
  '#B3E5FC', // sky
  '#C5E1A5', // lime
  '#FFE082', // gold
  '#DCEDC8', // light green
  '#B2EBF2', // aqua
  '#9FA8DA', // periwinkle
  '#F0F4C3', // yellow-green
];

/// Returns a color hex string for a category at [index] within its type.
///
/// - Index 0–9: uses the curated palette for the best visual result.
/// - Index 10+: generates a unique hue by evenly distributing around the
///   HSL wheel (saturation 45%, lightness 68%) so colors never repeat and
///   always remain readable on dark backgrounds.
String categoryColorAt(int index, {required bool isExpense}) {
  final palette = isExpense ? kExpensePalette : kIncomePalette;

  if (index < palette.length) return palette[index];

  // Generate unique hue beyond the palette.
  // Offset by 15° so generated colors don't land on the same starting hue
  // as the palette entries.
  final hue = (index * 137.508) % 360; // golden angle — maximises spread
  final color = HSLColor.fromAHSL(
    1.0,
    hue,
    0.45, // 45% saturation — visible but not vibrating
    0.68, // 68% lightness — readable on #0A0E14 background
  ).toColor();

  return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}

/// Parses [hex] and returns the color. If the color is white / near-white
/// (luminance > 0.65) — the old default — substitutes a palette color
/// based on [index] so existing categories always render distinctly.
///
/// [brightness] defaults to [Brightness.dark] (the curated palettes are tuned
/// for dark backgrounds, so existing callers are unchanged). When
/// [Brightness.light] is passed, the resolved color is darkened/saturated so it
/// stays legible on light-mode white cards — the palette pastels (luminance
/// ≈0.7–0.9) are otherwise near-invisible there. Hue is preserved, so a
/// category keeps its recognisable color, just deeper. (Plan 052 T1)
Color resolveSliceColor(
  String hex,
  int index, {
  Brightness brightness = Brightness.dark,
}) {
  Color color;
  try {
    color = Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    if (color.computeLuminance() > 0.65) {
      color = _parseHex(kExpensePalette[index % kExpensePalette.length]);
    }
  } catch (_) {
    color = _parseHex(kExpensePalette[index % kExpensePalette.length]);
  }
  return brightness == Brightness.light ? _darkenForLight(color) : color;
}

/// Deepens a dark-tuned palette color for use on light backgrounds: caps
/// lightness and floors saturation while keeping the hue, yielding a vivid
/// readable variant instead of a washed-out pastel.
Color _darkenForLight(Color c) {
  final hsl = HSLColor.fromColor(c);
  final saturation = hsl.saturation < 0.45 ? 0.6 : hsl.saturation;
  return hsl
      .withLightness(hsl.lightness.clamp(0.0, 0.42))
      .withSaturation(saturation.clamp(0.0, 1.0))
      .toColor();
}

Color _parseHex(String hex) {
  try {
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}

/// i.e. the old default color that needs migration.
bool isDefaultWhite(String hex) {
  try {
    final color = Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    return color.computeLuminance() > 0.65;
  } catch (_) {
    return false;
  }
}
