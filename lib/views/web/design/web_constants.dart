/// Shared numeric constants for the Treasury web v2 kit (Plan 063, Phase 2).
///
/// These are the few values that several widgets and pages must agree on. Per
/// widget styling (paddings, font sizes) stays with the widget that owns it.
library;

import 'package:flutter/material.dart';

/// The one date range every web date picker accepts. Pages used to pass their
/// own `firstDate`/`lastDate`, and they drifted (2020–2030 here, 2000–2100
/// there); every `showDatePicker` on the web reads from this instead.
final DateTimeRange kWebDateRange = DateTimeRange(
  start: DateTime(2020),
  end: DateTime(2035, 12, 31),
);

/// Minimum width of one column in an even strip (`WebStatStrip`) before it
/// wraps to the next row.
const double kWebTabletMinColumn = 200;

/// Default dialog width on the canvas.
const double kWebDialogWidth = 520;

/// The wider dialog variant (`.dlg.wide` on the canvas) for forms with two
/// columns of fields, such as the account form.
const double kWebDialogWideWidth = 600;

/// Height of a standard single-line input (`.in` on the canvas).
const double kWebInputHeight = 46;

/// Height of the large amount input (`.in.big` on the canvas).
const double kWebAmountInputHeight = 64;

/// Height of a dialog footer button (`.btn` on the canvas). Taller than the
/// page-level `kWebButtonMinHeight` so the commit action in a form reads as
/// the primary target.
const double kWebDialogButtonHeight = 44;

/// Minimum hit area of a pointer target on the web. Icon-only controls (the
/// row ⋯ button, the dialog ×) size their hit area to this even when their
/// visual is smaller.
const double kWebHitTarget = 44;
