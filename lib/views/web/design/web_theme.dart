import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app_colors.dart';
import '../../../design_tokens_nudgr.dart';
import '../../../utils/app_radii.dart';

/// App-level theme mode for the web companion. Lifted out of the widget tree so
/// the shell's topbar toggle and the login page's toggle can flip light/dark
/// without prop-threading through the stateful composition root. Defaults to
/// the dark Solo-Leveling identity.
final ValueNotifier<ThemeMode> webThemeMode = ValueNotifier(ThemeMode.dark);

/// Web-only theme for the Treasury companion. Unified with the mobile **Nudgr**
/// design system (docs/design_system_nudgr_spec.md) so desktop and mobile share
/// one identity — near-black dark surfaces, derived light palette, and the
/// domain-semantic accents. Only [TreasuryWebApp] uses these builders.
///
/// Every value is drawn from the Nudgr tokens ([NudgrDark]/[NudgrLight]); the
/// web keeps a desktop-tuned surface arrangement (grey page / white cards in
/// light mode) and injects [AppThemeExtension] so web charts resolve the domain
/// colors per mode, exactly like the mobile app.
///
/// `colorScheme.secondary` is the food/teal accent, the same slot mobile uses.
/// It used to carry the warning orange, which made every selected chip and
/// secondary-tinted control brown; the warning tone now lives only on
/// `context.appColors.bills` (alias `orange`), which is where the web widgets
/// read it from (Plan 063, Phase 0).
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
  static const dSecondary = NudgrDark.food; // #26C6DA teal, as on mobile
  static const dSecondaryContainer = Color(0xFF003033); // mobile value
  static const dSuccess = NudgrDark.move; // #46BD6B
  static const dSuccessContainer = Color(0xFF163A24);
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
  static const lSecondary = NudgrLight.food; // #0AACBF teal, as on mobile
  static const lSecondaryContainer = Color(0xFFB2EBF2); // mobile value
  static const lSuccess = NudgrLight.move; // #2EA055
  static const lSuccessContainer = NudgrLight.moveTrack; // #C8EDD6
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

/// Dialog corner radius shared by every web dialog (the design canvas uses 24).
const double kWebDialogRadius = 24;

/// Minimum height of a web button row — desktop pointer target, not the 44 px
/// mobile thumb target.
const double kWebButtonMinHeight = 40;

// ── Component sub-themes shared by both modes ───────────────────────────────
// Mobile defines chip / snackBar / bottomSheet / navigationBar themes in
// `app_theme.dart`; the web mirrors the ones a desktop page uses (chips,
// snack bars, buttons, dialogs). Values are taken from the color scheme so the
// same builder serves dark and light.

/// Chips (filter pills, reminder-day and duration choices). Flex's default
/// selected fill is the dark secondaryContainer; mobile overrides it with a
/// legible primary tint and a comfortable height, and the web does the same.
ChipThemeData _chipTheme(ColorScheme cs, {required bool dark}) => ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.primary.withValues(alpha: dark ? 0.20 : 0.16),
      disabledColor: cs.surfaceContainerHigh,
      showCheckmark: false,
      side: BorderSide(color: cs.outlineVariant),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
      labelStyle: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: cs.primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );

const SnackBarThemeData _snackBarTheme = SnackBarThemeData(
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: AppRadii.mdBorder),
);

const RoundedRectangleBorder _buttonShape =
    RoundedRectangleBorder(borderRadius: AppRadii.mdBorder);
const Size _buttonMinSize = Size(0, kWebButtonMinHeight);
const EdgeInsets _buttonPadding = EdgeInsets.symmetric(horizontal: 16);

FilledButtonThemeData _filledButtonTheme() => FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: _buttonMinSize,
        padding: _buttonPadding,
        shape: _buttonShape,
      ),
    );

OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
    OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: _buttonMinSize,
        padding: _buttonPadding,
        shape: _buttonShape,
        side: BorderSide(color: cs.outline),
      ),
    );

TextButtonThemeData _textButtonTheme() => TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: _buttonMinSize,
        padding: _buttonPadding,
        shape: _buttonShape,
      ),
    );

/// Dialogs sit on the card token with no M3 surface tint, radius 24.
DialogThemeData _dialogTheme(Color card) => DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kWebDialogRadius),
      ),
    );

ThemeData buildWebDarkTheme() {
  final base = FlexThemeData.dark(
    colors: const FlexSchemeColor(
      primary: _NudgrWeb.dPrimary,
      primaryContainer: _NudgrWeb.dPrimaryContainer,
      secondary: _NudgrWeb.dSecondary,
      secondaryContainer: _NudgrWeb.dSecondaryContainer,
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
  final cs = base.colorScheme.copyWith(
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
  );
  return base.copyWith(
    scaffoldBackgroundColor: _NudgrWeb.dScaffold,
    canvasColor: _NudgrWeb.dScaffold,
    colorScheme: cs,
    chipTheme: _chipTheme(cs, dark: true),
    snackBarTheme: _snackBarTheme,
    filledButtonTheme: _filledButtonTheme(),
    outlinedButtonTheme: _outlinedButtonTheme(cs),
    textButtonTheme: _textButtonTheme(),
    dialogTheme: _dialogTheme(_NudgrWeb.dCard),
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
      secondary: _NudgrWeb.lSecondary,
      secondaryContainer: _NudgrWeb.lSecondaryContainer,
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
  final cs = base.colorScheme.copyWith(
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
  );
  return base.copyWith(
    scaffoldBackgroundColor: _NudgrWeb.lScaffold,
    canvasColor: _NudgrWeb.lScaffold,
    colorScheme: cs,
    chipTheme: _chipTheme(cs, dark: false),
    snackBarTheme: _snackBarTheme,
    filledButtonTheme: _filledButtonTheme(),
    outlinedButtonTheme: _outlinedButtonTheme(cs),
    textButtonTheme: _textButtonTheme(),
    dialogTheme: _dialogTheme(_NudgrWeb.lCard),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: _NudgrWeb.lFg1, displayColor: _NudgrWeb.lFg1),
    primaryTextTheme:
        GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme),
    extensions: const [AppThemeExtension.light],
  );
}
