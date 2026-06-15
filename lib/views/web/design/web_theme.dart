import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../utils/app_radii.dart';
import '../../app_theme.dart';

/// Web-only theme for the Treasury companion — re-skins the shared base
/// ([buildDarkTheme]/[buildLightTheme]) to the **Pondr** design system used by
/// the Claude Design "Treasury Dashboard" reference
/// (`docs/design/treasury-web-reference/colors_and_type.css`).
///
/// Kept separate from `app_theme.dart` so the mobile app's Solo-Leveling
/// identity is untouched: only [TreasuryWebApp] uses these builders. Token
/// values are transcribed verbatim from the generated `colors_and_type.css`.
class _Pondr {
  // ── Dark (default) ──
  static const dBg = Color(0xFF20212C); // surface.default  grey.900
  static const dCard = Color(0xFF2B2C37); // card.default     grey.800
  static const dHigh = Color(0xFF384050); // surface.high     grey.700
  static const dBorderSubtle = Color(0xFF384050); // border.subtle
  static const dBorder = Color(0xFF4C5669); // border.default  grey.600
  static const dFg1 = Color(0xFFF4F7FD); // foreground.primary
  static const dFg2 = Color(0xFF7E899E); // foreground.secondary
  static const dPrimary = Color(0xFF8AB2EE); // primary (blue.200)
  static const dPrimaryContainer = Color(0xFF003077); // blue.800
  static const dOnPrimary = Color(0xFF003077); // on-action
  static const dSuccess = Color(0xFF22C55E); // income / positive green
  static const dWarning = Color(0xFFF59E0B); // amber action
  static const dDanger = Color(0xFFEF9B9B); // danger text (dark)

  // ── Light ──
  static const lBg = Color(0xFFF4F7FD); // surface.default  grey.50
  static const lCard = Color(0xFFFFFFFF); // white cards on grey page
  static const lHigh = Color(0xFFEDF1F8); // card-on-card inset
  static const lHighest = Color(0xFFE6EEFB); // hover/elevated  blue.50
  static const lBorderSubtle = Color(0xFFDDE3EB); // border.subtle  grey.100
  static const lBorder = Color(0xFFBEC8D7); // border.default grey.200
  static const lFg1 = Color(0xFF20212C); // foreground.primary
  static const lFg2 = Color(0xFF636E84); // foreground.secondary
  static const lPrimary = Color(0xFF0057D9); // action blue (blue.500)
  static const lPrimaryContainer = Color(0xFFB0CBF3); // blue.100
  static const lSuccess = Color(0xFF22C55E);
  static const lWarning = Color(0xFFF59E0B);
  static const lDanger = Color(0xFFDC2626);
}

const _subThemes = FlexSubThemesData(
  defaultRadius: AppRadii.lg,
  inputDecoratorRadius: AppRadii.md,
  cardRadius: AppRadii.lg,
  cardElevation: 0,
  bottomSheetRadius: AppRadii.xl,
  dialogRadius: AppRadii.xxl,
  chipRadius: AppRadii.sm,
  snackBarRadius: AppRadii.md,
);

ThemeData buildWebDarkTheme() {
  final base = FlexThemeData.dark(
    colors: const FlexSchemeColor(
      primary: _Pondr.dPrimary,
      primaryContainer: _Pondr.dPrimaryContainer,
      secondary: _Pondr.dWarning,
      secondaryContainer: Color(0xFF875706),
      tertiary: _Pondr.dSuccess,
      tertiaryContainer: Color(0xFF136C34),
      appBarColor: _Pondr.dBg,
      error: _Pondr.dDanger,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: _subThemes,
  );
  return base.copyWith(
    scaffoldBackgroundColor: _Pondr.dBg,
    canvasColor: _Pondr.dBg,
    colorScheme: base.colorScheme.copyWith(
      primary: _Pondr.dPrimary,
      onPrimary: _Pondr.dOnPrimary,
      surface: _Pondr.dCard,
      surfaceContainerLowest: _Pondr.dBg,
      surfaceContainerLow: _Pondr.dCard,
      surfaceContainer: _Pondr.dCard,
      surfaceContainerHigh: _Pondr.dHigh,
      surfaceContainerHighest: _Pondr.dHigh,
      onSurface: _Pondr.dFg1,
      onSurfaceVariant: _Pondr.dFg2,
      outline: _Pondr.dBorder,
      outlineVariant: _Pondr.dBorderSubtle,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: _Pondr.dFg1, displayColor: _Pondr.dFg1),
    primaryTextTheme:
        GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme),
  );
}

ThemeData buildWebLightTheme() {
  final base = FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: _Pondr.lPrimary,
      primaryContainer: _Pondr.lPrimaryContainer,
      secondary: _Pondr.lWarning,
      secondaryContainer: Color(0xFFFCE1B3),
      tertiary: _Pondr.lSuccess,
      tertiaryContainer: Color(0xFFBAEDCD),
      appBarColor: _Pondr.lCard,
      error: _Pondr.lDanger,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: _subThemes,
  );
  return base.copyWith(
    scaffoldBackgroundColor: _Pondr.lBg,
    canvasColor: _Pondr.lBg,
    colorScheme: base.colorScheme.copyWith(
      primary: _Pondr.lPrimary,
      onPrimary: const Color(0xFFF4F7FD),
      surface: _Pondr.lCard,
      surfaceContainerLowest: _Pondr.lBg,
      surfaceContainerLow: _Pondr.lCard,
      surfaceContainer: _Pondr.lCard,
      surfaceContainerHigh: _Pondr.lHigh,
      surfaceContainerHighest: _Pondr.lHighest,
      onSurface: _Pondr.lFg1,
      onSurfaceVariant: _Pondr.lFg2,
      outline: _Pondr.lBorder,
      outlineVariant: _Pondr.lBorderSubtle,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: _Pondr.lFg1, displayColor: _Pondr.lFg1),
    primaryTextTheme:
        GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme),
  );
}
