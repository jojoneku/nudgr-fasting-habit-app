import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lets scrollables (PageView, ListView, carousels, …) respond to mouse and
/// trackpad drags — not just touch/stylus — so swipe gestures work when the app
/// runs on web or desktop. Flutter's default [MaterialScrollBehavior] omits the
/// mouse from [dragDevices], which is why a PageView won't swipe with a cursor.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
