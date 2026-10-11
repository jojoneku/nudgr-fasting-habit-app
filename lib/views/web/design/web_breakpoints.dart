import 'package:flutter/widgets.dart';

/// Layout constants for the Treasury web companion (Plan 050).
///
/// The single source of truth for "are we on desktop web?" — the shell switches
/// to the sidebar layout at [rail], and page content is constrained to [content]
/// so a 4K monitor doesn't stretch tables to unreadable widths.
class WebBreakpoints {
  WebBreakpoints._();

  /// At/above this width the desktop sidebar shell renders; below it, the
  /// existing mobile views are used (free mobile-web parity).
  static const double rail = 840;

  /// Max content width for a page body — keeps line lengths and tables sane.
  static const double content = 1200;

  /// Max content width for the v2 shell (Plan 063). Pages fill the window
  /// beside the nav (and the Nudgy rail) up to this, then centre — so a
  /// laptop uses every pixel and a 4K monitor still keeps tables readable.
  static const double contentV2 = 1600;

  /// At/above this window width the v2 shell shows a page's right rail
  /// (Nudgy on the Dashboard) as a fixed column beside the content; below it
  /// the rail folds into the slide-over dock so the page keeps its width.
  static const double rightRail = 1280;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= rail;
}

/// Denser desktop spacing scale (the mobile `AppSpacing` is tuned for touch).
class WebInsets {
  WebInsets._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
