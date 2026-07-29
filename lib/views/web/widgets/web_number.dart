/// Tabular-figure numerics for the web companion — the desktop counterpart of
/// the mobile [AppNumberDisplay].
///
/// The mobile design system renders every figure through
/// `AppTextStyles.numeric`, which is **Plus Jakarta Sans with
/// [FontFeature.tabularFigures]** — the same family as body text, only with
/// fixed-advance digits. It is not a monospace face; `AppTextStyles.mono`
/// (JetBrains Mono) is a separate treatment the numbers never use.
///
/// Web already loads Plus Jakarta Sans for its whole text theme, so parity here
/// costs nothing at load time: it is the font feature that was missing, not the
/// font. Without it, digits carry proportional widths and a figure that ticks
/// from `₱1,111` to `₱8,888` visibly shifts the layout around it.
library;

import 'package:flutter/material.dart';

/// Returns [style] with tabular figures enabled, preserving everything else.
///
/// Prefer this over re-declaring sizes: web's `textTheme` is already Plus
/// Jakarta Sans, so a theme style plus this feature *is* the mobile numeric
/// treatment at that scale.
TextStyle? webNumericStyle(TextStyle? style, {Color? color}) => style?.copyWith(
      color: color ?? style.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The scales a web figure is rendered at, mapped onto the text theme so they
/// track the theme rather than hardcoding sizes.
enum WebNumberSize {
  /// Hero figure — the net-worth card.
  hero,

  /// Emphasised stat-tile value.
  tileLarge,

  /// Standard stat-tile value.
  tile,

  /// Mini-stat / inline card figure.
  body,

  /// Table cell or dense caption figure.
  caption,
}

/// A numeric value in the web companion's tabular-figure treatment.
///
/// Use for any currency, percentage, or count. Plain [Text] is still correct
/// for prose — this is specifically for figures that change.
class WebNumber extends StatelessWidget {
  final String value;
  final WebNumberSize size;
  final Color? color;
  final FontWeight? weight;
  final TextAlign? textAlign;
  final int maxLines;

  const WebNumber(
    this.value, {
    super.key,
    this.size = WebNumberSize.tile,
    this.color,
    this.weight,
    this.textAlign,
    this.maxLines = 1,
  });

  TextStyle? _base(TextTheme t) => switch (size) {
        WebNumberSize.hero => t.displaySmall,
        WebNumberSize.tileLarge => t.headlineMedium,
        WebNumberSize.tile => t.headlineSmall,
        WebNumberSize.body => t.titleLarge,
        WebNumberSize.caption => t.bodyMedium,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = webNumericStyle(
      _base(theme.textTheme),
      color: color ?? theme.colorScheme.onSurface,
    )?.copyWith(fontWeight: weight ?? FontWeight.w700);

    return Text(
      value,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}
