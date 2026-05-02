import 'package:flutter/material.dart';
import '../../../../utils/app_spacing.dart';
import '../../../../utils/app_text_styles.dart';

enum AppNumberSize { display, headline, title, body }
enum AppNumberLabelPosition { above, below }

/// Large numeric value with DM Mono + tabular figures. Prevents digit jitter.
class AppNumberDisplay extends StatelessWidget {
  const AppNumberDisplay({
    super.key,
    required this.value,
    this.label,
    this.prefix,
    this.suffix,
    this.size = AppNumberSize.title,
    this.labelPosition = AppNumberLabelPosition.below,
    this.color,
    this.textAlign = TextAlign.center,
  });

  final String value;
  final String? label;
  final String? prefix;
  final String? suffix;
  final AppNumberSize size;
  final AppNumberLabelPosition labelPosition;
  final Color? color;
  final TextAlign textAlign;

  TextStyle _baseStyle() => switch (size) {
        AppNumberSize.display => AppTextStyles.displayMedium,
        AppNumberSize.headline => AppTextStyles.headlineLarge,
        AppNumberSize.title => AppTextStyles.titleLarge,
        AppNumberSize.body => AppTextStyles.bodyLarge,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? theme.colorScheme.onSurface;
    final base = _baseStyle();
    final numericStyle = AppTextStyles.numeric(
      fontSize: base.fontSize,
      weight: base.fontWeight,
    ).copyWith(color: resolvedColor);
    final smallStyle = AppTextStyles.labelMedium.copyWith(
      color: resolvedColor.withValues(alpha: 0.7),
    );
    final labelStyle = AppTextStyles.labelMedium.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final numberRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefix != null)
          Text(prefix!, style: smallStyle, textAlign: textAlign),
        Text(value, style: numericStyle, textAlign: textAlign),
        if (suffix != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Text(suffix!, style: smallStyle, textAlign: textAlign),
          ),
      ],
    );

    if (label == null) return numberRow;

    final labelWidget =
        Text(label!, style: labelStyle, textAlign: textAlign);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: labelPosition == AppNumberLabelPosition.above
          ? [labelWidget, const SizedBox(height: 2), numberRow]
          : [numberRow, const SizedBox(height: 2), labelWidget],
    );
  }
}
