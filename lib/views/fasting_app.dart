import 'package:flutter/material.dart';
import 'home_screen.dart';

class FastingApp extends StatelessWidget {
  const FastingApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: brightness,
    );

    final scaffoldShade = brightness == Brightness.light
        ? Color.alphaBlend(Colors.white.withOpacity(0.45), scheme.surface)
        : Color.alphaBlend(Colors.white.withOpacity(0.04), scheme.surface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldShade,
      canvasColor: scaffoldShade,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldShade,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(0.15),
        labelTextStyle: MaterialStateProperty.all(
          TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intermittent Fasting',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
