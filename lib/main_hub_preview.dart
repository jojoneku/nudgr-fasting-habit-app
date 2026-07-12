// Dev-only visual harness for the Hub redesign — renders the REAL new painter
// widgets (full-circle AppRingProgress + MacroSplitRing) driven by the REAL
// HubRings data helpers, across states, in dark + light. Not a shipping entry
// point. The composed Hub (with live presenters) is covered by widget tests;
// this harness exists to eyeball the new custom-paint rendering + theming.
// Run: flutter run -t lib/main_hub_preview.dart -d web-server --web-port 8092
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'utils/hub_ring_data.dart';
import 'views/app_theme.dart';
import 'views/widgets/hub/macro_split_ring.dart';
import 'views/widgets/system/indicators/app_ring_progress.dart';

void main() => runApp(const _PreviewApp());

enum _Scene { active, idle, overGoal, nonFaster }

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _S();
}

class _S extends State<_PreviewApp> {
  ThemeMode _mode = ThemeMode.dark;
  _Scene _scene = _Scene.active;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in _Scene.values)
                      ChoiceChip(
                        label: Text(s.name),
                        selected: _scene == s,
                        onSelected: (_) => setState(() => _scene = s),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.brightness_6, size: 16),
                      label: Text(_mode == ThemeMode.dark ? 'dark' : 'light'),
                      onPressed: () => setState(() => _mode =
                          _mode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: Center(child: _Hero(scene: _scene))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors HubRingsHero's slot layout using the real ring widgets + data.
class _Hero extends StatelessWidget {
  final _Scene scene;
  const _Hero({required this.scene});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final cs = Theme.of(context).colorScheme;

    final fast = switch (scene) {
      _Scene.active => HubRings.fast(
          isFasting: true,
          elapsedSeconds: 8 * 3600 + 19 * 60,
          targetSeconds: 16 * 3600,
          isOvertime: false),
      _ => HubRings.fast(
          isFasting: false,
          elapsedSeconds: 0,
          targetSeconds: 57600,
          isOvertime: false),
    };

    final food = switch (scene) {
      _Scene.active => HubRings.food(calories: 1322, goal: 2000),
      _Scene.overGoal => HubRings.food(calories: 2312, goal: 2000),
      _ => HubRings.food(calories: 0, goal: 2000),
    };

    final move = scene == _Scene.active
        ? HubRings.move(steps: 7840, goal: 10000)
        : HubRings.move(steps: 0, goal: 10000);

    final slot1 = scene == _Scene.nonFaster
        ? MacroSplitRing(
            protein: 128,
            carbs: 210,
            fat: 62,
            proteinColor: cs.primary,
            carbsColor: c.gold,
            fatColor: cs.error,
            trackColor: cs.surfaceContainerHighest,
          )
        : _ring(context, fast, c.fast, c.fastTrack);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        slot1,
        _ring(context, food, food.isOver ? cs.error : c.food,
            food.isOver ? cs.error.withValues(alpha: 0.16) : c.foodTrack),
        _ring(context, move, c.move, c.moveTrack),
      ],
    );
  }

  Widget _ring(BuildContext context, HubRingData data, Color arc, Color track) {
    final theme = Theme.of(context);
    final Widget center = data.isIdle
        ? Icon(data.glyph, size: 24, color: arc.withValues(alpha: 0.55))
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.centerValue ?? '',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1)),
              if (data.centerLabel != null)
                Text(data.centerLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        letterSpacing: 0.5)),
            ],
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppRingProgress(
          value: data.value,
          size: 88,
          strokeWidth: 8,
          gapFraction: 0,
          primaryColor: arc,
          trackColor: track,
          center: center,
        ),
        const SizedBox(height: 6),
        Text(data.caption,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
