import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Rendering state for a single Hub hero ring.
enum HubRingState {
  /// Source hasn't started — track only + glyph, no progress arc.
  idle,

  /// Progress toward a goal.
  active,

  /// Over the goal — danger color, full arc, "over" amount in the center.
  over,
}

/// Pure, presentation-ready description of one hero ring. Built by the
/// [HubRings] factories from raw presenter values so the hero widget's
/// `build()` stays free of calculations/conditionals (System Rule 1).
@immutable
class HubRingData {
  const HubRingData({
    required this.value,
    required this.state,
    required this.caption,
    required this.glyph,
    this.centerValue,
    this.centerLabel,
  });

  /// Arc fill, already clamped to 0..1.
  final double value;
  final HubRingState state;

  /// Caption shown beneath the ring (e.g. `73%`, `Fast`, `Over goal`).
  final String caption;

  /// Idle-state glyph shown in the center when [state] is [HubRingState.idle].
  final IconData glyph;

  /// Primary center text when active/over (e.g. `11:41`, `678`, `+312`).
  final String? centerValue;

  /// Small center label under [centerValue] (e.g. `LEFT`, `OVER`, `STEPS`).
  final String? centerLabel;

  bool get isIdle => state == HubRingState.idle;
  bool get isOver => state == HubRingState.over;
}

/// Pure builders that turn raw presenter values into [HubRingData]. No state,
/// no widget dependencies beyond [IconData].
class HubRings {
  const HubRings._();

  static final NumberFormat _grouped = NumberFormat('#,###');

  /// Compact `H:MM` (or `HH:MM`) for a positive duration in seconds.
  static String _hm(int seconds) {
    final abs = seconds.abs();
    final h = abs ~/ 3600;
    final m = (abs % 3600) ~/ 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  static String _pct(double v) => '${(v.clamp(0.0, 1.0) * 100).round()}%';

  /// Fast ring — countdown to the fasting goal.
  static HubRingData fast({
    required bool isFasting,
    required int elapsedSeconds,
    required int targetSeconds,
    required bool isOvertime,
  }) {
    if (!isFasting) {
      return const HubRingData(
        value: 0,
        state: HubRingState.idle,
        caption: 'Fast',
        glyph: Icons.timer_outlined,
      );
    }
    if (isOvertime) {
      return const HubRingData(
        value: 1,
        state: HubRingState.active,
        caption: 'Goal reached',
        centerValue: 'Done',
        centerLabel: 'FAST',
        glyph: Icons.timer_outlined,
      );
    }
    final progress = targetSeconds <= 0 ? 0.0 : elapsedSeconds / targetSeconds;
    final remaining = (targetSeconds - elapsedSeconds).clamp(0, targetSeconds);
    return HubRingData(
      value: progress.clamp(0.0, 1.0),
      state: HubRingState.active,
      caption: _pct(progress),
      centerValue: _hm(remaining),
      centerLabel: 'LEFT',
      glyph: Icons.timer_outlined,
    );
  }

  /// Food ring — calories against the effective goal; flips to [over] when
  /// consumed exceeds the goal.
  static HubRingData food({
    required int calories,
    required int goal,
  }) {
    if (calories <= 0) {
      return const HubRingData(
        value: 0,
        state: HubRingState.idle,
        caption: 'Food',
        glyph: Icons.restaurant,
      );
    }
    final remaining = goal - calories;
    if (remaining < 0) {
      return HubRingData(
        value: 1,
        state: HubRingState.over,
        caption: 'Over goal',
        centerValue: '+${_grouped.format(-remaining)}',
        centerLabel: 'OVER',
        glyph: Icons.restaurant,
      );
    }
    final progress = goal <= 0 ? 0.0 : calories / goal;
    return HubRingData(
      value: progress.clamp(0.0, 1.0),
      state: HubRingState.active,
      caption: '${_pct(progress)} eaten',
      centerValue: _grouped.format(remaining),
      centerLabel: 'LEFT',
      glyph: Icons.restaurant,
    );
  }

  /// Move ring — steps against the step goal.
  static HubRingData move({
    required int steps,
    required int goal,
  }) {
    if (steps <= 0) {
      return const HubRingData(
        value: 0,
        state: HubRingState.idle,
        caption: 'Move',
        glyph: Icons.directions_run,
      );
    }
    final progress = goal <= 0 ? 0.0 : steps / goal;
    return HubRingData(
      value: progress.clamp(0.0, 1.0),
      state: HubRingState.active,
      caption: _pct(progress),
      centerValue: _grouped.format(steps),
      centerLabel: 'STEPS',
      glyph: Icons.directions_run,
    );
  }
}
