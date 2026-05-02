import 'package:flutter/animation.dart';

abstract final class AppMotion {
  // Durations
  static const Duration micro = Duration(milliseconds: 150);
  static const Duration appear = Duration(milliseconds: 200);
  static const Duration modal = Duration(milliseconds: 300);
  static const Duration page = Duration(milliseconds: 250);

  // Standard curves
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve decelerate = Curves.decelerate;

  /// HIG-feel spring — use on entrances (sheets, dialogs, overlays).
  static const Curve spring = Cubic(0.32, 0.72, 0, 1);
}
