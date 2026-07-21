import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../utils/app_radii.dart';
import '../utils/app_text_styles.dart';

/// Pure theme builders shared by the mobile app ([FastingApp]) and the
/// Treasury web companion ([TreasuryWebApp]). Extracted from `fasting_app.dart`
/// (Plan 042) so both entrypoints render the exact same dark/light identity
/// with zero duplication. No state, no side effects — just `ThemeData`.
ThemeData buildDarkTheme() {
  final base = FlexThemeData.dark(
    colors: const FlexSchemeColor(
      primary: AppColors.primary,
      primaryContainer: Color(0xFF003547),
      secondary: AppColors.secondary,
      secondaryContainer: Color(0xFF003033),
      tertiary: AppColors.accent,
      tertiaryContainer: Color(0xFF003033),
      appBarColor: AppColors.background,
      error: AppColors.error,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: const FlexSubThemesData(
      defaultRadius: AppRadii.lg,
      inputDecoratorRadius: AppRadii.md,
      cardRadius: AppRadii.lg,
      cardElevation: 0,
      bottomSheetRadius: AppRadii.xl,
      dialogRadius: AppRadii.xxl,
      chipRadius: AppRadii.sm,
      snackBarRadius: AppRadii.md,
      bottomNavigationBarMutedUnselectedIcon: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      },
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.surface,
      surfaceContainerLowest: AppColors.page,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceVariant,
      surfaceContainerHigh: AppColors.surfaceVariant,
      surfaceContainerHighest: AppColors.surfaceHigh,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderCard,
      outlineVariant: AppColors.borderInner,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.primary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primary.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
            fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary);
        }
        return const IconThemeData(color: AppColors.textSecondary);
      }),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: AppColors.sheet,
      modalBackgroundColor: AppColors.sheet,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // Chips (category / reminder-day / filter pills). Flex's default selected
    // fill lands on the near-black secondaryContainer; override with a legible
    // blue tint and a comfortable height (~44px, meeting the touch target) so
    // pills aren't dark or dwarfed by the 48px field boxes beside them.
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceVariant,
      selectedColor: AppColors.primary.withValues(alpha: 0.20),
      disabledColor: AppColors.surfaceVariant,
      showCheckmark: false,
      side: const BorderSide(color: AppColors.borderInner),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
      labelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    ),
    textTheme: AppTextStyles.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    primaryTextTheme: AppTextStyles.textTheme.apply(
      bodyColor: AppColors.primary,
      displayColor: AppColors.primary,
    ),
    extensions: const [AppThemeExtension.dark],
  );
}

ThemeData buildLightTheme() {
  final base = FlexThemeData.light(
    colors: const FlexSchemeColor(
      primary: AppColorsLight.primary,
      primaryContainer: Color(0xFFB3E5FC),
      secondary: AppColorsLight.secondary,
      secondaryContainer: Color(0xFFB2EBF2),
      tertiary: Color(0xFF0097A7),
      tertiaryContainer: Color(0xFFB2EBF2),
      appBarColor: AppColorsLight.surface,
      error: AppColorsLight.error,
    ),
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.level,
    blendLevel: 0,
    appBarStyle: FlexAppBarStyle.surface,
    appBarElevation: 0,
    subThemesData: const FlexSubThemesData(
      defaultRadius: AppRadii.lg,
      inputDecoratorRadius: AppRadii.md,
      cardRadius: AppRadii.lg,
      cardElevation: 0,
      bottomSheetRadius: AppRadii.xl,
      dialogRadius: AppRadii.xxl,
      chipRadius: AppRadii.sm,
      snackBarRadius: AppRadii.md,
      bottomNavigationBarMutedUnselectedIcon: true,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
      },
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColorsLight.background,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColorsLight.surface,
      surfaceContainerLowest: AppColorsLight.background,
      surfaceContainerLow: AppColorsLight.surface,
      surfaceContainer: AppColorsLight.surfaceVariant,
      surfaceContainerHigh: AppColorsLight.surfaceVariant,
      surfaceContainerHighest: AppColorsLight.surfaceHigh,
      onSurface: AppColorsLight.textPrimary,
      onSurfaceVariant: AppColorsLight.textSecondary,
      outline: AppColorsLight.borderCard,
      outlineVariant: AppColorsLight.borderInner,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColorsLight.surface,
      foregroundColor: AppColorsLight.primary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColorsLight.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColorsLight.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
            fontWeight: FontWeight.w600, color: AppColorsLight.textSecondary),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColorsLight.primary);
        }
        return const IconThemeData(color: AppColorsLight.textSecondary);
      }),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: AppColorsLight.sheet,
      modalBackgroundColor: AppColorsLight.sheet,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    // See dark theme: keep chip pills legible (blue tint, not a dark fill) and
    // tall enough to sit proportionately beside the field boxes.
    chipTheme: ChipThemeData(
      backgroundColor: AppColorsLight.surfaceVariant,
      selectedColor: AppColorsLight.primary.withValues(alpha: 0.16),
      disabledColor: AppColorsLight.surfaceVariant,
      showCheckmark: false,
      side: const BorderSide(color: AppColorsLight.borderInner),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.smBorder),
      labelStyle: const TextStyle(
        color: AppColorsLight.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: AppColorsLight.primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    ),
    textTheme: AppTextStyles.textTheme.apply(
      bodyColor: AppColorsLight.textPrimary,
      displayColor: AppColorsLight.textPrimary,
    ),
    primaryTextTheme: AppTextStyles.textTheme.apply(
      bodyColor: AppColorsLight.primary,
      displayColor: AppColorsLight.primary,
    ),
    extensions: const [AppThemeExtension.light],
  );
}
