import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intermittent_fasting/app_colors.dart';
import 'package:intermittent_fasting/design_tokens_nudgr.dart';
import 'package:intermittent_fasting/utils/category_colors.dart';

// Verifies the Nudgr semantic token layer (AppColors / AppColorsLight /
// AppThemeExtension) maps onto the raw NudgrDark/NudgrLight palette per
// docs/design_system_nudgr_spec.md. The full ThemeData wiring in app_theme.dart
// is exercised at runtime (it builds without error in the app + web companion);
// this suite avoids building it so it stays offline-deterministic (no
// google_fonts network fetch).

/// Relative luminance per WCAG 2.1. Color channels are 0..1 doubles.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Nudgr tokens — dark semantic layer', () {
    test('surfaces map to NudgrDark ramp', () {
      expect(AppColors.page, NudgrDark.page);
      expect(AppColors.background, NudgrDark.screen);
      expect(AppColors.sheet, NudgrDark.sheet);
      expect(AppColors.surface, NudgrDark.card);
      expect(AppColors.surfaceVariant, NudgrDark.input);
      expect(AppColors.surfaceHigh, NudgrDark.track);
    });

    test('surface ramp is monotonically lighter (page → track)', () {
      final ramp = [
        NudgrDark.page,
        NudgrDark.screen,
        NudgrDark.card,
        NudgrDark.input,
        NudgrDark.track,
      ];
      for (var i = 1; i < ramp.length; i++) {
        expect(_luminance(ramp[i]), greaterThan(_luminance(ramp[i - 1])),
            reason: 'ramp[$i] must be lighter than ramp[${i - 1}]');
      }
    });

    test('accents + borders wired', () {
      expect(AppColors.primary, NudgrDark.fast);
      expect(AppColors.accent, NudgrDark.food);
      expect(AppColors.success, NudgrDark.move);
      expect(AppColors.gold, NudgrDark.gold);
      expect(AppColors.error, NudgrDark.danger);
      expect(AppColors.borderCard, NudgrDark.borderCard);
      expect(AppColors.borderInner, NudgrDark.borderInner);
    });

    test('extension exposes full domain set', () {
      const ext = AppThemeExtension.dark;
      expect(ext.fast, NudgrDark.fast);
      expect(ext.food, NudgrDark.food);
      expect(ext.move, NudgrDark.move);
      expect(ext.bills, NudgrDark.bills);
      expect(ext.treasury, NudgrDark.gold);
      expect(ext.weight, NudgrDark.weight);
      expect(ext.fastTrack, NudgrDark.fastTrack);
      expect(ext.foodTrack, NudgrDark.foodTrack);
      expect(ext.moveTrack, NudgrDark.moveTrack);
      expect(ext.textTertiary, NudgrDark.textTertiary);
      expect(ext.textMuted, NudgrDark.textMuted);
      expect(ext.textInactive, NudgrDark.textInactive);
    });

    test('legacy aliases re-point to new hues (backwards compat)', () {
      const ext = AppThemeExtension.dark;
      expect(ext.success, ext.move);
      expect(ext.gold, ext.treasury);
      expect(ext.orange, ext.bills);
      expect(ext.purple, ext.weight);
    });

    test('body text meets AA (4.5:1) on scaffold and cards', () {
      expect(_contrast(NudgrDark.textPrimary, NudgrDark.screen),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(NudgrDark.textPrimary, NudgrDark.card),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(NudgrDark.textSecondary, NudgrDark.card),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('Nudgr tokens — light semantic layer', () {
    test('surfaces map to NudgrLight ramp', () {
      expect(AppColorsLight.background, NudgrLight.screen);
      expect(AppColorsLight.surface, NudgrLight.card);
      expect(AppColorsLight.surfaceVariant, NudgrLight.input);
      expect(AppColorsLight.borderCard, NudgrLight.borderCard);
    });

    test('accents wired', () {
      expect(AppColorsLight.primary, NudgrLight.fast);
      expect(AppColorsLight.accent, NudgrLight.food);
      expect(AppThemeExtension.light.treasury, NudgrLight.gold);
      expect(AppThemeExtension.light.weight, NudgrLight.weight);
    });

    test('legacy aliases re-point to new hues', () {
      const ext = AppThemeExtension.light;
      expect(ext.success, ext.move);
      expect(ext.gold, ext.treasury);
      expect(ext.orange, ext.bills);
      expect(ext.purple, ext.weight);
    });

    test('body text meets AA on white screen and cards', () {
      expect(_contrast(NudgrLight.textPrimary, NudgrLight.screen),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(NudgrLight.textPrimary, NudgrLight.card),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(NudgrLight.textSecondary, NudgrLight.card),
          greaterThanOrEqualTo(4.5));
    });
  });

  group('Nudgr tokens — chart category palette', () {
    Color parse(String hex) =>
        Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

    test('palettes are 10 entries and anchor on domain hues', () {
      expect(kExpensePalette.length, 10);
      expect(kIncomePalette.length, 10);
      expect(parse(kExpensePalette.first), NudgrDark.danger);
      expect(parse(kIncomePalette.first), NudgrDark.move);
    });

    test('no entry trips the resolveSliceColor >0.65 luminance guard', () {
      for (final hex in [...kExpensePalette, ...kIncomePalette]) {
        expect(parse(hex).computeLuminance(), lessThanOrEqualTo(0.65),
            reason: '$hex would be wrongly substituted as legacy-white');
      }
    });

    test('entries within a palette are distinct', () {
      expect(kExpensePalette.toSet().length, kExpensePalette.length);
      expect(kIncomePalette.toSet().length, kIncomePalette.length);
    });
  });
}
