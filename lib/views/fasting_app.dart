import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../presenters/settings_presenter.dart';
import '../services/local_storage_service.dart';
import '../utils/app_radii.dart';
import '../utils/app_text_styles.dart';
import 'home_screen.dart';

class FastingApp extends StatefulWidget {
  const FastingApp({super.key});

  @override
  State<FastingApp> createState() => _FastingAppState();
}

class _FastingAppState extends State<FastingApp> {
  late final LocalStorageService _storage;
  late final SettingsPresenter _settingsPresenter;

  @override
  void initState() {
    super.initState();
    _storage = LocalStorageService();
    _settingsPresenter = SettingsPresenter(_storage);
    _settingsPresenter.init();
  }

  @override
  void dispose() {
    _settingsPresenter.dispose();
    super.dispose();
  }

  ThemeData _darkTheme() {
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
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 12,
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
        appBarBackgroundSchemeColor: SchemeColor.surface,
        bottomNavigationBarMutedUnselectedIcon: true,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    ).copyWith(
      scaffoldBackgroundColor: AppColors.background,
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      textTheme: AppTextStyles.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      primaryTextTheme: AppTextStyles.textTheme.apply(
        bodyColor: AppColors.primary,
        displayColor: AppColors.primary,
      ),
    );
    return base;
  }

  ThemeData _lightTheme() {
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
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 4,
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
        appBarBackgroundSchemeColor: SchemeColor.surface,
        bottomNavigationBarMutedUnselectedIcon: true,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    ).copyWith(
      scaffoldBackgroundColor: AppColorsLight.background,
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      textTheme: AppTextStyles.textTheme.apply(
        bodyColor: AppColorsLight.textPrimary,
        displayColor: AppColorsLight.textPrimary,
      ),
      primaryTextTheme: AppTextStyles.textTheme.apply(
        bodyColor: AppColorsLight.primary,
        displayColor: AppColorsLight.primary,
      ),
    );
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settingsPresenter,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Nudgr',
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
        themeMode: _settingsPresenter.themeMode,
        home: const HomeScreen(),
      ),
    );
  }
}
