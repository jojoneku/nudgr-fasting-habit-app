import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app_colors.dart';
import '../../../design_tokens_nudgr.dart';
import '../../../utils/app_radii.dart';

/// Web-only theme for the Treasury companion. Unified with the mobile **Nudgr**
/// design system (docs/design_system_nudgr_spec.md) so desktop and mobile share
/// one identity — near-black dark surfaces, derived light palette, and the
/// domain-semantic accents. Only [TreasuryWebApp] uses these builders.
///
/// Every value is drawn from the Nudgr tokens ([NudgrDark]/[NudgrLight]); the
/// web keeps a desktop-tuned surface arrangement (grey page / white cards in
/// light mode) and injects [AppThemeExtension] so web charts resolve the domain
/// colors per mode, exactly like the mobile app.
class _NudgrWeb {
  // ── Dark ──
  static const dScaffold = NudgrDark.screen; // #131315 page
  static const dCard = NudgrDark.card; // #1C1C20 cards
  static const dLow = NudgrDark.page; // #0A0A0B deepest well
  static const dHigh = NudgrDark.input; // #252628 card-on-card / inputs
  static const dHighest = NudgrDark.track; // #26262A
  static const dBorder = NudgrDark.borderCard; // #2A2A2E
  static const dBorderSubtle = NudgrDark.borderInner; // #1E1E22
  static const dFg1 = NudgrDark.textPrimary; // #F7F7F8
  static const dFg2 = NudgrDark.textSecondary; // #C9CDD3
  static const dPrimary = NudgrDark.fast; // #2E90FA
  static const dOnPrimary = Color(0xFFFFFFFF);
  static const dPrimaryContainer = Color(0xFF10355C); // deep blue
  static const dSuccess = NudgrDark.move; // #46BD6B
  static const dSuccessContainer = Color(0xFF163A24);
  static const dWarning = NudgrDark.bills; // #FF8A4C
  static const dWarningContainer = Color(0xFF4A2F1C);
  static const dDanger = NudgrDark.danger; // #F6685E

  // ── Light (desktop: grey page + white cards) ──
  static const lScaffold = NudgrLight.page; // #F0F0F5 grey page
  static const lCard = NudgrLight.screen; // #FFFFFF white cards
  static const lInset = NudgrLight.card; // #F0F0F6 card-on-card
  static const lHigh = NudgrLight.input; // #E4E4EA
  static const lHighest = NudgrLight.track; // #E0E0E6
  static const lBorder = NudgrLight.borderCard; // #DCDCE3
  static const lBorderSubtle = NudgrLight.borderInner; // #E8E8EF
  static const lFg1 = NudgrLight.textPrimary; // #1A1A1E
  static const lFg2 = NudgrLight.textSecondary; // #4A4E58
  static const lPrimary = NudgrLight.fastLight; // #1860C8 deep for AA on white
  static const lOnPrimary = Color(0xFFFFFFFF);
  static const lPrimaryContainer = NudgrLight.fastTrack; // #D0E5FF
  static const lSuccess = NudgrLight.move; // #2EA055
  static const lSuccessContainer = NudgrLight.moveTrack; // #C8EDD6
  static const lWarning = NudgrLight.bills; // #D06010
  static const lWarningContainer = Color(0xFFFFE7D3);
  static const lDanger = NudgrLight.danger; // #D84840
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
      primary: _NudgrWeb.dPrimary,
      primaryContainer: _NudgrWeb.dPrimaryContainer,
      secondary: _NudgrWeb.dWarning,
      secondaryContainer: _NudgrWeb.dWarningContainer,
      tertiary: _NudgrWeb.dSuccess,
      tertiaryContainer: _NudgrWeb.dSuccessContainer,
      appBarColor: _NudgrWeb.dScaffold,
      error: _NudgrWeb.dDanger,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: _subThemes,
  );
  return base.copyWith(
    scaffoldBackgroundColor: _NudgrWeb.dScaffold,
    canvasColor: _NudgrWeb.dScaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: _NudgrWeb.dPrimary,
      onPrimary: _NudgrWeb.dOnPrimary,
      surface: _NudgrWeb.dCard,
      surfaceContainerLowest: _NudgrWeb.dLow,
      surfaceContainerLow: _NudgrWeb.dCard,
      surfaceContainer: _NudgrWeb.dCard,
      surfaceContainerHigh: _NudgrWeb.dHigh,
      surfaceContainerHighest: _NudgrWeb.dHighest,
      onSurface: _NudgrWeb.dFg1,
      onSurfaceVariant: _NudgrWeb.dFg2,
      outline: _NudgrWeb.dBorder,
      outlineVariant: _NudgrWeb.dBorderSubtle,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: _NudgrWeb.dFg1, displayColor: _NudgrWeb.dFg1),
    primaryTextTheme:
        GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme),
    extensions: const [AppThemeExtension.dark],
  );
}

ThemeData buildWebLightTheme() {
  final base = FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: _NudgrWeb.lPrimary,
      primaryContainer: _NudgrWeb.lPrimaryContainer,
      secondary: _NudgrWeb.lWarning,
      secondaryContainer: _NudgrWeb.lWarningContainer,
      tertiary: _NudgrWeb.lSuccess,
      tertiaryContainer: _NudgrWeb.lSuccessContainer,
      appBarColor: _NudgrWeb.lCard,
      error: _NudgrWeb.lDanger,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: _subThemes,
  );
  return base.copyWith(
    scaffoldBackgroundColor: _NudgrWeb.lScaffold,
    canvasColor: _NudgrWeb.lScaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: _NudgrWeb.lPrimary,
      onPrimary: _NudgrWeb.lOnPrimary,
      surface: _NudgrWeb.lCard,
      surfaceContainerLowest: _NudgrWeb.lCard,
      surfaceContainerLow: _NudgrWeb.lCard,
      surfaceContainer: _NudgrWeb.lInset,
      surfaceContainerHigh: _NudgrWeb.lHigh,
      surfaceContainerHighest: _NudgrWeb.lHighest,
      onSurface: _NudgrWeb.lFg1,
      onSurfaceVariant: _NudgrWeb.lFg2,
      outline: _NudgrWeb.lBorder,
      outlineVariant: _NudgrWeb.lBorderSubtle,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: _NudgrWeb.lFg1, displayColor: _NudgrWeb.lFg1),
    primaryTextTheme:
        GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme),
    extensions: const [AppThemeExtension.light],
  );
}
