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
